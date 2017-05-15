MODULE MOD_Particle_Vars
!===================================================================================================================================
! Contains the Particles' variables (general for all modules: PIC, DSMC, FP)
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
REAL, PARAMETER       :: BoltzmannConst=1.380648813E-23                      ! Boltzmann constant [J/K] SI-Unit!
REAL                  :: ManualTimeStep                                      ! Manual TimeStep
LOGICAL               :: useManualTimeStep                                   ! Logical Flag for manual timestep. For consistency
                                                                             ! with IAG programming style
LOGICAL               :: KeepWallParticles                                   ! Flag for tracking of adsorbed Particles
LOGICAL               :: printRandomSeeds                                    ! print random seeds or not
REAL                  :: dt_max_particles                                    ! Maximum timestep for particles (for static fields!)
REAL                  :: dt_maxwell                                          ! timestep for field solver (for static fields only!)
REAL                  :: dt_adapt_maxwell                                    ! adapted timestep for field solver dependent  
                                                                             ! on particle velocity (for static fields only!)
REAL                  :: dt_part_ratio, overrelax_factor                     ! factors for td200/201 overrelaxation/subcycling
INTEGER               :: NextTimeStepAdjustmentIter                          ! iteration of next timestep change
INTEGER               :: MaxwellIterNum                                      ! number of iterations for the maxwell solver
INTEGER               :: WeirdElems                                          ! Number of Weird Elements (=Elements which are folded
                                                                             ! into themselves)
REAL    , ALLOCATABLE :: PartState(:,:)                                      ! (1:NParts,1:6) with 2nd index: x,y,z,vx,vy,vz
REAL    , ALLOCATABLE :: PartPosRef(:,:)                                     ! (1:3,1:NParts) particles pos mapped to -1|1 space
INTEGER , ALLOCATABLE :: PartPosGauss(:,:)                                   ! (1:NParts,1:3) Gauss point localization of particles
REAL    , ALLOCATABLE :: Pt(:,:)                                             ! Derivative of PartState (vx,xy,vz) only
                                                                             ! since temporal derivative of position
                                                                             ! is the velocity. Thus we can take 
                                                                             ! PartState(:,4:6) as Pt(1:3)
                                                                             ! (1:NParts,1:6) with 2nd index: x,y,z,vx,vy,vz
#if defined(IMEX) || defined(IMPA)
REAL    , ALLOCATABLE :: PartStage (:,:,:)                                   ! ERK4 additional function values
REAL    , ALLOCATABLE :: PartStateN(:,:)                                     ! PartilceState at t^n
#endif /*IMEX*/
#if (PP_TimeDiscMethod==120) || (PP_TimeDiscMethod==121) || (PP_TimeDiscMethod==122)
!REAL    , ALLOCATABLE :: StagePartPos(:,:)                                   ! (1:NParts,1:3) with 2nd index: x,y,z
LOGICAL , ALLOCATABLE :: PartIsImplicit(:)                                   ! select, if specific particle is explicit or implicit
#endif
#ifdef IMPA
REAL    , ALLOCATABLE :: PartDeltaX(:,:)                                     ! Change of particle during Newton step
LOGICAL , ALLOCATABLE :: PartLambdaAccept(:)                                 ! Accept particle search direction
REAL    , ALLOCATABLE :: PartQ(:,:)                                          ! PartilceState at t^n or state at RK-level 0
! Newton iteration
REAL    , ALLOCATABLE :: F_PartX0(:,:)                                       ! Particle function evaluated at t^0
REAL    , ALLOCATABLE :: F_PartXK(:,:)                                       ! Particle function evaluated at iteration step k
REAL    , ALLOCATABLE :: Norm2_F_PartX0    (:)                               ! and the corresponding L2 norm
REAL    , ALLOCATABLE :: Norm2_F_PartXK    (:)                               ! and the corresponding L2 norm
REAL    , ALLOCATABLE :: Norm2_F_PartXK_Old(:)                               ! and the corresponding L2 norm
LOGICAL , ALLOCATABLE :: DoPartInNewton(:)                                   ! particle is treated implicitly && Newtons method
                                                                             ! is performed on it
#endif
REAL    , ALLOCATABLE :: Pt_temp(:,:)                                        ! LSERK4 additional derivative of PartState

                                                                             ! (1:NParts,1:6) with 2nd index: x,y,z,vx,vy,vz
REAL    , ALLOCATABLE :: LastPartPos(:,:)                                    ! (1:NParts,1:3) with 2nd index: x,y,z
INTEGER , ALLOCATABLE :: PartSpecies(:)                                      ! (1:NParts) 
REAL    , ALLOCATABLE :: PartMPF(:)                                          ! (1:NParts) MacroParticleFactor by variable MPF
INTEGER               :: PartLorentzType
CHARACTER(LEN=256)    :: ParticlePushMethod                                  ! Type of PP-Method
INTEGER               :: nrSeeds                                             ! Number of Seeds for Random Number Generator
INTEGER , ALLOCATABLE :: seeds(:)                        !        =>NULL()   ! Seeds for Random Number Generator

TYPE tConstPressure
  INTEGER                                :: nElemTotalInside                  ! Number of elements totally in Emission Particle  
  INTEGER                                :: nElemPartlyInside                 ! Number of elements partly in Emission Particle 
  INTEGER, ALLOCATABLE                   :: ElemTotalInside(:)                ! List of elements totally in Emission Particle 
                                                                              ! ElemTotalInside(1:nElemTotalInside)
  INTEGER, ALLOCATABLE                   :: ElemPartlyInside(:)               ! List of elements partly in Emission Particle 
                                                                              ! ElemTotalInside(1:nElemPartlyInside)
  INTEGER(2), ALLOCATABLE                :: ElemStat(:)                       ! Status of Element to Emission Particle Space
                                                                              ! ElemStat(nElem) = 1  -->  Element is totally insid
                                                                              !                 = 2  -->  Element is partly  insid
                                                                              !                 = 3  -->  Element is totally outsi
  REAL                                   :: OrthoVector(3)                    ! Vector othogonal on BaseVector1IC and BaseVector2
  REAL                                   :: Determinant                       ! Determinant for solving a 3x3 system of equations
                                                                              ! to see whether a point is inside a cuboid
  REAL                                   :: EkinInside                        ! Kinetic Energy in Emission-Area
  REAL                                   :: InitialTemp                       ! Initial MWTemerature
  REAL, ALLOCATABLE                      :: ConstPressureSamp(:,:)            ! ElemTotalInside(1:nElemTotalInside,1 = v_x
                                                                              !                                    2 = v_y
                                                                              !                                    3 = v_z
                                                                              !                                    4 = dens. [1/m3]
                                                                              !                                    5 = pressure
                                                                              !                                    6 = v of sound**2
END TYPE

TYPE tExcludeRegion
  CHARACTER(40)                          :: SpaceIC                          ! specifying Keyword for Particle Space condition
  REAL                                   :: RadiusIC                         ! Radius for IC circle
  REAL                                   :: Radius2IC                        ! Radius2 for IC cylinder (ring)
  REAL                                   :: NormalIC(3)                      ! Normal / Orientation of cylinder (altern. to BV1/2)
  REAL                                   :: BasePointIC(3)                   ! base point for IC cuboid and IC sphere
  REAL                                   :: BaseVector1IC(3)                 ! first base vector for IC cuboid
  REAL                                   :: BaseVector2IC(3)                 ! second base vector for IC cuboid
  REAL                                   :: CuboidHeightIC                   ! third measure of cuboid
                                                                             ! (set 0 for flat rectangle),
                                                                             ! negative value = opposite direction
  REAL                                   :: CylinderHeightIC                 ! third measure of cylinder
                                                                             ! (set 0 for flat circle),
                                                                             ! negative value = opposite direction
  REAL                                   :: ExcludeBV_lenghts(2)                    ! lenghts of BV1/2 (to be calculated)
END TYPE

TYPE tInit                                                                   ! Particle Data for each init emission for each species
  !Specific Emission/Init values
  LOGICAL                                :: UseForInit                       ! Use Init/Emission for init.?
  LOGICAL                                :: UseForEmission                   ! Use Init/Emission for emission?
  CHARACTER(40)                          :: SpaceIC                          ! specifying Keyword for Particle Space condition
  CHARACTER(30)                          :: velocityDistribution             ! specifying keyword for velocity distribution
  INTEGER(8)                             :: initialParticleNumber            ! Number of Particles at time 0.0
  REAL                                   :: RadiusIC                         ! Radius for IC circle
  REAL                                   :: Radius2IC                        ! Radius2 for IC cylinder (ring)
  REAL                                   :: RadiusICGyro                     ! Radius for Gyrotron gyro radius
  INTEGER                                :: Rotation                         ! direction of rotation, similar to TE-mode
  INTEGER                                :: VelocitySpreadMethod             ! method to compute the velocity spread
  REAL                                   :: VelocitySpread                   ! velocity spread in percent
  REAL                                   :: NormalIC(3)                      ! Normal / Orientation of circle
  REAL                                   :: BasePointIC(3)                   ! base point for IC cuboid and IC sphere
  REAL                                   :: BaseVector1IC(3)                 ! first base vector for IC cuboid
  REAL                                   :: BaseVector2IC(3)                 ! second base vector for IC cuboid
  REAL                                   :: CuboidHeightIC                   ! third measure of cuboid
                                                                             ! (set 0 for flat rectangle),
                                                                             ! negative value = opposite direction
  REAL                                   :: CylinderHeightIC                 ! third measure of cylinder
                                                                             ! (set 0 for flat rectangle),
                                                                             ! negative value = opposite direction
  LOGICAL                                :: CalcHeightFromDt                 ! Calc. cuboid/cylinder height from v and dt?
  REAL                                   :: VeloIC                           ! velocity for inital Data
  REAL                                   :: VeloVecIC(3)                     ! normalized velocity vector
  REAL                                   :: Amplitude                        ! Amplitude for sin-deviation initiation.
  REAL                                   :: WaveNumber                       ! WaveNumber for sin-deviation initiation.
  INTEGER                                :: maxParticleNumberX               ! Maximum Number of all Particles in x direction
  INTEGER                                :: maxParticleNumberY               ! Maximum Number of all Particles in y direction
  INTEGER                                :: maxParticleNumberZ               ! Maximum Number of all Particles in z direction
  REAL                                   :: MJxRatio                         ! x direction portion of velocity for Maxwell-Juettner
  REAL                                   :: MJyRatio                         ! y direction portion of velocity for Maxwell-Juettner
  REAL                                   :: MJzRatio                         ! z direction portion of velocity for Maxwell-Juettner
  REAL                                   :: WeibelVeloPar                    ! Parallel velocity component for Weibel
  REAL                                   :: WeibelVeloPer                    ! Perpendicular velocity component for Weibel
  REAL                                   :: OneDTwoStreamVelo                ! Stream Velocity for the Two Stream Instability
  REAL                                   :: OneDTwoStreamTransRatio          ! Ratio between perpendicular and parallel velocity
  REAL                                   :: Alpha                            ! WaveNumber for sin-deviation initiation.
  REAL                                   :: MWTemperatureIC                  ! Temperature for Maxwell Distribution
  REAL                                   :: ConstantPressure                 ! Pressure for an Area with a Constant Pressure
  REAL                                   :: ConstPressureRelaxFac            ! RelaxFac. for ConstPressureSamp
  REAL                                   :: PartDensity                      ! PartDensity (real particles per m^3) for LD_insert or
                                                                             ! (vpi_)cub./cyl. as alternative to Part.Emis. in Type1
  INTEGER                                :: ParticleEmissionType             ! Emission Type 1 = emission rate in 1/s,
                                                                             !               2 = emission rate 1/iteration
                                                                             !               3 = user def. emission rate
                                                                             !               4 = const. cell pressure
                                                                             !               5 = cell pres. w. complete part removal
                                                                             !               6 = outflow BC (characteristics method)
  REAL                                   :: ParticleEmission                 ! Emission in [1/s] or [1/Iteration]
  INTEGER(KIND=8)                        :: InsertedParticle                 ! Number of all already inserted Particles
  INTEGER(KIND=8)                        :: InsertedParticleSurplus          ! accumulated "negative" number of inserted Particles
  REAL                                   :: Nsigma                           ! sigma multiple of maxwell for virtual insert length
  LOGICAL                                :: VirtPreInsert                    ! virtual Pre-Inserting region (adapted SetPos/Velo)?
  CHARACTER(40)                          :: vpiDomainType                    ! specifying Keyword for virtual Pre-Inserting region
                                                                             ! implemented: - perpendicular_extrusion (default)
                                                                             !              - freestream
                                                                             !              - orifice
                                                                             !              - ...more following...
  LOGICAL                                :: vpiBVBuffer(4)                   ! incl. buffer region in -BV1/+BV1/-BV2/+BV2 direction?
  TYPE(tConstPressure)                   :: ConstPress!(:)           =>NULL() !
  INTEGER                                :: NumberOfExcludeRegions           ! Number of different regions to be excluded
  TYPE(tExcludeRegion), ALLOCATABLE      :: ExcludeRegion(:)
#ifdef MPI
  INTEGER                                :: InitComm                          ! number of init-communicator
#endif /*MPI*/
END TYPE tInit

TYPE tSurfFluxSubSideData
  REAL                                   :: projFak                          ! VeloVecIC projected to inwards normal
  REAL                                   :: a_nIn                            ! speed ratio projected to inwards normal
  REAL                                   :: Velo_t1                          ! Velo comp. of first orth. vector
  REAL                                   :: Velo_t2                          ! Velo comp. of second orth. vector
  REAL                                   :: nVFR                             ! normal volume flow rate through subside
  REAL                                   :: Dmax                             ! maximum Jacobian determinant of subside for opt. ARM
  REAL,ALLOCATABLE                       :: BezierControlPoints2D(:,:,:)     ! BCP of SubSide projected to VeloVecIC
                                                                             ! (1:2,0:NGeo,0:NGeo)
END TYPE tSurfFluxSubSideData

TYPE tSurfaceflux
  INTEGER                                :: BC                               ! PartBound to be emitted from
  CHARACTER(30)                          :: velocityDistribution             ! specifying keyword for velocity distribution
  REAL                                   :: VeloIC                           ! velocity for inital Data
  REAL                                   :: VeloVecIC(3)                     ! normalized velocity vector
  REAL                                   :: MWTemperatureIC                  ! Temperature for Maxwell Distribution
  REAL                                   :: PartDensity                      ! PartDensity (real particles per m^3)
  LOGICAL                                :: VeloIsNormal                     ! VeloIC is in Surf-Normal instead of VeloVecIC
  LOGICAL                                :: ReduceNoise                      ! reduce stat. noise by global calc. of PartIns
  LOGICAL                                :: AcceptReject                     ! perform ARM for skewness of RefMap-positioning
  INTEGER                                :: ARM_DmaxSampleN                  ! number of sample intervals in xi/eta for Dmax-calc.
  REAL                                   :: VFR_total                        ! Total Volumetric flow rate through surface
  REAL                     , ALLOCATABLE :: VFR_total_allProcs(:)            ! -''-, all values for root in ReduceNoise-case
  REAL                                   :: VFR_total_allProcsTotal          !     -''-, total
  INTEGER(KIND=8)                        :: InsertedParticle                 ! Number of all already inserted Particles
  INTEGER(KIND=8)                        :: InsertedParticleSurplus          ! accumulated "negative" number of inserted Particles
  INTEGER(KIND=8)                        :: tmpInsertedParticle              ! tmp Number of all already inserted Particles
  INTEGER(KIND=8)                        :: tmpInsertedParticleSurplus       ! tmp accumulated "negative" number of inserted Particles
  TYPE(tSurfFluxSubSideData), ALLOCATABLE :: SurfFluxSubSideData(:,:,:)      ! SF-specific Data of Sides (1:N,1:N,1:SideNumber)
  INTEGER, ALLOCATABLE                   :: SurfFluxSideRejectType(:)        ! Type if parts in side can be rejected (1:SideNumber)
  LOGICAL                                :: SimpleRadialVeloFit !fit of veloR/veloTot=-r*(A*exp(B*r)+C)
  REAL                                   :: preFac !A
  REAL                                   :: powerFac !B
  REAL                                   :: shiftFac !C
  INTEGER                                :: dir(3)                           ! axial (1) and orth. coordinates (2,3) of polar system
  REAL                                   :: origin(2)                        ! origin in orth. coordinates of polar system
  REAL                                   :: rmax                             ! max radius of to-be inserted particles
END TYPE

TYPE tSpecies                                                                ! Particle Data for each Species
  !General Species Values
  TYPE(tInit), ALLOCATABLE               :: Init(:)  !     =>NULL()          ! Particle Data for each Initialisation
  REAL                                   :: ChargeIC                         ! Particle Charge (without MPF)
  REAL                                   :: MassIC                           ! Particle Mass (without MPF)
  REAL                                   :: MacroParticleFactor              ! Number of Microparticle per Macroparticle
  INTEGER                                :: NumberOfInits                    ! Number of different initial particle placements
  INTEGER                                :: StartnumberOfInits               ! 0 if old emit defined (array is copied into 0. entry)
  TYPE(tSurfaceflux),ALLOCATABLE         :: Surfaceflux(:)                   ! Particle Data for each SurfaceFlux emission
  INTEGER                                :: nSurfacefluxBCs                  ! Number of SF emissions
#if (PP_TimeDiscMethod==120) || (PP_TimeDiscMethod==121) || (PP_TimeDiscMethod==122)
  LOGICAL                                :: IsImplicit
#endif
END TYPE

INTEGER                                  :: nSpecies                         ! number of species
TYPE(tSpecies), ALLOCATABLE              :: Species(:)  !           => NULL() ! Species Data Vector

TYPE tParticleElementMapping
  INTEGER                , ALLOCATABLE   :: Element(:)      !      =>NULL()  ! Element number allocated to each Particle
  INTEGER                , ALLOCATABLE   :: lastElement(:)  !      =>NULL()  ! Element number allocated
!#if (PP_TimeDiscMethod==120) || (PP_TimeDiscMethod==121) || (PP_TimeDiscMethod==122)
!  INTEGER                , ALLOCATABLE   :: StageElement(:)  !      =>NULL()  ! Element number allocated
!#endif
                                                                             ! to each Particle at previous timestep
!----------------------------------------------------------------------------!----------------------------------
                                                                             ! Following vectors are assigned in
                                                                             ! SUBROUTINE UpdateNextFreePosition
                                                                             ! IF (PIC%withDSMC .OR. PIC%withFP)
  INTEGER                , ALLOCATABLE    :: pStart(:)         !     =>NULL()  ! Start of Linked List for Particles in Element
                                                               !               ! pStart(1:PIC%nElem)
  INTEGER                , ALLOCATABLE    :: pNumber(:)        !     =>NULL()  ! Number of Particles in Element
                                                               !               ! pStart(1:PIC%nElem)
  INTEGER                , ALLOCATABLE    :: wNumber(:)        !     =>NULL()  ! Number of Wall-Particles in Element
                                                                               ! pStart(1:PIC%nElem)
  INTEGER                , ALLOCATABLE    :: pEnd(:)           !     =>NULL()  ! End of Linked List for Particles in Element
                                                               !               ! pEnd(1:PIC%nElem)
  INTEGER                , ALLOCATABLE    :: pNext(:)          !     =>NULL()  ! Next Particle in same Element (Linked List)
                                                                               ! pStart(1:PIC%maxParticleNumber)
END TYPE

TYPE(tParticleElementMapping)            :: PEM

TYPE tParticleDataManagement
  INTEGER                                :: CurrentNextFreePosition           ! Index of nextfree index in nextFreePosition-Array
  INTEGER                                :: maxParticleNumber                 ! Maximum Number of all Particles
  INTEGER                                :: ParticleVecLength                 ! Vector Length for Particle Push Calculation
  INTEGER                                :: insideParticleNumber              ! Number of all recent Particles inside
  INTEGER , ALLOCATABLE                  :: PartInit(:)                       ! (1:NParts), initial emission condition number
                                                                              ! the calculation area
  INTEGER ,ALLOCATABLE                   :: nextFreePosition(:)  !  =>NULL()  ! next_free_Position(1:max_Particle_Number)
                                                                              ! List of free Positon
  LOGICAL ,ALLOCATABLE                   :: ParticleInside(:)    !  =>NULL()  ! Particle_inside(1:Particle_Number)
  LOGICAL , ALLOCATABLE                  :: ParticleAtWall(:)                 ! Particle_adsorbed_on_to_wall(1:Particle_number)
  INTEGER , ALLOCATABLE                  :: PartAdsorbSideIndx(:,:)           ! Surface index on which Particle i adsorbed 
                                                                              ! (1:3,1:PDM%maxParticleNumber)
                                                                              ! 1: surface index ElemToSide(i,localsideID,ElementID)
                                                                              ! 2: p
                                                                              ! 3: q
  LOGICAL ,ALLOCATABLE                   :: dtFracPush(:)                     ! Push random fraction only
  LOGICAL ,ALLOCATABLE                   :: IsNewPart(:)                      ! Reconstruct RK-scheme in next stage
END TYPE

TYPE (tParticleDataManagement)           :: PDM

REAL                                     :: DelayTime

LOGICAL                                  :: ParticlesInitIsDone=.FALSE.

LOGICAL                                  :: WriteMacroValues                  ! Output of macroscopic values
INTEGER                                  :: MacroValSamplIterNum              ! Number of iterations for sampling   
                                                                              ! macroscopic values
REAL                                     :: MacroValSampTime                  ! Sampling time for WriteMacroVal. (e.g., for td201)
LOGICAL                                  :: usevMPF                           ! use the vMPF per particle
LOGICAL                                  :: enableParticleMerge               ! enables the particle merge routines
LOGICAL                                  :: doParticleMerge=.false.           ! flag for particle merge
INTEGER                                  :: vMPFMergeParticleTarget           ! number of particles wanted after merge
INTEGER                                  :: vMPFSplitParticleTarget           ! number of particles wanted after split
INTEGER                                  :: vMPFMergeParticleIter             ! iterations between particle merges
INTEGER                                  :: vMPFMergePolyOrder                ! order of polynom for vMPF merge
INTEGER                                  :: vMPFMergeCellSplitOrder           ! order of cell splitting (vMPF)
INTEGER, ALLOCATABLE                     :: vMPF_OrderVec(:,:)                ! Vec of vMPF poynom orders
INTEGER, ALLOCATABLE                     :: vMPF_SplitVec(:,:)                ! Vec of vMPF cell split orders
INTEGER, ALLOCATABLE                     :: vMPF_SplitVecBack(:,:,:)          ! Vec of vMPF cell split orders backward
REAL, ALLOCATABLE                        :: PartStateMap(:,:)                 ! part pos mapped on the -1,1 cube  
INTEGER, ALLOCATABLE                     :: PartStatevMPFSpec(:)              ! part state indx of spec to merge
REAL, ALLOCATABLE                        :: vMPFPolyPoint(:,:)                ! Points of Polynom in LM 
REAL, ALLOCATABLE                        :: vMPFPolySol(:)                    ! Solution of Polynom in LM
REAL                                     :: vMPF_oldMPFSum                    ! Sum of all old MPF in cell
REAL                                     :: vMPF_oldEngSum                    ! Sum of all old energies in cell
REAL                                     :: vMPF_oldMomSum(3)                 ! Sum of all old momentums in cell
REAL, ALLOCATABLE                        :: vMPFOldVelo(:,:)                  ! Old Particle Velo for Polynom
REAL, ALLOCATABLE                        :: vMPFOldBrownVelo(:,:)             ! Old brownian Velo
REAL, ALLOCATABLE                        :: vMPFOldPos(:,:)                   ! Old Particle Pos for Polynom
REAL, ALLOCATABLE                        :: vMPFOldMPF(:)                     ! Old Particle MPF
INTEGER, ALLOCATABLE                     :: vMPFNewPosNum(:)
INTEGER, ALLOCATABLE                     :: vMPF_SpecNumElem(:,:)             ! number of particles of spec (:,i) in element (j,:)
CHARACTER(30)                            :: vMPF_velocityDistribution         ! specifying keyword for velocity distribution
REAL, ALLOCATABLE                        :: vMPF_NewPosRefElem(:,:)          ! new positions in ref elem
LOGICAL                                  :: vMPF_relativistic
LOGICAL                                  :: PartPressureCell                  ! Flag: constant pressure in cells emission (type4)
LOGICAL                                  :: PartPressAddParts                 ! Should Parts be added to reach wanted pressure?
LOGICAL                                  :: PartPressRemParts                 ! Should Parts be removed to reach wanted pressure?
INTEGER                                  :: NumRanVec      ! Number of predefined random vectors
REAL, ALLOCATABLE                        :: RandomVec(:,:) ! Random Vectos (NumRanVec, direction)
REAL, ALLOCATABLE                        :: RegionElectronRef(:,:)          ! RegionElectronRef((rho0,phi0,Te[eV])|1:NbrOfRegions)
LOGICAL                                  :: useVTKFileBGG                     ! Flag for BGG via VTK-File
REAL, ALLOCATABLE                        :: BGGdataAtElem(:,:)                ! data for BGG via VTK-File
LOGICAL                                  :: OutputVpiWarnings                 ! Flag for warnings for rejected v if VPI+PartDensity
LOGICAL                                  :: DoSurfaceFlux                     ! Flag for emitting by SurfaceFluxBCs
LOGICAL                                  :: DoPoissonRounding                 ! Perform Poisson samling instead of random rounding
LOGICAL                                  :: DoZigguratSampling                ! Sample normal randoms with Ziggurat method
LOGICAL                                  :: FindNeighbourElems=.FALSE.

INTEGER(8)                               :: nTotalPart
INTEGER(8)                               :: nTotalHalfPart

INTEGER :: nCollectChargesBCs
INTEGER :: nDataBC_CollectCharges
TYPE tCollectCharges
  INTEGER                              :: BC
  REAL                                 :: NumOfRealCharges
  REAL                                 :: NumOfNewRealCharges
  REAL                                 :: ChargeDist
END TYPE
TYPE(tCollectCharges), ALLOCATABLE     :: CollectCharges(:)

!===================================================================================================================================
END MODULE MOD_Particle_Vars
