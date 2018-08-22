# BuildDayLive - Supermicro
The [Build Day Live with Supermicro BigTwin](https://builddaylive.com/supermicro/) was August 2nd 2018.

SuperAddHosts.ps1 was used to do initial configuration of the four ESXi hosts in the BigTwin and add them to vCentre. The script also creates a vSphere cluster with HA and DRS enables. There are two lines commented out which would enable VSAN on the cluster.