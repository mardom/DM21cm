"""Interpolators for energy depositions and secondary spectra."""

import h5py
import numpy as np
from functools import partial

import jax.numpy as jnp
from jax import jit, vmap, device_put


#===== interpolation =====

@jit
def interp1d(fp, xp, x):
    """Interpolates f(x), described by points fp and xp, at values in x.

    Args:
        fp (array): n(>=1)D array of function values. First dimension will be interpolated.
        xp (array): 1D array of x values.
        x (array): x values to interpolate.

    Notes:
        xp must be sorted. Does not do bound checks.
    """
    il = jnp.searchsorted(xp, x, side='right') - 1
    wl = (xp[il+1] - x) / (xp[il+1] - xp[il])
    return fp[il] * wl + fp[il+1] * (1 - wl)

@jit
@partial(vmap, in_axes=(None, None, None, 0))
def interp2d(fp, x0p, x1p, x01):
    """Interpolates f(x0, x1), described by points fp, x0p, and x1p, at values in x01.

    Args:
        fp (array): n(>=2)D array of function values. First two dimensions will be interpolated.
        x0p (array): 1D array of x0 values (first dimension of fp).
        x1p (array): 1D array of x1 values (second dimension of fp).
        x01 (array): [x0, x1] values to interpolate.

    Notes:
        x0p and x1p must be sorted. Does not do bound checks.
    """
    x0, x1 = x01
    
    i0l = jnp.searchsorted(x0p, x0, side='right') - 1
    wl0 = (x0p[i0l+1] - x0) / (x0p[i0l+1] - x0p[i0l])
    wr0 = 1 - wl0
    
    i1l = jnp.searchsorted(x1p, x1, side='right') - 1
    wl1 = (x1p[i1l+1] - x1) / (x1p[i1l+1] - x1p[i1l])
    wr1 = 1 - wl1
    
    return fp[i0l,i1l]*wl0*wl1 + fp[i0l+1,i1l]*wr0*wl1 + fp[i0l,i1l+1]*wl0*wr1 + fp[i0l+1,i1l+1]*wr0*wr1


#===== utilities =====

def v_is_within(v, absc):
    """v can be value or vector."""
    return jnp.all(v >= jnp.min(absc)) and jnp.all(v <= jnp.max(absc))


#===== interpolator class =====

class BatchInterpolator:
    """Interpolator for multidimensional data. Currently supports axes=('rs', 'Ein', 'nBs', 'x', 'out').

    Args:
        filename (str): HDF5 data file name.

    Attributes:
        axes (list): List of axis names.
        abscs (dict): Abscissas of axes.
        data (array): Grid data consistent with axes and abscs.
    """
    
    def __init__(self, filename):
        
        with h5py.File(filename, 'r') as hf:
            self.axes = hf['axes'][:]
            self.abscs = {}
            for k, item in hf['abscs'].items():
                self.abscs[k] = item[:]
            self.data = jnp.array(hf['data'][:]) # load into memory
        
        self.data = device_put(self.data)
        self.fixed_in_spec = None
        self.fixed_in_spec_data = None
    
    
    def set_fixed_in_spec(self, in_spec):
        
        self.fixed_in_spec = in_spec
        self.fixed_in_spec_data = jnp.einsum('e,renxo->rnxo', in_spec, self.data)
        self.fixed_in_spec_data = device_put(self.fixed_in_spec_data)
        
        
    def __call__(self, rs=None, in_spec=None, nBs_s=None, x_s=None,
                 sum_result=False, sum_weight=None, sum_batch_size=256**3,
                 out_of_bounds_action='error'):
        """Batch interpolate in (nBs and) x directions.
        
        First sum with in_spec (with caching), then interpolate to a rs point,
        then perform the interpolation on [(nBs_s), x_s]. If sum_result is True,
        sum over all interpolated value.
        
        Parameters:
            rs : [1]
            in_spec : [N * ...]
            nBs_s : [1]
            x_s : [1]
            sum_result : if True, return average in the batch dimension.
            sum_weight : if None, just sum. otherwise dot.
            sum_batch_size : perform batch interpolation (and averaging) in batches of this size.
            out_of_bounds_action : {'error', 'clip'}
        
        Return:
            interpolated box or average of interpolated box.
        """
        
        if out_of_bounds_action == 'clip':
            factor = 1.00001
            rs    = jnp.clip(rs,    jnp.min(self.abscs['rs'])*factor,  jnp.max(self.abscs['rs'])/factor)
            x_s   = jnp.clip(x_s,   jnp.min(self.abscs['x'])*factor,   jnp.max(self.abscs['x'])/factor)
            nBs_s = jnp.clip(nBs_s, jnp.min(self.abscs['nBs'])*factor, jnp.max(self.abscs['nBs'])/factor)
        else:
            if not v_is_within(rs, self.abscs['rs']):
                raise ValueError('rs out of bounds.')
            if not v_is_within(x_s, self.abscs['x']):
                raise ValueError('x_s out of bounds.')
            if not v_is_within(nBs_s, self.abscs['nBs']):
                raise ValueError('nBs_s out of bounds.')
        
        # 1. in_spec sum
        if jnp.all(in_spec == self.fixed_in_spec):
            in_spec_data = self.fixed_in_spec_data
        else:
            in_spec_data = jnp.einsum('e,renxo->rnxo', in_spec, self.data)
        
        # 2. rs interpolation
        data_at_rs = interp1d(in_spec_data, jnp.array(self.abscs['rs']), rs)
        
        if not sum_result:
            # 3. (nBs) x interpolation
            nBs_x_in = jnp.stack([nBs_s, x_s], axis=-1)
            return interp2d(
                data_at_rs,
                jnp.array(self.abscs['nBs']),
                jnp.array(self.abscs['x']),
                nBs_x_in
            )
            
        else:
            ## 3. (nBs) x sum
            split_n = int(jnp.ceil( len(x_s)/sum_batch_size ))
            if sum_weight is not None:
                sum_weight_batches = jnp.array_split(sum_weight, split_n)
                
            result = jnp.zeros( (len(self.abscs['out']),) ) # use numpy?
            
            nBs_x_in = jnp.stack([nBs_s, x_s], axis=-1)
            nBs_x_in_batches = jnp.array_split(nBs_x_in, split_n)

            for i_batch, nBs_x_in_batch in enumerate(nBs_x_in_batches):
                interp_result = interp2d(
                    data_at_rs,
                    self.abscs['nBs'],
                    self.abscs['x'],
                    nBs_x_in_batch
                )
                if sum_weight is None:
                    result += jnp.sum(interp_result, axis=0)
                else:
                    result += jnp.dot(sum_weight_batches[i_batch], interp_result)
                    
            return result
        
    
    def point_interp(self, rs=None, nBs=None, x=None):
        """Returns the transfer function at a (rs, nBs, x) point."""
        
        data = interp1d(self.data, self.abscs['rs'], rs) # enxo
        data = np.einsum('enxo -> nxeo', data) # nxeo
        data = interp1d(data, self.abscs['nBs'], nBs) # xeo
        data = interp1d(data, self.abscs['x'], x) # eo
        return data