#include "boltzplatz.h"

MODULE MOD_Particle_Boundary_Condition
!===================================================================================================================================
!! Determines how particles interact with a given boundary condition 
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------

! Public Part ----------------------------------------------------------------------------------------------------------------------
INTERFACE GetBoundaryInteraction
  MODULE PROCEDURE GetBoundaryInteraction
END INTERFACE

INTERFACE GetBoundaryInteractionRef
  MODULE PROCEDURE GetBoundaryInteractionRef
END INTERFACE

PUBLIC::GetBoundaryInteraction,GetBoundaryInteractionRef
!===================================================================================================================================

CONTAINS

SUBROUTINE GetBoundaryInteraction(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,ElemID)
!===================================================================================================================================
! Computes the post boundary state of a particle that interacts with a boundary condition
!  OpenBC                  = 1  
!  ReflectiveBC            = 2  
!  PeriodicBC              = 3  
!  SimpleAnodeBC           = 4  
!  SimpleCathodeBC         = 5  
!  MPINeighborhoodBC       = 6  
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Globals,                ONLY:Abort
USE MOD_Particle_Surfaces,      ONLY:CalcNormAndTangBilinear,CalcNormAndTangBezier
USE MOD_Particle_Vars,          ONLY:PDM,PartSpecies,PartState,LastPartPos,KeepWallParticles
USE MOD_Particle_Boundary_Vars, ONLY:PartBound
USE MOD_Particle_Surfaces_vars, ONLY:SideNormVec,SideType,epsilontol
!USE MOD_Particle_Surfaces_Vars, ONLY:BoundingBoxIsEmpty
USE MOD_Particle_Analyze,       ONLY:CalcEkinPart
USE MOD_Particle_Analyze_Vars,  ONLY:CalcPartBalance,nPartOut,PartEkinOut!,PartAnalyzeStep
USE MOD_Mesh_Vars,              ONLY:BC
! USE MOD_Particle_Mesh_Vars,     ONLY:PartBCSideList
USE MOD_DSMC_Vars,              ONLY:DSMC,useDSMC
USE MOD_DSMC_SurfModel_Tools,   ONLY:Particle_Wall_Adsorb
!USE MOD_BoundaryTools,          ONLY:SingleParticleToExactElement                                   !
!#if (PP_TimeDiscMethod==1)||(PP_TimeDiscMethod==2)||(PP_TimeDiscMethod==6)||(PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506)
#if defined(LSERK)
USE MOD_Particle_Vars,          ONLY:Pt_temp!,Pt
USE MOD_TimeDisc_Vars,          ONLY:RK_a!,iStage
#endif
#if (PP_TimeDiscMethod==121) || (PP_TimeDiscMethod==122)
USE MOD_Particle_Vars,           ONLY:PartIsImplicit
#endif /*PP_TimeDiscMethod==121 || PP_TimeDiscMethod==122  */
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN)                   :: iPart,SideID
REAL,INTENT(IN)                      :: xi,eta
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
INTEGER,INTENT(INOUT)                :: ElemID
REAL,INTENT(INOUT)                   :: alpha,PartTrajectory(1:3),lengthPartTrajectory
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                                 :: v_2(1:3),v_aux(1:3),n_loc(1:3),RanNum
INTEGER                              :: BCSideID, WallModeltype, adsorbindex
#if (PP_TimeDiscMethod==1)||(PP_TimeDiscMethod==2)||(PP_TimeDiscMethod==6)||(PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506)
REAL                                 :: absPt_temp
#endif
LOGICAL                              :: isSpeciesSwap
!===================================================================================================================================

IF (.NOT. ALLOCATED(PartBound%MapToPartBC)) THEN
CALL abort(&
__STAMP__&
,' ERROR: PartBound not allocated!.',999,999.)
END IF
IsSpeciesSwap=.FALSE.
! Select the corresponding boundary condition and calculate particle treatment
SELECT CASE(PartBound%TargetBoundCond(PartBound%MapToPartBC(BC(SideID))))
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(1) !PartBound%OpenBC)
!-----------------------------------------------------------------------------------------------------------------------------------
  IF(alpha/lengthPartTrajectory.LE.epsilontol)THEN !if particle is close to BC, it encounters the BC only if it leaves element/grid
    !BCSideID=PartBCSideList(SideID)
    SELECT CASE(SideType(SideID))
    CASE(PLANAR_RECT,PLANAR_NONRECT)
      n_loc=SideNormVec(1:3,SideID)
    CASE(BILINEAR)
      CALL CalcNormAndTangBilinear(nVec=n_loc,xi=xi,eta=eta,SideID=SideID)
    CASE(CURVED)
      CALL CalcNormAndTangBezier(nVec=n_loc,xi=xi,eta=eta,SideID=SideID)
    END SELECT 
    IF(DOT_PRODUCT(n_loc,PartTrajectory).LE.0.) RETURN
  END IF

  IF(CalcPartBalance) THEN
      nPartOut(PartSpecies(iPart))=nPartOut(PartSpecies(iPart)) + 1
      PartEkinOut(PartSpecies(iPart))=PartEkinOut(PartSpecies(iPart))+CalcEkinPart(iPart)
  END IF ! CalcPartBalance
  PDM%ParticleInside(iPart) = .FALSE.
  alpha=-1.
#if (PP_TimeDiscMethod==121) || (PP_TimeDiscMethod==122)
  PartIsImplicit(iPart) = .FALSE.
#endif /*PP_TimeDiscMethod==121 || PP_TimeDiscMethod==122  */

!-----------------------------------------------------------------------------------------------------------------------------------
CASE(2) !PartBound%ReflectiveBC)
!-----------------------------------------------------------------------------------------------------------------------------------
  !---- swap species?
  IF (PartBound%NbrOfSpeciesSwaps(PartBound%MapToPartBC(BC(SideID))).gt.0) THEN
    CALL SpeciesSwap(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap)
  END IF
  IF (PDM%ParticleInside(iPart)) THEN ! particle did not Swap to species 0 !deleted particle -> particle swaped to species 0
    ! Decide which WallModel is used
    IF (useDSMC) THEN
      WallModeltype = DSMC%WallModel
    ELSE
      WallModeltype = 0
    END IF
    IF (WallModeltype.EQ.0) THEN !previously used wall interaction model
      CALL RANDOM_NUMBER(RanNum)
      IF(RanNum.GE.PartBound%MomentumACC(PartBound%MapToPartBC(BC(SideID)))) THEN
        ! perfectly reflecting, specular re-emission
        CALL PerfectReflection(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap)
      ELSE
        CALL DiffuseReflection(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap)
      END IF
    ELSE IF (WallModeltype.EQ.1) THEN
               adsorbindex = 0
!--- Adsorption               
      CALL Particle_Wall_Adsorb(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap,adsorbindex)
      IF (adsorbindex.EQ.1) THEN
        IF (KeepWallParticles) THEN
          PDM%ParticleAtWall(iPart) = .TRUE.
        ELSE
          IF(CalcPartBalance) THEN
            nPartOut(PartSpecies(iPart))=nPartOut(PartSpecies(iPart)) + 1
            PartEkinOut(PartSpecies(iPart))=PartEkinOut(PartSpecies(iPart))+CalcEkinPart(iPart)
          END IF ! CalcPartBalance
          PDM%ParticleInside(iPart) = .FALSE.
          alpha=-1.
        END IF
      ELSE IF (adsorbindex.EQ.0) THEN
!--- Inelastic Reflection (not diffuse)               
        CALL PerfectReflection(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap)
      ELSE
        WRITE(*,*)'Boundary_PIC: Adsorption error.'
        CALL Abort(&
__STAMP__,&
'Boundary_Error: Adsorptionindex switched to unknown value.')
      END IF
    ELSE IF (WallModeltype.GT.1) THEN
      WRITE(*,*)'Boundary_PIC: wall model with adsorption chemistry (catalysis) not implemented yet.'
      CALL Abort(&
__STAMP__,&
'wall model 2 not implemented')
    END IF
  END IF
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(3) !PartBound%PeriodicBC)
!-----------------------------------------------------------------------------------------------------------------------------------
  ! new implementation, nothing to due :)
  ! however, never checked
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. (PartBound%PeriodicBC)',999,999.)
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(4) !PartBound%SimpleAnodeBC)
!-----------------------------------------------------------------------------------------------------------------------------------
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. (PartBound%SimpleAnodeBC)',999,999.)
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(5) !PartBound%SimpleCathodeBC)
!-----------------------------------------------------------------------------------------------------------------------------------
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. (PartBound%SimpleCathodeBC)',999,999.)
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(6) !PartBound%MPINeighborhoodBC)
!-----------------------------------------------------------------------------------------------------------------------------------
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. (PartBound%MPINeighborhoodBC)',999,999.)
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(10) !PartBound%SymmetryBC
!-----------------------------------------------------------------------------------------------------------------------------------
  CALL PerfectReflection(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap,opt_Symmetry=.TRUE.)


CASE DEFAULT
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. (unknown case)',999,999.)
END SELECT !PartBound%MapToPartBC(BC(SideID)

END SUBROUTINE GetBoundaryInteraction


SUBROUTINE GetBoundaryInteractionRef(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,ElemID)
!===================================================================================================================================
! Computes the post boundary state of a particle that interacts with a boundary condition
!  OpenBC                  = 1  
!  ReflectiveBC            = 2  
!  PeriodicBC              = 3  
!  SimpleAnodeBC           = 4  
!  SimpleCathodeBC         = 5  
!  MPINeighborhoodBC       = 6  
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Globals!,                ONLY:Abort
USE MOD_Particle_Surfaces,      ONLY:CalcNormAndTangBilinear,CalcNormAndTangBezier
USE MOD_Particle_Vars,          ONLY:PDM,PartSpecies,KeepWallParticles
USE MOD_Particle_Boundary_Vars, ONLY:PartBound
USE MOD_Particle_Surfaces_Vars, ONLY:SideType,SideNormVec,epsilontol
USE MOD_Particle_Analyze,       ONLY:CalcEkinPart
USE MOD_Particle_Analyze_Vars,  ONLY:CalcPartBalance,nPartOut,PartEkinOut!,PartAnalyzeStep
USE MOD_Mesh_Vars,              ONLY:BC,nSides
USE MOD_Particle_Mesh_Vars,     ONLY:PartBCSideList
USE MOD_DSMC_Vars,              ONLY:DSMC,useDSMC
USE MOD_DSMC_SurfModel_Tools,   ONLY:Particle_Wall_Adsorb
#if (PP_TimeDiscMethod==121) || (PP_TimeDiscMethod==122)
USE MOD_Particle_Vars,           ONLY:PartIsImplicit
#endif /*PP_TimeDiscMethod==121 || PP_TimeDiscMethod==122  */
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN)                   :: iPart,SideID
REAL,INTENT(IN)                      :: xi,eta
INTEGER,INTENT(IN)                   :: ElemID
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(INOUT)                   :: alpha,PartTrajectory(1:3),lengthPartTrajectory
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                                 :: RanNum,n_loc(1:3)
INTEGER                              :: BCSideID, WallModeltype, adsorbindex
LOGICAL                              :: IsSpeciesSwap
!===================================================================================================================================

IF (.NOT. ALLOCATED(PartBound%MapToPartBC)) THEN
CALL abort(&
__STAMP__&
,' ERROR: PartBound not allocated!.',999,999.)
END IF
IsSpeciesSwap=.FALSE.
! Select the corresponding boundary condition and calculate particle treatment
SELECT CASE(PartBound%TargetBoundCond(PartBound%MapToPartBC(BC(SideID))))
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(1) !PartBound%OpenBC)
!-----------------------------------------------------------------------------------------------------------------------------------
  IF(alpha/lengthPartTrajectory.LE.epsilontol)THEN !if particle is close to BC, it encounters the BC only if it leaves element/grid
    BCSideID=PartBCSideList(SideID)
    SELECT CASE(SideType(BCSideID))
    CASE(PLANAR_RECT,PLANAR_NONRECT)
      n_loc=SideNormVec(1:3,BCSideID)
    CASE(BILINEAR)
      CALL CalcNormAndTangBilinear(nVec=n_loc,xi=xi,eta=eta,SideID=BCSideID)
    CASE(CURVED)
      CALL CalcNormAndTangBezier(nVec=n_loc,xi=xi,eta=eta,SideID=BCSideID)
    END SELECT 
    IF(DOT_PRODUCT(n_loc,PartTrajectory).LE.0.) RETURN
  END IF

  IF(CalcPartBalance) THEN
      nPartOut(PartSpecies(iPart))=nPartOut(PartSpecies(iPart)) + 1
      PartEkinOut(PartSpecies(iPart))=PartEkinOut(PartSpecies(iPart))+CalcEkinPart(iPart)
  END IF ! CalcPartBalance
  PDM%ParticleInside(iPart) = .FALSE.
  alpha=-1.
#if (PP_TimeDiscMethod==121) || (PP_TimeDiscMethod==122)
  PartIsImplicit(iPart) = .FALSE.
#endif /*PP_TimeDiscMethod==121 || PP_TimeDiscMethod==122  */
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(2) !PartBound%ReflectiveBC)
!-----------------------------------------------------------------------------------------------------------------------------------
  !---- swap species?
  IF (PartBound%NbrOfSpeciesSwaps(PartBound%MapToPartBC(BC(SideID))).gt.0) THEN
    CALL SpeciesSwap(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap,BCSideID)
  END IF
  IF (PDM%ParticleInside(iPart)) THEN ! particle did not Swap to species 0 !deleted particle -> particle swaped to species 0
    ! Decide which WallModel is used
    IF (useDSMC) THEN
      WallModeltype = DSMC%WallModel
    ELSE
      WallModeltype = 0
    END IF
    IF (WallModeltype.EQ.0) THEN !previously used wall interaction model
      CALL RANDOM_NUMBER(RanNum)
      BCSideID=PartBCSideList(SideID)
      IF(RanNum.GE.PartBound%MomentumACC(PartBound%MapToPartBC(BC(SideID)))) THEN
        ! perfectly reflecting, specular re-emission
        CALL PerfectReflection(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap,BCSideID=BCSideID)
      ELSE
        CALL DiffuseReflection(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap,BCSideID)
      END IF
    ELSE IF (WallModeltype.EQ.1) THEN
               adsorbindex = 0
!--- Adsorption               
      CALL Particle_Wall_Adsorb(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap,adsorbindex)
      IF (adsorbindex.EQ.1) THEN
        IF (KeepWallParticles) THEN
          PDM%ParticleAtWall(iPart) = .TRUE.
        ELSE
          IF(CalcPartBalance) THEN
            nPartOut(PartSpecies(iPart))=nPartOut(PartSpecies(iPart)) + 1
            PartEkinOut(PartSpecies(iPart))=PartEkinOut(PartSpecies(iPart))+CalcEkinPart(iPart)
          END IF ! CalcPartBalance
          PDM%ParticleInside(iPart) = .FALSE.
          alpha=-1.
        END IF
      ELSE IF (adsorbindex.EQ.0) THEN
!--- Inelastic Reflection (not diffuse)  
        BCSideID=PartBCSideList(SideID)
        CALL PerfectReflection(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap,BCSideID=BCSideID)
      ELSE
        WRITE(*,*)'Boundary_PIC: Adsorption error.'
        CALL Abort(&
__STAMP__,&
'Boundary_Error: Adsorptionindex switched to unknown value.')
      END IF
    ELSE IF (WallModeltype.GT.1) THEN
      WRITE(*,*)'Boundary_PIC: wall model with adsorption chemistry (catalysis) not implemented yet.'
      CALL Abort(&
__STAMP__,&
'wall model 2 not implemented')
    END IF
  END IF
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(3) !PartBound%PeriodicBC)
!-----------------------------------------------------------------------------------------------------------------------------------
  ! new implementation, nothing to due :)
  ! however, never checked
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. (PartBound%PeriodicBC)',999,999.)
  !compute new bc
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(4) !PartBound%SimpleAnodeBC)
!-----------------------------------------------------------------------------------------------------------------------------------
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. (PartBound%SimpleAnodeBC)',999,999.)
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(5) !PartBound%SimpleCathodeBC)
!-----------------------------------------------------------------------------------------------------------------------------------
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. (PartBound%SimpleCathodeBC)',999,999.)
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(6) !PartBound%MPINeighborhoodBC)
!-----------------------------------------------------------------------------------------------------------------------------------
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. (PartBound%MPINeighborhoodBC)',999,999.)
!-----------------------------------------------------------------------------------------------------------------------------------
CASE(10) !PartBound%SymmetryBC
!-----------------------------------------------------------------------------------------------------------------------------------
  BCSideID=PartBCSideList(SideID)
  CALL PerfectReflection(&
    PartTrajectory,lengthPartTrajectory,alpha,xi,eta,iPart,SideID,IsSpeciesSwap,BCSideID=BCSideID,opt_Symmetry=.TRUE.)


CASE DEFAULT
CALL abort(&
__STAMP__&
,' ERROR: PartBound not associated!. BC(SideID)',BC(SideID),REAL(SideID/nSides))
END SELECT !PartBound%MapToPartBC(BC(SideID)

END SUBROUTINE GetBoundaryInteractionRef


SUBROUTINE PerfectReflection(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,PartID,SideID,IsSpeciesSwap,BCSideID,opt_Symmetry)
!----------------------------------------------------------------------------------------------------------------------------------!
! Computes the perfect reflection in 3D
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Particle_Boundary_Vars, ONLY:PartBound,SurfMesh,SampWall
USE MOD_Particle_Boundary_Vars, ONLY:dXiEQ_SurfSample,nSurfSample
USE MOD_Particle_Mesh_Vars,     ONLY:epsInCell,ElemBaryNGeo,PartSideToElem
USE MOD_Particle_Surfaces,      ONLY:CalcNormAndTangBilinear,CalcNormAndTangBezier
USE MOD_Particle_Vars,          ONLY:PartState,LastPartPos,nSpecies,PartSpecies,Species
USE MOD_Particle_Surfaces_vars, ONLY:SideNormVec,SideType,epsilontol
USE MOD_Mesh_Vars,              ONLY:BC
USE MOD_DSMC_Vars,              ONLY:PartStateIntEn, SpecDSMC, DSMC, useDSMC
USE MOD_DSMC_Vars,              ONLY:CollisMode, AnalyzeSurfCollis
USE MOD_LD_Vars,                ONLY: useLD
!#if (PP_TimeDiscMethod==1)||(PP_TimeDiscMethod==2)||(PP_TimeDiscMethod==6)||(PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506)
#if defined(LSERK)
USE MOD_Particle_Vars,          ONLY:Pt_temp,PDM!,Pt
!USE MOD_TimeDisc_Vars,          ONLY:RK_a!,iStage
#endif
#ifdef IMPA
USE MOD_Particle_Vars,          ONLY:PartQ,F_PartX0
USE MOD_LinearSolver_Vars,      ONLY:PartXk
#endif /*IMPA*/
USE MOD_Particle_Vars,          ONLY:WriteMacroValues
USE MOD_TImeDisc_Vars,          ONLY:dt,tend,time
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT VARIABLES 
REAL,INTENT(INOUT)                :: PartTrajectory(1:3), lengthPartTrajectory, alpha
REAL,INTENT(IN)                   :: xi, eta
INTEGER,INTENT(IN)                :: PartID, SideID!,ElemID
LOGICAL,INTENT(IN)                :: IsSpeciesSwap
INTEGER,INTENT(IN),OPTIONAL       :: BCSideID
LOGICAL,INTENT(IN),OPTIONAL       :: opt_Symmetry
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                                 :: v_old(1:3),v_2(1:3),v_aux(1:3),n_loc(1:3), v_help(3), WallVelo(3)
!#if (PP_TimeDiscMethod==1)||(PP_TimeDiscMethod==2)||(PP_TimeDiscMethod==6)||(PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506)
!#if defined(LSERK)
!REAL                                 :: absPt_temp
!#endif
#if IMPA
REAL                                 :: absVec
REAL                                 :: PartDiff(3)
#endif /*IMPA*/
INTEGER                              :: ElemID
!REAL,PARAMETER                       :: oneMinus=0.99999999
!REAL                                 :: oneMinus!=0.99999999
REAL                                  :: epsLength,epsReflect
REAL                                 :: Xitild,EtaTild
INTEGER                              :: p,q, SurfSideID
LOGICAL                              :: Symmetry
!===================================================================================================================================

!OneMinus=1.0-MAX(epsInCell,epsilontol)
epsLength=MAX(epsInCell,epsilontol)*lengthPartTrajectory
WallVelo=PartBound%WallVelo(1:3,PartBound%MapToPartBC(BC(SideID)))

IF(PRESENT(BCSideID))THEN
  SELECT CASE(SideType(BCSideID))
  CASE(PLANAR_RECT,PLANAR_NONRECT)
    n_loc=SideNormVec(1:3,BCSideID)
  CASE(BILINEAR)
    CALL CalcNormAndTangBilinear(nVec=n_loc,xi=xi,eta=eta,SideID=BCSideID)
  CASE(CURVED)
    CALL CalcNormAndTangBezier(nVec=n_loc,xi=xi,eta=eta,SideID=BCSideID)
  END SELECT 
ELSE
  SELECT CASE(SideType(SideID))
  CASE(PLANAR_RECT,PLANAR_NONRECT)
    n_loc=SideNormVec(1:3,SideID)
  CASE(BILINEAR)
    CALL CalcNormAndTangBilinear(nVec=n_loc,xi=xi,eta=eta,SideID=SideID)
  CASE(CURVED)
    CALL CalcNormAndTangBezier(nVec=n_loc,xi=xi,eta=eta,SideID=SideID)
  END SELECT 
END IF
IF(PRESENT(opt_Symmetry)) THEN
  Symmetry = opt_Symmetry
ELSE
  Symmetry = .FALSE.
END IF

IF(DOT_PRODUCT(PartTrajectory,n_loc).LE.0.) RETURN

! In vector notation: r_neu = r_alt + T - 2*((1-alpha)*<T,n>)*n
v_aux                  = -2.0*((LengthPartTrajectory-alpha)*DOT_PRODUCT(PartTrajectory(1:3),n_loc))*n_loc

!epsReflect=epsilontol*lengthPartTrajectory
!IF((DOT_PRODUCT(v_aux,v_aux)).GT.epsReflect)THEN

  ! particle position is exact at face
  ! LastPartPos(PartID,1:3) = LastPartPos(PartID,1:3) + PartTrajectory(1:3)*(alpha)
  !  particle is located eps in interior
  LastPartPos(PartID,1:3) = LastPartPos(PartID,1:3) + PartTrajectory(1:3)*alpha
  PartState(PartID,1:3)   = PartState(PartID,1:3)+v_aux
  v_old = PartState(PartID,4:6)

  ! move particle a bit in interior
  ElemID=PartSideToElem(S2E_ELEM_ID,SideID)
  v_help=LastPartPos(PartID,1:3)-ElemBaryNGeo(1:3,ElemID)
  LastPartPos(PartID,1:3)=ElemBaryNGeo(1:3,ElemID)+v_help*MAX(1.0-epsInCell/SQRT(DOT_PRODUCT(v_help,v_help)),0.)

  ! new velocity vector 
  !v_2=(1-alpha)*PartTrajectory(1:3)+v_aux
  v_2=(LengthPartTrajectory-alpha)*PartTrajectory(1:3)+v_aux
  PartState(PartID,4:6)   = SQRT(DOT_PRODUCT(PartState(PartID,4:6),PartState(PartID,4:6)))*&
                           (1/(SQRT(DOT_PRODUCT(v_2,v_2))))*v_2 + WallVelo
  
  PartTrajectory=PartState(PartID,1:3) - LastPartPos(PartID,1:3)
  lengthPartTrajectory=SQRT(PartTrajectory(1)*PartTrajectory(1) &
                           +PartTrajectory(2)*PartTrajectory(2) &
                           +PartTrajectory(3)*PartTrajectory(3) )
  PartTrajectory=PartTrajectory/lengthPartTrajectory
  lengthPartTrajectory=lengthPartTrajectory!+epsilontol
  
  ! Wall sampling Macrovalues
  IF((.NOT.Symmetry).AND.(.NOT.UseLD)) THEN !surface mesh is not build for the symmetry BC!?!
    IF ((DSMC%CalcSurfaceVal.AND.(Time.ge.(1-DSMC%TimeFracSamp)*TEnd)).OR.(DSMC%CalcSurfaceVal.AND.WriteMacroValues)) THEN
      SurfSideID=SurfMesh%SideIDToSurfID(SideID)
      ! compute p and q
      ! correction of xi and eta, can only be applied if xi & eta are not used later!
      Xitild =MIN(MAX(-1.,xi ),0.99)
      Etatild=MIN(MAX(-1.,eta),0.99)
      p=INT((Xitild +1.0)/dXiEQ_SurfSample)+1
      q=INT((Etatild+1.0)/dXiEQ_SurfSample)+1
      
    !----  Sampling Forces at walls
!       SampWall(SurfSideID)%State(10:12,p,q)= SampWall(SurfSideID)%State(10:12,p,q) + Species(PartSpecies(PartID))%MassIC &
!                                          * (v_old(1:3) - PartState(PartID,4:6)) * Species(PartSpecies(PartID))%MacroParticleFactor
      SampWall(SurfSideID)%State(10,p,q)= SampWall(SurfSideID)%State(10,p,q) + Species(PartSpecies(PartID))%MassIC &
                                          * (v_old(1) - PartState(PartID,4)) * Species(PartSpecies(PartID))%MacroParticleFactor
      SampWall(SurfSideID)%State(11,p,q)= SampWall(SurfSideID)%State(11,p,q) + Species(PartSpecies(PartID))%MassIC &
                                          * (v_old(2) - PartState(PartID,4)) * Species(PartSpecies(PartID))%MacroParticleFactor
      SampWall(SurfSideID)%State(12,p,q)= SampWall(SurfSideID)%State(12,p,q) + Species(PartSpecies(PartID))%MassIC &
                                          * (v_old(3) - PartState(PartID,4)) * Species(PartSpecies(PartID))%MacroParticleFactor
    !---- Counter for collisions (normal wall collisions - not to count if only Swaps to be counted, IsSpeciesSwap: already counted)
!       IF (.NOT.DSMC%CalcSurfCollis_OnlySwaps) THEN
      IF (.NOT.DSMC%CalcSurfCollis_OnlySwaps .AND. .NOT.IsSpeciesSwap) THEN
        SampWall(SurfSideID)%State(12+PartSpecies(PartID),p,q) = SampWall(SurfSideID)%State(12+PartSpecies(PartID),p,q) + 1
        IF (DSMC%AnalyzeSurfCollis) THEN
          AnalyzeSurfCollis%Number(PartSpecies(PartID)) = AnalyzeSurfCollis%Number(PartSpecies(PartID)) + 1
          AnalyzeSurfCollis%Number(nSpecies+1) = AnalyzeSurfCollis%Number(nSpecies+1) + 1
          IF (AnalyzeSurfCollis%Number(nSpecies+1) .GT. AnalyzeSurfCollis%maxPartNumber) THEN
CALL Abort(&
__STAMP__&
,'maxSurfCollisNumber reached!')
          END IF
          AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),1:3) &
            = LastPartPos(PartID,1:3) + alpha * PartTrajectory(1:3)
          AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),4) &
            = PartState(PartID,4)
          AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),5) &
            = PartState(PartID,5)
          AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),6) &
            = PartState(PartID,6)
          AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),7) &
            = LastPartPos(PartID,1)
          AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),8) &
            = LastPartPos(PartID,2)
          AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),9) &
            = LastPartPos(PartID,3)
          AnalyzeSurfCollis%Spec(AnalyzeSurfCollis%Number(nSpecies+1)) &
            = PartSpecies(PartID)
        END IF
      END IF
    END IF
  END IF
  
#if defined(LSERK)
!#if (PP_TimeDiscMethod==1)||(PP_TimeDiscMethod==2)||(PP_TimeDiscMethod==6)||(PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506)
   ! correction for Runge-Kutta (correct position!!)
!---------- old ----------
!  absPt_temp=SQRT(Pt_temp(PartID,1)*Pt_temp(PartID,1)+Pt_temp(PartID,2)*Pt_temp(PartID,2)+Pt_temp(PartID,3)*Pt_temp(PartID,3))
!  ! scale PartTrajectory to new Pt_temp
!  Pt_temp(PartID,1:3)=absPt_temp*PartTrajectory(1:3)
!  ! deleate force history
!  Pt_temp(PartID,4:6)=0.
!  ! what happens with force term || acceleration?
!-------------------------
   IF (.NOT.AlmostZero(DOT_PRODUCT(WallVelo,WallVelo))) THEN
     PDM%IsNewPart(PartID)=.TRUE. !reconstruction in timedisc during push
   ELSE
     Pt_temp(PartID,1:3)=Pt_temp(PartID,1:3)-2.*DOT_PRODUCT(Pt_temp(PartID,1:3),n_loc)*n_loc
     IF (Symmetry) THEN !reflect also force history for symmetry
       Pt_temp(PartID,4:6)=Pt_temp(PartID,4:6)-2.*DOT_PRODUCT(Pt_temp(PartID,4:6),n_loc)*n_loc
     ELSE
       Pt_temp(PartID,4:6)=0. !produces best result compared to analytical solution in plate capacitor...
     END IF
   END IF
#endif  /*LSERK*/
#ifdef IMPA
  ! at least EulerImplicit
  ! F_PartX0
  absVec = SQRT(DOT_PRODUCT(F_PartX0(1:3,PartID),F_PartX0(1:3,PartID)))
  F_PartX0(1:3,PartID)=absVec*PartTrajectory(1:3)
  absVec = SQRT(DOT_PRODUCT(F_PartX0(4:6,PartID),F_PartX0(4:6,PartID)))
  F_PartX0(4:6,PartID)=absVec*PartTrajectory
  ! PartXK
  PartXK(:,PartID) = PartState(PartID,:) 
  ! rewrite history
  PartDiff=PartState(PartID,1:3) - PartQ(1:3,PartID)
  absVec = SQRT(DOT_PRODUCT(PartDiff(1:3),PartDiff(1:3)))
  PartQ(1:3,PartID)=PartState(PartID,1:3) +absVec*PartTrajectory(1:3)
  !absVec = SQRT(DOT_PRODUCT(PartDiff(4:6),PartDiff(4:6)))
  PartQ(4:6,PartID)=PartState(PartID,4:6) !+absVec*PartTrajectory(1:3)
#endif /*IMPA*/
!END IF

END SUBROUTINE PerfectReflection


SUBROUTINE DiffuseReflection(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,PartID,SideID,IsSpeciesSwap,BCSideID)
!----------------------------------------------------------------------------------------------------------------------------------!
! Computes the diffuse reflection in 3D
! only implemented for DoRefMapping tracking
! PartBCs are reduced!
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals,                ONLY:CROSSNORM,abort,UNITVECTOR,myRank
USE MOD_Globals_Vars,           ONLY:PI
USE MOD_Particle_Mesh_Vars,     ONLY:epsInCell,ElemBaryNGeo,PartSideToElem
USE MOD_Particle_Boundary_Vars, ONLY:PartBound,SurfMesh,SampWall
USE MOD_Particle_Boundary_Vars, ONLY:dXiEQ_SurfSample,nSurfSample
USE MOD_Particle_Surfaces,      ONLY:CalcNormAndTangBilinear,CalcNormAndTangBezier
USE MOD_Particle_Vars,          ONLY:PartState,LastPartPos,Species,BoltzmannConst,PartSpecies,nSpecies
#if defined(LSERK)
USE MOD_Particle_Vars,          ONLY:PDM
#endif
USE MOD_Particle_Surfaces_vars, ONLY:SideNormVec,SideType,BezierControlPoints3D
USE MOD_Mesh_Vars,              ONLY:BC,NGEO
USE MOD_DSMC_Vars,              ONLY:SpecDSMC,CollisMode
USE MOD_DSMC_Vars,              ONLY:PartStateIntEn,DSMC, useDSMC
USE MOD_DSMC_Vars,              ONLY:AnalyzeSurfCollis, PolyatomMolDSMC, VibQuantsPar
USE MOD_Particle_Vars,          ONLY:WriteMacroValues
USE MOD_TimeDisc_Vars,          ONLY:dt,tend,time,RKdtFrac
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT VARIABLES 
REAL,INTENT(INOUT)                :: PartTrajectory(1:3), lengthPartTrajectory, alpha
REAL,INTENT(IN)                   :: xi, eta
INTEGER,INTENT(IN)                :: PartID, SideID
LOGICAL,INTENT(IN)                :: IsSpeciesSwap
INTEGER,INTENT(IN),OPTIONAL       :: BCSideID
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                              :: locBCID, vibQuant, vibQuantNew, VibQuantWall
REAL                                 :: VibQuantNewR                                                !
!REAL,PARAMETER                       :: oneMinus=0.99999999
INTEGER                              :: ElemID
REAL                                 :: v_help(3)
REAL                                 :: oneMinus                
REAL                                 :: VeloReal, RanNum, EtraOld, VeloCrad, Fak_D
REAL                                 :: EtraWall, EtraNew
REAL                                 :: WallVelo(1:3), WallTemp, TransACC, VibACC, RotACC
REAL                                 :: n_loc(1:3), tang1(1:3),tang2(1:3), NewVelo(3)
REAL                                 :: ErotNew, ErotWall, EVibNew, Phi, Cmr, VeloCx, VeloCy, VeloCz
REAL                                 :: Xitild,EtaTild
!REAL                                 :: WallTransACC
INTEGER                              :: p,q, SurfSideID
REAL                                 :: POI_fak, TildPos(3),TildTrajectory(3)
! Polyatomic Molecules
REAL, ALLOCATABLE                    :: RanNumPoly(:), VibQuantNewRPoly(:)
INTEGER                              :: iPolyatMole, iDOF
INTEGER, ALLOCATABLE                 :: VibQuantNewPoly(:), VibQuantWallPoly(:), VibQuantTemp(:)
! REAL, ALLOCATABLE                    :: VecXVibPolyFP(:), VecYVibPolyFP(:), CmrVibPolyFP(:)
! REAL, ALLOCATABLE                    :: EVPolyNewFP(:), EVPolyWallFP(:)
REAL                                 :: ErotOldPoly(3), ErotNewPoly(3), ErotWallPoly(3), CmrRotPoly(3)
!===================================================================================================================================

!OneMinus=1.0-epsInCell

! additional states
locBCID=PartBound%MapToPartBC(BC(SideID))
! get BC values
WallVelo     = PartBound%WallVelo(1:3,locBCID)
WallTemp     = PartBound%WallTemp(locBCID)
TransACC = PartBound%TransACC(locBCID)
VibACC       = PartBound%VibACC(locBCID)
RotACC       = PartBound%RotACC(locBCID)

IF(PRESENT(BCSideID))THEN
  SELECT CASE(SideType(BCSideID))
  CASE(PLANAR_RECT,PLANAR_NONRECT)
    n_loc=SideNormVec(1:3,BCSideID)
    tang1=UNITVECTOR(BezierControlPoints3D(:,NGeo,0,BCSideID)-BezierControlPoints3D(:,0,0,BCSideID))
    tang2=CROSSNORM(n_loc,tang1)
    !tang2=BezierControlPoints3D(:,0,NGeo,BCSideID)-BezierControlPoints3D(:,0,0,BCSideID)
  CASE(BILINEAR)
    CALL CalcNormAndTangBilinear(n_loc,tang1,tang2,xi,eta,BCSideID)
  CASE(CURVED)
    CALL CalcNormAndTangBezier(n_loc,tang1,tang2,xi,eta,BCSideID)
  !   CALL abort(__STAMP__'nvec for bezier not implemented!',999,999.)
  END SELECT 
ELSE
  SELECT CASE(SideType(SideID))
  CASE(PLANAR_RECT,PLANAR_NONRECT)
    n_loc=SideNormVec(1:3,SideID)
    tang1=UNITVECTOR(BezierControlPoints3D(:,NGeo,0,SideID)-BezierControlPoints3D(:,0,0,SideID))
    tang2=CROSSNORM(n_loc,tang1)
    !tang2=BezierControlPoints3D(:,0,NGeo,SideID)-BezierControlPoints3D(:,0,0,SideID)
  CASE(BILINEAR)
    CALL CalcNormAndTangBilinear(n_loc,tang1,tang2,xi,eta,SideID)
  CASE(CURVED)
    CALL CalcNormAndTangBezier(n_loc,tang1,tang2,xi,eta,SideID)
  !   CALL abort(__STAMP__'nvec for bezier not implemented!',999,999.)
  END SELECT 
END IF

IF(DOT_PRODUCT(n_loc,PartTrajectory).LT.0.)  RETURN

! calculate new velocity vector (Extended Maxwellian Model)
VeloReal = SQRT(PartState(PartID,4) * PartState(PartID,4) + &
                PartState(PartID,5) * PartState(PartID,5) + &
                PartState(PartID,6) * PartState(PartID,6))

EtraOld     = 0.5 * Species(PartSpecies(PartID))%MassIC * VeloReal**2 
CALL RANDOM_NUMBER(RanNum)
VeloCrad    = SQRT(-LOG(RanNum))
CALL RANDOM_NUMBER(RanNum)
VeloCz      = SQRT(-LOG(RanNum))
Fak_D       = VeloCrad**2 + VeloCz**2

EtraWall    = BoltzmannConst * WallTemp * Fak_D
EtraNew     = EtraOld + TransACC * (EtraWall - EtraOld)
Cmr         = SQRT(2.0 * EtraNew / (Species(PartSpecies(PartID))%MassIC * Fak_D))
CALL RANDOM_NUMBER(RanNum)
Phi     = 2.0 * PI * RanNum
VeloCx  = Cmr * VeloCrad * COS(Phi) ! tang1
VeloCy  = Cmr * VeloCrad * SIN(Phi) ! tang2
VeloCz  = Cmr * VeloCz

IF ((DSMC%CalcSurfaceVal.AND.(Time.ge.(1-DSMC%TimeFracSamp)*TEnd)).OR.(DSMC%CalcSurfaceVal.AND.WriteMacroValues)) THEN
!----  Sampling for energy (translation) accommodation at walls
! has to be corrected to new scheme
  SurfSideID=SurfMesh%SideIDToSurfID(SideID)
  ! compute p and q
  ! correction of xi and eta, can only be applied if xi & eta are not used later!
  Xitild =MIN(MAX(-1.,XI ),0.99)
  Etatild=MIN(MAX(-1.,Eta),0.99)
  p=INT((Xitild +1.0)/dXiEQ_SurfSample)+1
  q=INT((Etatild+1.0)/dXiEQ_SurfSample)+1

  SampWall(SurfSideID)%State(1,p,q)= SampWall(SurfSideID)%State(1,p,q)+EtraOld       &
                                   *Species(PartSpecies(PartID))%MacroParticleFactor
  SampWall(SurfSideID)%State(2,p,q)= SampWall(SurfSideID)%State(2,p,q)+EtraWall      &
                                   *Species(PartSpecies(PartID))%MacroParticleFactor
  SampWall(SurfSideID)%State(3,p,q)= SampWall(SurfSideID)%State(3,p,q)+EtraNew       &
                                   *Species(PartSpecies(PartID))%MacroParticleFactor
END IF
 
!   Transformation local distribution -> global coordinates
! from flux comutaion
! v = nv*u+t1*v+t2*f3

!NewVelo = VeloCx*tang1+CROSS(-n_loc,tang1)*VeloCy-VeloCz*n_loc
NewVelo = VeloCx*tang1-tang2*VeloCy-VeloCz*n_loc

! intersection point with surface
LastPartPos(PartID,1:3) = LastPartPos(PartID,1:3) + PartTrajectory(1:3)*alpha

ElemID=PartSideToElem(S2E_ELEM_ID,SideID)
v_help=LastPartPos(PartID,1:3)-ElemBaryNGeo(1:3,ElemID)
!LastPartPos(PartID,1:3)=ElemBaryNGeo(1:3,ElemID)+v_help*MAX(1.0-epsInCell/SQRT(DOT_PRODUCT(v_help,v_help)),0.)
LastPartPos(PartID,1:3)=ElemBaryNGeo(1:3,ElemID)+v_help*(1.0-epsInCell)

! recompute initial position and ignoring preceding reflections and trajectory between current position and recomputed position
!TildPos       =PartState(PartID,1:3)-dt*RKdtFrac*PartState(PartID,4:6)
TildTrajectory=dt*RKdtFrac*PartState(PartID,4:6)
POI_fak=1.- (lengthPartTrajectory-alpha)/SQRT(DOT_PRODUCT(TildTrajectory,TildTrajectory))
! travel rest of particle vector
!PartState(PartID,1:3)   = LastPartPos(PartID,1:3) + (1.0 - alpha/lengthPartTrajectory) * dt*RKdtFrac * NewVelo(1:3)
IF (PartBound%Resample(locBCID)) CALL RANDOM_NUMBER(POI_fak) !Resample Equilibirum Distribution
PartState(PartID,1:3)   = LastPartPos(PartID,1:3) + (1.0 - POI_fak) * dt*RKdtFrac * NewVelo(1:3)

!---- Internal energy accommodation
IF (useDSMC) THEN
IF (CollisMode.GT.1) THEN
IF ((SpecDSMC(PartSpecies(PartID))%InterID.EQ.2).OR.(SpecDSMC(PartSpecies(PartID))%InterID.EQ.20)) THEN

  !---- Rotational energy accommodation
! #if (PP_TimeDiscMethod==300)
!   IF(SpecDSMC(PartSpecies(PartID))%PolyatomicMol) THEN
!     iPolyatMole = SpecDSMC(PartSpecies(PartID))%SpecToPolyArray  
!     IF (PolyatomMolDSMC(iPolyatMole)%LinearMolec) THEN
!       ErotOld = PartStateIntEn(PartID,2)
!       VeloCx  = rnor()                !normal distri
!       VeloCy  = rnor()                !normal distri
!       Fak_D       = VeloCx*VeloCx + VeloCy*VeloCy
!       ErotWall    = BoltzmannConst * WallTemp * Fak_D
!       ErotNew = ErotOld + RotACC * (ErotWall - ErotOld)
!       Cmr     = SQRT(ErotNew / (PolyatomMolFP(iPolyatMole)%RotMomDOF(1)* Fak_D))
!     ELSE
!       ErotOldPoly(1)= 0.5*PolyatomMolFP(iPolyatMole)%RotMomDOF(1) & 
!               *FPInnerVelos(PartID)%FP_RotVelo(1)*FPInnerVelos(PartID)%FP_RotVelo(1)
!       ErotOldPoly(2)= 0.5*PolyatomMolFP(iPolyatMole)%RotMomDOF(2) & 
!               *FPInnerVelos(PartID)%FP_RotVelo(2)*FPInnerVelos(PartID)%FP_RotVelo(3)
!       ErotOldPoly(3)= 0.5*PolyatomMolFP(iPolyatMole)%RotMomDOF(3) & 
!               *FPInnerVelos(PartID)%FP_RotVelo(3)*FPInnerVelos(PartID)%FP_RotVelo(3)
!       VeloCx  = rnor()                !normal distri
!       VeloCy  = rnor()                !normal distri
!       VeloCz  = rnor()
!       Fak_D       = PolyatomMolFP(iPolyatMole)%RotMomDOF(1)*VeloCx*VeloCx
!       ErotWallPoly(1)    = BoltzmannConst * WallTemp * Fak_D
!       ErotNewPoly(1) = ErotOldPoly(1) + RotACC * (ErotWallPoly(1) - ErotOldPoly(1))
!       CmrRotPoly(1)     = SQRT(ErotNewPoly(1) / (Fak_D))
!       Fak_D       = PolyatomMolFP(iPolyatMole)%RotMomDOF(2)*VeloCy*VeloCy
!       ErotWallPoly(2)    = BoltzmannConst * WallTemp * Fak_D
!       ErotNewPoly(2) = ErotOldPoly(2) + RotACC * (ErotWallPoly(2) - ErotOldPoly(2))
!       CmrRotPoly(2)     = SQRT(ErotNewPoly(2) / (Fak_D))
!       Fak_D       = PolyatomMolFP(iPolyatMole)%RotMomDOF(3)*VeloCz*VeloCz
!       ErotWallPoly(3)    = BoltzmannConst * WallTemp * Fak_D
!       ErotNewPoly(3) = ErotOldPoly(3) + RotACC * (ErotWallPoly(3) - ErotOldPoly(3))
!       CmrRotPoly(3)     = SQRT(ErotNewPoly(3) / (Fak_D))
!       ErotWall = ErotWallPoly(1) + ErotWallPoly(2) + ErotWallPoly(3)
!       ErotNew = ErotNewPoly(1) + ErotNewPoly(2) + ErotNewPoly(3)
!     END IF
!   ELSE
!      ErotOld = PartStateIntEn(PartID,2)
!      VeloCx  = rnor()                !normal distri
!      VeloCy  = rnor()                !normal distri
!      Fak_D       = VeloCx*VeloCx + VeloCy*VeloCy
!      ErotWall    = BoltzmannConst * WallTemp * Fak_D
!      ErotNew = ErotOld + RotACC * (ErotWall - ErotOld)
!      Cmr     = SQRT(ErotNew / (SpecFP(PartSpecies(PartID))%RotMomentum * Fak_D))
!   END IF
! #else
    CALL RANDOM_NUMBER(RanNum)
    ErotWall = - BoltzmannConst * WallTemp * LOG(RanNum)
    ErotNew  = PartStateIntEn(PartID,2) + RotACC *(ErotWall - PartStateIntEn(PartID,2))
! #endif

    IF ((DSMC%CalcSurfaceVal.AND.(Time.ge.(1-DSMC%TimeFracSamp)*TEnd)).OR.(DSMC%CalcSurfaceVal.AND.WriteMacroValues)) THEN
    !----  Sampling for internal energy accommodation at walls
      SampWall(SurfSideID)%State(4,p,q)=SampWall(SurfSideID)%State(4,p,q)+PartStateIntEn(PartID,2) &
                                                                          *Species(PartSpecies(PartID))%MacroParticleFactor
      SampWall(SurfSideID)%State(5,p,q)=SampWall(SurfSideID)%State(5,p,q)+ErotWall &
                                                                          * Species(PartSpecies(PartID))%MacroParticleFactor
      SampWall(SurfSideID)%State(6,p,q)=SampWall(SurfSideID)%State(6,p,q)+ErotNew &
                                                                          * Species(PartSpecies(PartID))%MacroParticleFactor 
     END IF  

! #if (PP_TimeDiscMethod==300)
!     IF(SpecDSMC(PartSpecies(PartID))%PolyatomicMol) THEN
!       iPolyatMole = SpecDSMC(PartSpecies(PartID))%SpecToPolyArray  
!       IF (PolyatomMolDSMC(iPolyatMole)%LinearMolec) THEN
!        FPInnerVelos(PartID)%FP_RotVelo(1) = Cmr * VeloCx
!        FPInnerVelos(PartID)%FP_RotVelo(2) = Cmr * VeloCy
!       ELSE
!        FPInnerVelos(PartID)%FP_RotVelo(1) = CmrRotPoly(1) * VeloCx
!        FPInnerVelos(PartID)%FP_RotVelo(2) = CmrRotPoly(2) * VeloCy
!        FPInnerVelos(PartID)%FP_RotVelo(3) = CmrRotPoly(3) * VeloCz
!       END IF
!     ELSE
!      FPInnerVelos(PartID)%FP_RotVelo(1) = Cmr * VeloCx
!      FPInnerVelos(PartID)%FP_RotVelo(2) = Cmr * VeloCy
!     END IF
!     PartStateIntEn(PartID,2) = ErotNew   
! #else
    PartStateIntEn(PartID,2) = ErotNew
! #endif

! #if (PP_TimeDiscMethod==300)
!     IF(SpecDSMC(PartSpecies(PartID))%PolyatomicMol) THEN              
!        iPolyatMole = SpecDSMC(PartSpecies(PartID))%SpecToPolyArray
!        ALLOCATE(VecXVibPolyFP(PolyatomMolDSMC(iPolyatMole)%VibDOF), VecYVibPolyFP(PolyatomMolDSMC(iPolyatMole)%VibDOF),&
!            CmrVibPolyFP(PolyatomMolDSMC(iPolyatMole)%VibDOF), EVPolyNewFP(PolyatomMolDSMC(iPolyatMole)%VibDOF), &
!            EVPolyWallFP(PolyatomMolDSMC(iPolyatMole)%VibDOF))
!        DO iDOF = 1, PolyatomMolDSMC(iPolyatMole)%VibDOF
!          EvibOld = 0.5*(FPInnerVelos(PartID)%FP_VibVelo((iDOF-1)*2 +1)*FPInnerVelos(PartID)%FP_VibVelo((iDOF-1)*2 +1) &
!                     + FPInnerVelos(PartID)%FP_VibVelo((iDOF-1)*2 +2)*FPInnerVelos(PartID)%FP_VibVelo((iDOF-1)*2 +2))
!          VecXVibPolyFP(iDOF)  = rnor()                !normal distri
!          VecYVibPolyFP(iDOF)  = rnor()                !normal distri
!          Fak_D       = VecXVibPolyFP(iDOF)*VecXVibPolyFP(iDOF) + VecYVibPolyFP(iDOF)*VecYVibPolyFP(iDOF)
!          EVPolyWallFP(iDOF)   = (BoltzmannConst*PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(iDOF) &
!             /(EXP(PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(iDOF)/WallTemp)-1.)) * Fak_D
!          EVPolyNewFP(iDOF) = EvibOld + VibACC * (EVPolyWallFP(iDOF) - EvibOld)
!          CmrVibPolyFP(iDOF) = SQRT(EVPolyNewFP(iDOF) /Fak_D)
!        END DO
!     ELSE
!        EvibOld = PartStateIntEn(PartID,1) - DSMC%GammaQuant*SpecDSMC(PartSpecies(PartID))%CharaTVib*BoltzmannConst
!        VeloCx  = rnor()                !normal distri
!        VeloCy  = rnor()                !normal distri
!        Fak_D       = VeloCx*VeloCx + VeloCy*VeloCy
!        EVibWall    = (BoltzmannConst*SpecDSMC(PartSpecies(PartID))%CharaTVib &
!           /(EXP(SpecDSMC(PartSpecies(PartID))%CharaTVib/WallTemp)-1.)) * Fak_D
!        EVibNew = EvibOld + VibACC * (EVibWall - EvibOld)
!        Cmr     = SQRT(EvibNew /Fak_D)
!     END IF
! #else
   !---- Vibrational energy accommodation
      IF(SpecDSMC(PartSpecies(PartID))%PolyatomicMol) THEN
        EvibNew = 0.0
        iPolyatMole = SpecDSMC(PartSpecies(PartID))%SpecToPolyArray
        ALLOCATE(RanNumPoly(PolyatomMolDSMC(iPolyatMole)%VibDOF),VibQuantWallPoly(PolyatomMolDSMC(iPolyatMole)%VibDOF), &
                 VibQuantNewRPoly(PolyatomMolDSMC(iPolyatMole)%VibDOF), VibQuantNewPoly(PolyatomMolDSMC(iPolyatMole)%VibDOF), &
                 VibQuantTemp(PolyatomMolDSMC(iPolyatMole)%VibDOF))
        CALL RANDOM_NUMBER(RanNumPoly)
        VibQuantWallPoly(:) = INT(-LOG(RanNumPoly(:)) * WallTemp / PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(:))
        DO WHILE (ALL(VibQuantWallPoly.GE.PolyatomMolDSMC(iPolyatMole)%MaxVibQuantDOF))
          CALL RANDOM_NUMBER(RanNumPoly)
          VibQuantWallPoly(:) = INT(-LOG(RanNumPoly(:)) * WallTemp / PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(:))
        END DO
        VibQuantNewRPoly(:) = VibQuantsPar(PartID)%Quants(:) + VibACC*(VibQuantWallPoly(:) - VibQuantsPar(PartID)%Quants(:))
        VibQuantNewPoly = INT(VibQuantNewRPoly)
        DO iDOF = 1, PolyatomMolDSMC(iPolyatMole)%VibDOF
          CALL RANDOM_NUMBER(RanNum)
          IF (RanNum.LT.(VibQuantNewRPoly(iDOF) - VibQuantNewPoly(iDOF))) THEN
            EvibNew = EvibNew + (VibQuantNewPoly(iDOF) + DSMC%GammaQuant + 1.0d0) &
                      * BoltzmannConst*PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(iDOF)
            VibQuantTemp(iDOF) = VibQuantNewPoly(iDOF) + 1
          ELSE
            EvibNew = EvibNew + (VibQuantNewPoly(iDOF) + DSMC%GammaQuant) &
                      * BoltzmannConst*PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(iDOF)
            VibQuantTemp(iDOF) = VibQuantNewPoly(iDOF)
          END IF
        END DO
      ELSE
        VibQuant     = NINT(PartStateIntEn(PartID,1)/(BoltzmannConst*SpecDSMC(PartSpecies(PartID))%CharaTVib) &
                    - DSMC%GammaQuant)
        CALL RANDOM_NUMBER(RanNum)
        VibQuantWall = INT(-LOG(RanNum) * WallTemp / SpecDSMC(PartSpecies(PartID))%CharaTVib)
        DO WHILE (VibQuantWall.GE.SpecDSMC(PartSpecies(PartID))%MaxVibQuant)
          CALL RANDOM_NUMBER(RanNum)
          VibQuantWall = INT(-LOG(RanNum) * WallTemp / SpecDSMC(PartSpecies(PartID))%CharaTVib)
        END DO
        VibQuantNewR = VibQuant + VibACC*(VibQuantWall - VibQuant)
        VibQuantNew = INT(VibQuantNewR)
        CALL RANDOM_NUMBER(RanNum)
        IF (RanNum.LT.(VibQuantNewR - VibQuantNew)) THEN
          EvibNew = (VibQuantNew + DSMC%GammaQuant + 1.0d0)*BoltzmannConst*SpecDSMC(PartSpecies(PartID))%CharaTVib
        ELSE
          EvibNew = (VibQuantNew + DSMC%GammaQuant)*BoltzmannConst*SpecDSMC(PartSpecies(PartID))%CharaTVib
        END IF
      END IF
! #endif

      IF ((DSMC%CalcSurfaceVal.AND.(Time.ge.(1-DSMC%TimeFracSamp)*TEnd)).OR.(DSMC%CalcSurfaceVal.AND.WriteMacroValues)) THEN
   !----  Sampling for internal energy accommodation at walls
! #if (PP_TimeDiscMethod==300)
!         IF(SpecDSMC(PartSpecies(PartID))%PolyatomicMol) THEN
!           iPolyatMole = SpecDSMC(PartSpecies(PartID))%SpecToPolyArray
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(7) = &
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(7)  &
!                      + PartStateIntEn(PartID,1) * Species(PartSpecies(PartID))%MacroParticleFactor
!           DO iDOF = 1, PolyatomMolDSMC(iPolyatMole)%VibDOF
!             SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(8) = &
!             SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(8) + &
!                     EVPolyWallFP(iDOF)  * Species(PartSpecies(PartID))%MacroParticleFactor
!             SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(9) = &
!             SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(9) + &
!                     EVPolyNewFP(iDOF) * Species(PartSpecies(PartID))%MacroParticleFactor
!           END DO
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(8) = &
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(8) + &
!                   PolyatomMolDSMC(iPolyatMole)%EZeroPoint * Species(PartSpecies(PartID))%MacroParticleFactor
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(9) = &
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(9) + &
!                   PolyatomMolDSMC(iPolyatMole)%EZeroPoint * Species(PartSpecies(PartID))%MacroParticleFactor
!         ELSE
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(7) = &
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(7)  &
!                      + PartStateIntEn(PartID,1) * Species(PartSpecies(PartID))%MacroParticleFactor
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(8) = &
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(8) + (EVibWall + DSMC%GammaQuant &
!                      * BoltzmannConst * SpecDSMC(PartSpecies(PartID))%CharaTVib) * Species(PartSpecies(PartID))%MacroParticleFactor
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(9) = &
!           SampWall(SurfMesh%GlobSideToSurfSideMap(ElemToSide(1,iLocSide,Element)))%Energy(9) &
!                      + (EvibNew + DSMC%GammaQuant*SpecDSMC(PartSpecies(PartID))%CharaTVib*BoltzmannConst) &
!                     * Species(PartSpecies(PartID))%MacroParticleFactor
!         END IF
! #else
        IF(SpecDSMC(PartSpecies(PartID))%PolyatomicMol) THEN
          iPolyatMole = SpecDSMC(PartSpecies(PartID))%SpecToPolyArray
          DO iDOF = 1, PolyatomMolDSMC(iPolyatMole)%VibDOF
            SampWall(SurfSideID)%State(7,p,q)= SampWall(SurfSideID)%State(7,p,q) &
                    + (VibQuantsPar(PartID)%Quants(iDOF) + DSMC%GammaQuant) * BoltzmannConst &
                    * PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(iDOF) * Species(PartSpecies(PartID))%MacroParticleFactor
            SampWall(SurfSideID)%State(8,p,q)= SampWall(SurfSideID)%State(8,p,q) + VibQuantWall &
                    * BoltzmannConst * SpecDSMC(PartSpecies(PartID))%CharaTVib * Species(PartSpecies(PartID))%MacroParticleFactor
          END DO
        ELSE
          SampWall(SurfSideID)%State(7,p,q)= SampWall(SurfSideID)%State(7,p,q) + (VibQuant + DSMC%GammaQuant) &
                  * BoltzmannConst * SpecDSMC(PartSpecies(PartID))%CharaTVib * Species(PartSpecies(PartID))%MacroParticleFactor
          SampWall(SurfSideID)%State(8,p,q)= SampWall(SurfSideID)%State(8,p,q) + VibQuantWallPoly(iDOF) * BoltzmannConst &
                       * PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(iDOF) * Species(PartSpecies(PartID))%MacroParticleFactor
        END IF
        SampWall(SurfSideID)%State(9,p,q)= SampWall(SurfSideID)%State(9,p,q) + &
                                            EvibNew * Species(PartSpecies(PartID))%MacroParticleFactor
! #endif
      END IF     
! #if (PP_TimeDiscMethod==300)
!      IF(SpecDSMC(PartSpecies(PartID))%PolyatomicMol) THEN
!        iPolyatMole = SpecDSMC(PartSpecies(PartID))%SpecToPolyArray
!        PartStateIntEn(PartID,1) = 0.0
!        DO iDOF = 1, PolyatomMolDSMC(iPolyatMole)%VibDOF
!         FPInnerVelos(PartID)%FP_VibVelo((iDOF-1)*2 +1) = CmrVibPolyFP(iDOF) * VecXVibPolyFP(iDOF)
!         FPInnerVelos(PartID)%FP_VibVelo((iDOF-1)*2 +2) = CmrVibPolyFP(iDOF) * VecYVibPolyFP(iDOF)
!         PartStateIntEn(PartID,1) = PartStateIntEn(PartID,1) + EVPolyNewFP(iDOF)
!        END DO
!        PartStateIntEn(PartID,1) = PartStateIntEn(PartID,1) + PolyatomMolDSMC(iPolyatMole)%EZeroPoint
!      ELSE
!        FPInnerVelos(PartID)%FP_VibVelo(1) = Cmr * VeloCx
!        FPInnerVelos(PartID)%FP_VibVelo(2) = Cmr * VeloCy
!        PartStateIntEn(PartID,1) = EvibNew + DSMC%GammaQuant*SpecDSMC(PartSpecies(PartID))%CharaTVib*BoltzmannConst
!      END IF
! #else
      IF(SpecDSMC(PartSpecies(PartID))%PolyatomicMol) VibQuantsPar(PartID)%Quants(:) = VibQuantTemp(:)
      PartStateIntEn(PartID,1) = EvibNew
! #endif
    END IF
    END IF ! CollisMode > 1
    END IF ! useDSMC

IF ((DSMC%CalcSurfaceVal.AND.(Time.GE.(1.-DSMC%TimeFracSamp)*TEnd)).OR.(DSMC%CalcSurfaceVal.AND.WriteMacroValues)) THEN
!----  Sampling force at walls
  SampWall(SurfSideID)%State(10,p,q)= SampWall(SurfSideID)%State(10,p,q) &
      + Species(PartSpecies(PartID))%MassIC * (PartState(PartID,4) - NewVelo(1)) * Species(PartSpecies(PartID))%MacroParticleFactor
  SampWall(SurfSideID)%State(11,p,q)= SampWall(SurfSideID)%State(11,p,q) &
      + Species(PartSpecies(PartID))%MassIC * (PartState(PartID,5) - NewVelo(2)) * Species(PartSpecies(PartID))%MacroParticleFactor
  SampWall(SurfSideID)%State(12,p,q)= SampWall(SurfSideID)%State(12,p,q) &
      + Species(PartSpecies(PartID))%MassIC * (PartState(PartID,6) - NewVelo(3)) * Species(PartSpecies(PartID))%MacroParticleFactor
 !---- Counter for collisions (normal wall collisions - not to count if only SpeciesSwaps to be counted)
  IF (.NOT.DSMC%CalcSurfCollis_OnlySwaps .AND. .NOT.IsSpeciesSwap) THEN
    SampWall(SurfSideID)%State(12+PartSpecies(PartID),p,q)= SampWall(SurfSideID)%State(12+PartSpecies(PartID),p,q) +1
    IF (DSMC%AnalyzeSurfCollis) THEN
      AnalyzeSurfCollis%Number(PartSpecies(PartID)) = AnalyzeSurfCollis%Number(PartSpecies(PartID)) + 1
      AnalyzeSurfCollis%Number(nSpecies+1) = AnalyzeSurfCollis%Number(nSpecies+1) + 1
      IF (AnalyzeSurfCollis%Number(nSpecies+1) .GT. AnalyzeSurfCollis%maxPartNumber) THEN
CALL Abort(&
__STAMP__&
,'maxSurfCollisNumber reached!')
      END IF
      AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),1:3) &
        = LastPartPos(PartID,1:3) + alpha * PartTrajectory(1:3)
      AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),4) &
        = PartState(PartID,4)
      AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),5) &
        = PartState(PartID,5)
      AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),6) &
        = PartState(PartID,6)
      AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),7) &
        = LastPartPos(PartID,1)
      AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),8) &
        = LastPartPos(PartID,2)
      AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),9) &
        = LastPartPos(PartID,3)
      AnalyzeSurfCollis%Spec(AnalyzeSurfCollis%Number(nSpecies+1)) &
        = PartSpecies(PartID)
    END IF
  END IF
END IF
!----  saving new particle velocity
PartState(PartID,4:6)   = NewVelo(1:3) + WallVelo(1:3)

! recompute trajectory etc
PartTrajectory=PartState(PartID,1:3) - LastPartPos(PartID,1:3)
lengthPartTrajectory=SQRT(PartTrajectory(1)*PartTrajectory(1) &
                         +PartTrajectory(2)*PartTrajectory(2) &
                         +PartTrajectory(3)*PartTrajectory(3) )
PartTrajectory=PartTrajectory/lengthPartTrajectory
!lengthPartTrajectory=lengthPartTrajectory!+epsilontol

#if defined(LSERK)
PDM%IsNewPart(PartID)=.TRUE. !reconstruction in timedisc during push
#endif

END SUBROUTINE DiffuseReflection

SUBROUTINE SpeciesSwap(PartTrajectory,lengthPartTrajectory,alpha,xi,eta,PartID,GlobSideID,IsSpeciesSwap,BCSideID)
!----------------------------------------------------------------------------------------------------------------------------------!
! Computes the Species Swap on ReflectiveBC
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals,                ONLY:abort
USE MOD_Particle_Boundary_Vars, ONLY:PartBound,SampWall,dXiEQ_SurfSample,SurfMesh
USE MOD_Particle_Vars,          ONLY:PartState,LastPartPos,PartSpecies,PDM
USE MOD_Particle_Vars,          ONLY:WriteMacroValues,nSpecies
USE MOD_Particle_Analyze_Vars,  ONLY:CalcPartBalance,nPartOut,PartEkinOut
USE MOD_Particle_Analyze,       ONLY: CalcEkinPart
USE MOD_Mesh_Vars,              ONLY:BC
USE MOD_DSMC_Vars,              ONLY:DSMC
USE MOD_DSMC_Vars,              ONLY:AnalyzeSurfCollis
USE MOD_TimeDisc_Vars,          ONLY:TEnd,Time
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT VARIABLES 
REAL,INTENT(INOUT)                :: PartTrajectory(1:3), lengthPartTrajectory, alpha
REAL,INTENT(IN)                   :: xi, eta
INTEGER,INTENT(IN)                :: PartID, GlobSideID
INTEGER,INTENT(IN),OPTIONAL       :: BCSideID
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
LOGICAL,INTENT(INOUT)             :: IsSpeciesSwap
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                           :: targetSpecies, iSwaps
REAL                              :: RanNum
REAL                              :: Xitild,EtaTild
INTEGER                           :: p,q,SurfSideID
!===================================================================================================================================

CALL RANDOM_NUMBER(RanNum)
IF(RanNum.LE.PartBound%ProbOfSpeciesSwaps(PartBound%MapToPartBC(BC(GlobSideID)))) THEN
  targetSpecies=-1 !dummy init value
  DO iSwaps=1,PartBound%NbrOfSpeciesSwaps(PartBound%MapToPartBC(BC(GlobSideID)))
  IF (PartSpecies(PartID).eq.PartBound%SpeciesSwaps(1,iSwaps,PartBound%MapToPartBC(BC(GlobSideID)))) &
    targetSpecies = PartBound%SpeciesSwaps(2,iSwaps,PartBound%MapToPartBC(BC(GlobSideID)))
  END DO
  !swap species
  IF (targetSpecies.ge.0) IsSpeciesSwap=.TRUE.
  IF ( (targetSpecies.eq.0) .OR. (.NOT.DSMC%CalcSurfCollis_Only0Swaps) ) THEN
    IF ((DSMC%CalcSurfaceVal.AND.(Time.ge.(1-DSMC%TimeFracSamp)*TEnd)) &
      .OR.(DSMC%CalcSurfaceVal.AND.WriteMacroValues)) THEN
      !---- Counter for swap species collisions
      SurfSideID=SurfMesh%SideIDToSurfID(GlobSideID)
      ! compute p and q
      ! correction of xi and eta, can only be applied if xi & eta are not used later!
      Xitild =MIN(MAX(-1.,xi ),0.99)
      Etatild=MIN(MAX(-1.,eta),0.99)
      p=INT((Xitild +1.0)/dXiEQ_SurfSample)+1
      q=INT((Etatild+1.0)/dXiEQ_SurfSample)+1
      SampWall(SurfSideID)%State(12+PartSpecies(PartID),p,q) = SampWall(SurfSideID)%State(12+PartSpecies(PartID),p,q) + 1
      IF (DSMC%AnalyzeSurfCollis) THEN
        AnalyzeSurfCollis%Number(PartSpecies(PartID)) = AnalyzeSurfCollis%Number(PartSpecies(PartID)) + 1
        AnalyzeSurfCollis%Number(nSpecies+1) = AnalyzeSurfCollis%Number(nSpecies+1) + 1
        IF (AnalyzeSurfCollis%Number(nSpecies+1) .GT. AnalyzeSurfCollis%maxPartNumber) THEN
CALL Abort(&
__STAMP__&
,'maxSurfCollisNumber reached!')
        END IF
        AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),1:3) &
          = LastPartPos(PartID,1:3) + alpha * PartTrajectory(1:3)
        AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),4) &
          = PartState(PartID,4)
        AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),5) &
          = PartState(PartID,5)
        AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),6) &
          = PartState(PartID,6)
        AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),7) &
          = LastPartPos(PartID,1)
        AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),8) &
          = LastPartPos(PartID,2)
        AnalyzeSurfCollis%Data(AnalyzeSurfCollis%Number(nSpecies+1),9) &
          = LastPartPos(PartID,3)
        AnalyzeSurfCollis%Spec(AnalyzeSurfCollis%Number(nSpecies+1)) &
          = PartSpecies(PartID)
      END IF
    END IF
  END IF
  IF (targetSpecies.eq.0) THEN !delete particle -> same as PartBound%OpenBC
    IF(CalcPartBalance) THEN
      nPartOut(PartSpecies(PartID))=nPartOut(PartSpecies(PartID)) + 1
      PartEkinOut(PartSpecies(PartID))=PartEkinOut(PartSpecies(PartID))+CalcEkinPart(PartID)
    END IF ! CalcPartBalance
    PDM%ParticleInside(PartID) = .FALSE.
    alpha=-1.
  ELSEIF (targetSpecies.gt.0) THEN !swap species
    PartSpecies(PartID)=targetSpecies
  END IF
END IF
END SUBROUTINE SpeciesSwap

END MODULE MOD_Particle_Boundary_Condition
