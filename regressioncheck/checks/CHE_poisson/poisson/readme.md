# PIC (Poisson) Discharge
* RF discharge between two electrodes with Helium
    * Ionization of background gas
* Secondary electron emission at x-direction boundaries
    * only happens rarely for this setup (but code coverage of SEE modules is still performed)
    * Emission model: SEE-I (bombarding electrons are removed, Argon ions on different materials is considered for secondary e- emission with 0.13 probability) by Depla2009
* The results (total number of particles) are shown in *n_parts_total.jpg* for *MPI=1,...,10*
