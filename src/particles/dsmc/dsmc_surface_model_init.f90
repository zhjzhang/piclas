#include "boltzplatz.h"

MODULE MOD_DSMC_SurfModelInit
!===================================================================================================================================
! Initialization of DSMC
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE InitDSMCSurfModel
  MODULE PROCEDURE InitDSMCSurfModel
END INTERFACE

INTERFACE FinalizeDSMCSurfModel
  MODULE PROCEDURE FinalizeDSMCSurfModel
END INTERFACE

!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC                       :: InitDSMCSurfModel
PUBLIC                       :: FinalizeDSMCSurfModel
!===================================================================================================================================

CONTAINS


SUBROUTINE InitDSMCSurfModel()
!===================================================================================================================================
! Init of DSMC Vars
!===================================================================================================================================
! MODULES
USE MOD_Globals,                ONLY : abort
USE MOD_Mesh_Vars,              ONLY : nElems!, BC
USE MOD_DSMC_Vars,              ONLY : Adsorption, DSMC!, CollisMode
USE MOD_PARTICLE_Vars,          ONLY : nSpecies, PDM
USE MOD_PARTICLE_Vars,          ONLY : KeepWallParticles, PEM
USE MOD_Particle_Mesh_Vars,     ONLY : nTotalSides
USE MOD_ReadInTools
USE MOD_Particle_Boundary_Vars, ONLY : nSurfSample, SurfMesh!, PartBound
#ifdef MPI
USE MOD_Particle_Boundary_Vars, ONLY : SurfCOMM
USE MOD_Particle_MPI_Vars     , ONLY : AdsorbSendBuf,AdsorbRecvBuf,SurfExchange
#endif
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES                                                                      !
  CHARACTER(32)                    :: hilf
  INTEGER                          :: iSpec, iSide!, iSurf, IDcounter
#ifdef MPI
  INTEGER                          :: iProc
#endif
!===================================================================================================================================
KeepWallParticles = GETLOGICAL('Particles-KeepWallParticles','.FALSE.')
IF (KeepWallParticles) THEN
  ALLOCATE(PDM%ParticleAtWall(1:PDM%maxParticleNumber)  , &
          PDM%PartAdsorbSideIndx(1:3,1:PDM%maxParticleNumber))
  PDM%ParticleAtWall(1:PDM%maxParticleNumber) = .FALSE.
  ALLOCATE(PEM%wNumber(1:nElems))
END IF
! allocate info and constants
#if (PP_TimeDiscMethod==42)
ALLOCATE( Adsorption%AdsorpInfo(1:nSpecies))
#endif
IF (DSMC%WallModel.EQ.1) THEN 
  ALLOCATE( Adsorption%MaxCoverage(1:SurfMesh%nSides,1:nSpecies),& 
            Adsorption%InitStick(1:SurfMesh%nSides,1:nSpecies),& 
            Adsorption%PrefactorStick(1:SurfMesh%nSides,1:nSpecies),& 
            Adsorption%Adsorbexp(1:SurfMesh%nSides,1:nSpecies),& 
            Adsorption%Nu_a(1:SurfMesh%nSides,1:nSpecies),& 
            Adsorption%Nu_b(1:SurfMesh%nSides,1:nSpecies),& 
            Adsorption%DesorbEnergy(1:SurfMesh%nSides,1:nSpecies),& 
            Adsorption%Intensification(1:SurfMesh%nSides,1:nSpecies))
ELSE IF (DSMC%WallModel.GT.1) THEN 
  ALLOCATE( Adsorption%HeatOfAdsZero(1:nSpecies),&
            Adsorption%Coordination(1:nSpecies),&
            Adsorption%DiCoord(1:nSpecies))
  ! initialize info and constants
END IF
DO iSpec = 1,nSpecies
#if (PP_TimeDiscMethod==42)
  Adsorption%AdsorpInfo(iSpec)%MeanProbAds = 0.
  Adsorption%AdsorpInfo(iSpec)%MeanProbDes = 0.
  Adsorption%AdsorpInfo(iSpec)%MeanEads = 0.
  Adsorption%AdsorpInfo(iSpec)%WallCollCount = 0
  Adsorption%AdsorpInfo(iSpec)%WallSpecNumCount = 0
  Adsorption%AdsorpInfo(iSpec)%NumOfAds = 0
  Adsorption%AdsorpInfo(iSpec)%NumOfDes = 0
  Adsorption%AdsorpInfo(iSpec)%Accomodation = 0
#endif
  WRITE(UNIT=hilf,FMT='(I2)') iSpec
  IF (DSMC%WallModel.EQ.1) THEN
    Adsorption%MaxCoverage(:,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-MaximumCoverage','0.')
    Adsorption%InitStick(:,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-InitialStick','0.')
    Adsorption%PrefactorStick(:,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-PrefactorStick','0.')
    Adsorption%Adsorbexp(:,iSpec) = GETINT('Part-Species'//TRIM(hilf)//'-Adsorbexp','1')
    Adsorption%Nu_a(:,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Nu-a','0.')
    Adsorption%Nu_b(:,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Nu-b','0.')
    Adsorption%DesorbEnergy(:,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Desorption-Energy-K','1.')
    Adsorption%Intensification(:,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Intensification-K','0.')
  ELSE IF (DSMC%WallModel.GT.1) THEN 
    Adsorption%Coordination(iSpec) = GETINT('Part-Species'//TRIM(hilf)//'-Coordination','0')
    Adsorption%DiCoord(iSpec) = GETINT('Part-Species'//TRIM(hilf)//'-DiCoordination','0')
    Adsorption%HeatOfAdsZero(iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-HeatOfAdsorption-K','0.')
  END IF
END DO
! initialize surface atom mass: if not set define as atom mass of Pt
IF (DSMC%WallModel.GT.1) Adsorption%SurfMassIC = GETREAL('Part-Species'//TRIM(hilf)//'-SurfMassIC','3.2395E-25')

#if (PP_TimeDiscMethod==42)
  Adsorption%TPD = GETLOGICAL('Particles-DSMC-Adsorption-doTPD','.FALSE.')
  Adsorption%TPD_beta = GETREAL('Particles-DSMC-Adsorption-TPD-Beta','0.')
  Adsorption%TPD_Temp = 0.
#endif
! allocate and initialize adsorption variables
ALLOCATE( Adsorption%Coverage(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%ProbAds(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%ProbDes(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%SumDesorbPart(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%SumReactPart(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%SumAdsorbPart(1:nSurfSample,1:nSurfSample,1:SurfMesh%nTotalSides,1:nSpecies),&
          Adsorption%SurfSideToGlobSideMap(1:SurfMesh%nTotalSides),&
          Adsorption%DensSurfAtoms(1:SurfMesh%nTotalSides))
IF (DSMC%WallModel.EQ.2) THEN
  ALLOCATE( Adsorption%ProbSigAds(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies,1:36*nSpecies),&
            Adsorption%ProbSigDes(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies,1:36*nSpecies),&
            Adsorption%Sigma(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies,1:36*nSpecies),&
            Adsorption%ProbSigma(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies,1:36*nSpecies))
END IF
! IDcounter = 0
Adsorption%SurfSideToGlobSideMap(:) = -1
DO iSide = 1,nTotalSides
!   IF(BC(iSide).EQ.0) CYCLE
!   IF (PartBound%TargetBoundCond(PartBound%MapToPartBC(BC(iSide))).EQ.PartBound%ReflectiveBC) THEN
!     IDcounter = IDcounter + 1
!     Adsorption%SurfSideToGlobSideMap(IDcounter) = iSide
!   END IF
  IF (SurfMesh%SideIDToSurfID(iSide).LE.0) CYCLE
  Adsorption%SurfSideToGlobSideMap(SurfMesh%SideIDToSurfID(iSide)) = iSide
END DO
! DO iSurf = 1,SurfMesh%nSides
!   WRITE(UNIT=hilf,FMT='(I2)') iSurf
!   Adsorption%DensSurfAtoms(iSurf) = GETREAL('Particles-Surface'//TRIM(hilf)//'-AtomsDensity','1.0E+19')
! END DO
! extend later to different densities for each boundary
Adsorption%DensSurfAtoms(:) = GETREAL('Particles-Surface-AtomsDensity','1.0E+19')

DO iSpec = 1,nSpecies
  WRITE(UNIT=hilf,FMT='(I2)') iSpec
  Adsorption%Coverage(:,:,:,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-InitialCoverage','0.')
END DO
Adsorption%ProbAds(:,:,:,:) = 0.
Adsorption%ProbDes(:,:,:,:) = 0.
Adsorption%SumDesorbPart(:,:,:,:) = 0
Adsorption%SumAdsorbPart(:,:,:,:) = 0
Adsorption%SumReactPart(:,:,:,:) = 0

#ifdef MPI
! allocate send and receive buffer
ALLOCATE(AdsorbSendBuf(SurfCOMM%nMPINeighbors))
ALLOCATE(AdsorbRecvBuf(SurfCOMM%nMPINeighbors))
DO iProc=1,SurfCOMM%nMPINeighbors
  ALLOCATE(AdsorbSendBuf(iProc)%content_int(nSpecies*(nSurfSample**2)*SurfExchange%nSidesSend(iProc)))
  ALLOCATE(AdsorbRecvBuf(iProc)%content_int(nSpecies*(nSurfSample**2)*SurfExchange%nSidesRecv(iProc)))
  AdsorbSendBuf(iProc)%content_int=0
  AdsorbRecvBuf(iProc)%content_int=0
END DO ! iProc
#endif /*MPI*/

IF (DSMC%WallModel.EQ.2) THEN
  Adsorption%ProbSigAds(:,:,:,:,:) = 0.
  Adsorption%ProbSigDes(:,:,:,:,:) = 0.
  Adsorption%Sigma(:,:,:,:,:) = 1.
  Adsorption%ProbSigma(:,:,:,:,:) = 0.
END IF

IF (DSMC%WallModel.GT.1) THEN
  CALL Init_SurfDist()
!   IF (CollisMode.EQ.3) 
  CALL Init_SurfChem()
END IF

END SUBROUTINE InitDSMCSurfModel

SUBROUTINE Init_SurfDist()
!===================================================================================================================================
! Initializing surface distibution Model for calculating of coverage effects on heat of adsorption
!===================================================================================================================================
  USE MOD_Globals,                ONLY : abort, MPIRoot, UNIT_StdOut
  USE MOD_ReadInTools
  USE MOD_Particle_Vars,          ONLY : nSpecies, Species, KeepWallParticles
  USE MOD_DSMC_Vars,              ONLY : Adsorption, SurfDistInfo
  USE MOD_Particle_Boundary_Vars, ONLY : nSurfSample, SurfMesh
  USE MOD_DSMC_SurfModel_Tools,   ONLY : CalcDiffusion
#ifdef MPI
  USE MOD_Particle_Boundary_Vars, ONLY : SurfCOMM
  USE MOD_Particle_MPI_Vars,      ONLY : SurfDistSendBuf,SurfDistRecvBuf,SurfExchange, NbrSurfPos
  USE MOD_DSMC_SurfModel_Tools,   ONLY : ExchangeSurfDistInfo
#endif /*MPI*/
!===================================================================================================================================
  IMPLICIT NONE
!=================================================================================================================================== 
! Local variable declaration
  INTEGER                          :: iSurfSide, subsurfxi, subsurfeta, iSpec, iInterAtom
  INTEGER                          :: surfsquare, dist, Adsorbates
  INTEGER                          :: Surfpos, Surfnum, Indx, Indy, UsedSiteMapPos
  REAL                             :: RanNum
  INTEGER                          :: xpos, ypos
  INTEGER                          :: Coord, nSites, nInterAtom, nNeighbours
#ifdef MPI
  INTEGER                          :: iProc, CommSize
#endif
!===================================================================================================================================
! position of binding sites in the surface lattice (rectangular lattice)
!------------[        surfsquare       ]--------------
!             |       |       |       |
!         3---2---3---2---3---2---3---2---3
!         |       |       |       |       |
!         2   1   2   1   2   1   2   1   2
!         |       |       |       |       |
!         3---2---3---2---3---2---3---2---3
!         |       |       |       |       |
!         2   1   2   1   2   1   2   1   2
!         |       |       |       |       |
!         3---2---3---2---3---2---3---2---3
!         |       |       |       |       |
!         2   1   2   1   2   1   2   1   2
!         |       |       |       |       |
!         3---2---3---2---3---2---3---2---3
!         |       |       |       |       |
!         2   1   2   1   2   1   2   1   2
!         |       |       |       |       |
!         3---2---3---2---3---2---3---2---3
! For now:
! Neighbours are all sites, that have the same binding surface atom. 
! Except for top sites(3) they also interact with the next top site.
SWRITE(UNIT_stdOut,'(A)')' INIT SURFACE DISTRIBUTION...'
ALLOCATE(SurfDistInfo(1:nSurfSample,1:nSurfSample,1:SurfMesh%nTotalSides))
DO iSurfSide = 1,SurfMesh%nTotalSides
  DO subsurfeta = 1,nSurfSample
  DO subsurfxi = 1,nSurfSample
    ALLOCATE( SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(1:3),&
              SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SitesRemain(1:3),&
              SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%adsorbnum_tmp(1:nSpecies),&
              SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%desorbnum_tmp(1:nSpecies),&
              SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%reactnum_tmp(1:nSpecies))
  END DO
  END DO
END DO
IF (.NOT.KeepWallParticles) THEN
  surfsquare = GETINT('Particles-DSMC-AdsorptionSites','10000')
  surfsquare = INT(SQRT(REAL(surfsquare))) - 1
END IF

DO iSurfSide = 1,SurfMesh%nTotalSides
  DO subsurfeta = 1,nSurfSample
  DO subsurfxi = 1,nSurfSample
    IF (KeepWallParticles) THEN ! does not work with vMPF
      surfsquare = INT(Adsorption%DensSurfAtoms(iSurfSide) &
                    * SurfMesh%SurfaceArea(subsurfxi,subsurfeta,iSurfSide) &
                    / Species(1)%MacroParticleFactor)
      surfsquare = INT(SQRT(REAL(surfsquare))) - 1
    END IF
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(1) = INT(surfsquare**2)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(2) = INT( 2*(surfsquare*(surfsquare+1)) )
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(3) = INT((surfsquare+1)**2)
#ifdef MPI
    NbrSurfPos = SUM(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(:))
#endif /*MPI*/
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SitesRemain(:) = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(:)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%adsorbnum_tmp(1:nSpecies) = 0.
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%desorbnum_tmp(1:nSpecies) = 0.
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%reactnum_tmp(1:nSpecies) = 0.
    
    ALLOCATE( SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SurfAtomBondOrder(1:nSpecies,1:surfsquare+1,1:surfsquare+1))
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SurfAtomBondOrder(:,:,:) = 0
    
    ALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1:3))
    DO Coord = 1,3    
      SELECT CASE (Coord)
      CASE(1)
        nSites = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(Coord)
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%nInterAtom = 4
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%nNeighbours = 16
      CASE(2)
        nSites = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(Coord)
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%nInterAtom = 2
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%nNeighbours = 14
      CASE(3)
        nSites = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(Coord)
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%nInterAtom = 1
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%nNeighbours = 12
      END SELECT
        
      nInterAtom = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%nInterAtom
      nNeighbours = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%nNeighbours
      ALLOCATE( SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%BondAtomIndx(1:nSites,nInterAtom),&
                SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%BondAtomIndy(1:nSites,nInterAtom),&
                SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%NeighPos(1:nSites,1:nNeighbours),&
                SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%NeighSite(1:nSites,1:nNeighbours))
      ALLOCATE( SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%UsedSiteMap(1:nSites),&
                SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%Species(1:nSites))
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%UsedSiteMap(:) = 0
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%Species(:) = 0
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%BondAtomIndx(:,:) = 0
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%BondAtomIndy(:,:) = 0
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%NeighPos(:,:) = 0
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%NeighSite(:,:) = 0
    END DO
  END DO
  END DO
END DO

DO iSurfSide = 1,SurfMesh%nTotalSides
DO subsurfeta = 1,nSurfSample
DO subsurfxi = 1,nSurfSample
  ! surfsquare chosen from nSite(1) for correct SurfIndx definitions
  surfsquare = INT(SQRT(REAL(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(1))))
  ! allocate and define surface indexes for adsorbate distribution and build mapping of respective bondatoms and neighbours      
  Indx = 1
  Indy = 1
  DO Surfpos = 1,SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(1)
    IF (Indx.GT.surfsquare) THEN
      Indx = 1
      Indy = Indy + 1
    END IF
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%UsedSiteMap(Surfpos) = Surfpos
    ! mapping respective neighbours first hollow then bridge then top
    ! hollow
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,1) = Surfpos - surfsquare - 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,2) = Surfpos - surfsquare
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,3) = Surfpos - surfsquare + 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,4) = Surfpos - 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,5) = Surfpos + 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,6) = Surfpos + surfsquare - 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,7) = Surfpos + surfsquare
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,8) = Surfpos + surfsquare + 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,1:8) = 1
    ! bridge
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,9) = Surfpos +(surfsquare+1)*(Indy-1)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,10) = Surfpos +surfsquare +(surfsquare+1)*(Indy-1)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,11) = Surfpos +surfsquare +(surfsquare+1)*(Indy-1) +1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,12) = Surfpos +surfsquare +(surfsquare+1)*(Indy)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,9:12) = 2
    ! top
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,13) = Surfpos + (Indy-1)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,14) = Surfpos + 1 + (Indy-1)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,15) = Surfpos + (surfsquare+1) + (Indy-1)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighPos(Surfpos,16) = Surfpos + (surfsquare+1) + 1 + (Indy-1)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,13:16) = 3
    ! account for empty edges
    IF (Indy .EQ. 1) SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,1:3) = 0
    IF (Indy .EQ. surfsquare) SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,6:8) = 0
    IF (Indx .EQ. 1) THEN
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,1) = 0
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,4) = 0
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,6) = 0
    END IF
    IF (Indx .EQ. surfsquare) THEN
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,3) = 0
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,5) = 0
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%NeighSite(Surfpos,8) = 0
    END IF
    ! mapping respective bond atoms
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%BondAtomIndx(Surfpos,1) = Indx
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%BondAtomIndy(Surfpos,1) = Indy
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%BondAtomIndx(Surfpos,2) = Indx+1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%BondAtomIndy(Surfpos,2) = Indy
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%BondAtomIndx(Surfpos,3) = Indx
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%BondAtomIndy(Surfpos,3) = Indy+1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%BondAtomIndx(Surfpos,4) = Indx+1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(1)%BondAtomIndy(Surfpos,4) = Indy+1
    Indx = Indx + 1
  END DO
  Indx = 1
  Indy = 1
  DO Surfpos = 1,SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(2)
    IF (Indx.GT.(2*surfsquare+1)) THEN
      Indx = 1
      Indy = Indy + 1
    END IF
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%UsedSiteMap(Surfpos) = Surfpos
    IF (Indx .LE. surfsquare) THEN ! surface atoms are LEFT an RIGHT of adsorbate site
      ! mapping respective neighbours first hollow then bridge then top
      ! hollow
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,1) = Surfpos-surfsquare -(surfsquare+1)*(Indy-1) -1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,2) = Surfpos-surfsquare -(surfsquare+1)*(Indy-1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,3) = Surfpos-surfsquare -(surfsquare+1)*(Indy-1) +1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,4) = Surfpos -(surfsquare+1)*(Indy-1) -1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,5) = Surfpos -(surfsquare+1)*(Indy-1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,6) = Surfpos -(surfsquare+1)*(Indy-1) +1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,1:6) = 1
      ! bridge
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,7) = Surfpos - (surfsquare+1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,8) = Surfpos - (surfsquare+1) + 1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,9) = Surfpos - 1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,10) = Surfpos + 1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,11) = Surfpos + surfsquare
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,12) = Surfpos + surfsquare + 1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,7:12) = 2
      ! top
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,13) = Surfpos -(surfsquare)*(Indy-1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,14) = Surfpos +1 -(surfsquare)*(Indy-1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,13:14) = 3
      ! account for empty edges
      IF (Indy .EQ. 1) THEN
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,1:3) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,7:8) = 0
      END IF
      IF (Indy .EQ. surfsquare+1) THEN
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,4:6) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,11:12) = 0
      END IF
      IF (Indx .EQ. 1) THEN
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,1) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,4) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,9) = 0
      END IF
      IF (Indx .EQ. surfsquare) THEN
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,3) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,6) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,10) = 0
      END IF
      ! mapping respective bond atoms
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%BondAtomIndx(Surfpos,1) = Indx
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%BondAtomIndy(Surfpos,1) = Indy
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%BondAtomIndx(Surfpos,2) = Indx+1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%BondAtomIndy(Surfpos,2) = Indy
    ELSE ! surface atoms are TOP and DOWN of adsorbate site
      ! mapping respective neighbours first hollow then bridge then top
      ! hollow
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,1) = Surfpos -(2*surfsquare) &
                                                                                  -(surfsquare+1)*(Indy-1) -1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,2) = Surfpos -(2*surfsquare)&
                                                                                  -(surfsquare+1)*(Indy-1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,3) = Surfpos -surfsquare &
                                                                                  -(surfsquare+1)*(Indy-1) -1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,4) = Surfpos - surfsquare -(surfsquare+1)*(Indy-1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,5) = Surfpos -(surfsquare+1)*(Indy-1) -1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,6) = Surfpos -(surfsquare+1)*(Indy-1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,1:6) = 1
      ! bridge
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,7) = Surfpos - surfsquare - (surfsquare+1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,8) = Surfpos - surfsquare - 1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,9) = Surfpos - surfsquare
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,10) = Surfpos + (surfsquare+1) - 1
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,11) = Surfpos + (surfsquare+1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,12) = Surfpos + surfsquare + (surfsquare+1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,7:12) = 2
      ! top
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,13) = Surfpos -surfsquare*(Indy)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighPos(Surfpos,14) = Surfpos -surfsquare*(Indy) +(surfsquare+1)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,13:14) = 3
      ! account for empty edges
      IF (Indy .EQ. 1) THEN
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,1:2) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,7) = 0
      END IF
      IF (Indy .EQ. surfsquare) THEN
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,5:6) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,12) = 0
      END IF
      IF (Indx .EQ. (surfsquare+1)) THEN
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,1) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,3) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,5) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,8) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,10) = 0
      END IF
      IF (Indx .EQ. 2*surfsquare+1) THEN
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,2) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,4) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,6) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,9) = 0
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%NeighSite(Surfpos,11) = 0
      END IF
      ! mapping respective bond atoms
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%BondAtomIndx(Surfpos,1) = Indx - surfsquare
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%BondAtomIndy(Surfpos,1) = Indy 
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%BondAtomIndx(Surfpos,2) = Indx - surfsquare
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(2)%BondAtomIndy(Surfpos,2) = Indy+1
    END IF
    Indx = Indx + 1
  END DO
  Indx = 1
  Indy = 1
  DO Surfpos = 1,SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(3)
    IF (Indx.GT.surfsquare+1) THEN
      Indx = 1
      Indy = Indy + 1
    END IF
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%UsedSiteMap(Surfpos) = Surfpos
    ! mapping respective neighbours first hollow then bridge then top
    ! hollow
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,1) = Surfpos - (surfsquare+1) - 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,2) = Surfpos - (surfsquare+1)
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,3) = Surfpos - surfsquare + 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,4) = Surfpos - 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighSite(Surfpos,1:4) = 1
    ! bridge
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,5) = Surfpos + 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,6) = Surfpos + surfsquare - 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,7) = Surfpos + surfsquare
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,8) = Surfpos + surfsquare + 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighSite(Surfpos,5:8) = 2
    ! top
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,9) = Surfpos - surfsquare - 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,10) = Surfpos - surfsquare
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,11) = Surfpos - surfsquare + 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighPos(Surfpos,12) = Surfpos - surfsquare + 1
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%NeighSite(Surfpos,9:12) = 3
    ! mapping respective bond atoms
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%BondAtomIndx(Surfpos,1) = Indx
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(3)%BondAtomIndy(Surfpos,1) = Indy
    Indx = Indx + 1
  END DO
  
END DO
END DO
END DO

DO iSurfSide = 1,SurfMesh%nSides
DO subsurfeta = 1,nSurfSample
DO subsurfxi = 1,nSurfSample    
  DO iSpec = 1,nSpecies
    ! adjust coverage to actual discret value
    Adsorbates = INT(Adsorption%Coverage(subsurfxi,subsurfeta,iSurfSide,iSpec) &
                * SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(Adsorption%Coordination(iSpec)))
    Adsorption%Coverage(subsurfxi,subsurfeta,iSurfSide,iSpec) = REAL(Adsorbates) &
        / REAL(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites(3))
    IF (SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SitesRemain(Adsorption%Coordination(iSpec)).LT.Adsorbates) THEN
      CALL abort(&
      __STAMP__&
      ,'Error in Init_SurfDist: Too many Adsorbates! - Choose lower Coverages for coordination:',Adsorption%Coordination(iSpec))
    END IF
    ! distribute adsorbates randomly on the surface on the correct site and assign surface atom bond order
    dist = 1
    Coord = Adsorption%Coordination(iSpec)
    Surfnum = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SitesRemain(Coord)
    DO WHILE (dist.LE.Adsorbates) 
      CALL RANDOM_NUMBER(RanNum)
      Surfpos = 1 + INT(Surfnum * RanNum)
      UsedSiteMapPos = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%UsedSiteMap(Surfpos)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%Species(UsedSiteMapPos) = iSpec
      ! assign bond order of respective surface atoms in the surfacelattice
      DO iInterAtom = 1,SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%nInterAtom
        xpos = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%BondAtomIndx(UsedSiteMapPos,iInterAtom)
        ypos = SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%BondAtomIndy(UsedSiteMapPos,iInterAtom)
        SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SurfAtomBondOrder(iSpec,xpos,ypos) = &
          SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SurfAtomBondOrder(iSpec,xpos,ypos) + 1
      END DO
      ! rearrange UsedSiteMap-Surfpos-array
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%UsedSiteMap(Surfpos) = &
          SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%UsedSiteMap(Surfnum)
      SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(Coord)%UsedSiteMap(Surfnum) = UsedSiteMapPos
      Surfnum = Surfnum - 1
      dist = dist + 1
    END DO
    SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SitesRemain(Coord) = Surfnum
  END DO
END DO
END DO
END DO

! initial distribution into equilibrium distribution
#if (PP_TimeDiscMethod==42)
  DO i=1,3
    CALL CalcDiffusion()
  END DO
#endif

#ifdef MPI
 CommSize = 3 + 2*NbrSurfPos! nCoord*1(SitesRemain) + 2*Number_of_surface_positions(position_mapping+species_on_position)
! allocate send and receive buffer
ALLOCATE(SurfDistSendBuf(SurfCOMM%nMPINeighbors))
ALLOCATE(SurfDistRecvBuf(SurfCOMM%nMPINeighbors))
DO iProc=1,SurfCOMM%nMPINeighbors
  ALLOCATE(SurfDistSendBuf(iProc)%content_int(CommSize*(nSurfSample**2)*SurfExchange%nSidesSend(iProc)))
  ALLOCATE(SurfDistRecvBuf(iProc)%content_int(CommSize*(nSurfSample**2)*SurfExchange%nSidesRecv(iProc)))
  SurfDistSendBuf(iProc)%content_int=0.
  SurfDistRecvBuf(iProc)%content_int=0.
END DO ! iProc

! fill halo surface distribution through mpi communication
CALL ExchangeSurfDistInfo()
#endif /*MPI*/

SWRITE(UNIT_stdOut,'(A)')' INIT SURFACE DISTRIBUTION DONE!'
    
END SUBROUTINE Init_SurfDist

SUBROUTINE Init_SurfChem()
!===================================================================================================================================
! Initializing surface reaction variables
!===================================================================================================================================
! MODULES
USE MOD_Globals,                ONLY : abort, MPIRoot, UNIT_StdOut
USE MOD_DSMC_Vars,              ONLY : Adsorption, SpecDSMC
USE MOD_PARTICLE_Vars,          ONLY : nSpecies
USE MOD_ReadInTools
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  CHARACTER(32)                    :: hilf, hilf2
  INTEGER                          :: iSpec, iSpec2, iReactNum, iReactNum2
  INTEGER                          :: ReactNum
  INTEGER                          :: MaxDissNum, MaxReactNum, MaxAssocNum
  INTEGER , ALLOCATABLE            :: nAssocReact(:)
!===================================================================================================================================
SWRITE(UNIT_stdOut,'(A)')' INIT SURFACE CHEMISTRY...'

! Adsorption constants
ALLOCATE( Adsorption%Ads_Powerfactor(1:nSpecies),&
          Adsorption%Ads_Prefactor(1:nSpecies))!,&
!           Adsorption%ER_Powerfactor(1:nSpecies),&
!           Adsorption%ER_Prefactor(1:nSpecies))
DO iSpec = 1,nSpecies            
  WRITE(UNIT=hilf,FMT='(I2)') iSpec
  Adsorption%Ads_Powerfactor(iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Adsorption-Powerfactor','0.')
  Adsorption%Ads_Prefactor(iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Adsorption-Prefactor','0.')
!   Adsorption%ER_Powerfactor(iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-ER-Adsorption-Powerfactor','0.')
!   Adsorption%ER_Prefactor(iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-ER-Adsorption-Prefactor','0.')
END DO

MaxDissNum = GETINT('Part-Species-MaxDissNum','0')
MaxAssocNum = MaxDissNum

! allocate and initialize dissociative and associative reactions species map
IF ( (MaxDissNum.GT.0) .OR. (MaxAssocNum.GT.0) ) THEN
  ALLOCATE( Adsorption%DissocReact(1:2,1:MaxDissNum,1:nSpecies),&
            Adsorption%Diss_Powerfactor(1:MaxDissNum,1:nSpecies),&
            Adsorption%Diss_Prefactor(1:MaxDissNum,1:nSpecies))
  ! Read in dissociative reactions and respective dissociation bond energies
  DO iSpec = 1,nSpecies            
    WRITE(UNIT=hilf,FMT='(I2)') iSpec
    DO iReactNum = 1,MaxDissNum
      WRITE(UNIT=hilf2,FMT='(I2)') iReactNum
      Adsorption%DissocReact(:,iReactNum,iSpec) = &
                                       GETINTARRAY('Part-Species'//TRIM(hilf)//'-SurfDiss'//TRIM(hilf2)//'-Products',2,'0,0')
      IF ((Adsorption%DissocReact(1,iReactNum,iSpec).GT.nSpecies).OR.(Adsorption%DissocReact(2,iReactNum,iSpec).GT.nSpecies) ) THEN
        CALL abort(&
        __STAMP__&
        ,'Error in Init_SurfChem: Product species for reaction '//TRIM(hilf2)//' not defined!')
      END IF
      Adsorption%Diss_Powerfactor(iReactNum,iSpec) = &
                                       GETREAL('Part-Species'//TRIM(hilf)//'-SurfDiss'//TRIM(hilf2)//'-Powerfactor','0.')
      Adsorption%Diss_Prefactor(iReactNum,iSpec) = &
                                       GETREAL('Part-Species'//TRIM(hilf)//'-SurfDiss'//TRIM(hilf2)//'-Prefactor','0.')
    END DO
  END DO
  
  ! find max number of associative reactions for each species from dissociations
  ALLOCATE(nAssocReact(1:nSpecies))
  nAssocReact(:) = 0
  DO iSpec = 1,nSpecies
    DO iSpec2 = 1,nSpecies
    DO iReactNum = 1,MaxDissNum
      IF ((Adsorption%DissocReact(1,iReactNum,iSpec2).EQ.iSpec).OR.(Adsorption%DissocReact(2,iReactNum,iSpec2).EQ.iSpec) ) THEN
        nAssocReact(iSpec) = nAssocReact(iSpec) + 1
      END IF
    END DO
    END DO
  END DO
  MaxAssocNum = MAXVAL(nAssocReact)
  DEALLOCATE(nAssocReact)
  
  ! fill associative reactions species map from defined dissociative reactions
  MaxReactNum = MaxDissNum + MaxAssocNum
  ALLOCATE( Adsorption%AssocReact(1:2,1:MaxAssocNum,1:nSpecies),&
            Adsorption%EDissBond(0:MaxReactNum,1:nSpecies),&
            Adsorption%EDissBondAdsorbPoly(0:1,1:nSpecies))
  Adsorption%EDissBond(0:MaxReactNum,1:nSpecies) = 0.
  Adsorption%EDissBondAdsorbPoly(0:1,1:nSpecies) = 0.
  DO iSpec = 1,nSpecies            
    WRITE(UNIT=hilf,FMT='(I2)') iSpec
    DO iReactNum = 1,MaxDissNum
      WRITE(UNIT=hilf2,FMT='(I2)') iReactNum
      Adsorption%EDissBond(iReactNum,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-SurfDiss'//TRIM(hilf2)//'-EDissBond','0.')
    END DO
    IF (SpecDSMC(iSpec)%InterID.EQ.2) THEN
      Adsorption%EDissBond(0,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Adsorption-EDissBond','0.')
      IF(SpecDSMC(iSpec)%PolyatomicMol) THEN
        Adsorption%EDissBondAdsorbPoly(0,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Adsorption-EDissBondPoly1','0.')
        Adsorption%EDissBondAdsorbPoly(1,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Adsorption-EDissBondPoly2','0.')
      END IF
    END IF
  END DO
  DO iSpec = 1,nSpecies
    ReactNum = 1
    DO iSpec2 = 1,nSpecies
    DO iReactNum2 = 1,MaxDissNum
      IF (Adsorption%DissocReact(1,iReactNum2,iSpec2).EQ.iSpec) THEN
        Adsorption%AssocReact(1,ReactNum,iSpec) = Adsorption%DissocReact(2,iReactNum2,iSpec2)
        Adsorption%AssocReact(2,ReactNum,iSpec) = iSpec2
        Adsorption%EDissBond((MaxDissNum+ReactNum),iSpec) = Adsorption%EDissBond(iReactNum2,iSpec2)
        ReactNum = ReactNum + 1
      ELSE IF (Adsorption%DissocReact(2,iReactNum2,iSpec2).EQ.iSpec) THEN
        Adsorption%AssocReact(1,ReactNum,iSpec) = Adsorption%DissocReact(1,iReactNum2,iSpec2)
        Adsorption%AssocReact(2,ReactNum,iSpec) = iSpec2
        Adsorption%EDissBond((MaxDissNum+ReactNum),iSpec) = Adsorption%EDissBond(iReactNum2,iSpec2)
        ReactNum = ReactNum + 1
      ELSE
        CYCLE
      END IF
    END DO
    END DO
    IF (ReactNum.LE.(MaxAssocNum)) THEN
      Adsorption%AssocReact(:,ReactNum:(MaxReactNum-MaxDissNum),iSpec) = 0
    END IF
  END DO
ELSE !MaxDissNum = 0
  MaxReactNum = 0
  ALLOCATE(Adsorption%EDissBond(0:1,1:nSpecies))
  ALLOCATE(Adsorption%EDissBondAdsorbPoly(0:1,1:nSpecies))
  Adsorption%EDissBond(:,:)=0.
  Adsorption%EDissBondAdsorbPoly(:,:) = 0.
  DO iSpec = 1,nSpecies
    WRITE(UNIT=hilf,FMT='(I2)') iSpec
    IF (SpecDSMC(iSpec)%InterID.EQ.2) THEN
      Adsorption%EDissBond(0,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Adsorption-EDissBond','0.')
      IF(SpecDSMC(iSpec)%PolyatomicMol) THEN
        Adsorption%EDissBondAdsorbPoly(0,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Adsorption-EDissBondPoly1','0.')
        Adsorption%EDissBondAdsorbPoly(1,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-Adsorption-EDissBondPoly2','0.')
      END IF
    END IF
  END DO
END IF !MaxDissNum > 0
! save defined number of surface reactions
Adsorption%DissNum = MaxDissNum
Adsorption%ReactNum = MaxReactNum

END SUBROUTINE Init_SurfChem

SUBROUTINE FinalizeDSMCSurfModel()
!===================================================================================================================================
! Deallocate Surface model vars
!===================================================================================================================================
! MODULES
USE MOD_DSMC_Vars,              ONLY : Adsorption, SurfDistInfo
USE MOD_PARTICLE_Vars,          ONLY : PDM, PEM
USE MOD_Particle_Boundary_Vars, ONLY : nSurfSample, SurfMesh
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                      :: subsurfxi,subsurfeta,iSurfSide,iCoord
!===================================================================================================================================
SDEALLOCATE(PDM%ParticleAtWall)
SDEALLOCATE(PDM%PartAdsorbSideIndx)
SDEALLOCATE(PEM%wNumber)
#if (PP_TimeDiscMethod==42)
SDEALLOCATE( Adsorption%AdsorpInfo)
#endif
SDEALLOCATE(Adsorption%InitStick)
SDEALLOCATE(Adsorption%PrefactorStick)
SDEALLOCATE(Adsorption%Adsorbexp)
SDEALLOCATE(Adsorption%Nu_a)
SDEALLOCATE(Adsorption%Nu_b)
SDEALLOCATE(Adsorption%DesorbEnergy)
SDEALLOCATE(Adsorption%Intensification)
SDEALLOCATE(Adsorption%HeatOfAdsZero)
SDEALLOCATE(Adsorption%DissocReact)
SDEALLOCATE(Adsorption%AssocReact)
SDEALLOCATE(Adsorption%EDissBond)
SDEALLOCATE(Adsorption%EDissBondAdsorbPoly)
SDEALLOCATE(Adsorption%Coordination)
SDEALLOCATE(Adsorption%DiCoord)

SDEALLOCATE(Adsorption%MaxCoverage)
SDEALLOCATE(Adsorption%Coverage)
SDEALLOCATE(Adsorption%ProbAds)
SDEALLOCATE(Adsorption%ProbDes)
SDEALLOCATE(Adsorption%SumDesorbPart)
SDEALLOCATE(Adsorption%SumAdsorbPart)
SDEALLOCATE(Adsorption%SurfSideToGlobSideMap)
SDEALLOCATE(Adsorption%ProbSigAds)
SDEALLOCATE(Adsorption%ProbSigDes)
SDEALLOCATE(Adsorption%Sigma)
SDEALLOCATE(Adsorption%ProbSigma)
SDEALLOCATE(Adsorption%DensSurfAtoms)

IF (ALLOCATED(SurfDistInfo)) THEN
DO iSurfSide=1,SurfMesh%nSides
  DO subsurfeta = 1,nSurfSample
  DO subsurfxi = 1,nSurfSample
    DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SurfAtomBondOrder)
    DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%SitesRemain)
    DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%nSites)
    DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%adsorbnum_tmp)
    DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%desorbnum_tmp)
    DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%reactnum_tmp)
    IF (ALLOCATED(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap)) THEN
      DO iCoord = 1,3
        DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(iCoord)%UsedSiteMap)
        DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(iCoord)%Species)
        DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(iCoord)%BondAtomIndx)
        DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(iCoord)%BondAtomIndy)
        DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(iCoord)%NeighPos)
        DEALLOCATE(SurfDistInfo(subsurfxi,subsurfeta,iSurfSide)%AdsMap(iCoord)%NeighSite)
      END DO
    END IF
  END DO
  END DO
END DO
DEALLOCATE(SurfDistInfo)
END IF

END SUBROUTINE FinalizeDSMCSurfModel

END MODULE MOD_DSMC_SurfModelInit
