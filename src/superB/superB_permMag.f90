!==================================================================================================================================
! Copyright (c) 2019 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
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

MODULE MOD_SuperB_PermMag
!===================================================================================================================================
!> Contains the calculation of the magnetic field of a permanent magnet
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
PUBLIC :: CalculateCuboidMagneticPotential, CalculateSphericMagneticPotential, CalculateCylindricMagneticPotential, &
          CalculateConicMagneticPotential, CalculateGradient
!===================================================================================================================================

INTERFACE CalculateCuboidMagneticPotential
  MODULE PROCEDURE CalculateCuboidMagneticPotential
END INTERFACE CalculateCuboidMagneticPotential

INTERFACE CalculateSphericMagneticPotential
  MODULE PROCEDURE CalculateSphericMagneticPotential
END INTERFACE CalculateSphericMagneticPotential

INTERFACE CalculateCylindricMagneticPotential
  MODULE PROCEDURE CalculateCylindricMagneticPotential
END INTERFACE CalculateCylindricMagneticPotential

INTERFACE CalculateConicMagneticPotential
  MODULE PROCEDURE CalculateConicMagneticPotential
END INTERFACE CalculateConicMagneticPotential

INTERFACE CalculateNormalVector
  MODULE PROCEDURE CalculateNormalVector
END INTERFACE CalculateNormalVector

INTERFACE CalculateGradient
  MODULE PROCEDURE CalculateGradient
END INTERFACE CalculateGradient
!===================================================================================================================================

CONTAINS

SUBROUTINE CalculateCuboidMagneticPotential(iMagnet)
!===================================================================================================================================
!> Calculates the magnetic potential of a cuboid permanent magnet
!===================================================================================================================================
! MODULES
USE MOD_Globals_Vars       ,ONLY: PI
USE MOD_Preproc            ,ONLY: PP_N
USE MOD_Mesh_Vars          ,ONLY: nElems, Elem_xGP
USE MOD_Basis              ,ONLY: LegendreGaussNodesAndWeights
USE MOD_Interpolation_Vars ,ONLY: BGFieldVTKOutput
USE MOD_SuperB_Vars        ,ONLY: PermanentMagnetInfo, PsiMag, MagnetFlag
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN) :: iMagnet
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL, ALLOCATABLE :: xGP(:), wGP(:)
REAL              :: vector1(3), vector2(3), vector3(3), basePoint(3), BPToNode(3), CPToNode(3)
REAL              :: vector1L, vector2L, vector3L, normL
REAL              :: normalVector12(3), normalVector13(3), normalVector23(3)
REAL              :: normalUnitVector12(3), normalUnitVector13(3), normalUnitVector23(3)
INTEGER           :: numNodes
INTEGER           :: iElem, i, j, k, ii, jj, kk
REAL              :: psiMagTemp, dist, volume, magnetVolume
REAL              :: magnetNode(3)
CHARACTER(LEN=26) :: myFileName
!===================================================================================================================================

ALLOCATE(xGP(PermanentMagnetInfo(iMagnet)%NumNodes))
ALLOCATE(wGP(PermanentMagnetInfo(iMagnet)%NumNodes))

! Get the Gauss-Legendre Nodes and Weigths
! ATTENTION: The nodes are still in [-1,1] and need to be mapped
CALL LegendreGaussNodesAndWeights(PermanentMagnetInfo(iMagnet)%NumNodes - 1, xGP, wGP)

vector1 = PermanentMagnetInfo(iMagnet)%BaseVector1
vector2 = PermanentMagnetInfo(iMagnet)%BaseVector2
vector3 = PermanentMagnetInfo(iMagnet)%BaseVector3

! Lengths of the base vectors
vector1L = SQRT(vector1(1)**2 + vector1(2)**2 + vector1(3)**2)
vector2L = SQRT(vector2(1)**2 + vector2(2)**2 + vector2(3)**2)
vector3L = SQRT(vector3(1)**2 + vector3(2)**2 + vector3(3)**2)

! Calculate the surface normal vectors
CALL CalculateNormalVector(vector1, vector2, vector3, &
                           normalVector12, normalUnitVector12)
CALL CalculateNormalVector(vector1, vector3, vector2, &
                           normalVector13, normalUnitVector13)
CALL CalculateNormalVector(vector2, vector3, vector1, &
                           normalVector23, normalUnitVector23)

magnetVolume = ABS(DOT_PRODUCT(normalVector12, vector3))

numNodes = PermanentMagnetInfo(iMagnet)%NumNodes

DO iElem=1,nElems
  DO i=0,PP_N; DO j=0,PP_N; DO k=0,PP_N
    ! Check if the mesh point is inside the magnet
    BPToNode(:) = Elem_xGP(:,i,j,k,iElem) - PermanentMagnetInfo(iMagnet)%BasePoint(:)
    CPToNode(:) = Elem_xGP(:,i,j,k,iElem) - (PermanentMagnetInfo(iMagnet)%BasePoint(:) +&
                  vector1 + vector2 + vector3)
    volume = (ABS(DOT_PRODUCT(normalVector12,BPToNode)) + ABS(DOT_PRODUCT(normalVector12,CPToNode)) +&
              ABS(DOT_PRODUCT(normalVector13,BPToNode)) + ABS(DOT_PRODUCT(normalVector13,CPToNode)) +&
              ABS(DOT_PRODUCT(normalVector23,BPToNode)) + ABS(DOT_PRODUCT(normalVector23,CPToNode)))/3

    IF(volume.EQ.magnetVolume) THEN
      MagnetFlag(i,j,k,iElem) = iMagnet
    END IF


    ! Sides spanned by vector 1 and 2
    psiMagTemp = 0
    DO ii=1,numNodes; DO jj=1,numNodes
      ! Side with kk=1
      ! Calculate the magnet node
      magnetNode(:) = PermanentMagnetInfo(iMagnet)%BasePoint(:) +&
                      vector1(:) / 2. * (1 + xGP(ii)) +&
                      vector2(:) / 2. * (1 + xGP(jj))

      ! Calculate the distance between the mesh point and the magnet point
      dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                  (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                  (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

      psiMagTemp = psiMagTemp + wGP(ii) * wGP(jj) / (4 * PI) / dist *&
                   DOT_PRODUCT(normalUnitVector12, PermanentMagnetInfo(iMagnet)%Magnetisation)

      ! Side with kk=N
      ! Calculate the magnet node
      magnetNode(:) = PermanentMagnetInfo(iMagnet)%BasePoint(:) +&
                      vector1(:) / 2. * (1 + xGP(ii)) +&
                      vector2(:) / 2. * (1 + xGP(jj)) +&
                      vector3(:)

      ! Calculate the distance between the mesh point and the magnet point
      dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                  (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                  (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

      psiMagTemp = psiMagTemp + wGP(ii) * wGP(jj) / (4 * PI) / dist *&
                   DOT_PRODUCT(-normalUnitVector12, PermanentMagnetInfo(iMagnet)%Magnetisation)
    END DO; END DO
    normL = sqrt(normalVector12(1)**2 + normalVector12(2)**2 + normalVector12(3)**2)
    PsiMag(i,j,k,iElem) = PsiMag(i,j,k,iElem) + psiMagTemp * normL / 4

    ! Sides spanned by vector 1 and 3
    psiMagTemp = 0
    DO ii=1,numNodes; DO kk=1,numNodes
      ! Side with jj=1
      ! Calculate the magnet node
      magnetNode(:) = PermanentMagnetInfo(iMagnet)%BasePoint(:) +&
                      vector1(:) / 2. * (1 + xGP(ii)) +&
                      vector3(:) / 2. * (1 + xGP(kk))

      ! Calculate the distance between the mesh point and the magnet point
      dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                  (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                  (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

      psiMagTemp = psiMagTemp + wGP(ii) * wGP(kk) / (4 * PI) / dist *&
                   DOT_PRODUCT(normalUnitVector13, PermanentMagnetInfo(iMagnet)%Magnetisation)

      ! Side with jj=N
      ! Calculate the magnet node
      magnetNode(:) = PermanentMagnetInfo(iMagnet)%BasePoint(:) +&
                      vector1(:) / 2. * (1 + xGP(ii)) +&
                      vector3(:) / 2. * (1 + xGP(kk)) +&
                      vector2(:)

      ! Calculate the distance between the mesh point and the magnet point
      dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                  (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                  (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

      psiMagTemp = psiMagTemp + wGP(ii) * wGP(kk) / (4 * PI) / dist *&
                   DOT_PRODUCT(-normalUnitVector13, PermanentMagnetInfo(iMagnet)%Magnetisation)
    END DO; END DO
    normL = sqrt(normalVector13(1)**2 + normalVector13(2)**2 + normalVector13(3)**2)
    PsiMag(i,j,k,iElem) = PsiMag(i,j,k,iElem) + psiMagTemp * normL / 4

    ! Sides spanned by vector 2 and 3
    psiMagTemp = 0
    DO jj=1,numNodes; DO kk=1,numNodes
      ! Side with ii=1
      ! Calculate the magnet node
      magnetNode(:) = PermanentMagnetInfo(iMagnet)%BasePoint(:) +&
                      vector2(:) / 2. * (1 + xGP(jj)) +&
                      vector3(:) / 2. * (1 + xGP(kk))

      ! Calculate the distance between the mesh point and the magnet point
      dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                  (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                  (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

      psiMagTemp = psiMagTemp + wGP(jj) * wGP(kk) / (4 * PI) / dist *&
                   DOT_PRODUCT(normalUnitVector23, PermanentMagnetInfo(iMagnet)%Magnetisation)

      ! Side with ii=N
      ! Calculate the magnet node
      magnetNode(:) = PermanentMagnetInfo(iMagnet)%BasePoint(:) +&
                      vector2(:) / 2. * (1 + xGP(jj)) +&
                      vector3(:) / 2. * (1 + xGP(kk)) +&
                      vector1(:)

      ! Calculate the distance between the mesh point and the magnet point
      dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                  (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                  (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

      psiMagTemp = psiMagTemp + wGP(jj) * wGP(kk) / (4 * PI) / dist *&
                   DOT_PRODUCT(-normalUnitVector23, PermanentMagnetInfo(iMagnet)%Magnetisation)
    END DO; END DO
    normL = sqrt(normalVector23(1)**2 + normalVector23(2)**2 + normalVector23(3)**2)
    PsiMag(i,j,k,iElem) = PsiMag(i,j,k,iElem) + psiMagTemp * normL / 4
  END DO; END DO; END DO
END DO

basePoint = PermanentMagnetInfo(iMagnet)%BasePoint

IF(BGFieldVTKOutput) THEN
  WRITE(myFileName,'(A11,I2.2,A4)')'MagnetMesh_',iMagnet,'.vtk'
  OPEN(1112,FILE=myFileName,STATUS='replace')
  WRITE(1112,'(A)')'# vtk DataFile Version 2.0 '
  WRITE(1112,'(A)')'Debug Mesh '
  WRITE(1112,'(A)')'ASCII'
  WRITE(1112,'(A)')'DATASET UNSTRUCTURED_GRID'
  WRITE(1112,'(A)')''
  WRITE(1112,'(A,I0,A)')'POINTS ',8,' FLOAT'
  WRITE(1112,*) basePoint(1:3)
  WRITE(1112,*) basePoint(1:3) + vector1(1:3)
  WRITE(1112,*) basePoint(1:3) + vector1(1:3) + vector2(1:3)
  WRITE(1112,*) basePoint(1:3) + vector2(1:3)
  WRITE(1112,*) basePoint(1:3) + vector3(1:3)
  WRITE(1112,*) basePoint(1:3) + vector1(1:3) + vector3(1:3)
  WRITE(1112,*) basePoint(1:3) + vector1(1:3) + vector2(1:3) + vector3(1:3)
  WRITE(1112,*) basePoint(1:3) + vector2(1:3) + vector3(1:3)
  WRITE(1112,*)''
  WRITE(1112,'(A,I0,1X,I0)')'CELLS ',1,9
  WRITE(1112,'(I0,1X,I0,1X,I0,1X,I0,1X,I0,1X,I0,1X,I0,1X,I0,1X,I0)') 8, 0, 1, 2, 3, 4, 5, 6, 7
  WRITE(1112,*)''
  WRITE(1112,'(A,I0)')'CELL_TYPES ',1
  WRITE(1112,'(1X,I0)') 12

  CLOSE(1112)
END IF

SDEALLOCATE( xGP)
SDEALLOCATE( wGP)

END SUBROUTINE CalculateCuboidMagneticPotential


SUBROUTINE CalculateSphericMagneticPotential(iMagnet)
!===================================================================================================================================
!> Calculates the magnetic potential of a spheric permanent magnet
!===================================================================================================================================
! MODULES
USE MOD_Globals_Vars       ,ONLY: PI
USE MOD_Preproc            ,ONLY: PP_N
USE MOD_Mesh_Vars          ,ONLY: nElems, Elem_xGP
USE MOD_Basis              ,ONLY: LegendreGaussNodesAndWeights
USE MOD_Interpolation_Vars ,ONLY: BGFieldVTKOutput
USE MOD_SuperB_Vars        ,ONLY: PermanentMagnetInfo, PsiMag, MagnetFlag
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN) :: iMagnet
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL, ALLOCATABLE :: xGP(:), wGP(:)
REAL              :: radius, psiMagTemp, theta, phi, dist, BPToNodeLength
REAL              :: magnetNode(3), normalVector(3), normalUnitVector(3), BPToNode(3)
INTEGER           :: iElem, i, j, k, jj, kk, iCell, iPoint
CHARACTER(LEN=26) :: myFileName
!===================================================================================================================================

ALLOCATE(xGP(PermanentMagnetInfo(iMagnet)%NumNodes))
ALLOCATE(wGP(PermanentMagnetInfo(iMagnet)%NumNodes))

! Get the Gauss-Legendre Nodes and Weigths of the polar angle
! ATTENTION: The nodes are still in [-1,1] and need to be mapped to an angle
CALL LegendreGaussNodesAndWeights(PermanentMagnetInfo(iMagnet)%NumNodes - 1, xGP, wGP)

radius = PermanentMagnetInfo(iMagnet)%Radius

IF(BGFieldVTKOutput) THEN
  ! OUTPUT: Writing the VTK Header
  WRITE(myFileName,'(A11,I2.2,A4)')'MagnetMesh_',iMagnet,'.vtk'
  OPEN(1112,FILE=myFileName,STATUS='replace')
  WRITE(1112,'(A)')'# vtk DataFile Version 2.0 '
  WRITE(1112,'(A)')'Debug Mesh '
  WRITE(1112,'(A)')'ASCII'
  WRITE(1112,'(A)')'DATASET UNSTRUCTURED_GRID'
  WRITE(1112,'(A)')''
  ! OUTPUT: Number of Points and type of points
  WRITE(1112,'(A,I0,A)')'POINTS ',2*PermanentMagnetInfo(iMagnet)%NumNodes*PermanentMagnetInfo(iMagnet)%NumNodes,' FLOAT'
END IF

DO iElem=1,nElems
  DO i=0,PP_N; DO j=0,PP_N; DO k=0,PP_N
    ! Mark element if it is inside the Magnet
    BPToNode = Elem_xGP(:,i,j,k,iElem) - PermanentMagnetInfo(iMagnet)%BasePoint(:)
    BPToNodeLength = SQRT(BPToNode(1)**2 + BPToNode(2)**2 + BPToNode(3)**2)
    IF (BPToNodeLength.LE.radius) THEN
      MagnetFlag(i,j,k,iElem) = iMagnet
    END IF

    psiMagTemp = 0
    DO jj=1,PermanentMagnetInfo(iMagnet)%NumNodes ! Polar angle
      theta = ACOS(xGP(jj))
      DO kk=1,2*PermanentMagnetInfo(iMagnet)%NumNodes ! Azimuthal angle
        phi = kk * PI / PermanentMagnetInfo(iMagnet)%NumNodes

        ! Calculate the magnet node in cartesian coordinates
        magnetNode(:) = PermanentMagnetInfo(iMagnet)%BasePoint(:) +&
                        (/radius * SIN(theta) * COS(phi),&
                          radius * SIN(theta) * SIN(phi),&
                          radius * COS(theta)/)

        ! OUTPUT: Write the magnet mesh points one time in the VTK File
        IF(BGFieldVTKOutput) THEN
          IF ((iElem.EQ.1).AND.(i.EQ.0).AND.(j.EQ.0).AND.(k.EQ.0)) THEN
            WRITE(1112,*) magnetNode(1:3)
          END IF
        END IF
        ! Calculate the unit normal vector
        normalVector(:) = magnetNode(:) - PermanentMagnetInfo(iMagnet)%BasePoint(:)
        normalUnitVector = normalVector / radius

        ! Calculate the distance between the mesh point and the magnet point
        dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                    (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                    (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

        ! Calculate the magnetic potential of the node with the Gaussian quadrature
        psiMagTemp = psiMagTemp + wGP(jj) / (4 * PI) / dist *&
                     radius * radius *&
                     DOT_PRODUCT(normalUnitVector, PermanentMagnetInfo(iMagnet)%Magnetisation)
      END DO !kk
    END DO !jj
    PsiMag(i,j,k,iElem) = PI / PermanentMagnetInfo(iMagnet)%NumNodes * psiMagTemp
  END DO; END DO; END DO
END DO

IF(BGFieldVTKOutput) THEN
  WRITE(1112,*)''
  ! OUTPUT: Number of cells and total number of list entries for the cells
  WRITE(1112,'(A,I0,1X,I0)')'CELLS ',PermanentMagnetInfo(iMagnet)%NumNodes-1+2,&
                                     (4*PermanentMagnetInfo(iMagnet)%NumNodes+3)*(PermanentMagnetInfo(iMagnet)%NumNodes-1)+&
                                     (2*PermanentMagnetInfo(iMagnet)%NumNodes + 1)*2
  ! OUTPUT: Side cells
  DO iCell=1,PermanentMagnetInfo(iMagnet)%NumNodes-1
    WRITE(1112,'(I0)',ADVANCE="NO") 4*PermanentMagnetInfo(iMagnet)%NumNodes + 2
    DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
      WRITE(1112,'(1X,I0)',ADVANCE="NO") (iCell - 1)*2*PermanentMagnetInfo(iMagnet)%NumNodes + iPoint - 1
      WRITE(1112,'(1X,I0)',ADVANCE="NO") iCell*2*PermanentMagnetInfo(iMagnet)%NumNodes + iPoint - 1
    END DO
    WRITE(1112,'(1X,I0)',ADVANCE="NO") (iCell - 1)*2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,'(1X,I0)',ADVANCE="NO") iCell*2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,*)''
  END DO
  ! OUTPUT: Bottom cell
  WRITE(1112,'(I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,'(1X,I0)',ADVANCE="NO") iPoint - 1
  END DO
  WRITE(1112,*)''
  ! OUTPUT: Top cell
  WRITE(1112,'(I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,'(1X,I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes*(PermanentMagnetInfo(iMagnet)%NumNodes-1)+&
                                       iPoint - 1
  END DO
  WRITE(1112,*)''
  WRITE(1112,*)''
  ! OUTPUT: Cell Types. Side cells are strips of triangles and bottom/top cells are polygons
  WRITE(1112,'(A,I0)')'CELL_TYPES ',PermanentMagnetInfo(iMagnet)%NumNodes-1+2
  DO iCell=1,PermanentMagnetInfo(iMagnet)%NumNodes-1
    WRITE(1112,'(1X,I0)',ADVANCE="NO")6
  END DO
  WRITE(1112,'(1X,I0)',ADVANCE="NO")7
  WRITE(1112,'(1X,I0)',ADVANCE="NO")7
  WRITE(1112,*)''

  CLOSE(1112)
END IF

SDEALLOCATE( xGP)
SDEALLOCATE( wGP)

END SUBROUTINE CalculateSphericMagneticPotential


SUBROUTINE CalculateCylindricMagneticPotential(iMagnet)
!===================================================================================================================================
!> Calculates the magnetic potential of a cylindric permanent magnet
!===================================================================================================================================
! MODULES
USE MOD_Preproc
USE MOD_Globals_Vars       ,ONLY: PI
USE MOD_Mesh_Vars          ,ONLY: nElems, Elem_xGP
USE MOD_Basis              ,ONLY: LegendreGaussNodesAndWeights
USE MOD_SuperB_Tools       ,ONLY: FindLinIndependentVectors, GramSchmidtAlgo
USE MOD_SuperB_Vars        ,ONLY: PermanentMagnetInfo, psiMag, MagnetFlag
USE MOD_Interpolation_Vars ,ONLY: BGFieldVTKOutput
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN) :: iMagnet
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                :: AxisVec1(3), AxisVec2(3), magnetNode(3), normalUnitVector(3), normalVector(3), l(3), d(3)
REAL                :: TrafoMatrix(3,3)
INTEGER             :: iElem, i, j, k, ii, jj, kk, iPoint
REAL, ALLOCATABLE   :: xGP(:), wGP(:)
REAL                :: psiMagTemp, z, radius, phi, dist, height, normalLength, tmin
CHARACTER(LEN=26)   :: myFileName
!===================================================================================================================================

ALLOCATE(xGP(PermanentMagnetInfo(iMagnet)%NumNodes))
ALLOCATE(wGP(PermanentMagnetInfo(iMagnet)%NumNodes))

! Get the Gauss-Legendre Nodes and Weigths of the polar angle
! ATTENTION: The nodes are still in [-1,1] and need to be mapped to an angle
CALL LegendreGaussNodesAndWeights(PermanentMagnetInfo(iMagnet)%NumNodes - 1, xGP, wGP)

height = SQRT(PermanentMagnetInfo(iMagnet)%HeightVector(1)**2 + PermanentMagnetInfo(iMagnet)%HeightVector(2)**2 +&
              PermanentMagnetInfo(iMagnet)%HeightVector(3)**2)

! Transformation matrix from the cylindric coordinates to the original coordiante system
CALL FindLinIndependentVectors(PermanentMagnetInfo(iMagnet)%HeightVector, AxisVec1, AxisVec2)
CALL GramSchmidtAlgo(PermanentMagnetInfo(iMagnet)%HeightVector, AxisVec1, AxisVec2)
TrafoMatrix(:,1) = AxisVec1
TrafoMatrix(:,2) = AxisVec2
TrafoMatrix(:,3) = PermanentMagnetInfo(iMagnet)%HeightVector

DO iElem=1,nElems
  DO i=0,PP_N; DO j=0,PP_N; DO k=0,PP_N
    psiMagTemp = 0
    ! Top
    z = height / 2.
    DO ii=1,PermanentMagnetInfo(iMagnet)%NumNodes
      radius = PermanentMagnetInfo(iMagnet)%Radius / 2. * (1 + xGP(ii))
      DO jj=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
        phi = jj * PI / PermanentMagnetInfo(iMagnet)%NumNodes
        magnetNode = (/radius*COS(phi), radius*SIN(phi), z/)
        magnetNode = MATMUL(TrafoMatrix, magnetNode)
        magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

        normalUnitVector = PermanentMagnetInfo(iMagnet)%HeightVector

        ! Calculate the distance between the mesh point and the magnet point
        dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                    (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                    (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

        ! Calculate the magnetic potential of the node with the Gaussian quadrature
        psiMagTemp = psiMagTemp + wGP(ii) / (4 * PI) / dist * radius *&
                     DOT_PRODUCT(normalUnitVector, PermanentMagnetInfo(iMagnet)%Magnetisation)
      END DO
    END DO
    psiMag(i,j,k,iElem) = psiMag(i,j,k,iElem) + PI / PermanentMagnetInfo(iMagnet)%NumNodes *&
                          PermanentMagnetInfo(iMagnet)%Radius / 2. * psiMagTemp

    ! Bottom
    psiMagTemp = 0
    z = -height / 2.
    DO ii=1,PermanentMagnetInfo(iMagnet)%NumNodes
      radius = PermanentMagnetInfo(iMagnet)%Radius / 2. * (1 + xGP(ii))
      DO jj=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
        phi = jj * PI / PermanentMagnetInfo(iMagnet)%NumNodes
        magnetNode = (/radius*COS(phi), radius*SIN(phi), z/)
        magnetNode = MATMUL(TrafoMatrix, magnetNode)
        magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

        normalUnitVector = - PermanentMagnetInfo(iMagnet)%HeightVector

        ! Calculate the distance between the mesh point and the magnet point
        dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                    (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                    (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

        ! Calculate the magnetic potential of the node with the Gaussian quadrature
        psiMagTemp = psiMagTemp + wGP(ii) / (4 * PI) / dist * radius *&
                     DOT_PRODUCT(normalUnitVector, PermanentMagnetInfo(iMagnet)%Magnetisation)
      END DO
    END DO
    psiMag(i,j,k,iElem) = psiMag(i,j,k,iElem) + PI / PermanentMagnetInfo(iMagnet)%NumNodes *&
                          PermanentMagnetInfo(iMagnet)%Radius / 2. * psiMagTemp

    ! Side
    psiMagTemp = 0
    radius = PermanentMagnetInfo(iMagnet)%Radius
    DO kk=1,PermanentMagnetInfo(iMagnet)%NumNodes
      z = height / 2. * xGP(kk)
      DO jj=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
        phi = jj * PI / PermanentMagnetInfo(iMagnet)%NumNodes
        magnetNode = (/radius*COS(phi), radius*SIN(phi), z/)
        magnetNode = MATMUL(TrafoMatrix, magnetNode)
        magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

        normalVector = (/radius*COS(phi), radius*SIN(phi), 0./)
        normalVector = MATMUL(TrafoMatrix, normalVector)
        normalLength = SQRT(normalVector(1)**2 + normalVector(2)**2 + normalVector(3)**2)
        normalUnitVector = normalVector / normalLength

        ! Calculate the distance between the mesh point and the magnet point
        dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                    (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                    (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

        ! Calculate the magnetic potential of the node with the Gaussian quadrature
        psiMagTemp = psiMagTemp + wGP(kk) / (4 * PI) / dist *&
                     DOT_PRODUCT(normalUnitVector, PermanentMagnetInfo(iMagnet)%Magnetisation)
      END DO
    END DO
    psiMag(i,j,k,iElem) = psiMag(i,j,k,iElem) + PI / PermanentMagnetInfo(iMagnet)%NumNodes * height / 2. * psiMagTemp

    ! Check if the mesh point is in the cylinder
    tMin = (DOT_PRODUCT(Elem_xGP(:,i,j,k,iElem), height*PermanentMagnetInfo(iMagnet)%HeightVector) -&
            DOT_PRODUCT(PermanentMagnetInfo(iMagnet)%BasePoint - height*PermanentMagnetInfo(iMagnet)%HeightVector/2, &
                        height*PermanentMagnetInfo(iMagnet)%HeightVector)) /&
            DOT_PRODUCT(height*PermanentMagnetInfo(iMagnet)%HeightVector, height*PermanentMagnetInfo(iMagnet)%HeightVector)
    l = PermanentMagnetInfo(iMagnet)%BasePoint(:) - height*PermanentMagnetInfo(iMagnet)%HeightVector(:)/2 +&
        tMin * height*PermanentMagnetInfo(iMagnet)%HeightVector(:)
    d = l - Elem_xGP(:,i,j,k,iElem)
    dist = SQRT(DOT_PRODUCT(d, d))

    IF ((tMin.GE.0).AND.(tMin.LE.1).AND.(dist.LE.PermanentMagnetInfo(iMagnet)%Radius)) THEN
      MagnetFlag(i,j,k,iElem) = iMagnet
    END IF

  END DO; END DO; END DO
END DO

SDEALLOCATE( xGP)
SDEALLOCATE( wGP)

IF(BGFieldVTKOutput) THEN
  WRITE(myFileName,'(A11,I2.2,A4)')'MagnetMesh_',iMagnet,'.vtk'
  OPEN(1112,FILE=myFileName,STATUS='replace')
  WRITE(1112,'(A)')'# vtk DataFile Version 2.0 '
  WRITE(1112,'(A)')'Debug Mesh '
  WRITE(1112,'(A)')'ASCII'
  WRITE(1112,'(A)')'DATASET UNSTRUCTURED_GRID'
  WRITE(1112,'(A)')''
  WRITE(1112,'(A,I0,A)')'POINTS ',4 * PermanentMagnetInfo(iMagnet)%NumNodes,' FLOAT'
  z=-height/2
  radius = PermanentMagnetInfo(iMagnet)%Radius
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    phi = iPoint * PI / PermanentMagnetInfo(iMagnet)%NumNodes

    magnetNode = (/radius*COS(phi), radius*SIN(phi), z/)
    magnetNode = MATMUL(TrafoMatrix, magnetNode)
    magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

    WRITE(1112,*) magnetNode(1:3)
  END DO
  z=height/2
  radius = PermanentMagnetInfo(iMagnet)%Radius
  DO iPoint=2*PermanentMagnetInfo(iMagnet)%NumNodes+1,4*PermanentMagnetInfo(iMagnet)%NumNodes
    phi = iPoint * PI / PermanentMagnetInfo(iMagnet)%NumNodes

    magnetNode = (/radius*COS(phi), radius*SIN(phi), z/)
    magnetNode = MATMUL(TrafoMatrix, magnetNode)
    magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

    WRITE(1112,*) magnetNode(1:3)
  END DO
  WRITE(1112,*)''
  WRITE(1112,'(A,I0,1X,I0)')'CELLS ',3,8*PermanentMagnetInfo(iMagnet)%NumNodes+5
  ! Side
  WRITE(1112,'(I0)',ADVANCE="NO") 4*PermanentMagnetInfo(iMagnet)%NumNodes+2
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,'(1X,I0)',ADVANCE="NO") iPoint - 1
    WRITE(1112,'(1X,I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes + iPoint -1
  END DO
  WRITE(1112,'(1X,I0)',ADVANCE="NO") 0
  WRITE(1112,'(1X,I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes
  WRITE(1112,*)''
  ! Button
  WRITE(1112,'(I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,'(1X,I0)',ADVANCE="NO") iPoint - 1
  END DO
  WRITE(1112,*)''
  ! Top
  WRITE(1112,'(I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,'(1X,I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes + iPoint - 1
  END DO
  WRITE(1112,*)''
  WRITE(1112,*)''
  WRITE(1112,'(A,I0)')'CELL_TYPES ',3
  WRITE(1112,'(1X,I0,1X,I0,1X,I0)') 6,7,7

  CLOSE(1112)
END IF

END SUBROUTINE CalculateCylindricMagneticPotential


SUBROUTINE CalculateConicMagneticPotential(iMagnet)
!===================================================================================================================================
!> Calculates the magnetic potential of a conic part
!===================================================================================================================================
! MODULES
USE MOD_Globals_Vars       ,ONLY: PI
USE MOD_Preproc
USE MOD_Mesh_Vars          ,ONLY: nElems, Elem_xGP
USE MOD_Basis              ,ONLY: LegendreGaussNodesAndWeights
USE MOD_SuperB_Vars        ,ONLY: PermanentMagnetInfo, psiMag, MagnetFlag
USE MOD_SuperB_Tools       ,ONLY: FindLinIndependentVectors, GramSchmidtAlgo
USE MOD_Interpolation_Vars ,ONLY: BGFieldVTKOutput
! IMPLICIT NONE
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN) :: iMagnet
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,ALLOCATABLE   :: xGP(:), wGP(:)
REAL               :: height, psiMagTemp, z, radius, phi, normalLength, dist, tMin
REAL               :: TrafoMatrix(3,3)
REAl               :: AxisVec1(3), AxisVec2(3), magnetNode(3), normalVector(3), normalUnitVector(3), l(3), d(3), HeightV(3)
INTEGER            :: iElem, i, j, k, ii, jj, kk, iPoint
CHARACTER(LEN=26)  :: myFileName
!===================================================================================================================================

ALLOCATE(xGP(PermanentMagnetInfo(iMagnet)%NumNodes))
ALLOCATE(wGP(PermanentMagnetInfo(iMagnet)%NumNodes))

! Get the Gauss-Legendre Nodes and Weigths of the polar angle
! ATTENTION: The nodes are still in [-1,1] and need to be mapped to an angle
CALL LegendreGaussNodesAndWeights(PermanentMagnetInfo(iMagnet)%NumNodes - 1, xGP, wGP)

height = SQRT(PermanentMagnetInfo(iMagnet)%HeightVector(1)**2 + PermanentMagnetInfo(iMagnet)%HeightVector(2)**2 +&
              PermanentMagnetInfo(iMagnet)%HeightVector(3)**2)
HeightV = PermanentMagnetInfo(iMagnet)%HeightVector(:)

! Transformation matrix from the cylindric coordinates to the original coordiante system
CALL FindLinIndependentVectors(PermanentMagnetInfo(iMagnet)%HeightVector, AxisVec1, AxisVec2)
CALL GramSchmidtAlgo(PermanentMagnetInfo(iMagnet)%HeightVector, AxisVec1, AxisVec2)
TrafoMatrix(:,1) = AxisVec1
TrafoMatrix(:,2) = AxisVec2
TrafoMatrix(:,3) = PermanentMagnetInfo(iMagnet)%HeightVector

DO iElem=1,nElems
  DO i=0,PP_N; DO j=0,PP_N; DO k=0,PP_N
    ! Top
    psiMagTemp = 0
    z = height
    DO ii=1,PermanentMagnetInfo(iMagnet)%NumNodes
      radius = PermanentMagnetInfo(iMagnet)%Radius2 / 2. * (1 + xGP(ii))
      DO jj=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
        phi = jj * PI / PermanentMagnetInfo(iMagnet)%NumNodes
        magnetNode = (/radius * COS(phi), radius * SIN(phi), z/)
        magnetNode = MATMUL(TrafoMatrix, magnetNode)
        magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

        normalUnitVector = PermanentMagnetInfo(iMagnet)%HeightVector / height

        ! Calculate the distance between the mesh point and the magnet point
        dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                    (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                    (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

        ! Calculate the magnetic potential of the node with the Gaussian quadrature
        psiMagTemp = psiMagTemp + wGP(ii) / (4 * PI) / dist * radius *&
                     DOT_PRODUCT(normalUnitVector, PermanentMagnetInfo(iMagnet)%Magnetisation)
      END DO
    END DO

    psiMag(i,j,k,iElem) = psiMag(i,j,k,iElem) + PI / PermanentMagnetInfo(iMagnet)%NumNodes *&
                          PermanentMagnetInfo(iMagnet)%Radius2 / 2. * psiMagTemp

    ! Bottom
    psiMagTemp = 0
    z = 0
    DO ii=1,PermanentMagnetInfo(iMagnet)%NumNodes
      radius = PermanentMagnetInfo(iMagnet)%Radius / 2. * (1 + xGP(ii))
      DO jj=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
        phi = jj * PI / PermanentMagnetInfo(iMagnet)%NumNodes
        magnetNode = (/radius * COS(phi), radius * SIN(phi), z/)
        magnetNode = MATMUL(TrafoMatrix, magnetNode)
        magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

        normalUnitVector = -PermanentMagnetInfo(iMagnet)%HeightVector / height

        ! Calculate the distance between the mesh point and the magnet point
        dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                    (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                    (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

        ! Calculate the magnetic potential of the node with the Gaussian quadrature
        psiMagTemp = psiMagTemp + wGP(ii) / (4 * PI) / dist * radius *&
                     DOT_PRODUCT(normalUnitVector, PermanentMagnetInfo(iMagnet)%Magnetisation)
      END DO
    END DO

    psiMag(i,j,k,iElem) = psiMag(i,j,k,iElem) + PI / PermanentMagnetInfo(iMagnet)%NumNodes *&
                          PermanentMagnetInfo(iMagnet)%Radius / 2. * psiMagTemp

    ! Side
    psiMagTemp = 0
    DO kk=1,PermanentMagnetInfo(iMagnet)%NumNodes
      z = height / 2. * (1 + xGP(kk))
      radius = PermanentMagnetInfo(iMagnet)%Radius * (1 - z / height) + PermanentMagnetInfo(iMagnet)%Radius2 * z / height
      DO jj=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
        phi = jj * PI / PermanentMagnetInfo(iMagnet)%NumNodes
        magnetNode = (/radius * COS(phi), radius * SIN(phi), z/)
        magnetNode = MATMUL(TrafoMatrix, magnetNode)
        magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

        normalVector = (/radius * COS(phi), radius * SIN(phi), (PermanentMagnetInfo(iMagnet)%Radius - &
                                                                PermanentMagnetInfo(iMagnet)%Radius2)/(2*height)/)
        normalVector = MATMUL(TrafoMatrix, normalVector)
        normalLength = SQRT(normalVector(1)**2 + normalVector(2)**2 + normalVector(3)**2)
        normalUnitVector = normalVector / normalLength

        ! Calculate the distance between the mesh point and the magnet point
        dist = SQRT((magnetNode(1) - Elem_xGP(1,i,j,k,iElem))**2 +&
                    (magnetNode(2) - Elem_xGP(2,i,j,k,iElem))**2 +&
                    (magnetNode(3) - Elem_xGP(3,i,j,k,iElem))**2)

        ! Calculate the magnetic potential of the node with the Gaussian quadrature
        psiMagTemp = psiMagTemp + wGP(kk) / (4 * PI) / dist *&
                     SQRT((PermanentMagnetInfo(iMagnet)%Radius - PermanentMagnetInfo(iMagnet)%Radius2)**2 + height**2) / height *&
                     DOT_PRODUCT(normalUnitVector, PermanentMagnetInfo(iMagnet)%Magnetisation)
        END DO
      END DO
      psiMag(i,j,k,iElem) = psiMag(i,j,k,iElem) + PI / PermanentMagnetInfo(iMagnet)%NumNodes * height / 2. * psiMagTemp

      ! Check if the mesh point is in the cylinder
      tMin = (DOT_PRODUCT(Elem_xGP(:,i,j,k,iElem), HeightV) -&
            DOT_PRODUCT(PermanentMagnetInfo(iMagnet)%BasePoint, HeightV)) /&
            DOT_PRODUCT(HeightV, HeightV)
      l = PermanentMagnetInfo(iMagnet)%BasePoint(:) + tMin * HeightV(:)
      d = l - Elem_xGP(:,i,j,k,iElem)
      dist = SQRT(DOT_PRODUCT(d, d))

      radius = PermanentMagnetInfo(iMagnet)%Radius * (1 - tMin) + PermanentMagnetInfo(iMagnet)%Radius2 * tMin

      IF ((tMin.GE.0).AND.(tMin.LE.1).AND.(dist.LE.radius)) THEN
        MagnetFlag(i,j,k,iElem) = iMagnet
      END IF
  END DO; END DO; END DO
END DO

SDEALLOCATE( xGP)
SDEALLOCATE( wGP)
IF(BGFieldVTKOutput) THEN
  WRITE(myFileName,'(A11,I2.2,A4)')'MagnetMesh_',iMagnet,'.vtk'
  OPEN(1112,FILE=myFileName,STATUS='replace')
  WRITE(1112,'(A)')'# vtk DataFile Version 2.0 '
  WRITE(1112,'(A)')'Debug Mesh '
  WRITE(1112,'(A)')'ASCII'
  WRITE(1112,'(A)')'DATASET UNSTRUCTURED_GRID'
  WRITE(1112,'(A)')''
  WRITE(1112,'(A,I0,A)')'POINTS ',4 * PermanentMagnetInfo(iMagnet)%NumNodes,' FLOAT'
  z=0
  radius = PermanentMagnetInfo(iMagnet)%Radius
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    phi = iPoint * PI / PermanentMagnetInfo(iMagnet)%NumNodes

    magnetNode = (/radius*COS(phi), radius*SIN(phi), z/)
    magnetNode = MATMUL(TrafoMatrix, magnetNode)
    magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

    WRITE(1112,*) magnetNode(1:3)
  END DO
  z=height
  radius = PermanentMagnetInfo(iMagnet)%Radius2
  DO iPoint=2*PermanentMagnetInfo(iMagnet)%NumNodes+1,4*PermanentMagnetInfo(iMagnet)%NumNodes
    phi = iPoint * PI / PermanentMagnetInfo(iMagnet)%NumNodes

    magnetNode = (/radius*COS(phi), radius*SIN(phi), z/)
    magnetNode = MATMUL(TrafoMatrix, magnetNode)
    magnetNode = magnetNode + PermanentMagnetInfo(iMagnet)%BasePoint

    WRITE(1112,*) magnetNode(1:3)
  END DO
  WRITE(1112,*)''
  WRITE(1112,'(A,I0,1X,I0)')'CELLS ',3,8*PermanentMagnetInfo(iMagnet)%NumNodes+5
  ! Side
  WRITE(1112,'(I0)',ADVANCE="NO") 4*PermanentMagnetInfo(iMagnet)%NumNodes+2
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,'(1X,I0)',ADVANCE="NO") iPoint - 1
    WRITE(1112,'(1X,I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes + iPoint -1
  END DO
  WRITE(1112,'(1X,I0)',ADVANCE="NO") 0
  WRITE(1112,'(1X,I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes
  WRITE(1112,*)''
  ! Button
  WRITE(1112,'(I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,'(1X,I0)',ADVANCE="NO") iPoint - 1
  END DO
  WRITE(1112,*)''
  ! Top
  WRITE(1112,'(I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes
  DO iPoint=1,2*PermanentMagnetInfo(iMagnet)%NumNodes
    WRITE(1112,'(1X,I0)',ADVANCE="NO") 2*PermanentMagnetInfo(iMagnet)%NumNodes + iPoint - 1
  END DO
  WRITE(1112,*)''
  WRITE(1112,*)''
  WRITE(1112,'(A,I0)')'CELL_TYPES ',3
  WRITE(1112,'(1X,I0,1X,I0,1X,I0)') 6,7,7

  CLOSE(1112)
END IF

END SUBROUTINE CalculateConicMagneticPotential


SUBROUTINE CalculateNormalVector(vec1, vec2, vec3, normalVec, normalUnitVec)
!===================================================================================================================================
!> Contains the calculation of the surface normal vector and its corresponding unit vector
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)  :: vec1(3), vec2(3), vec3(3)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL, INTENT(OUT) :: normalVec(3), normalUnitVec(3)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL              :: tripleProduct
REAL              :: normalVectorLength
!===================================================================================================================================

! Calculate the normal vector via the cross product
normalVec(1) = vec1(2)*vec2(3) - vec1(3)*vec2(2) 
normalVec(2) = vec1(3)*vec2(1) - vec1(1)*vec2(3)
normalVec(3) = vec1(1)*vec2(2) - vec1(2)*vec2(1)

! Calculate the triple product (a * (b x c)). If the result is greater than zero the normal vector and the third vector
! are pointing in the same direction and the normal vector needs to be turned around
tripleProduct = DOT_PRODUCT(vec3, normalVec)
IF (tripleProduct.GE.0) normalVec = -normalVec

! Calculate the unit normal vector with the length
normalVectorLength = SQRT(normalVec(1)**2 + normalVec(2)**2 + normalVec(3)**2)
normalUnitVec = normalVec/normalVectorLength

END SUBROUTINE CalculateNormalVector

SUBROUTINE CalculateGradient()
!===================================================================================================================================
!> Contains the calculation of the gradient of the magnetic potential to get the B-Field
!===================================================================================================================================
! MODULES
USE MOD_Preproc
USE MOD_Mesh_Vars          ,ONLY: Metrics_fTilde, Metrics_gTilde, Metrics_hTilde, sJ
USE MOD_SuperB_Vars
USE MOD_Interpolation_Vars ,ONLY: BGField
USE MOD_Basis
USE MOD_Interpolation_Vars ,ONLY: xGP
USE MOD_Equation_Vars      ,ONLY: mu0
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL, DIMENSION(0:PP_N,0:PP_N,0:PP_N)                 :: gradPsi_xi, gradPsi_eta, gradPsi_zeta
REAL, DIMENSION(0:PP_N,0:PP_N)                        :: D
REAL, DIMENSION(1:3,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems) :: HField
INTEGER                                               :: i, j, k, l, iElem, iMagnet
!===================================================================================================================================

! Compute the polynomial derivative Matrix
CALL PolynomialDerivativeMatrix(N,xGP,D)

DO iElem=1,PP_nElems
  ! Compute the gradient in the reference system
  gradPsi_xi   = 0.
  gradPsi_eta  = 0.
  gradPsi_zeta = 0.
  DO l=0,PP_N
    DO k=0,PP_N
      DO j=0,PP_N
        DO i=0,PP_N
          gradPsi_xi(i,j,k)   = gradPsi_xi(i,j,k)   + D(i,l) * PsiMag(l,j,k,iElem)
          gradPsi_eta(i,j,k)  = gradPsi_eta(i,j,k)  + D(j,l) * PsiMag(i,l,k,iElem)
          gradPsi_zeta(i,j,k) = gradPsi_zeta(i,j,k) + D(k,l) * PsiMag(i,j,l,iElem)
        END DO !i
      END DO !j
    END DO !k
  END DO !l
  ! Transform the gradients from the reference system to the xyz-System. Only exact for cartesian mesh!
  DO k=0,N
    DO j=0,N
      DO i=0,N
        HField(1,i,j,k,iElem) = -1 * sJ(i,j,k,iElem) * (&
                                 Metrics_fTilde(1,i,j,k,iElem) * gradPsi_xi(i,j,k)   +&
                                 Metrics_gTilde(1,i,j,k,iElem) * gradPsi_eta(i,j,k)  +&
                                 Metrics_hTilde(1,i,j,k,iElem) * gradPsi_zeta(i,j,k))
        HField(2,i,j,k,iElem) = -1 * sJ(i,j,k,iElem) * (&
                                 Metrics_fTilde(2,i,j,k,iElem) * gradPsi_xi(i,j,k)   +&
                                 Metrics_gTilde(2,i,j,k,iElem) * gradPsi_eta(i,j,k)  +&
                                 Metrics_hTilde(2,i,j,k,iElem) * gradPsi_zeta(i,j,k) )
        HField(3,i,j,k,iElem) = -1 * sJ(i,j,k,iElem) * (&
                                 Metrics_fTilde(3,i,j,k,iElem) * gradPsi_xi(i,j,k)   +&
                                 Metrics_gTilde(3,i,j,k,iElem) * gradPsi_eta(i,j,k)  +&
                                 Metrics_hTilde(3,i,j,k,iElem) * gradPsi_zeta(i,j,k) )
        ! HField(:,i,j,k,iElem) = - HField(:,i,j,k,iElem)
        iMagnet = MagnetFlag(i,j,k,iElem)
        IF(iMagnet.EQ.0) THEN
          BGField(:,i,j,k,iElem) = mu0 * HField(:,i,j,k,iElem)
        ELSE
          BGField(:,i,j,k,iElem) = mu0 * (HField(:,i,j,k,iElem) + PermanentMagnetInfo(iMagnet)%Magnetisation(:))
        END IF
      END DO !i
    END DO !j
  END DO !k
END DO

END SUBROUTINE CalculateGradient

END MODULE MOD_SuperB_PermMag