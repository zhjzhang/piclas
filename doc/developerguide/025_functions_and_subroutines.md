\hypertarget{functions_and_subroutines}{}

# Useful Functions and Subroutines \label{chap:functions_and_subroutines}

This chapter contains a summary of useful functions and subroutines that might be re-used in the
future.

## General Functions and Subroutines

| Function     | Module        | Input          | Output     | Description                                                                                                |
| :----------: | :-----------: | :-----------:  | :--------: | :------------------------------------------------------------                                              |
| `UNITVECTOR` | `MOD_Globals` | 3D vector      | 3D vector  | Normalizes a given vector by dividing all vectors entries by the vector's magnitude                        |
| `CROSSNORM`  | `MOD_Globals` | two 3D vectors | 3D vector  | Computes the cross product of two 3-dimensional vectors: cross=v1 x v2 and normalizes the resulting vector |
| `CROSS`      | `MOD_Globals` | two 3D vectors | 3D vector  | Computes the cross product of two 3-dimensional vectors: cross=v1 x v2                                     |
| `VECNORM`    | `MOD_Globals` | 3D vector      | `REAL`     | Computes the Euclidean norm (length) of a vector                                                           |
| `DOTPRODUCT` | `MOD_Globals` | 3D vector      | `REAL`     | Computes the dot product of a vector with itself                                                           |

## Particle Functions and Subroutines

| Function                    | Module           | Input                                                            | Output                 | Description                                                                                                                                  |
| :-------------------------: | :--------------: | :----------------:                                               | :----------:           | :------------------------------------                                                                                                              |
| `isChargedParticle`         | `MOD_part_tools` | 3D vector                                                        | `LOGICAL`              | Check if particle has charge unequal to zero                                                                                                 |
| `isDepositParticle`         | `MOD_part_tools` | 3D vector                                                        | `LOGICAL`              | Check if particle is to be deposited on the grid                                                                                             |
| `isPushParticle`            | `MOD_part_tools` | two 3D vectors                                                   | `LOGICAL`              | Check if particle is to be pushed (integrated in time)                                                                                       |
| `isInterpolateParticle`     | `MOD_part_tools` | two 3D vectors                                                   | `LOGICAL`              | Check if the field at a particle's is to be interpolated (accelerated)                                                                       |
| `VeloFromDistribution`      | `MOD_part_tools` | distribution type, species ID, Tempergy                          | 3D vector              | Calculates a velocity vector from a defined velocity distribution, species ID and Tempergy (temperature [K] or energy [J] or velocity [m/s]) |
| `DiceUnitVector`            | `MOD_part_tools` | `None`                                                           | 3D vector              | Calculates a normalized vector in 3D (unit space) in random direction                                                                        |
| `CreateParticle`            | `MOD_part_tools` | species ID, position, element ID, velocity and internal energies | particle ID (optional) | Creates a new particle at a given position and energetic state and return the new particle ID (optional)                                     |
| `GetParticleWeight`         | `MOD_part_tools` | particle ID                                                      | `REAL`                 | Determines the weighting factor of a particle                                                                                                |
