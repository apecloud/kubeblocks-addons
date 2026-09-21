# SeaweedFS Cluster chart

Creates a KubeBlocks 1.0 Cluster. Install `addons/seaweedfs` first. See the [addon guide](../../addons/seaweedfs/README.md) for topology limits, credentials and validation status.

```sh
helm dependency build addons-cluster/seaweedfs
helm install seaweedfs addons-cluster/seaweedfs -n demo
helm install seaweedfs-dist addons-cluster/seaweedfs -n demo \
  --set topology=distributed --set s3.replicas=2
```

`topology=standalone` fixes master and volume at one replica. `distributed` fixes master at three, uses `volume.replicas` (default three, minimum two), and requires distinct nodes for each master/volume component's replicas. The filer is always a single persistent instance; this is not complete HA. `s3.replicas` controls the stateless gateway. Storage sizes, resources and StorageClass can be specified in values. The default `extra.terminationPolicy=DoNotTerminate` prevents accidental deletion.

The cluster also runs a single Admin instance with a 1 GiB PVC (`admin.storage`).
Its internal `<cluster>-admin` Service exposes `console:23646`; login reuses the
existing S3 admin account. No separate account or external Service is created.
