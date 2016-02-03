!
! Copyright (C) 2013 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!----------------------------------------------------------------------------
SUBROUTINE run_pwscf ( exit_status ) 
  !----------------------------------------------------------------------------
  !
  ! ... Run an instance of the Plane Wave Self-Consistent Field code 
  ! ... MPI initialization and input data reading is performed in the 
  ! ... calling code - returns in exit_status the exit code for pw.x, 
  ! ... returned in the shell. Values are:
  ! ... * 0: completed successfully
  ! ... * 1: an error has occurred (value returned by the errore() routine)
  ! ... * 2-127: convergence error
  ! ...   * 2: scf convergence error
  ! ...   * 3: ion convergence error
  ! ... * 128-255: code exited due to specific trigger
  !       * 255: exit due to user request, or signal trapped,
  !              or time > max_seconds
  ! ...     (note: in the future, check_stop_now could also return a value
  ! ...     to specify the reason of exiting, and the value could be used
  ! ..      to return a different value for different reasons)
  ! ... Will be eventually merged with NEB
  !
  USE io_global,        ONLY : stdout, ionode, ionode_id
  USE parameters,       ONLY : ntypx, npk, lmaxx
  USE cell_base,        ONLY : fix_volume, fix_area
  USE control_flags,    ONLY : conv_elec, gamma_only, lscf, twfcollect
  USE control_flags,    ONLY : conv_ions, istep, nstep, restart, lmd, lbfgs
  USE force_mod,        ONLY : lforce, lstres, sigma, force
  USE check_stop,       ONLY : check_stop_init, check_stop_now
  USE mp_images,        ONLY : intra_image_comm
  USE qmmm,             ONLY : qmmm_initialization, qmmm_shutdown, &
                               qmmm_update_positions, qmmm_update_forces
  USE lsda_mod,         ONLY : nspin                ! LEONID
  USE io_rho_xml,       ONLY : read_rho             ! LEONID
  USE scf,              ONLY : rho, charge_density, vltot    ! LEONID
  USE kinds,            ONLY : DP                   ! LEONID
  USE fft_base,         ONLY : dfftp                ! LEONID
  USE mp,               ONLY : mp_sum               ! LEONID
  USE mp_bands,         ONLY : intra_bgrp_comm      ! LEONID
  USE cell_base,        ONLY : omega                ! LEONID
  USE io_files,         ONLY : prefix               ! LEONID
  USE input_parameters, ONLY : prefix_flipper_charge, lflipper          ! LEONID
  USE vlocal,           ONLY : strf, vloc                               ! LEONID
  USE ions_base,        ONLY : nat, ityp, tau, ntyp => nsp, zv          ! LEONID
  USE gvect,            ONLY :  ngm, gstart, g, eigts1, &
                                eigts2, eigts3, gcutm, &
                                gg,ngl, nl, igtongl                     ! LEONID
  USE cell_base,        ONLY : bg, at, alat                             ! LEONID
  USE fft_interfaces,   ONLY : fwfft
  
  USE force_mod,      ONLY : force 
  USE wavefunctions_module,  ONLY: psic !Aris
  USE flipper_mod

  IMPLICIT NONE
  INTEGER, INTENT(OUT) :: exit_status
  !
  !
  ! START LEONID
!  LOGICAL  :: lflipper                                  ! LEONID
  INTEGER  :: igrid,iatom,igm                                     ! LEONID
  INTEGER  :: ntyp_save                                 ! LEONID
!  INTEGER  :: nr_of_pinballs                                  ! LEONID
  INTEGER  :: counter                                   ! LEONID
  INTEGER  :: na                                   ! LEONID
  INTEGER  :: ipol                                   ! LEONID
!  REAL(DP) :: charge_density_diff, charge_all           ! LEONID
!  REAL(DP) :: flipper_energy_external, flipper_ewld_energy     ! LEONID
!  REAL(DP) :: flipper_ewld_forces                       ! LEONID
  CHARACTER(LEN=256) :: normal_prefix                   ! LEONID
  REAL(DP), EXTERNAL :: ewald                           ! LEONID
!  REAL(DP), ALLOCATABLE :: flipper_ewald_force(:,:)                ! LEONID
!  REAL(DP), ALLOCATABLE :: flipper_forcelc(:,:)                ! LEONID
!  REAL(DP), ALLOCATABLE :: total_force(:,:)                ! LEONID
!  REAL(DP), ALLOCATABLE :: aux_rho_of_r(:,:)                ! LEONID
!  COMPLEX(DP), ALLOCATABLE :: charge_g(:)                ! LEONID
  
  


  
  IF (ionode .and. lflipper) THEN
    print*, ' ##########################################'
    print*, '      THIS IS A FLIPPER CALCULATION'
    print*, ' ##########################################'
    
    
    
  END IF
  ! END LEONID
  
  !
  exit_status = 0
  IF ( ionode ) WRITE( unit = stdout, FMT = 9010 ) ntypx, npk, lmaxx
  !
  IF (ionode) CALL plugin_arguments()
  CALL plugin_arguments_bcast( ionode_id, intra_image_comm )
  !
  ! ... needs to come before iosys() so some input flags can be
  !     overridden without needing to write PWscf specific code.
  ! 
  CALL qmmm_initialization()
  !
  ! ... convert to internal variables
  !
  CALL iosys()
  !
  IF ( gamma_only ) WRITE( UNIT = stdout, &
     & FMT = '(/,5X,"gamma-point specific algorithms are used")' )
  !
  ! call to void routine for user defined / plugin patches initializations
  !
  CALL plugin_initialization()
  !
  CALL check_stop_init()
  !
  CALL setup ()
  !
  CALL qmmm_update_positions()
  !
  CALL init_run()
  !
  ! ... dry run: code will stop here if called with exit file present
  ! ... useful for a quick and automated way to check input data
  !
  IF ( check_stop_now() ) THEN
     CALL punch( 'config' )
     exit_status = 255
     RETURN
  ENDIF
  !
  
  IF (lflipper) THEN
    
!~     flipper_ityp = atm(ityp(ia))
    ! GET THE NUMBER OF PINBALLS
    nr_of_pinballs = 0
    DO counter = 1, nat
        IF (ityp(counter) == 1) THEN
            nr_of_pinballs = nr_of_pinballs + 1
        END IF
    END DO
    
    if (ionode) THEN
        print*, '    THIS IS A FLIPPER CALCULATION'
        print*, '    NrPinballs  =  ', nr_of_pinballs
    end if
    ! set the nr_of_pinballs back
!~     nr_of_pinballs = nat

!     ALLOCATE(flipper_ewald_force( 3, nr_of_pinballs ))
!     ALLOCATE(flipper_forcelc( 3, nr_of_pinballs))
!     ALLOCATE(total_force( 3, nr_of_pinballs))
!     ALLOCATE(aux_rho_of_g( ngm ))
!     ALLOCATE(aux_rho_of_r( dfftp%nnr, nspin ))
     call allocate_flipper()   
!~      flipper_forcelc(:,:) = 0.d0

     ! print*,'before', prefix_flipper_charge, prefix 
     ! READ THE CHARGE DENSITY GIVEN BY AN EARLIER CALCULATION
     normal_prefix = prefix
     prefix = prefix_flipper_charge 
     print*, '&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&'
     CALL read_rho(charge_density, nspin)
     print*, '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
     prefix = normal_prefix
     
!     aux_rho_of_r(1:dfftp%nnr,1:nspin) = charge_density%of_r(1:dfftp%nnr,1:nspin)
     
!     aux_rho_of_g(:) = CMPLX( aux_rho_of_r(:,1), 0.0_dp, kind=dp )
    
     psic(:)=(0.d0,0.d0)
         
!~      CALL fwfft ('Dense', aux_rho_of_g, dfftp)
     psic(1:dfftp%nnr)=dcmplx(charge_density%of_r(1:dfftp%nnr,1)) 
     CALL fwfft ('Dense', psic, dfftp)
     DO igm=1,ngm 
        charge_g(igm)=psic(nl(igm))
     END DO
  END IF
  
  
  main_loop: DO
     !
     ! ... electronic self-consistency or band structure calculation
     !
     
     IF ( .NOT. lflipper) THEN
         IF ( .NOT. lscf) THEN
            CALL non_scf ()
         ELSE
            CALL electrons()
         END IF
         !
         ! ... code stopped by user or not converged
         !
         IF ( check_stop_now() .OR. .NOT. conv_elec ) THEN
            IF ( check_stop_now() ) exit_status = 255
            IF ( .NOT. conv_elec )  exit_status =  2
            ! workaround for the case of a single k-point
            twfcollect = .FALSE.
            CALL punch( 'config' )
            RETURN
         ENDIF
     ENDIF
     !
     ! ... ionic section starts here
     !
     
     CALL start_clock( 'ions' )
     conv_ions = .TRUE.
     !
     ! ... recover from a previous run, if appropriate
     !
     !IF ( restart .AND. lscf ) CALL restart_in_ions()
     !
     ! ... file in CASINO format written here if required
     !
     IF ( lmd ) CALL pw2casino()
     !
     ! ... force calculation
     !
     
     ! LEONID
     IF (lflipper) THEN

        !
        ! ... initialize the structure factor
        !
        ntyp_save = ntyp
        ntyp = 1
        CALL struc_fact( nat, tau, ntyp, ityp, ngm, g, bg, &
                   dfftp%nr1, dfftp%nr2, dfftp%nr3, strf, eigts1, eigts2, eigts3 )
        CALL flipper_setlocal()
        ! set ntyp back to what it originally was. Is that necessary?
        ntyp = ntyp_save
        
        flipper_ewld_energy = ewald( alat, nat, ntyp, ityp, zv, at, bg, tau, &
                omega, g, gg, ngm, gcutm, gstart, gamma_only, strf )
        
!~         if (ionode) print*, 'FLIPPER: TOTAL POTENTIAL ENERGY: ',flipper_energy_external+flipper_ewld_energy  !Aris
        
!~         if (ionode) print*, 'CALCULATING EWALD FORCES'
        
!        CALL flipper_force_ewald( alat, nat, nr_of_pinballs, ntyp, ityp, zv, at, bg, tau, omega, g, &
!                 gg, ngm, gstart, gamma_only, gcutm, strf, flipper_ewald_force )
         CALL flipper_force_ewald( alat, nat, ntyp, ityp, zv, at, bg, tau, omega, g, &
                 gg, ngm, gstart, gamma_only, gcutm, strf )

        
!~         if (ionode) print*, 'CALCULATING LOCAL FORCES'
!        CALL flipper_force_lc( nat, nr_of_pinballs, tau, ityp, alat, omega, ngm, ngl, igtongl, &
!                 g, aux_rho_of_g, nl, nspin, gstart, gamma_only, vloc, &
!                 flipper_forcelc )
         CALL flipper_force_lc( nat, tau, ityp, alat, omega, ngm, ngl, igtongl, &
                 g, nl, nspin, gstart, gamma_only, vloc )
!~         if (ionode) print*, flipper_forcelc
!~         if (ionode) print*, 'DONE'
                 
        
        DO ipol = 1, 3
             DO na = 1, nr_of_pinballs
                total_force(ipol,na) = &
                                flipper_ewald_force(ipol,na)    + &
                                flipper_forcelc(ipol,na)   
            END DO
        END DO
        
        ! LEONID: set the conserved quantity
        
        ! LEONID: let's reduce the writing into the main output file
!~         DO na = 1, nr_of_pinballs
!~         !
!~             WRITE( stdout, 9035) na, ityp(na), total_force(:,na)
!~         !
!~         END DO

        force(:,:)=0.d0
        do iatom=1,nr_of_pinballs
            force(1:3,iatom)=total_force(1:3,iatom)
        end do
        CALL move_ions()
        !
        
        !
!~             IF ( istep < nstep .AND. .NOT. conv_ions ) &
!~                CALL punch( 'config' )
!~         flipper_cons_qty = flipper_energy_external+flipper_ewld_energy+flipper_energy_kin
!~         if (ionode) print*, '    FLIPPER: Ekin ', flipper_energy_kin  !Aris
!~         if (ionode) print*, '    FLIPPER: EWALD ENERGY: ',flipper_ewld_energy  !Aris
!~         if (ionode) print*, '    FLIPPER: EXTERNAL ENERGY: ',flipper_energy_external  !Aris
!~         if (ionode) print*, '    FLIPPER: CONSERVED ENERGY', flipper_cons_qty  !Aris
            
     
      ELSE 
         IF ( lforce ) CALL forces()          
         !
         ! ... stress calculation
         !
         IF ( lstres ) CALL stress ( sigma )
         !
         ! ... send out forces to MM code in QM/MM run
         !
         CALL qmmm_update_forces(force)
         !
         IF ( lmd .OR. lbfgs ) THEN
            !
            if (fix_volume) CALL impose_deviatoric_stress(sigma)
            !
            if (fix_area)  CALL  impose_deviatoric_stress_2d(sigma)
            !
            ! ... ionic step (for molecular dynamics or optimization)
            !
            CALL move_ions()
            !
            ! ... then we save restart information for the new configuration
            IF ( istep < nstep .AND. .NOT. conv_ions ) &
               CALL punch( 'config' )
            !
         END IF
     END IF
     !
     CALL stop_clock( 'ions' )
     !
     ! ... exit condition (ionic convergence) is checked here
     !
     IF ( conv_ions ) EXIT main_loop
     !
     ! ... receive new positions from MM code in QM/MM run
     !
     IF ( .NOT. lflipper) THEN
        CALL qmmm_update_positions()
         !
         ! ... terms of the hamiltonian depending upon nuclear positions
         ! ... are reinitialized here
         !
         IF ( lmd .OR. lbfgs ) CALL hinit1()
         !
     END IF
  END DO main_loop
  
  
!  IF (lflipper)  DEALLOCATE(flipper_ewald_force)                 ! LEONID
!  IF (lflipper)  DEALLOCATE(flipper_forcelc)                 ! LEONID
!  IF (lflipper)  DEALLOCATE(total_force)                 ! LEONID
  IF (lflipper)  then 
!      DEALLOCATE(aux_rho_of_g)                 ! LEONID
!      DEALLOCATE(aux_rho_of_r)                 ! LEONID
      call deallocate_flipper()
  END IF
  !
  ! ... save final data file
  !
  IF ( .not. lmd) CALL pw2casino()
  CALL punch('all')
  !
  CALL qmmm_shutdown()
  !
  IF ( .NOT. conv_ions )  exit_status =  3
  RETURN
  !
9010 FORMAT( /,5X,'Current dimensions of program PWSCF are:', &
           & /,5X,'Max number of different atomic species (ntypx) = ',I2,&
           & /,5X,'Max number of k-points (npk) = ',I6,&
           & /,5X,'Max angular momentum in pseudopotentials (lmaxx) = ',i2)
           
9035 FORMAT(5X,'atom ',I4,' type ',I2,'   force = ',3F14.8)  ! LEONID
END SUBROUTINE run_pwscf
