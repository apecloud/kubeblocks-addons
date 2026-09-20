# SeaweedFS examples

Install the addon first; see [the addon guide](../../addons/seaweedfs/README.md).

- `cluster.yaml`: one master, volume, filer and S3 gateway (`seaweedfs`).
- `cluster-distributed.yaml`: three masters, three volumes, one filer and two gateways (`seaweedfs-dist`); requires at least three schedulable nodes. The filer remains a single point of availability and metadata persistence.
- `restart.yaml`, `stop.yaml`, `start.yaml`, `verticalscale.yaml`, `volume-expand.yaml`: operation candidates targeting `seaweedfs`. PVC expansion requires an expandable StorageClass.
- `s3-scale-out.yaml`, then `s3-scale-in.yaml`: grow then reduce the stateless S3 gateway, retaining at least one replica.
- `volume-scale-out.yaml`: add one data server to `seaweedfs-dist`; required anti-affinity needs another eligible node. No volume scale-in example is supplied because safe removal needs data migration.

Examples default to `DoNotTerminate`. They are intended for acceptance testing; offline render checks do not establish production support. Change the Cluster termination policy explicitly only when deleting its persisted data is intended.
