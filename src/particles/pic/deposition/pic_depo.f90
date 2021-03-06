!==================================================================================================================================
! Copyright (c) 2010 - 2018 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
!
! This file is part of PICLas (gitlab.com/piclas/piclas). PICLas is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3
! of the License, or (at your option) any later version.
!
! PICLas is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with PICLas. If not, see <http://www.gnu.org/licenses/>.
!==================================================================================================================================
#include "piclas.h"

MODULE MOD_PICDepo
!===================================================================================================================================
! MOD PIC Depo
!===================================================================================================================================
 IMPLICIT NONE
 PRIVATE
!===================================================================================================================================
INTERFACE Deposition
  MODULE PROCEDURE Deposition
END INTERFACE

INTERFACE InitializeDeposition
  MODULE PROCEDURE InitializeDeposition
END INTERFACE

INTERFACE FinalizeDeposition
  MODULE PROCEDURE FinalizeDeposition
END INTERFACE

PUBLIC:: Deposition, InitializeDeposition, FinalizeDeposition
!===================================================================================================================================

CONTAINS

SUBROUTINE InitializeDeposition
!===================================================================================================================================
! Initialize the deposition variables first
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PICDepo_Vars
USE MOD_PICDepo_Tools          ,ONLY: CalcCellLocNodeVolumes,ReadTimeAverage,beta,DeBoor
USE MOD_Particle_Vars
USE MOD_Globals_Vars           ,ONLY: PI
USE MOD_Mesh_Vars              ,ONLY: nElems, XCL_NGeo,Elem_xGP, sJ,nGlobalElems, nNodes
USE MOD_Particle_Mesh_Vars     ,ONLY: Geo, FindNeighbourElems
USE MOD_Interpolation_Vars     ,ONLY: xGP,wBary,wGP
USE MOD_Basis                  ,ONLY: ComputeBernsteinCoeff
USE MOD_Basis                  ,ONLY: BarycentricWeights,InitializeVandermonde
USE MOD_Basis                  ,ONLY: LegendreGaussNodesAndWeights,LegGaussLobNodesAndWeights
USE MOD_ChangeBasis            ,ONLY: ChangeBasis3D
USE MOD_Preproc
USE MOD_ReadInTools            ,ONLY: GETREAL,GETINT,GETLOGICAL,GETSTR,GETREALARRAY,GETINTARRAY
USE MOD_PICInterpolation_Vars  ,ONLY: InterpolationType
USE MOD_Eval_xyz               ,ONLY: GetPositionInRefElem
USE MOD_Particle_Tracking_Vars ,ONLY: DoRefMapping
#if USE_MPI
USE MOD_Particle_MPI_Vars      ,ONLY: DoExternalParts
#endif
USE MOD_ReadInTools            ,ONLY: PrintOption
#if USE_MPI
USE MOD_PICDepo_MPI            ,ONLY: MPIBackgroundMeshInit
#endif /*USE_MPI*/
USE MOD_Interpolation_Vars     ,ONLY: NodeTypeVISU,NodeType
USE MOD_Interpolation          ,ONLY: GetVandermonde
USE MOD_Mesh_Vars              ,ONLY: Vdm_EQ_N
USE MOD_Dielectric_Vars        ,ONLY: DoDielectricSurfaceCharge
USE MOD_PICDepo_Method         ,ONLY: InitDepositionMethod
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,ALLOCATABLE          :: wBary_tmp(:),Vdm_GaussN_EquiN(:,:), Vdm_GaussN_NDepo(:,:)
REAL,ALLOCATABLE          :: dummy(:,:,:,:),dummy2(:,:,:,:),xGP_tmp(:),wGP_tmp(:)
INTEGER                   :: ALLOCSTAT, iElem, i, j, k, m, dir, weightrun, r, s, t, iSFfix, iPoint, iVec, iBC, kk, ll, mm
REAL                      :: MappedGauss(1:PP_N+1), xmin, ymin, zmin, xmax, ymax, zmax, x0
REAL                      :: auxiliary(0:3),weight(1:3,0:3), VolumeShapeFunction, r_sf_average
REAL                      :: DetLocal(1,0:PP_N,0:PP_N,0:PP_N), DetJac(1,0:1,0:1,0:1)
REAL, ALLOCATABLE         :: Vdm_tmp(:,:)
REAL                      :: SFdepoLayersCross(3),BaseVector(3),BaseVector2(3),SFdepoLayersChargedens,n1(3),n2(3),nhalf
REAL                      :: NormVecCheck(3),eps,diff,BoundPoints(3,8),BVlengths(2),DistVec(3),Dist(3)
CHARACTER(32)             :: hilf, hilf2
CHARACTER(255)            :: TimeAverageFile
LOGICAL                   :: LayerOutsideOfBounds, ChangeOccured
REAL                      :: dimFactorSF
INTEGER                   :: nTotalDOF
!===================================================================================================================================

SWRITE(UNIT_stdOut,'(A)') ' INIT PARTICLE DEPOSITION...'
#if USE_MPI
  DoExternalParts=.FALSE. ! Initialize
#endif /*USE_MPI*/

DoDeposition = GETLOGICAL('PIC-DoDeposition','T')
IF(.NOT.DoDeposition) THEN
  ! fill deposition type with emtpy string
  DepositionType='NONE'
  OutputSource=.FALSE.
  RelaxDeposition=.FALSE.
  RETURN
END IF

! Initialize Deposition
CALL InitDepositionMethod()

!--- Allocate arrays for charge density collection and initialize
ALLOCATE(PartSource(1:4,0:PP_N,0:PP_N,0:PP_N,nElems),STAT=ALLOCSTAT)
IF (ALLOCSTAT.NE.0) THEN
  CALL abort(&
  __STAMP__&
  ,'ERROR in pic_depo.f90: Cannot allocate PartSource!')
END IF
PartSource=0.
PartSourceConstExists=.FALSE.

!--- check if relaxation of current PartSource with RelaxFac into PartSourceOld
RelaxDeposition = GETLOGICAL('PIC-RelaxDeposition','F')
IF (RelaxDeposition) THEN
  RelaxFac     = GETREAL('PIC-RelaxFac','0.001')
#if ((USE_HDG) && (PP_nVar==1))
  ALLOCATE(PartSourceOld(1,1:2,0:PP_N,0:PP_N,0:PP_N,nElems),STAT=ALLOCSTAT)
#else
  ALLOCATE(PartSourceOld(1:4,1:2,0:PP_N,0:PP_N,0:PP_N,nElems),STAT=ALLOCSTAT)
#endif
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
__STAMP__&
,'ERROR in pic_depo.f90: Cannot allocate PartSourceOld!')
  END IF
  PartSourceOld=0.
  OutputSource = .TRUE.
ELSE
  OutputSource = GETLOGICAL('PIC-OutputSource','F')
END IF

!--- check if chargedensity is computed from TimeAverageFile
TimeAverageFile = GETSTR('PIC-TimeAverageFile','none')
IF (TRIM(TimeAverageFile).NE.'none') THEN
  CALL ReadTimeAverage(TimeAverageFile)
  IF (.NOT.RelaxDeposition) THEN
  !-- switch off deposition: use only the read PartSource
    DoDeposition=.FALSE.
    DepositionType='constant'
    RETURN
  ELSE
  !-- use read PartSource as initialValue for relaxation
  !-- CAUTION: will be overwritten by DG_Source if present in restart-file!
    DO iElem = 1, nElems
      DO kk = 0, PP_N
        DO ll = 0, PP_N
          DO mm = 0, PP_N
#if ((USE_HDG) && (PP_nVar==1))
            PartSourceOld(1,1,mm,ll,kk,iElem) = PartSource(4,mm,ll,kk,iElem)
            PartSourceOld(1,2,mm,ll,kk,iElem) = PartSource(4,mm,ll,kk,iElem)
#else
            PartSourceOld(1:4,1,mm,ll,kk,iElem) = PartSource(1:4,mm,ll,kk,iElem)
            PartSourceOld(1:4,2,mm,ll,kk,iElem) = PartSource(1:4,mm,ll,kk,iElem)
#endif
          END DO !mm
        END DO !ll
      END DO !kk
    END DO !iElem
  END IF
END IF


! e.g. 'shape_function', 'shape_function_1d', 'shape_function_cylindrical', 'shape_function_spherical', 'shape_function_simple'
IF(TRIM(DepositionType(1:MIN(14,LEN(TRIM(ADJUSTL(DepositionType)))))).EQ.'shape_function')THEN
  r_sf                  = GETREAL('PIC-shapefunction-radius')
  alpha_sf              = GETINT('PIC-shapefunction-alpha')
  DoSFEqui              = GETLOGICAL('PIC-shapefunction-equi')
  DoSFLocalDepoAtBounds = GETLOGICAL('PIC-shapefunction-local-depo-BC')
  r2_sf = r_sf * r_sf  ! Radius squared
  r2_sf_inv = 1./r2_sf ! Inverse of radius squared


  IF(DoSFLocalDepoAtBounds)THEN ! init cell vol weight
    IF(.NOT.TRIM(DepositionType).EQ.'shape_function_2d') CALL abort(&
        __STAMP__&
        ,' PIC-shapefunction-local-depo-BC=T is currently only implemented for shape_function_2d!')
    ALLOCATE(CellVolWeightFac(0:PP_N),wGP_tmp(0:PP_N) , xGP_tmp(0:PP_N))
    ALLOCATE(CellVolWeight_Volumes(0:1,0:1,0:1,nElems))
    CellVolWeightFac(0:PP_N) = xGP(0:PP_N)
    CellVolWeightFac(0:PP_N) = (CellVolWeightFac(0:PP_N)+1.0)/2.0
    CALL LegendreGaussNodesAndWeights(1,xGP_tmp,wGP_tmp)
    ALLOCATE( Vdm_tmp(0:1,0:PP_N))
    CALL InitializeVandermonde(PP_N,1,wBary,xGP,xGP_tmp,Vdm_tmp)
    DO iElem=1, nElems
      DO k=0,PP_N
        DO j=0,PP_N
          DO i=0,PP_N
            DetLocal(1,i,j,k)=1./sJ(i,j,k,iElem)
          END DO ! i=0,PP_N
        END DO ! j=0,PP_N
      END DO ! k=0,PP_N
      CALL ChangeBasis3D(1,PP_N, 1,Vdm_tmp, DetLocal(:,:,:,:),DetJac(:,:,:,:))
      DO k=0,1
        DO j=0,1
          DO i=0,1
            CellVolWeight_Volumes(i,j,k,iElem) = DetJac(1,i,j,k)*wGP_tmp(i)*wGP_tmp(j)*wGP_tmp(k)
          END DO ! i=0,PP_N
        END DO ! j=0,PP_N
      END DO ! k=0,PP_N
    END DO
    DEALLOCATE(Vdm_tmp)
    DEALLOCATE(wGP_tmp, xGP_tmp)
  END IF



END IF

!--- init DepositionType-specific vars
SELECT CASE(TRIM(DepositionType))
CASE('nearest_blurrycenter')
CASE('nearest_blurycenter')
  DepositionType = 'nearest_blurrycenter'
CASE('cell_volweight')
  ALLOCATE(CellVolWeightFac(0:PP_N),wGP_tmp(0:PP_N) , xGP_tmp(0:PP_N))
  ALLOCATE(CellVolWeight_Volumes(0:1,0:1,0:1,nElems))
  CellVolWeightFac(0:PP_N) = xGP(0:PP_N)
  CellVolWeightFac(0:PP_N) = (CellVolWeightFac(0:PP_N)+1.0)/2.0
  CALL LegendreGaussNodesAndWeights(1,xGP_tmp,wGP_tmp)
  ALLOCATE( Vdm_tmp(0:1,0:PP_N))
  CALL InitializeVandermonde(PP_N,1,wBary,xGP,xGP_tmp,Vdm_tmp)
  DO iElem=1, nElems
    DO k=0,PP_N
      DO j=0,PP_N
        DO i=0,PP_N
          DetLocal(1,i,j,k)=1./sJ(i,j,k,iElem)
        END DO ! i=0,PP_N
      END DO ! j=0,PP_N
    END DO ! k=0,PP_N
    CALL ChangeBasis3D(1,PP_N, 1,Vdm_tmp, DetLocal(:,:,:,:),DetJac(:,:,:,:))
    DO k=0,1
      DO j=0,1
        DO i=0,1
          CellVolWeight_Volumes(i,j,k,iElem) = DetJac(1,i,j,k)*wGP_tmp(i)*wGP_tmp(j)*wGP_tmp(k)
        END DO ! i=0,PP_N
      END DO ! j=0,PP_N
    END DO ! k=0,PP_N
  END DO
  DEALLOCATE(Vdm_tmp)
  DEALLOCATE(wGP_tmp, xGP_tmp)
CASE('cell_volweight_mean', 'cell_volweight_mean2')
  IF ((TRIM(InterpolationType).NE.'cell_volweight')) THEN
    ALLOCATE(CellVolWeightFac(0:PP_N))
    CellVolWeightFac(0:PP_N) = xGP(0:PP_N)
    CellVolWeightFac(0:PP_N) = (CellVolWeightFac(0:PP_N)+1.0)/2.0
  END IF
  ALLOCATE(CellLocNodes_Volumes(nNodes))
  CALL CalcCellLocNodeVolumes()
  FindNeighbourElems = .TRUE.

  ! Additional source for cell_volweight_mean (external or surface charge)
  IF(DoDielectricSurfaceCharge)THEN
    ALLOCATE(NodeSourceExt(1:nNodes))
    NodeSourceExt = 0.0
    ALLOCATE(NodeSourceExtTmp(1:nNodes))
    NodeSourceExtTmp = 0.0
  END IF ! DoDielectricSurfaceCharge

  ! Allocate and determine Vandermonde mapping from equidistant (visu) to NodeType node set
  ALLOCATE(Vdm_EQ_N(0:PP_N,0:1))
  CALL GetVandermonde(1, NodeTypeVISU, PP_N, NodeType, Vdm_EQ_N, modal=.FALSE.)

CASE('epanechnikov')
  r_sf     = GETREAL('PIC-epanechnikov-radius','1.')
  r2_sf = r_sf * r_sf
  ALLOCATE( tempcharge(1:nElems))
CASE('nearest_gausspoint')
  ! Allocate array for particle positions in -1|1 space (used for deposition as well as interpolation)
  ! only if NOT DoRefMapping
  IF(.NOT.DoRefMapping)THEN
    ALLOCATE(PartPosRef(1:3,PDM%MaxParticleNumber), STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) CALL abort(&
    __STAMP__&
    ,' Cannot allocate partposref!')
  END IF
  ! compute the borders of the virtual volumes around the gauss points in -1|1 space
  ALLOCATE(GaussBorder(1:PP_N),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
    __STAMP__&
    ,'ERROR in pic_depo.f90: Cannot allocate Mapped Gauss Border Coords!')
  END IF
  DO i=0,PP_N
    ! bullshit here, use xGP
    !CALL GetPositionInRefElem(Elem_xGP(:,i,1,1,1),Temp(:),1)
    !MappedGauss(i+1) = Temp(1)
    MappedGauss(i+1) = xGP(i)
  END DO
  DO i = 1,PP_N
    GaussBorder(i) = (MappedGauss(i+1) + MappedGauss(i))/2
  END DO
  ! allocate array for saving the gauss points of particles for nearest_gausspoint interpolation
  IF(TRIM(InterpolationType).EQ.'nearest_gausspoint')THEN
    SDEALLOCATE(PartPosGauss)
    ALLOCATE(PartPosGauss(1:PDM%maxParticleNumber,1:3),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(&
      __STAMP__&
      ,'ERROR in pic_depo.f90: Cannot allocate Part Pos Gauss!')
    END IF
  END IF
CASE('shape_function','shape_function_simple')
#if USE_MPI
  DoExternalParts=.TRUE.
#endif /*USE_MPI*/
  !ALLOCATE(PartToFIBGM(1:6,1:PDM%maxParticleNumber),STAT=ALLOCSTAT)
  !IF (ALLOCSTAT.NE.0) CALL abort(&
  !    __STAMP__&
  !    ' Cannot allocate PartToFIBGM!')
  !ALLOCATE(ExtPartToFIBGM(1:6,1:PDM%ParticleVecLength),STAT=ALLOCSTAT)
  !IF (ALLOCSTAT.NE.0) THEN
  !  CALL abort(__STAMP__&
  !    ' Cannot allocate ExtPartToFIBGM!')
  BetaFac = beta(1.5, REAL(alpha_sf) + 1.)
  w_sf = 1./(2. * BetaFac * REAL(alpha_sf) + 2 * BetaFac) &
                        * (REAL(alpha_sf) + 1.)/(PI*(r_sf**3))
  !-- fixes for shape func depo at planar BCs
  NbrOfSFdepoFixes = GETINT('PIC-NbrOfSFdepoFixes','0')
  PrintSFDepoWarnings=GETLOGICAL('PrintSFDepoWarnings','.FALSE.')
  IF (NbrOfSFdepoFixes.GT.0) THEN
    SFdepoFixesEps = GETREAL('PIC-SFdepoFixesEps','0.')
    SDEALLOCATE(SFdepoFixesGeo)
    SDEALLOCATE(SFdepoFixesChargeMult)
    SDEALLOCATE(SFdepoFixesPartOfLink)
    SDEALLOCATE(SFdepoFixesBounds)
    ALLOCATE(SFdepoFixesGeo(1:NbrOfSFdepoFixes,1:2,1:3),STAT=ALLOCSTAT)  !1:nFixes;1:2(base,normal);1:3(x,y,z)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(&
      __STAMP__&
      ,'ERROR in pic_depo.f90: Cannot allocate SFdepoFixesGeo!')
    END IF
    ALLOCATE(SFdepoFixesChargeMult(1:NbrOfSFdepoFixes),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(&
      __STAMP__&
      ,'ERROR in pic_depo.f90: Cannot allocate SFdepoFixesChargeMult!')
    END IF
    ALLOCATE(SFdepoFixesPartOfLink(0:NbrOfSFdepoFixes),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoFixesPartOfLink!')
    END IF
    SFdepoFixesPartOfLink=.FALSE.
    ALLOCATE(SFdepoFixesBounds(1:NbrOfSFdepoFixes,1:2,1:3),STAT=ALLOCSTAT)  !1:nFixes;1:2(min,max);1:3(x,y,z)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(&
      __STAMP__&
      ,'ERROR in pic_depo.f90: Cannot allocate SFdepoFixesBounds!')
    END IF
    DO iSFfix=1,NbrOfSFdepoFixes
      WRITE(UNIT=hilf,FMT='(I0)') iSFfix
      SFdepoFixesGeo(iSFfix,1,1:3) = &
        GETREALARRAY('PIC-SFdepoFixes'//TRIM(hilf)//'-Basepoint',3,'0. , 0. , 0.')
      SFdepoFixesGeo(iSFfix,2,1:3) = &
        GETREALARRAY('PIC-SFdepoFixes'//TRIM(hilf)//'-Normal',3,'1. , 0. , 0.') !directed outwards
      IF (SFdepoFixesGeo(iSFfix,2,1)**2 + SFdepoFixesGeo(iSFfix,2,2)**2 + SFdepoFixesGeo(iSFfix,2,3)**2 .GT. 0.) THEN
        SFdepoFixesGeo(iSFfix,2,1:3) = SFdepoFixesGeo(iSFfix,2,1:3) &
          / SQRT(SFdepoFixesGeo(iSFfix,2,1)**2 + SFdepoFixesGeo(iSFfix,2,2)**2 + SFdepoFixesGeo(iSFfix,2,3)**2)
      ELSE
        CALL abort(&
      __STAMP__&
      ,' SFdepoFixesXX-Normal is zero for Fix ',iSFfix)
      END IF
      SFdepoFixesChargeMult(iSFfix) = &
        GETREAL('PIC-SFdepoFixes'//TRIM(hilf)//'-ChargeMult','1.')
      WRITE(UNIT=hilf2,FMT='(E16.8)') -HUGE(1.0)
      SFdepoFixesBounds(iSFfix,1,1)   = GETREAL('PIC-SFdepoFixes'//TRIM(hilf)//'-xmin',TRIM(hilf2))
      SFdepoFixesBounds(iSFfix,1,2)   = GETREAL('PIC-SFdepoFixes'//TRIM(hilf)//'-ymin',TRIM(hilf2))
      SFdepoFixesBounds(iSFfix,1,3)   = GETREAL('PIC-SFdepoFixes'//TRIM(hilf)//'-zmin',TRIM(hilf2))
      WRITE(UNIT=hilf2,FMT='(E16.8)') HUGE(1.0)
      SFdepoFixesBounds(iSFfix,2,1)   = GETREAL('PIC-SFdepoFixes'//TRIM(hilf)//'-xmax',TRIM(hilf2))
      SFdepoFixesBounds(iSFfix,2,2)   = GETREAL('PIC-SFdepoFixes'//TRIM(hilf)//'-ymax',TRIM(hilf2))
      SFdepoFixesBounds(iSFfix,2,3)   = GETREAL('PIC-SFdepoFixes'//TRIM(hilf)//'-zmax',TRIM(hilf2))
    END DO
    NbrOfSFdepoFixLinks = GETINT('PIC-NbrOfSFdepoFixLinks','0')
    IF (NbrOfSFdepoFixLinks.GT.0) THEN
      SDEALLOCATE(SFdepoFixLinks)
      ALLOCATE(SFdepoFixLinks(1:NbrOfSFdepoFixLinks,1:3),STAT=ALLOCSTAT)
      IF (ALLOCSTAT.NE.0) THEN
        CALL abort(&
          __STAMP__&
          ,'ERROR in pic_depo.f90: Cannot allocate SFdepoFixesChargeMult!')
      END IF
      DO iSFfix=1,NbrOfSFdepoFixLinks
        WRITE(UNIT=hilf,FMT='(I0)') iSFfix
        SFdepoFixLinks(iSFfix,1:2) = &
          GETINTARRAY('PIC-SFdepoFixLink'//TRIM(hilf),2,'1 , 2')
        IF (   SFdepoFixLinks(iSFfix,1).GT.NbrOfSFdepoFixes &
          .OR. SFdepoFixLinks(iSFfix,2).GT.NbrOfSFdepoFixes &
          .OR. SFdepoFixLinks(iSFfix,1).LE.0 &
          .OR. SFdepoFixLinks(iSFfix,2).LE.0) THEN
          CALL abort(&
            __STAMP__&
            ,' SFdepoFixes not defined for Link ',iSFfix)
        ELSE
          SFdepoFixesPartOfLink(SFdepoFixLinks(iSFfix,1))=.TRUE.
          n1=SFdepoFixesGeo(SFdepoFixLinks(iSFfix,1),2,1:3)
          SFdepoFixesPartOfLink(SFdepoFixLinks(iSFfix,2))=.TRUE.
          n2=SFdepoFixesGeo(SFdepoFixLinks(iSFfix,2),2,1:3)
          nhalf=ACOS(-(DOT_PRODUCT(n1,n2))) !n already normalized
          IF (nhalf.EQ.0.) THEN
            CALL abort(__STAMP__, &
              'ERROR in pic_depo.f90: angle between vectors of SFdepoFixLinks is zero!')
          ELSE
            nhalf=PI/nhalf
          END IF
          IF ( ABS(nhalf-1.5).LT.SFdepoFixesEps ) THEN !120 deg
            SFdepoFixLinks(iSFfix,3)=-2 !negative as flag for special case (120 deg), 2 since abs(-2) is needed for respective loop
            SWRITE(*,*) 'SFdepoFixLink ',iSFfix,' was determined to have an angle of 120 deg...'
          ELSE IF ( ABS(nhalf-NINT(nhalf)).GT.SFdepoFixesEps .OR. NINT(nhalf).LT.2 ) THEN !check if integer fraction (>2) of 180 deg
            CALL abort(__STAMP__, &
              'ERROR in pic_depo.f90: angle between vectors of SFdepoFixLink is neither 120 deg nor a fraction of 180 deg!', &
              NINT(nhalf),ABS(nhalf-NINT(nhalf)))
          ELSE !integer fraction of 180 deg
            SFdepoFixLinks(iSFfix,3) = NINT(nhalf)
            SWRITE(*,*) 'SFdepoFixLink ',iSFfix,' was determined to divide 180 deg into ',NINT(nhalf),' parts...'
          END IF
        END IF
      END DO
    END IF !NbrOfSFdepoFixLinks>0
    DO iSFfix=0,NbrOfSFdepoFixes
      SWRITE(*,*) 'SFdepoFix ',iSFfix,' is part of link: ',SFdepoFixesPartOfLink(iSFfix)
    END DO
  END IF !NbrOfSFdepoFixes>0

  !-- const. PartSource layer for shape func depo at planar BCs
  NbrOfSFdepoLayers = GETINT('PIC-NbrOfSFdepoLayers','0')
  IF (NbrOfSFdepoLayers.GT.0) THEN
    SDEALLOCATE(SFdepoLayersGeo)
    SDEALLOCATE(SFdepoLayersBounds)
    SDEALLOCATE(SFdepoLayersUseFixBounds)
    SDEALLOCATE(SFdepoLayersSpace)
    SDEALLOCATE(SFdepoLayersBaseVector)
    SDEALLOCATE(SFdepoLayersSpec)
    SDEALLOCATE(SFdepoLayersMPF)
    SDEALLOCATE(SFdepoLayersPartNum)
    SDEALLOCATE(SFdepoLayersRadius)
    ALLOCATE(SFdepoLayersGeo(1:NbrOfSFdepoLayers,1:2,1:3),STAT=ALLOCSTAT)  !1:nLayers;1:2(base,normal);1:3(x,y,z)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoLayersGeo!')
    END IF
    ALLOCATE(SFdepoLayersBounds(1:NbrOfSFdepoLayers,1:2,1:3),STAT=ALLOCSTAT)  !1:nLayers;1:2(min,max);1:3(x,y,z)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoLayersBounds!')
    END IF
    ALLOCATE(SFdepoLayersUseFixBounds(1:NbrOfSFdepoLayers),STAT=ALLOCSTAT)  !1:nLayers;1:2(min,max);1:3(x,y,z)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoLayersUseFixBounds!')
    END IF
    ALLOCATE(SFdepoLayersSpace(1:NbrOfSFdepoLayers),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoLayersSpace!')
    END IF
    ALLOCATE(SFdepoLayersBaseVector(1:NbrOfSFdepoLayers,1:2,1:3),STAT=ALLOCSTAT)  !1:nLayers;1:2(base,normal);1:3(x,y,z)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoLayersBaseVector!')
    END IF
    ALLOCATE(SFdepoLayersSpec(1:NbrOfSFdepoLayers),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoLayersSpec!')
    END IF
    ALLOCATE(SFdepoLayersMPF(1:NbrOfSFdepoLayers),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoLayersMPF!')
    END IF
    ALLOCATE(SFdepoLayersPartNum(1:NbrOfSFdepoLayers),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoLayersPartNum!')
    END IF
    ALLOCATE(SFdepoLayersRadius(1:NbrOfSFdepoLayers),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate SFdepoLayersRadius!')
    END IF
    SFdepoLayersRadius=0. !not used for cuboid...
    SFdepoLayersAlreadyDone=.FALSE.
    ConstantSFdepoLayers=GETLOGICAL('PIC-ConstantSFdepoLayers','.FALSE.')
    IF (ConstantSFdepoLayers) PartSourceConstExists=.TRUE.
    DO iSFfix=1,NbrOfSFdepoLayers
#if !((USE_HDG) && (PP_nVar==1))
      CALL abort(__STAMP__, &
        ' NbrOfSFdepoLayers are only implemented for electrostatic HDG!')
#endif
      WRITE(UNIT=hilf,FMT='(I0)') iSFfix
      SFdepoLayersGeo(iSFfix,1,1:3) = &
        GETREALARRAY('PIC-SFdepoLayers'//TRIM(hilf)//'-Basepoint',3,'0. , 0. , 0.')
      SFdepoLayersGeo(iSFfix,2,1:3) = &
        GETREALARRAY('PIC-SFdepoLayers'//TRIM(hilf)//'-Normal',3,'1. , 0. , 0.') !directed outwards
      IF (SFdepoLayersGeo(iSFfix,2,1)**2 + SFdepoLayersGeo(iSFfix,2,2)**2 + SFdepoLayersGeo(iSFfix,2,3)**2 .GT. 0.) THEN
        SFdepoLayersGeo(iSFfix,2,1:3) = SFdepoLayersGeo(iSFfix,2,1:3) &
          / SQRT(SFdepoLayersGeo(iSFfix,2,1)**2 + SFdepoLayersGeo(iSFfix,2,2)**2 + SFdepoLayersGeo(iSFfix,2,3)**2)
      ELSE
        CALL abort(__STAMP__&
          ,' SFdepoLayersXX-Normal is zero for Layer ',iSFfix)
      END IF
      WRITE(UNIT=hilf2,FMT='(E16.8)') -HUGE(1.0)
      SFdepoLayersBounds(iSFfix,1,1)   = MAX(GETREAL('PIC-SFdepoLayers'//TRIM(hilf)//'-xmin',TRIM(hilf2)),GEO%xmin-r_sf)
      SFdepoLayersBounds(iSFfix,1,2)   = MAX(GETREAL('PIC-SFdepoLayers'//TRIM(hilf)//'-ymin',TRIM(hilf2)),GEO%ymin-r_sf)
      SFdepoLayersBounds(iSFfix,1,3)   = MAX(GETREAL('PIC-SFdepoLayers'//TRIM(hilf)//'-zmin',TRIM(hilf2)),GEO%zmin-r_sf)
      WRITE(UNIT=hilf2,FMT='(E16.8)') HUGE(1.0)
      SFdepoLayersBounds(iSFfix,2,1)   = MIN(GETREAL('PIC-SFdepoLayers'//TRIM(hilf)//'-xmax',TRIM(hilf2)),GEO%xmax+r_sf)
      SFdepoLayersBounds(iSFfix,2,2)   = MIN(GETREAL('PIC-SFdepoLayers'//TRIM(hilf)//'-ymax',TRIM(hilf2)),GEO%ymax+r_sf)
      SFdepoLayersBounds(iSFfix,2,3)   = MIN(GETREAL('PIC-SFdepoLayers'//TRIM(hilf)//'-zmax',TRIM(hilf2)),GEO%zmax+r_sf)
      IF (NbrOfSFdepoFixes.EQ.0) THEN
        SFdepoLayersUseFixBounds(iSFfix) = .FALSE.
          ELSE
        SFdepoLayersUseFixBounds(iSFfix) = GETLOGICAL('PIC-SFdepoLayers'//TRIM(hilf)//'-UseFixBounds','.TRUE.')
      END IF
      SFdepoLayersSpace(iSFfix) = &
        GETSTR('PIC-SFdepoLayers'//TRIM(hilf)//'-Space','cuboid')
      LayerOutsideOfBounds = .FALSE.
      ChangeOccured = .FALSE.
      SELECT CASE (TRIM(SFdepoLayersSpace(iSFfix)))
      CASE('cuboid')
        SFdepoLayersBaseVector(iSFfix,1,1:3)   = GETREALARRAY('PIC-SFdepoLayers'//TRIM(hilf)//'-BaseVector1',3,'0. , 1. , 0.')
        SFdepoLayersBaseVector(iSFfix,2,1:3)   = GETREALARRAY('PIC-SFdepoLayers'//TRIM(hilf)//'-BaseVector2',3,'0. , 0. , 1.')
        !--check if BV1/2 are perpendicular to NormalVec (need to be for domain reduction with BoundPoints, otherwise should not matter)
        eps=1.0E-10
        NormVecCheck=CROSS(SFdepoLayersBaseVector(iSFfix,1,1:3),SFdepoLayersBaseVector(iSFfix,2,1:3))
        IF (NormVecCheck(1)**2 + NormVecCheck(2)**2 + NormVecCheck(3)**2 .GT. 0.) THEN
          NormVecCheck(1:3) = NormVecCheck(1:3) / SQRT(NormVecCheck(1)**2 + NormVecCheck(2)**2 + NormVecCheck(3)**2)
          diff = SQRT(DOT_PRODUCT(NormVecCheck-SFdepoLayersGeo(iSFfix,2,:),NormVecCheck-SFdepoLayersGeo(iSFfix,2,:))) !NormVecCheck - SFdepoLayersGeo(iSFfix,2,1) should be (/0,0,0/) when identical with same sign
          IF (diff.GT.eps) THEN
            diff = MIN(diff,SQRT(DOT_PRODUCT(NormVecCheck+SFdepoLayersGeo(iSFfix,2,:),NormVecCheck+SFdepoLayersGeo(iSFfix,2,:)))) !NormVecCheck + SFdepoLayersGeo(iSFfix,2,1) should be (/0,0,0/) when identical with opposite sign
            IF (diff.GT.eps) THEN !yes, the first diff could be checked again...
              CALL abort(__STAMP__&
                ,' SFdepoLayersBaseVectors are not perpendicular to Normal for Layer ',iSFfix,diff)
            END IF
          END IF
        ELSE
          CALL abort(__STAMP__&
            ,' SFdepoLayersBaseVectors are parallel for Layer ',iSFfix)
        END IF
        !--calculate area and check if BV1/2 are orthgonal (need to be for domain reduction with BoundPoints, otherwise should not matter)
        SFdepoLayersCross(1) = SFdepoLayersBaseVector(iSFfix,1,2)*SFdepoLayersBaseVector(iSFfix,2,3) &
                             - SFdepoLayersBaseVector(iSFfix,1,3)*SFdepoLayersBaseVector(iSFfix,2,2)
        SFdepoLayersCross(2) = SFdepoLayersBaseVector(iSFfix,1,3)*SFdepoLayersBaseVector(iSFfix,2,1) &
                             - SFdepoLayersBaseVector(iSFfix,1,1)*SFdepoLayersBaseVector(iSFfix,2,3)
        SFdepoLayersCross(3) = SFdepoLayersBaseVector(iSFfix,1,1)*SFdepoLayersBaseVector(iSFfix,2,2) &
                             - SFdepoLayersBaseVector(iSFfix,1,2)*SFdepoLayersBaseVector(iSFfix,2,1)
        SFdepoLayersPartNum(iSFfix)=ABS(DOT_PRODUCT(SFdepoLayersCross,SFdepoLayersGeo(iSFfix,2,1:3))) !area of parallelogram
        BVlengths(1)=SQRT(DOT_PRODUCT(SFdepoLayersBaseVector(iSFfix,1,:),SFdepoLayersBaseVector(iSFfix,1,:)))
        BVlengths(2)=SQRT(DOT_PRODUCT(SFdepoLayersBaseVector(iSFfix,2,:),SFdepoLayersBaseVector(iSFfix,2,:)))
        IF (.NOT.ALMOSTEQUAL( SFdepoLayersPartNum(iSFfix),BVlengths(1)*BVlengths(2) )) THEN !area of assumed rectangle
          CALL abort(__STAMP__&
            ,' SFdepoLayersBaseVectors are not orthogonal for Layer ',iSFfix)
        END IF
        !--domain reduction based on BoundPoints
        BoundPoints(:,1) = (/SFdepoLayersBounds(iSFfix,1,1),SFdepoLayersBounds(iSFfix,1,2),SFdepoLayersBounds(iSFfix,1,3)/)
        BoundPoints(:,2) = (/SFdepoLayersBounds(iSFfix,2,1),SFdepoLayersBounds(iSFfix,1,2),SFdepoLayersBounds(iSFfix,1,3)/)
        BoundPoints(:,3) = (/SFdepoLayersBounds(iSFfix,1,1),SFdepoLayersBounds(iSFfix,2,2),SFdepoLayersBounds(iSFfix,1,3)/)
        BoundPoints(:,4) = (/SFdepoLayersBounds(iSFfix,2,1),SFdepoLayersBounds(iSFfix,2,2),SFdepoLayersBounds(iSFfix,1,3)/)
        BoundPoints(:,5) = (/SFdepoLayersBounds(iSFfix,1,1),SFdepoLayersBounds(iSFfix,1,2),SFdepoLayersBounds(iSFfix,2,3)/)
        BoundPoints(:,6) = (/SFdepoLayersBounds(iSFfix,2,1),SFdepoLayersBounds(iSFfix,1,2),SFdepoLayersBounds(iSFfix,2,3)/)
        BoundPoints(:,7) = (/SFdepoLayersBounds(iSFfix,1,1),SFdepoLayersBounds(iSFfix,2,2),SFdepoLayersBounds(iSFfix,2,3)/)
        BoundPoints(:,8) = (/SFdepoLayersBounds(iSFfix,2,1),SFdepoLayersBounds(iSFfix,2,2),SFdepoLayersBounds(iSFfix,2,3)/)
        !-1: shift BasePoint if applicable
        Dist=HUGE(1.)
        DO iPoint=1,8
          DistVec = BoundPoints(:,iPoint) - SFdepoLayersGeo(iSFfix,1,:) !vec from Basepoint to BoundPoint
          DO iVec=1,2
            Dist(iVec) = MIN(Dist(iVec),MAX(0.,DOT_PRODUCT(DistVec,SFdepoLayersBaseVector(iSFfix,iVec,:))/BVlengths(iVec))) !DistVec projected on BaseVec, if > 0
          END DO
          iVec=3
          Dist(iVec) = MIN(Dist(iVec),MAX(0.,DOT_PRODUCT(DistVec,SFdepoLayersGeo(iSFfix,2,:)))) !smallest DistVec projected on (already normalized) NormVec, if > 0
        END DO
        DO iVec=1,3 !shift of BP is independently for the 3 vectors possible because they are orthogonal!
          IF ( Dist(iVec).LT.HUGE(1.) .AND. Dist(iVec).GT.0. ) THEN !not-initial and positive dist was found (negative would not be reduction of domain)
            ChangeOccured = .TRUE.
            IF (iVec.NE.3) THEN
              IF (Dist(iVec).GE.BVlengths(iVec)) THEN !new BVlength would be < 0
                LayerOutsideOfBounds = .TRUE.
                EXIT
              ELSE !shift BP and reduce BVlength so that end of domain is at same position
                SFdepoLayersGeo(iSFfix,1,:) &
                  = SFdepoLayersGeo(iSFfix,1,:) + Dist(iVec)/BVlengths(iVec)*SFdepoLayersBaseVector(iSFfix,iVec,:)
                SFdepoLayersBaseVector(iSFfix,iVec,:) &
                  = SFdepoLayersBaseVector(iSFfix,iVec,:) * (BVlengths(iVec)-Dist(iVec))/BVlengths(iVec)
                BVlengths(iVec)=BVlengths(iVec)-Dist(iVec)
              END IF
            ELSE !NormalVec (r_SF is fix)
              IF (Dist(iVec).GE.r_SF) THEN
                LayerOutsideOfBounds = .TRUE.
                EXIT
              END IF
            END IF
          END IF
        END DO
        !-2: shorten BaseVectors if applicable (r_SF is fix)
        IF (.NOT.LayerOutsideOfBounds) THEN
          Dist=-HUGE(1.)
          DO iPoint=1,8
            DistVec = BoundPoints(:,iPoint) - SFdepoLayersGeo(iSFfix,1,:) !vec from Basepoint to BoundPoint
            DO iVec=1,2
              Dist(iVec) = MAX(Dist(iVec),DOT_PRODUCT(DistVec,SFdepoLayersBaseVector(iSFfix,iVec,:))/BVlengths(iVec)) !largest DistVec projected on BaseVec
            END DO
            iVec=3
            Dist(iVec) = MAX(Dist(iVec),DOT_PRODUCT(DistVec,SFdepoLayersGeo(iSFfix,2,:)))
          END DO
          DO iVec=1,3
            IF ( Dist(iVec).LE.0.) THEN !completely outside
              LayerOutsideOfBounds = .TRUE.
              EXIT
            ELSE IF ( iVec.NE.3 ) THEN
              IF (Dist(iVec).LT.BVlengths(iVec)) THEN !positive dist < BVlength was found (> BVlength would not be reduction of domain)
                ChangeOccured = .TRUE.
                SFdepoLayersBaseVector(iSFfix,iVec,:) = SFdepoLayersBaseVector(iSFfix,iVec,:) * (Dist(iVec))/BVlengths(iVec)
                BVlengths(iVec)=Dist(iVec)
              END IF
            END IF
          END DO
        END IF
        SFdepoLayersPartNum(iSFfix)=BVlengths(1)*BVlengths(2)
      CASE('cylinder')
        !calc BaseVectors from Normalvector
        IF (SFdepoLayersGeo(iSFfix,2,3).NE.0) THEN
          BaseVector(1) = 1.0
          BaseVector(2) = 1.0
          BaseVector(3) = -(SFdepoLayersGeo(iSFfix,2,1)+SFdepoLayersGeo(iSFfix,2,2))/ &
            SFdepoLayersGeo(iSFfix,2,3)
        ELSE
          IF (SFdepoLayersGeo(iSFfix,2,2).NE.0) THEN
            BaseVector(1) = 1.0
            BaseVector(3) = 1.0
            BaseVector(2) = -(SFdepoLayersGeo(iSFfix,2,1)+SFdepoLayersGeo(iSFfix,2,3))/ &
              SFdepoLayersGeo(iSFfix,2,2)
          ELSE
            IF (SFdepoLayersGeo(iSFfix,2,1).NE.0) THEN
              BaseVector(2) = 1.0
              BaseVector(3) = 1.0
              BaseVector(1) = -(SFdepoLayersGeo(iSFfix,2,2)+SFdepoLayersGeo(iSFfix,2,3))/ &
                SFdepoLayersGeo(iSFfix,2,1)
            END IF
          END IF
        END IF
        BaseVector = BaseVector / SQRT(BaseVector(1) * BaseVector(1) + BaseVector(2) * &
          BaseVector(2) + BaseVector(3) * BaseVector(3))
        BaseVector2(1) = SFdepoLayersGeo(iSFfix,2,2) * BaseVector(3) - &
          SFdepoLayersGeo(iSFfix,2,3) * BaseVector(2)
        BaseVector2(2) = SFdepoLayersGeo(iSFfix,2,3) * BaseVector(1) - &
          SFdepoLayersGeo(iSFfix,2,1) * BaseVector(3)
        BaseVector2(3) = SFdepoLayersGeo(iSFfix,2,1) * BaseVector(2) - &
          SFdepoLayersGeo(iSFfix,2,2) * BaseVector(1)
        BaseVector2 = BaseVector2 / SQRT(BaseVector2(1) * BaseVector2(1) + BaseVector2(2) * &
          BaseVector2(2) + BaseVector2(3) * BaseVector2(3))
        SFdepoLayersBaseVector(iSFfix,1,1:3)=BaseVector
        SFdepoLayersBaseVector(iSFfix,2,1:3)=BaseVector2
        SFdepoLayersRadius(iSFfix) = &
          GETREAL('PIC-SFdepoLayers'//TRIM(hilf)//'-SFdepoLayersRadius','1.')
        SFdepoLayersPartNum(iSFfix)=PI*SFdepoLayersRadius(iSFfix)*SFdepoLayersRadius(iSFfix) !volume scaled with height (r_sf)
      CASE DEFAULT
        CALL abort(__STAMP__, &
          ' Wrong Space for SFdepoLayer: only cuboid and cylinder implemented!')
      END SELECT
      SFdepoLayersChargedens = GETREAL('PIC-SFdepoLayers'//TRIM(hilf)//'-Chargedens','1.')
      SFdepoLayersSpec(iSFFix) = GETINT('PIC-SFdepoLayers'//TRIM(hilf)//'-Spec','1')
      WRITE(UNIT=hilf2,FMT='(E16.8)') Species(SFdepoLayersSpec(iSFfix))%MacroParticleFactor
      SFdepoLayersMPF(iSFfix)   = GETREAL('PIC-SFdepoLayers'//TRIM(hilf)//'-MPF',TRIM(hilf2))
      IF (.NOT.LayerOutsideOfBounds) THEN
        SFdepoLayersGeo(iSFfix,2,:) = SFdepoLayersGeo(iSFfix,2,:)*r_sf
        IF (SFdepoLayersPartNum(iSFfix).LE.0.) CALL abort(__STAMP__&
          ,' Volume of SFdepoLayersXX is zero for Layer ',iSFfix)
        SFdepoLayersPartNum(iSFfix) = SFdepoLayersPartNum(iSFfix)*r_sf &
          * SFdepoLayersChargedens/SFdepoLayersMPF(iSFfix)
        IF (SFdepoLayersPartNum(iSFfix)+1.0 .GT. HUGE(iSFfix)) CALL abort(__STAMP__, &
          ' ERROR in SFdepoLayer: number of to-be inserted particles exceeds max INT. Layer/factor: ',iSFfix, &
          (SFdepoLayersPartNum(iSFfix)+1.0)/REAL(HUGE(iSFfix)))
        SWRITE(*,'(E12.5,A,I0)') SFdepoLayersPartNum(iSFfix), &
          ' additional particles will be inserted for SFdepoLayer ',iSFfix
        IF (ChangeOccured) THEN
          IF(PrintSFDepoWarnings)THEN
            IPWRITE(*,'(I4,A,I0,A)') ' WARNING: SFdepoLayer ',iSFfix,' was changed!'
            IPWRITE(*,'(I4,A,3(x,E12.5))')                 '          xyz minBounds:',SFdepoLayersBounds(iSFfix,1,:)
            IPWRITE(*,'(I4,A,3(x,E12.5))')                 '          xyz maxBounds:',SFdepoLayersBounds(iSFfix,2,:)
            IPWRITE(*,'(I4,A,3(x,E12.5))')                 '          New Basepoint:',SFdepoLayersGeo(iSFfix,1,:)
            IPWRITE(*,'(I4,A,3(x,E12.5))')                 '          New BaseVec01:',SFdepoLayersBaseVector(iSFfix,1,:)
            IPWRITE(*,'(I4,A,3(x,E12.5))')                 '          New BaseVec02:',SFdepoLayersBaseVector(iSFfix,2,:)
          END IF
        END IF
      ELSE !LayerOutsideOfBounds
        SFdepoLayersPartNum(iSFfix)=0
        IF(PrintSFDepoWarnings)THEN
          IPWRITE(*,'(I4,A,I0,A)') ' WARNING: SFdepoLayer ',iSFfix,' was disabled!'
          IPWRITE(*,'(I4,A,3(x,E12.5))')                 '          xyz minBounds:',SFdepoLayersBounds(iSFfix,1,:)
          IPWRITE(*,'(I4,A,3(x,E12.5))')                 '          xyz maxBounds:',SFdepoLayersBounds(iSFfix,2,:)
        END IF
      END IF
    END DO
  END IF !NbrOfSFdepoLayers>0

  !-- ResampleAnalyzeSurfCollis
  SFResampleAnalyzeSurfCollis = GETLOGICAL('PIC-SFResampleAnalyzeSurfCollis','.FALSE.')
  IF (SFResampleAnalyzeSurfCollis) THEN
    LastAnalyzeSurfCollis%PartNumberSamp = 0
    LastAnalyzeSurfCollis%PartNumberDepo = 0
    LastAnalyzeSurfCollis%ReducePartNumber = GETLOGICAL('PIC-SFResampleReducePartNumber','.FALSE.')
    LastAnalyzeSurfCollis%PartNumThreshold = GETINT('PIC-PartNumThreshold','0')
    IF (LastAnalyzeSurfCollis%ReducePartNumber) THEN
      WRITE(UNIT=hilf,FMT='(I0)') LastAnalyzeSurfCollis%PartNumThreshold
      LastAnalyzeSurfCollis%PartNumberReduced = GETINT('PIC-SFResamplePartNumberReduced',TRIM(hilf)) !def. PartNumThreshold
    END IF
    WRITE(UNIT=hilf,FMT='(E16.8)') -HUGE(1.0)
    LastAnalyzeSurfCollis%Bounds(1,1)   = MAX(GETREAL('PIC-SFResample-xmin',TRIM(hilf)),GEO%xmin-r_sf)
    LastAnalyzeSurfCollis%Bounds(1,2)   = MAX(GETREAL('PIC-SFResample-ymin',TRIM(hilf)),GEO%ymin-r_sf)
    LastAnalyzeSurfCollis%Bounds(1,3)   = MAX(GETREAL('PIC-SFResample-zmin',TRIM(hilf)),GEO%zmin-r_sf)
    WRITE(UNIT=hilf,FMT='(E16.8)') HUGE(1.0)
    LastAnalyzeSurfCollis%Bounds(2,1)   = MIN(GETREAL('PIC-SFResample-xmax',TRIM(hilf)),GEO%xmax+r_sf)
    LastAnalyzeSurfCollis%Bounds(2,2)   = MIN(GETREAL('PIC-SFResample-ymax',TRIM(hilf)),GEO%ymax+r_sf)
    LastAnalyzeSurfCollis%Bounds(2,3)   = MIN(GETREAL('PIC-SFResample-zmax',TRIM(hilf)),GEO%zmax+r_sf)
    IF (NbrOfSFdepoFixes.EQ.0) THEN
      LastAnalyzeSurfCollis%UseFixBounds = .FALSE.
    ELSE
      LastAnalyzeSurfCollis%UseFixBounds = GETLOGICAL('PIC-SFResample-UseFixBounds','.TRUE.')
    END IF
    LastAnalyzeSurfCollis%NormVecOfWall = GETREALARRAY('PIC-NormVecOfWall',3,'1. , 0. , 0.')  !directed outwards
    IF (DOT_PRODUCT(LastAnalyzeSurfCollis%NormVecOfWall,LastAnalyzeSurfCollis%NormVecOfWall).GT.0.) THEN
      LastAnalyzeSurfCollis%NormVecOfWall = LastAnalyzeSurfCollis%NormVecOfWall &
        / SQRT( DOT_PRODUCT(LastAnalyzeSurfCollis%NormVecOfWall,LastAnalyzeSurfCollis%NormVecOfWall) )
    END IF
    LastAnalyzeSurfCollis%Restart = GETLOGICAL('PIC-SFResampleRestart','.FALSE.')
    IF (LastAnalyzeSurfCollis%Restart) THEN
      LastAnalyzeSurfCollis%DSMCSurfCollisRestartFile = GETSTR('PIC-SFResampleRestartFile','dummy')
    END IF
    !-- BCs
    LastAnalyzeSurfCollis%NumberOfBCs = GETINT('PIC-SFResampleNumberOfBCs','1')
    SDEALLOCATE(LastAnalyzeSurfCollis%BCs)
    ALLOCATE(LastAnalyzeSurfCollis%BCs(1:LastAnalyzeSurfCollis%NumberOfBCs),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate LastAnalyzeSurfCollis%BCs!')
    END IF
    IF (LastAnalyzeSurfCollis%NumberOfBCs.EQ.1) THEN !already allocated
      LastAnalyzeSurfCollis%BCs = GETINTARRAY('PIC-SFResampleSurfCollisBC',1,'0') ! 0 means all...
    ELSE
      hilf2=''
      DO iBC=1,LastAnalyzeSurfCollis%NumberOfBCs !build default string: 0,0,0,...
        WRITE(UNIT=hilf,FMT='(I0)') 0
        hilf2=TRIM(hilf2)//TRIM(hilf)
        IF (iBC.NE.LastAnalyzeSurfCollis%NumberOfBCs) hilf2=TRIM(hilf2)//','
      END DO
      LastAnalyzeSurfCollis%BCs = GETINTARRAY('PIC-SFResampleSurfCollisBC',LastAnalyzeSurfCollis%NumberOfBCs,hilf2)
    END IF
    !-- spec for dt-calc
    LastAnalyzeSurfCollis%NbrOfSpeciesForDtCalc = GETINT('PIC-SFResampleNbrOfSpeciesForDtCalc','1')
    SDEALLOCATE(LastAnalyzeSurfCollis%SpeciesForDtCalc)
    ALLOCATE(LastAnalyzeSurfCollis%SpeciesForDtCalc(1:LastAnalyzeSurfCollis%NbrOfSpeciesForDtCalc),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) THEN
      CALL abort(__STAMP__, &
        'ERROR in pic_depo.f90: Cannot allocate LastAnalyzeSurfCollis%SpeciesForDtCalc!')
    END IF
    IF (LastAnalyzeSurfCollis%NbrOfSpeciesForDtCalc.EQ.1) THEN !already allocated
      LastAnalyzeSurfCollis%SpeciesForDtCalc = GETINTARRAY('PIC-SFResampleSpeciesForDtCalc',1,'0') ! 0 means all...
    ELSE
      hilf2=''
      DO iBC=1,LastAnalyzeSurfCollis%NbrOfSpeciesForDtCalc !build default string: 0,0,0,...
        WRITE(UNIT=hilf,FMT='(I0)') 0
        hilf2=TRIM(hilf2)//TRIM(hilf)
        IF (iBC.NE.LastAnalyzeSurfCollis%NbrOfSpeciesForDtCalc) hilf2=TRIM(hilf2)//','
      END DO
      LastAnalyzeSurfCollis%SpeciesForDtCalc &
        = GETINTARRAY('PIC-SFResampleSpeciesForDtCalc',LastAnalyzeSurfCollis%NbrOfSpeciesForDtCalc,hilf2)
    END IF
  END IF

  VolumeShapeFunction=4./3.*PI*r_sf**3
  nTotalDOF=nGlobalElems*(PP_N+1)**3
  IF(MPIRoot)THEN
    IF(VolumeShapeFunction.GT.GEO%MeshVolume) &
      CALL abort(&
      __STAMP__&
      ,'ShapeFunctionVolume > MeshVolume')
  END IF

  CALL PrintOption('Average DOFs in Shape-Function','CALCUL.',RealOpt=REAL(nTotalDOF)*VolumeShapeFunction/GEO%MeshVolume)

  ALLOCATE(ElemDepo_xGP(1:3,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) CALL abort(&
      __STAMP__&
      ,' Cannot allocate ElemDepo_xGP!')
  IF(DoSFEqui)THEN
    ALLOCATE( Vdm_EquiN_GaussN(0:PP_N,0:PP_N)     &
            , Vdm_GaussN_EquiN(0:PP_N,0:PP_N)     &
            , wGP_tmp(0:PP_N)                     &
            , xGP_tmp(0:PP_N)                     &
            , wBary_tmp(0:PP_N)                   )
    DO i=0,PP_N
      xGP_tmp(i) = 2./REAL(PP_N) * REAL(i) - 1.
    END DO
    CALL BarycentricWeights(PP_N,xGP_tmp,wBary_tmp)
    ! to Gauss
    CALL InitializeVandermonde(PP_N,PP_N,wBary_tmp,xGP_tmp,xGP ,Vdm_EquiN_GaussN)
    ! from Gauss
    CALL InitializeVandermonde(PP_N,PP_N,wBary,xGP,xGP_tmp ,Vdm_GaussN_EquiN)
    DO iElem=1,PP_nElems
      CALL ChangeBasis3D(3,PP_N,PP_N,Vdm_GaussN_EquiN,Elem_xGP(:,:,:,:,iElem),ElemDepo_xGP(:,:,:,:,iElem))
    END DO ! iElem=1,PP_nElems
    DEALLOCATE( Vdm_GaussN_EquiN, wGP_tmp, xGP_tmp, wBary_tmp)
  ELSE
    ElemDepo_xGP=Elem_xGP
  END IF

CASE('shape_function_1d','shape_function_2d')
#if USE_MPI
  DoExternalParts=.TRUE.
#endif /*USE_MPI*/
  ! Get deposition direction for 1D or perpendicular direction for 2D
  sf1d_dir = GETINT ('PIC-shapefunction1d-direction')
  ! Distribute the charge over the volume (3D) or line (1D)/area (2D): default is TRUE
  sfDepo3D = GETLOGICAL('PIC-shapefunction-3D-deposition')
  hilf2='volume'

  SELECT CASE(TRIM(DepositionType))
  CASE('shape_function_1d')
    ! Set perpendicular directions
    IF(sf1d_dir.EQ.1)THEN ! Shape function deposits charge in x-direction
      dimFactorSF = (GEO%ymaxglob-GEO%yminglob)*(GEO%zmaxglob-GEO%zminglob)
    ELSE IF (sf1d_dir.EQ.2)THEN ! Shape function deposits charge in y-direction
      dimFactorSF = (GEO%xmaxglob-GEO%xminglob)*(GEO%zmaxglob-GEO%zminglob)
    ELSE IF (sf1d_dir.EQ.3)THEN ! Shape function deposits charge in z-direction
      dimFactorSF = (GEO%xmaxglob-GEO%xminglob)*(GEO%ymaxglob-GEO%yminglob)
    ELSE
      w_sf=2*GEO%MeshVolume
    END IF
    IF(sfDepo3D)THEN ! Distribute the charge over the volume (3D)
      ! Set prefix factor
      w_sf = GAMMA(REAL(alpha_sf)+1.5)/(SQRT(PI)*r_sf*GAMMA(REAL(alpha_sf+1))*dimFactorSF)
    ELSE ! Distribute the charge over the line (1D)
      ! Set prefix factor
      w_sf = GAMMA(REAL(alpha_sf)+1.5)/(SQRT(PI)*r_sf*GAMMA(REAL(alpha_sf+1)))
      ! Set shape function length (1D volume)
      !VolumeShapeFunction=2*r_sf
      hilf2='line'
    END IF
    ! Set shape function length (3D volume)
    VolumeShapeFunction=2*r_sf*dimFactorSF
    ! Calculate number of 1D DOF (assume second and third direction with 1 cell layer and area given by dimFactorSF)
    nTotalDOF=nGlobalElems*(PP_N+1)
    hilf='1D'
  CASE('shape_function_2d')
    ! Set perpendicular direction
    IF(sf1d_dir.EQ.1)THEN ! Shape function deposits charge in y-z-direction (const. in x)
      dimFactorSF = (GEO%xmaxglob-GEO%xminglob)
    ELSE IF (sf1d_dir.EQ.2)THEN ! Shape function deposits charge in x-z-direction (const. in y)
      dimFactorSF = (GEO%ymaxglob-GEO%yminglob)
    ELSE IF (sf1d_dir.EQ.3)THEN! Shape function deposits charge in x-y-direction (const. in z)
      dimFactorSF = (GEO%zmaxglob-GEO%zminglob)
    ELSE
      w_sf=2*GEO%MeshVolume
    END IF
    IF(sfDepo3D)THEN ! Distribute the charge over the volume (3D)
      ! Set prefix factor
      w_sf = (REAL(alpha_sf)+1.0)/(PI*r2_sf*dimFactorSF)
    ELSE ! Distribute the charge over the area (2D)
      ! Set prefix factor
      w_sf = (REAL(alpha_sf)+1.0)/(PI*r2_sf)
      ! Set shape function length (2D volume)
      !VolumeShapeFunction=PI*(r_sf**2)
      hilf2='area'
    END IF
    ! Set shape function length (3D volume)
    VolumeShapeFunction=PI*(r_sf**2)*dimFactorSF
    ! Calculate number of 2D DOF (assume third direction with 1 cell layer and width dimFactorSF)
    nTotalDOF=nGlobalElems*(PP_N+1)**2
    hilf='2D'
  END SELECT

  ASSOCIATE(nTotalDOFin3D             => nGlobalElems*(PP_N+1)**3   ,&
            VolumeShapeFunctionSphere => 4./3.*PI*r_sf**3           )
    SWRITE(UNIT_stdOut,'(A)') ' The complete charge is '//TRIM(hilf2)//' distributed (deposition function is '//TRIM(hilf)//')'
    IF(.NOT.sfDepo3D)THEN
      SWRITE(UNIT_stdOut,'(A)') ' Note that the integral of the charge density over the volume is larger than the complete charge!'
    END IF
    IF(TRIM(DepositionType).EQ.'shape_function_1d')THEN
      CALL PrintOption('Shape function volume (3D box)', 'CALCUL.', RealOpt=VolumeShapeFunction)
    ELSE
      CALL PrintOption('Shape function volume (3D cylinder)', 'CALCUL.', RealOpt=VolumeShapeFunction)
    END IF
    !CALL PrintOption('Shape function volume ('//TRIM(hilf)//')'                , 'CALCUL.' , RealOpt=VolumeShapeFunction)
    IF(MPIRoot)THEN
      IF(VolumeShapeFunction.GT.GEO%MeshVolume)THEN
        CALL PrintOption('Mesh volume ('//TRIM(hilf)//')'                , 'CALCUL.' , RealOpt=GEO%MeshVolume)
        WRITE(UNIT_stdOut,'(A)') ' Maybe wrong perpendicular direction (PIC-shapefunction1d-direction)?'
        CALL abort(&
        __STAMP__&
        ,'ShapeFunctionVolume > MeshVolume ('//TRIM(hilf)//' shape function)')
      END IF
    END IF
    CALL PrintOption('Average DOFs in Shape-Function '//TRIM(hilf2)//' ('//TRIM(hilf)//')'       , 'CALCUL.' , RealOpt=&
         REAL(nTotalDOF)*VolumeShapeFunction/GEO%MeshVolume)
    CALL PrintOption('Average DOFs in Shape-Function (corresponding 3D sphere)' , 'CALCUL.' , RealOpt=&
         REAL(nTotalDOFin3D)*VolumeShapeFunctionSphere/GEO%MeshVolume)
  END ASSOCIATE

  ALLOCATE(ElemDepo_xGP(1:3,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) CALL abort(&
      __STAMP__&
      ,' Cannot allocate ElemDepo_xGP!')
  IF(DoSFEqui)THEN
    ALLOCATE( Vdm_EquiN_GaussN(0:PP_N,0:PP_N)     &
            , Vdm_GaussN_EquiN(0:PP_N,0:PP_N)     &
            , wGP_tmp(0:PP_N)                     &
            , xGP_tmp(0:PP_N)                     &
            , wBary_tmp(0:PP_N)                   )
    DO i=0,PP_N
      xGP_tmp(i) = 2./REAL(PP_N) * REAL(i) - 1.
    END DO
    CALL BarycentricWeights(PP_N,xGP_tmp,wBary_tmp)
    ! to Gauss
    CALL InitializeVandermonde(PP_N,PP_N,wBary_tmp,xGP_tmp,xGP ,Vdm_EquiN_GaussN)
    ! from Gauss
    CALL InitializeVandermonde(PP_N,PP_N,wBary,xGP,xGP_tmp ,Vdm_GaussN_EquiN)
    DO iElem=1,PP_nElems
      CALL ChangeBasis3D(3,PP_N,PP_N,Vdm_GaussN_EquiN,Elem_xGP(:,:,:,:,iElem),ElemDepo_xGP(:,:,:,:,iElem))
    END DO ! iElem=1,PP_nElems
    DEALLOCATE( Vdm_GaussN_EquiN, wGP_tmp, xGP_tmp, wBary_tmp)
  ELSE
    ElemDepo_xGP=Elem_xGP
  END IF

CASE('shape_function_cylindrical','shape_function_spherical')
#if USE_MPI
  DoExternalParts=.TRUE.
#endif /*USE_MPI*/
  !IF(.NOT.DoRefMapping) CALL abort(&
  !  __STAMP__&
  !  ,' Shape function has to be used with ref element tracking.')
  !ALLOCATE(PartToFIBGM(1:6,1:PDM%maxParticleNumber),STAT=ALLOCSTAT)
  !IF (ALLOCSTAT.NE.0) CALL abort(&
  !    __STAMP__&
  !    ' Cannot allocate PartToFIBGM!')
  !ALLOCATE(ExtPartToFIBGM(1:6,1:PDM%ParticleVecLength),STAT=ALLOCSTAT)
  !IF (ALLOCSTAT.NE.0) THEN
  !  CALL abort(__STAMP__&
  !    ' Cannot allocate ExtPartToFIBGM!')
  IF(TRIM(DepositionType).EQ.'shape_function_cylindrical')THEN
    SfRadiusInt=2
  ELSE
    SfRadiusInt=3
  END IF
  r_sf0      = GETREAL   ('PIC-shapefunction-radius0','1.')
  r_sf_scale = GETREAL   ('PIC-shapefunction-scale','0.')
  BetaFac    = beta(1.5, REAL(alpha_sf) + 1.)
  w_sf = 1./(2. * BetaFac * REAL(alpha_sf) + 2 * BetaFac) &
                        * (REAL(alpha_sf) + 1.)!/(PI*(r_sf**3))

  r_sf_average=0.5*(r_sf+r_sf0)
  VolumeShapeFunction=4./3.*PI*r_sf_average*r_sf_average
  nTotalDOF=nGlobalElems*(PP_N+1)**3
  IF(MPIRoot)THEN
    IF(VolumeShapeFunction.GT.GEO%MeshVolume) &
      CALL abort(&
      __STAMP__&
      ,'ShapeFunctionVolume > MeshVolume')
  END IF

  CALL PrintOption('Average DOFs in Shape-Function','CALCUL.',RealOpt=REAL(nTotalDOF)*VolumeShapeFunction/GEO%MeshVolume)

  ALLOCATE(ElemDepo_xGP(1:3,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) CALL abort(&
      __STAMP__&
      ,' Cannot allocate ElemDepo_xGP!')
  IF(DoSFEqui)THEN
    ALLOCATE( Vdm_EquiN_GaussN(0:PP_N,0:PP_N)     &
            , Vdm_GaussN_EquiN(0:PP_N,0:PP_N)     &
            , wGP_tmp(0:PP_N)                     &
            , xGP_tmp(0:PP_N)                     &
            , wBary_tmp(0:PP_N)                   )
    DO i=0,PP_N
      xGP_tmp(i) = 2./REAL(PP_N) * REAL(i) - 1.
    END DO
    CALL BarycentricWeights(PP_N,xGP_tmp,wBary_tmp)
    ! to Gauss
    CALL InitializeVandermonde(PP_N,PP_N,wBary_tmp,xGP_tmp,xGP ,Vdm_EquiN_GaussN)
    ! from Gauss
    CALL InitializeVandermonde(PP_N,PP_N,wBary,xGP,xGP_tmp ,Vdm_GaussN_EquiN)
    DO iElem=1,PP_nElems
      CALL ChangeBasis3D(3,PP_N,PP_N,Vdm_GaussN_EquiN,Elem_xGP(:,:,:,:,iElem),ElemDepo_xGP(:,:,:,:,iElem))
    END DO ! iElem=1,PP_nElems
    DEALLOCATE( Vdm_GaussN_EquiN, wGP_tmp, xGP_tmp, wBary_tmp)
  ELSE
    ElemDepo_xGP=Elem_xGP
  END IF

CASE('delta_distri')
  ! Allocate array for particle positions in -1|1 space (used for deposition as well as interpolation)
  IF(.NOT.DoRefMapping)THEN
    ALLOCATE(PartPosRef(1:3,PDM%MaxParticleNumber), STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) CALL abort(&
    __STAMP__&
    ,' Cannot allocate partposref!')
  END IF
  DeltaType = GETINT('PIC-DeltaType','1')
  WRITE(hilf,'(I0)') PP_N
  NDepo     = GETINT('PIC-DeltaType-N',hilf)
  SELECT CASE(DeltaType)
  CASE(1)
    SWRITE(UNIT_stdOut,'(A)') ' Lagrange-Polynomial'
  CASE(2)
    SWRITE(UNIT_stdOut,'(A)') ' Bernstein-Polynomial'
    !CALL BuildBernSteinVdm(PP_N,xGP)
    ALLOCATE(NDepochooseK(0:NDepo,0:NDepo))
    CALL ComputeBernsteinCoeff(NDepo,NDepoChooseK)
  CASE(3)
    SWRITE(UNIT_stdOut,'(A)') ' Uniform B-Spline '
    NKnots=(NDepo+1)*2-1
    ALLOCATE( Knots(0:NKnots)  )
    ! knots distance is 2 [-1,1)
    X0=-1.-REAL(NDepo)*2.0
    DO i=0,nKnots
      Knots(i) =X0+2.0*REAL(i)
    END DO ! i
  CASE DEFAULT
    CALL abort(&
    __STAMP__&
    ,' Wrong Delta-Type')
  END SELECT
  IF(NDepo.GT.PP_N) CALL abort(&
    __STAMP__&
    ,' NDepo must be smaller than N!')
  DeltaDistriChangeBasis=.FALSE.
  IF(NDepo.NE.PP_N) DeltaDistriChangeBasis=.TRUE.
  ALLOCATE(DDMassInv(0:NDepo,0:NDepo,0:NDepo,1:PP_nElems) &
          , XiNDepo(0:NDepo)                              &
          , swGPNDepo(0:NDepo)                            &
          , wBaryNDepo(0:NDepo)                           )
  DDMassInv=0.
#if (PP_NodeType==1)
  CALL LegendreGaussNodesAndWeights(NDepo,XiNDepo,swGPNDepo)
#elif (PP_NodeType==2)
  CALL LegGaussLobNodesAndWeights(NDepo,XiNDepo,swGPNDepo)
#endif
  CALL BarycentricWeights(NDepo,XiNDepo,wBaryNDepo)

  IF(DeltaDistriChangeBasis)THEN
    ALLOCATE( Vdm_NDepo_GaussN(0:PP_N,0:NDepo)             &
            , Vdm_GaussN_NDepo(0:NDepo,0:PP_N)             &
            , dummy(1,0:PP_N,0:PP_N,0:PP_N)                &
            , dummy2(1,0:NDepo,0:NDepo,0:NDepo)            )
    CALL InitializeVandermonde(NDepo,PP_N,wBaryNDepo,XiNDepo,xGP,Vdm_NDepo_GaussN)
    ! and inverse of mass matrix
    DO i=0,NDepo
      swGPNDepo(i)=1.0/swGPNDepo(i)
    END DO ! i=0,PP_N
    CALL InitializeVandermonde(PP_N,NDepo,wBary,xGP,xiNDepo,Vdm_GaussN_NDepo)
    DO iElem=1,PP_nElems
      dummy(1,:,:,:)=sJ(:,:,:,iElem)
      CALL ChangeBasis3D(1,PP_N,NDepo,Vdm_GaussN_NDepo,dummy,dummy2)
      DO k=0,NDepo
        DO j=0,NDepo
          DO i=0,NDepo
            DDMassInv(i,j,k,iElem)=dummy2(1,i,j,k)*swGPNDepo(i)*swGPNDepo(j)*swGPNDepo(k)
          END DO ! i
        END DO ! j
      END DO ! k
    END DO ! iElem=1,PP_nElems
    !DEALLOCATE(Vdm_NDepo_GaussN)
    DEALLOCATE(Vdm_GaussN_NDepo)
    DEALLOCATE(dummy,dummy2)
  ELSE
    DO i=0,NDepo
      swGPNDepo(i)=1.0/wGP(i)
    END DO ! i=0,PP_N
    DO iElem=1,PP_nElems
      DO k=0,NDepo
        DO j=0,NDepo
          DO i=0,NDepo
            DDMassInv(i,j,k,iElem)=sJ(i,j,k,iElem)*swGPNDepo(i)*swGPNDepo(j)*swGPNDepo(k)
          END DO ! i
        END DO ! j
      END DO ! k
    END DO ! iElem=1,PP_nElems
  END IF
  DEALLOCATE(swGPNDepo)

CASE('cartmesh_volumeweighting')

  ! read in background mesh size
  BGMdeltas(1:3) = GETREALARRAY('PIC-BGMdeltas',3,'0. , 0. , 0.')
  FactorBGM(1:3) = GETREALARRAY('PIC-FactorBGM',3,'1. , 1. , 1.')
  BGMdeltas(1:3) = 1./FactorBGM(1:3)*BGMdeltas(1:3)
  IF (ANY(BGMdeltas.EQ.0.0)) THEN
    CALL abort(&
    __STAMP__&
    ,'ERROR: PIC-BGMdeltas: No size for the cartesian background mesh definded.')
  END IF
  ! calc min and max coordinates for local mesh
  xmin = 1.0E200
  ymin = 1.0E200
  zmin = 1.0E200
  xmax = -1.0E200
  ymax = -1.0E200
  zmax = -1.0E200
  DO iElem = 1, nElems
    xmin=MIN(xmin,MINVAL(XCL_NGeo(1,:,:,:,iElem)))
    xmax=MAX(xmax,MAXVAL(XCL_NGeo(1,:,:,:,iElem)))
    ymin=MIN(ymin,MINVAL(XCL_NGeo(2,:,:,:,iElem)))
    ymax=MAX(ymax,MAXVAL(XCL_NGeo(2,:,:,:,iElem)))
    zmin=MIN(zmin,MINVAL(XCL_NGeo(3,:,:,:,iElem)))
    zmax=MAX(zmax,MAXVAL(XCL_NGeo(3,:,:,:,iElem)))
  END DO
  ! define minimum and maximum backgroundmesh index, compute volume
  BGMVolume = BGMdeltas(1)*BGMdeltas(2)*BGMdeltas(3)
  BGMminX = FLOOR(xmin/BGMdeltas(1)-0.0001)
  BGMminY = FLOOR(ymin/BGMdeltas(2)-0.0001)
  BGMminZ = FLOOR(zmin/BGMdeltas(3)-0.0001)
  BGMmaxX = CEILING(xmax/BGMdeltas(1)+0.0001)
  BGMmaxY = CEILING(ymax/BGMdeltas(2)+0.0001)
  BGMmaxZ = CEILING(zmax/BGMdeltas(3)+0.0001)
  ! mapping from gausspoints to BGM
  ALLOCATE(GaussBGMIndex(1:3,0:PP_N,0:PP_N,0:PP_N,1:nElems),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
    __STAMP__&
    ,'ERROR in pic_depo.f90: Cannot allocate GaussBGMIndex!')
  END IF
  ALLOCATE(GaussBGMFactor(1:3,0:PP_N,0:PP_N,0:PP_N,1:nElems),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
    __STAMP__&
    ,'ERROR in pic_depo.f90: Cannot allocate GaussBGMFactor!')
  END IF
  DO iElem = 1, nElems
    DO j = 0, PP_N
      DO k = 0, PP_N
        DO m = 0, PP_N
          GaussBGMIndex(1,j,k,m,iElem) = FLOOR(Elem_xGP(1,j,k,m,iElem)/BGMdeltas(1))
          GaussBGMIndex(2,j,k,m,iElem) = FLOOR(Elem_xGP(2,j,k,m,iElem)/BGMdeltas(2))
          GaussBGMIndex(3,j,k,m,iElem) = FLOOR(Elem_xGP(3,j,k,m,iElem)/BGMdeltas(3))
          GaussBGMFactor(1,j,k,m,iElem) = (Elem_xGP(1,j,k,m,iElem)/BGMdeltas(1))-REAL(GaussBGMIndex(1,j,k,m,iElem))
          GaussBGMFactor(2,j,k,m,iElem) = (Elem_xGP(2,j,k,m,iElem)/BGMdeltas(2))-REAL(GaussBGMIndex(2,j,k,m,iElem))
          GaussBGMFactor(3,j,k,m,iElem) = (Elem_xGP(3,j,k,m,iElem)/BGMdeltas(3))-REAL(GaussBGMIndex(3,j,k,m,iElem))
        END DO
      END DO
    END DO
  END DO
#if USE_MPI
  CALL MPIBackgroundMeshInit()
#else
  IF(GEO%nPeriodicVectors.GT.0)THEN
    ! Compute PeriodicBGMVectors (from PeriodicVectors and BGMdeltas)
    ALLOCATE(GEO%PeriodicBGMVectors(1:3,1:GEO%nPeriodicVectors),STAT=allocStat)
    IF (allocStat .NE. 0) THEN
      CALL abort(&
      __STAMP__&
      ,'ERROR in MPIBackgroundMeshInit: cannot allocate GEO%PeriodicBGMVectors!')
    END IF
    DO i = 1, GEO%nPeriodicVectors
      GEO%PeriodicBGMVectors(1,i) = NINT(GEO%PeriodicVectors(1,i)/BGMdeltas(1))
      IF(ABS(GEO%PeriodicVectors(1,i)/BGMdeltas(1)-REAL(GEO%PeriodicBGMVectors(1,i))).GT.1E-10)THEN
        CALL abort(&
        __STAMP__&
        ,'ERROR: Periodic Vector ist not multiple of background mesh delta')
      END IF
      GEO%PeriodicBGMVectors(2,i) = NINT(GEO%PeriodicVectors(2,i)/BGMdeltas(2))
      IF(ABS(GEO%PeriodicVectors(2,i)/BGMdeltas(2)-REAL(GEO%PeriodicBGMVectors(2,i))).GT.1E-10)THEN
        CALL abort(&
        __STAMP__&
        ,'ERROR: Periodic Vector ist not multiple of background mesh delta')
      END IF
      GEO%PeriodicBGMVectors(3,i) = NINT(GEO%PeriodicVectors(3,i)/BGMdeltas(3))
      IF(ABS(GEO%PeriodicVectors(3,i)/BGMdeltas(3)-REAL(GEO%PeriodicBGMVectors(3,i))).GT.1E-10)THEN
        CALL abort(&
        __STAMP__&
        ,'ERROR: Periodic Vector ist not multiple of background mesh delta')
      END IF
    END DO
  END IF
#endif
  ALLOCATE(BGMSource(BGMminX:BGMmaxX,BGMminY:BGMmaxY,BGMminZ:BGMmaxZ,1:4))
CASE('cartmesh_splines')
  BGMdeltas(1:3) = GETREALARRAY('PIC-BGMdeltas',3,'0. , 0. , 0.')
  FactorBGM(1:3) = GETREALARRAY('PIC-FactorBGM',3,'1. , 1. , 1.')
  BGMdeltas(1:3) = 1./FactorBGM(1:3)*BGMdeltas(1:3)
  IF (ANY(BGMdeltas.EQ.0)) THEN
    CALL abort(&
    __STAMP__&
    ,'ERROR: PIC-BGMdeltas: No size for the cartesian background mesh definded.')
  END IF
  ! calc min and max coordinates for local mesh
  xmin = 1.0E200
  ymin = 1.0E200
  zmin = 1.0E200
  xmax = -1.0E200
  ymax = -1.0E200
  zmax = -1.0E200
  DO iElem = 1, nElems
    xmin=MIN(xmin,MINVAL(XCL_NGeo(1,:,:,:,iElem)))
    xmax=MAX(xmax,MAXVAL(XCL_NGeo(1,:,:,:,iElem)))
    ymin=MIN(ymin,MINVAL(XCL_NGeo(2,:,:,:,iElem)))
    ymax=MAX(ymax,MAXVAL(XCL_NGeo(2,:,:,:,iElem)))
    zmin=MIN(zmin,MINVAL(XCL_NGeo(3,:,:,:,iElem)))
    zmax=MAX(zmax,MAXVAL(XCL_NGeo(3,:,:,:,iElem)))
  END DO
  ! define minimum and maximum backgroundmesh index, compute volume
  BGMVolume = BGMdeltas(1)*BGMdeltas(2)*BGMdeltas(3)
  BGMminX = FLOOR(xmin/BGMdeltas(1)-0.0001)-2
  BGMminY = FLOOR(ymin/BGMdeltas(2)-0.0001)-2
  BGMminZ = FLOOR(zmin/BGMdeltas(3)-0.0001)-2
  BGMmaxX = CEILING(xmax/BGMdeltas(1)+0.0001)+2
  BGMmaxY = CEILING(ymax/BGMdeltas(2)+0.0001)+2
  BGMmaxZ = CEILING(zmax/BGMdeltas(3)+0.0001)+2
  ! mapping from gausspoints to BGM
  ALLOCATE(GaussBGMIndex(1:3,0:PP_N,0:PP_N,0:PP_N,1:nElems),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
    __STAMP__&
    ,'ERROR in pic_depo.f90: Cannot allocate GaussBGMIndex!')
  END IF
  ALLOCATE(GaussBGMFactor(1:3,0:PP_N,0:PP_N,0:PP_N,1:nElems),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
    __STAMP__&
    ,'ERROR in pic_depo.f90: Cannot allocate GaussBGMFactor!')
  END IF
  DO iElem = 1, nElems
    DO j = 0, PP_N
      DO k = 0, PP_N
        DO m = 0, PP_N
          GaussBGMIndex(1,j,k,m,iElem) = FLOOR(Elem_xGP(1,j,k,m,iElem)/BGMdeltas(1))
          GaussBGMIndex(2,j,k,m,iElem) = FLOOR(Elem_xGP(2,j,k,m,iElem)/BGMdeltas(2))
          GaussBGMIndex(3,j,k,m,iElem) = FLOOR(Elem_xGP(3,j,k,m,iElem)/BGMdeltas(3))
        END DO
      END DO
    END DO
  END DO
  ! pre-build weights for BGM to gausspoint interpolation
  ALLOCATE(GPWeight(1:nElems,0:PP_N,0:PP_N,0:PP_N,1:4,1:4,1:4),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
    __STAMP__&
    ,'ERROR in pic_depo.f90: Cannot allocate GPWeight!')
  END IF
  DO iElem = 1, nElems
    DO j = 0, PP_N
      DO k = 0, PP_N
        DO m = 0, PP_N
          DO dir = 1,3               ! x,y,z direction
            DO weightrun = 0,3
              DO mm = 0, 3
                IF (mm.EQ.weightrun) then
                  auxiliary(mm) = 1.0
                ELSE
                  auxiliary(mm) = 0.0
                END IF
              END DO
              CALL DeBoor(GaussBGMIndex(dir,j,k,m,iElem),auxiliary,Elem_xGP(dir,j,k,m,iElem),weight(dir,weightrun),dir)
            END DO
          END DO
          DO r = 1,4
            DO s = 1,4
              DO t = 1,4
                GPWeight(iElem,j,k,m,r,s,t) = weight(1,-(r-4)) * weight(2,-(s-4)) * weight(3,-(t-4))
              END DO !t
            END DO !s
          END DO !r
        END DO !m
      END DO !k
    END DO !j
  END DO !iElem
#if USE_MPI
  CALL MPIBackgroundMeshInit()
#else
  IF(GEO%nPeriodicVectors.GT.0)THEN
    ! Compute PeriodicBGMVectors (from PeriodicVectors and BGMdeltas)
    ALLOCATE(GEO%PeriodicBGMVectors(1:3,1:GEO%nPeriodicVectors),STAT=allocStat)
    IF (allocStat .NE. 0) THEN
      CALL abort(&
      __STAMP__&
      ,'ERROR in MPIBackgroundMeshInit: cannot allocate GEO%PeriodicBGMVectors!')
    END IF
    DO i = 1, GEO%nPeriodicVectors
      GEO%PeriodicBGMVectors(1,i) = NINT(GEO%PeriodicVectors(1,i)/BGMdeltas(1))
      IF(ABS(GEO%PeriodicVectors(1,i)/BGMdeltas(1)-REAL(GEO%PeriodicBGMVectors(1,i))).GT.1E-10)THEN
        CALL abort(&
        __STAMP__ &
        ,'ERROR: Periodic Vector ist not multiple of background mesh delta')
      END IF
      GEO%PeriodicBGMVectors(2,i) = NINT(GEO%PeriodicVectors(2,i)/BGMdeltas(2))
      IF(ABS(GEO%PeriodicVectors(2,i)/BGMdeltas(2)-REAL(GEO%PeriodicBGMVectors(2,i))).GT.1E-10)THEN
        CALL abort(&
        __STAMP__&
        ,'ERROR: Periodic Vector ist not multiple of background mesh delta')
      END IF
      GEO%PeriodicBGMVectors(3,i) = NINT(GEO%PeriodicVectors(3,i)/BGMdeltas(3))
      IF(ABS(GEO%PeriodicVectors(3,i)/BGMdeltas(3)-REAL(GEO%PeriodicBGMVectors(3,i))).GT.1E-10)THEN
        CALL abort(&
        __STAMP__&
        ,'ERROR: Periodic Vector ist not multiple of background mesh delta')
      END IF
    END DO
  END IF
#endif
  ALLOCATE(BGMSource(BGMminX:BGMmaxX,BGMminY:BGMmaxY,BGMminZ:BGMmaxZ,1:4))
CASE DEFAULT
  CALL abort(&
  __STAMP__&
  ,'Unknown DepositionType in pic_depo.f90')
END SELECT

IF (PartSourceConstExists) THEN
  ALLOCATE(PartSourceConst(1:4,0:PP_N,0:PP_N,0:PP_N,nElems),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
__STAMP__&
,'ERROR in pic_depo.f90: Cannot allocate PartSourceConst!')
  END IF
  PartSourceConst=0.
END IF

SWRITE(UNIT_stdOut,'(A)')' INIT PARTICLE DEPOSITION DONE!'

END SUBROUTINE InitializeDeposition


SUBROUTINE Deposition(DoInnerParts,doParticle_In)
!============================================================================================================================
! This subroutine performs the deposition of the particle charge and current density to the grid
! following list of distribution methods are implemented
! - nearest blurrycenter (barycenter of hexahedra)
! - nearest Gauss Point  (only volume of IP - higher resolution than nearest blurrycenter )
! - shape function       (only one type implemented)
! - delta distribution
! useVMPF added, therefore, this routine contains automatically the use of variable mpfs
!============================================================================================================================
! use MODULES
USE MOD_PICDepo_Vars
USE MOD_Particle_Vars
USE MOD_PreProc
USE MOD_Globals
#if USE_MPI
USE MOD_Particle_MPI_Vars           ,ONLY: PartMPIExchange
#endif  /*USE_MPI*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers          ,ONLY: LBStartTime,LBPauseTime
#endif /*USE_LOADBALANCE*/
USE MOD_PICDepo_Method              ,ONLY: DepositionMethod
!-----------------------------------------------------------------------------------------------------------------------------------
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT variable declaration
LOGICAL,INTENT(IN)               :: DoInnerParts                           ! TODO: definition of this variable
LOGICAL,INTENT(IN),OPTIONAL      :: doParticle_In(1:PDM%ParticleVecLength) ! TODO: definition of this variable
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT variable declaration
!-----------------------------------------------------------------------------------------------------------------------------------
! Local variable declaration
!-----------------------------------------------------------------------------------------------------------------------------------
LOGICAL            :: doPartInExists
#if USE_LOADBALANCE
REAL               :: tLBStart
#endif /*USE_LOADBALANCE*/
INTEGER            :: FirstPart,LastPart
!============================================================================================================================
! Return, if no deposition is required
IF(.NOT.DoDeposition) RETURN

! Start time measurement for shape function deposition only
#if USE_LOADBALANCE
IF(TRIM(DepositionType(1:MIN(14,LEN(TRIM(ADJUSTL(DepositionType)))))).EQ.'shape_function')THEN
  CALL LBStartTime(tLBStart) ! Start time measurement
END IF ! TRIM(DepositionType(1:MIN(14,LEN(TRIM(ADJUSTL(DepositionType)))))).EQ.'shape_function'
#endif /*USE_LOADBALANCE*/

doPartInExists=.FALSE.
IF(PRESENT(doParticle_In)) doPartInExists=.TRUE.

IF(DoInnerParts)THEN
  PartSource = 0.0
  FirstPart  = 1
  LastPart   = PDM%ParticleVecLength
  !IF(FirstPart.GT.LastPart) RETURN
ELSE
#if USE_MPI
  FirstPart=PDM%ParticleVecLength-PartMPIExchange%nMPIParticles+1
  LastPart =PDM%ParticleVecLength
#else
  FirstPart=1
  LastPart =0
#endif /*USE_MPI*/
END IF

! Do the actual deposition (cell_volweight, shapefunction, spline etc.)
CALL DepositionMethod(FirstPart,LastPart,DoInnerParts,doPartInExists,doParticle_In)

! End time measurement for shape function deposition only
#if USE_LOADBALANCE
IF(TRIM(DepositionType(1:MIN(14,LEN(TRIM(ADJUSTL(DepositionType)))))).EQ.'shape_function')THEN
  CALL LBPauseTime(LB_DEPOSITION,tLBStart)
END IF ! TRIM(DepositionType(1:MIN(14,LEN(TRIM(ADJUSTL(DepositionType)))))).EQ.'shape_function'
#endif /*USE_LOADBALANCE*/

RETURN
END SUBROUTINE Deposition


SUBROUTINE FinalizeDeposition()
!----------------------------------------------------------------------------------------------------------------------------------!
! finalize pic deposition
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_PICDepo_Vars
USE MOD_Particle_Mesh_Vars,   ONLY:Geo
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

SDEALLOCATE(PartSource)
SDEALLOCATE(PartSourceConst)
SDEALLOCATE(PartSourceOld)
SDEALLOCATE(GaussBorder)
SDEALLOCATE(ElemDepo_xGP)
SDEALLOCATE(Vdm_EquiN_GaussN)
SDEALLOCATE(Knots)
SDEALLOCATE(GaussBGMIndex)
SDEALLOCATE(GaussBGMFactor)
SDEALLOCATE(GEO%PeriodicBGMVectors)
SDEALLOCATE(BGMSource)
SDEALLOCATE(GPWeight)
SDEALLOCATE(ElemRadius2_sf)
SDEALLOCATE(Vdm_NDepo_GaussN)
SDEALLOCATE(DDMassInv)
SDEALLOCATE(XiNDepo)
SDEALLOCATE(swGPNDepo)
SDEALLOCATE(wBaryNDepo)
SDEALLOCATE(NDepochooseK)
SDEALLOCATE(tempcharge)
SDEALLOCATE(CellVolWeightFac)
SDEALLOCATE(CellVolWeight_Volumes)
SDEALLOCATE(CellLocNodes_Volumes)
SDEALLOCATE(NodeSourceExt)
SDEALLOCATE(NodeSourceExtTmp)
END SUBROUTINE FinalizeDeposition

END MODULE MOD_PICDepo
