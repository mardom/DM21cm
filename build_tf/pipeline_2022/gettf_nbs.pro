PRO gettf_nbs, check=check, fixed_cfdt=fixed_cfdt, part_i=part_i
; fixed_cfdt : flag for fixed conformal delta t

    ; abscissa for nBs, xH=xHe, z(actually 1+z)
    nBs_s_global = [0.0001000000d, 0.0001995262d, 0.0003981072d, 0.0007943282d, 0.0015848932d, 0.0031622777d, 0.0063095734d, 0.0125892541d, 0.0251188643d, 0.0501187234d, 0.1000000000d, 0.2600000000d, 0.4200000000d, 0.5800000000d, 0.7400000000d, 0.9000000000d, 1.0600000000d, 1.2200000000d, 1.3800000000d, 1.5400000000d, 1.7000000000d, 3.1777777778d, 4.6555555556d, 6.1333333333d, 7.6111111111d, 9.0888888889d, 10.5666666667d, 12.0444444444d, 13.5222222222d, 15.0000000000d]
    x_s_global = [0.0000100000d, 0.5000000000d, 0.9999900000d]
    z_s_global = [10.0000000000d]
    
    ; photeng
    nphoteng     = 500
    dlnphoteng   = ALOG(5565952217145.328d/1d-4)/nphoteng
    photbins     = 1d-4*EXP(DINDGEN(nphoteng+1)*dlnphoteng)
    photenglow   = photbins[0:nphoteng-1]
    photenghigh  = photbins[1:nphoteng]
    photbinwidth = photenghigh - photenglow
    photeng      = SQRT(photenglow*photenghigh)
    injElow_i    = VALUE_LOCATE(photeng, 125) ; lowest photon input energy for highengphot is > 125eV
    injE_s       = photeng[injElow_i:*]
    
    ; eleceng
    neleceng     = 500
    dlneleceng   = ALOG(5565952217145.328d)/neleceng
    melec        = 510998.903
    elecbins     = melec + EXP(DINDGEN(neleceng+1)*dlneleceng)
    elecenglow   = elecbins[0:neleceng-1]
    elecenghigh  = elecbins[1:neleceng]
    elecbinwidth = elecenghigh - elecenglow ; bin width [eV]
    eleceng      = melec + SQRT((elecenglow-melec)*(elecenghigh-melec)) ; electron total energies [eV]
    
    ; part & tqdms
    nBs_s  = nBs_s_global
    xH_s   = [x_s_global[part_i]]
    z_s    = z_s_global
    part_total = N_ELEMENTS(xH_s) * N_ELEMENTS(nBs_s) * N_ELEMENTS(injE_s)
    prog   = 0
    
    ; config
    IF N_ELEMENTS(fixed_cfdt) NE 0 THEN BEGIN
        Mpc = 3.08568d24 ; cm
        c0 = 29979245800d ; cm/s
        cfdt = 0.6742 * 1d * Mpc / c0 ; s
    ENDIF
    channel = 'delta'
    outfolder = '/zfs/yitians/dm21cm/DM21cm/data/idl_output/test/'
    
    ; Planck parameters
    H0 = 1d/4.5979401d17 ; s^-1
    Omega_M = 0.3175d
    Omega_Lam = 0.6825d
    Omega_rad = 8d-5

    PRINT, '--------------------'
    PRINT, STRING('xH   start=', xH_s[0]  , ' end=', xH_s[-1]  , ' n_step=', N_ELEMENTS(xH_s)  , format='(A,E0.3,A,E0.3,A,I0)')
    PRINT, STRING('nBs  start=', nBs_s[0] , ' end=', nBs_s[-1] , ' n_step=', N_ELEMENTS(nBs_s) , format='(A,E0.3,A,E0.3,A,I0)')
    PRINT, STRING('z    start=', z_s[0]   , ' end=', z_s[-1]   , ' n_step=', N_ELEMENTS(z_s)   , format='(A,E0.3,A,E0.3,A,I0)')
    PRINT, STRING('injE start=', injE_s[0], ' end=', injE_s[-1], ' n_step=', N_ELEMENTS(injE_s), format='(A,E0.3,A,E0.3,A,I0)')
    PRINT, outfolder
    PRINT, '--------------------'
    
    IF KEYWORD_SET(check) THEN RETURN
    
    PRINT, '' ; preventing printing tqdms line together with idl outputs
    PRINT, STRING('tqdms init ', part_i, ' ', part_total, format='(A,I0,A,I0)')
    
    for xH_i   = 0, N_ELEMENTS(xH_s)-1   DO BEGIN
    for nBs_i  = 0, N_ELEMENTS(nBs_s)-1  DO BEGIN
    for z_i    = 0, N_ELEMENTS(z_s)-1    DO BEGIN
    
        ; ---------- Initialize tfs ----------
        zinit = z_s[z_i] ; actually 1+z
        xH  = xH_s[xH_i]
        xHe = xH_s[xH_i]
        nBs = nBs_s[nBs_i]

        IF N_ELEMENTS(fixed_cfdt) EQ 0 THEN BEGIN
            ; dlnz = 1d-3 ; nBs_test
            dlnz = 0.04879016d ; nBs_test_2
        ENDIF ELSE BEGIN
            hubblerate = H0 * sqrt(Omega_M*zinit^3 + Omega_rad*zinit^4 + Omega_Lam)
            phys_dt = cfdt / zinit
            dlnz = phys_dt * hubblerate
        ENDELSE
        
        epsilon = 1e-100
        hep_tf = DBLARR(nphoteng, nphoteng) + epsilon
        lep_tf = DBLARR(nphoteng, nphoteng) + epsilon
        lee_tf = DBLARR(neleceng, nphoteng) + epsilon
        hed_tf  = DBLARR(4, nphoteng)
        cmbloss = DBLARR(nphoteng)
        lowerbound = 0d
        
        ; ---------- Initialize variables for each tf ----------
        UNDEFINE, tot_time
        UNDEFINE, reuse_electronprocesses
        UNDEFINE, reuse_photon_input_electronprocesses
        
        for injE_i = 0, N_ELEMENTS(injE_s)-1 DO BEGIN ; higher injection take a longer time
        
            injE = injE_s[injE_i]

            ; ---------- Call ih_transferfunction ----------
            ih_transferfunction, $
            dlnz=dlnz, zinit=zinit, zfinal=zfinal, $
            numsteps=2, mwimp=injE, channel=channel, $
            customionization=xH, xHe=xHe, $
            nBscale=nBs, $
            ; outfolder=outfolder, $
            output=output, $
            reuse_electronprocesses=reuse_electronprocesses, $
            reuse_photoninput_electronprocesses=reuse_photoninput_electronprocesses, $
            timeinfo=timeinfo, $
            /singleinjection, /altpp, /ionizationdetailed, /comptonsmooth, $
            /modIFiedheat, /modIFiedion, /depositiondetailed, depositionpartition=3d3, $
            /planckparams,/fixedbinning, nphoteng=nphoteng, /heliumseparated, $
            /dontredshIFtphotons, /silent

            prog += 1
            str  = STRING('tqdms ', part_i, ' ', prog, format='(A,I0,A,I0)')

            str += STRING(' xH='  , xH    , ': ', xH_i+1  , '/', N_ELEMENTS(xH_s)  , format='(A,E0.3,A,I0,A,I0)')
            str += STRING(' nBs=' , nBs   , ': ', nBs_i+1 , '/', N_ELEMENTS(nBs_s) , format='(A,E0.3,A,I0,A,I0)')
            str += STRING(' zini=', zinit , ': ', z_i+1   , '/', N_ELEMENTS(z_s)   , format='(A,E0.3,A,I0,A,I0)')
            str += STRING(' dlnz=', dlnz  , format='(A,E0.3)')
            str += STRING(' injE=', injE  , ': ', injE_i+1, '/', N_ELEMENTS(injE_s), format='(A,E0.3,A,I0,A,I0)')
            PRINT, str
            
            ; ---------- Save output ----------
            E_i = injElow_i + injE_i
            
            hep_tf[*, E_i] = output.photonspectrum[*, 1]*photbinwidth / 2d
            lep_tf[*, E_i] = output.lowengphot[*, 1]*photbinwidth / 2d
            lee_tf[*, E_i] = output.lowengelec[*, 1]*elecbinwidth / 2d
            hed_tf[*, E_i] = output.highdeposited_grid[1, *] / 2d
            cmbloss[E_i] = output.cmblosstable[1] / 2d
            lowerbound = output.lowerbound[1]
            
            ; ---------- timeinfo ----------
            IF injE_i GE 1 THEN BEGIN
                IF KEYWORD_SET(tot_time) THEN BEGIN
                    tot_time += REFORM(timeinfo.time.TOARRAY())
                ENDIF ELSE BEGIN
                    tot_time = REFORM(timeinfo.time.TOARRAY())
                ENDELSE
            ENDIF

        ENDFOR
        
        ; ---------- Save to file ----------
        save_struct = { $
            hep_tf : hep_tf, $
            lep_tf : lep_tf, $
            lee_tf : lee_tf, $
            hed_tf : hed_tf, $
            cmbloss : cmbloss, $
            lowerbound : lowerbound $
        }
        outname = STRING('tf_z_', zinit, '_x_', xH, '_nBs_', nBs, $
                         format='(A,E0.3,A,E0.3,A,E0.3)')
        outname = outfolder + outname + '.fits'
        mwrfits, save_struct, outname, /create, /silent
        
        PRINT, 'timeinfo:'
        PRINT, REFORM(timeinfo.title.TOARRAY())
        PRINT, tot_time / FLOAT(N_ELEMENTS(injE_s)-1)
        
    ENDFOR
    ENDFOR
    ENDFOR
    
    RETURN
END