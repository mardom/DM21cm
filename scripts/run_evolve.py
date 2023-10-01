import sys
import argparse

from astropy.cosmology import Planck18
import py21cmfast as p21c

sys.path.append("..")
from dm21cm.dm_params import DMParams
from dm21cm.evolve import evolve


if __name__ == '__main__':

    # parser = argparse.ArgumentParser()
    # parser.add_argument('-m', type=float, default=1.)
    # args = parser.parse_args()

    # print(f"Running m={args.m}...")

    return_dict = evolve(
        run_name = f'xc_ours_sfr0926-2_noatten',
        z_start = 45.,
        z_end = 5.,
        zplusone_step_factor = 1.01,
        dm_params = DMParams(
            mode='swave',
            primary='phot_delta',
            m_DM=1e0,
            sigmav=1e-50,
            struct_boost_model='erfc 1e-3',
        ),
        enable_elec = False,
        tf_version = '230629xc',
        
        p21c_initial_conditions = p21c.initial_conditions(
            user_params = p21c.UserParams(
                HII_DIM = 32,
                BOX_LEN = 32 * 2, # [conformal Mpc]
                N_THREADS = 32,
            ),
            cosmo_params = p21c.CosmoParams(
                OMm = Planck18.Om0,
                OMb = Planck18.Ob0,
                POWER_INDEX = Planck18.meta['n'],
                SIGMA_8 = Planck18.meta['sigma8'],
                hlittle = Planck18.h,
            ),
            random_seed = 54321,
            write = True,
        ),
        
        rerun_DH = False,
        clear_cache = True,
        use_tqdm = False,
        debug_flags = ['xraycheck', 'xc-noatten'],
        debug_xray_multiplier = 1.,
        debug_astro_params = p21c.AstroParams(
            L_X = 0. # log10 value
        ),
        debug_copy_dh_init = 'xc_base',
        debug_dont_use_dh_init = True,
    )