# SeaweedFS

SeaweedFS is an object store with separate master, volume, filer and S3 services. This addon targets **KubeBlocks 1.0** and SeaweedFS **4.47** (`serviceVersion: "4.47.0"`). The [Chinese design](DESIGN.zh-CN.md) explains the component boundaries and validation plan.

This is an initial implementation. Offline script, chart and KubeBlocks 1.0 schema checks are available; live acceptance is still required. Neither topology is claimed to be production ready.

## Topologies

| Component | standalone (default) | distributed | Persistent directory |
| --- | --- | --- | --- |
| master | Exactly 1 | Exactly 3, native Raft election | `/data/master` |
| volume | Exactly 1, one data copy (`000`) | 2–32, two copies on distinct volume servers (`001`) | `/data/volume` |
| filer | Exactly 1 | Exactly 1 | `/data/filer`, LevelDB2 |
| s3 | 1–32 | 1–32 | Stateless |
| admin | Exactly 1 | Exactly 1 | `/data/admin`, session keys and maintenance state |

**The distributed topology still has a single filer.** Loss of its PVC can lose the object namespace even when volume data survives. It is not a complete HA or backup solution. Volume scale-out adds capacity; existing data is not automatically rebalanced. Direct volume scale-in is rejected by a lifecycle action because it requires data evacuation. Master membership and filer replicas are fixed.

The distributed example needs at least three schedulable nodes: its master and volume pods use required anti-affinity. Increasing volume replicas requires another eligible node per replica unless the operator deliberately changes that scheduling policy. Replication placement does not promise availability-zone separation.

## Install and create

Install KubeBlocks from the `release-1.0` line first. From the root of this repository:

```sh
helm dependency build addons/seaweedfs
helm upgrade --install seaweedfs addons/seaweedfs -n kb-system
kubectl create namespace demo
kubectl apply -f examples/seaweedfs/cluster.yaml
```

For the distributed example:

```sh
kubectl apply -f examples/seaweedfs/cluster-distributed.yaml
```

Alternatively, install the Cluster chart after the addon:

```sh
helm dependency build addons-cluster/seaweedfs
helm install seaweedfs addons-cluster/seaweedfs -n demo
# For distributed, use a different release name:
helm install seaweedfs-dist addons-cluster/seaweedfs -n demo \
  --set topology=distributed --set s3.replicas=2
```

Examples explicitly set the engine version and PVC sizes. They use the default StorageClass; set `storageClassName` in the Cluster chart or each example PVC when needed. `DoNotTerminate` is the default deletion policy. Deleting stored data requires an explicit change to the Cluster termination policy.

Definition and script/config names are shared, cluster-wide addon identities. Install one addon release per Kubernetes cluster; instances may live in different namespaces. Do not install a second addon release into another namespace to try to create an independent copy of those definitions.

## S3 access

The `default` S3 service is `<cluster>-s3`, port 8333. Only expose this gateway to application clients. Master, volume and filer interfaces have no internal authentication in this first version and require a trusted cluster network.

```sh
kubectl -n demo port-forward svc/seaweedfs-s3 8333:8333
```

In another shell with AWS CLI installed, load the generated account without printing the secret:

```sh
export AWS_ACCESS_KEY_ID="$(kubectl -n demo get secret seaweedfs-s3-account-admin -o jsonpath='{.data.username}' | base64 --decode)"
export AWS_SECRET_ACCESS_KEY="$(kubectl -n demo get secret seaweedfs-s3-account-admin -o jsonpath='{.data.password}' | base64 --decode)"
export AWS_DEFAULT_REGION=us-east-1
aws --endpoint-url http://127.0.0.1:8333 s3 mb s3://example-bucket
printf 'hello SeaweedFS\n' > /tmp/seaweedfs-example.txt
aws --endpoint-url http://127.0.0.1:8333 s3 cp /tmp/seaweedfs-example.txt s3://example-bucket/object.txt
aws --endpoint-url http://127.0.0.1:8333 s3 cp s3://example-bucket/object.txt -
```

Use path-style S3 addressing. The gateway fails to start if either credential is absent. Credentials are read from environment variables, so changing the account Secret requires restarting **all** S3 instances. Automatic credential rotation and general account management are not implemented. The anonymous `/healthz` endpoint only checks that the gateway responds; it does not prove authenticated object reads or filer/volume availability.

## Admin console

The `default` Admin service is `<cluster>-admin`, with the `console` port 23646.
Log in using the existing `<cluster>-s3-account-admin` username and password;
no additional account is generated. In KBE, enabling or disabling the console
controls its external access Service; the Admin component continues running.
The Admin process requires both credentials
and refuses to start without them. Credential changes require restarting Admin
as well as every S3 instance.

```sh
kubectl -n demo port-forward svc/seaweedfs-admin 23646:23646
```

Open `http://127.0.0.1:23646`. For remote access, use an authenticated network path
and HTTPS termination; the addon itself creates only an internal Service.
Admin runs as one instance with a dedicated 1 GiB PVC for session keys, configuration,
and maintenance task state. Scaling it with the S3 gateways would create independent
sessions and maintenance schedulers, so its replica count is fixed at one.
No Worker component is provisioned; operations that require workers need a separately
configured worker and are not enabled by adding this UI.

## Monitoring and logs

Master, volume, filer and S3 expose native Prometheus metrics at `http://<pod-ip>:9327/metrics`.
The port follows the [SeaweedFS 4.47 community chart](https://github.com/seaweedfs/seaweedfs/blob/4.47/k8s/charts/seaweedfs/values.yaml).
Each ComponentDefinition declares a native exporter with the named `http-metrics`
port; a compatible monitoring integration can discover these endpoints.
No exporter sidecar or Pushgateway is needed. Metrics are not added to client Services
and require a trusted cluster network, like the internal engine interfaces.

All four processes log to container stderr (`-logtostderr=true`). Kubernetes container
logs and a configured cluster log collector can read them without an additional file
log sidecar. This does not enable S3 access/audit logs.

## Operations and boundaries

All listed operations require live acceptance against the pinned candidate before being considered supported in production. Run operations sequentially and verify object checksums after each one.

| Operation | Implementation / boundary | Example |
| --- | --- | --- |
| Restart | Existing data is reused; singleton filer/standalone components have downtime | [restart](../../examples/seaweedfs/restart.yaml) |
| Stop / Start | Intended to retain PVCs and reopen existing state | [stop](../../examples/seaweedfs/stop.yaml), [start](../../examples/seaweedfs/start.yaml) |
| Vertical scaling | Recreates the selected component pods | [verticalscale](../../examples/seaweedfs/verticalscale.yaml) |
| PVC expansion | Requires an expandable StorageClass/CSI; shrinking is not supported | [volume-expand](../../examples/seaweedfs/volume-expand.yaml) |
| S3 scaling | Stateless replicas; keep at least one. Scale out before the scale-in example | [out](../../examples/seaweedfs/s3-scale-out.yaml), [in](../../examples/seaweedfs/s3-scale-in.yaml) |
| Volume scale-out | Distributed topology only; new capacity, no automatic rebalance | [volume-scale-out](../../examples/seaweedfs/volume-scale-out.yaml) |
| Volume scale-in | Rejected; migrate and verify data before a separately designed removal | No destructive example |
| Master / filer scaling | Fixed membership / single LevelDB2 store | Not supported |
| TLS, backup/restore, PITR, rebuild | No implementation or capability declarations | Not supported |
| Engine upgrade, reconfigure, planned switchover | Single tested-version target; no operation contract yet | Not supported |

Creation/update order is master → volume → filer → s3 → admin; termination is the reverse. Master pods are created in parallel to permit election, then updated serially, with followers before the leader. The engine performs failover; this addon does not offer a planned Switchover operation.

## Configuration and runtime inputs

`image.registry` and `image.repository` support equivalent mirrors. The supported tag is fixed at `4.47`; changing the tag/version requires a reviewed version matrix. `volumeSizeLimitMB` defaults to 1024 MiB per SeaweedFS volume file, independently of PVC capacity. The volume server derives its maximum volume count from disk space (`-max=0`). Do not change a cluster-wide definition's setting for running instances without a separately validated migration.

Startup scripts use these explicit input contracts:

| Variable | Source / format |
| --- | --- |
| `POD_NAME` | Kubernetes downward API, the actual Pod name |
| `SEAWEEDFS_POD_FQDNS` | Current componentVarRef, comma-separated actual Pod FQDNs |
| `SEAWEEDFS_MASTER_FQDNS` | Master componentVarRef, comma-separated actual Pod FQDNs |
| `SEAWEEDFS_MASTER_REPLICAS` | Definition constant, exactly `1` or `3` |
| `SEAWEEDFS_REPLICATION` | Definition constant, `000` or `001` |
| `SEAWEEDFS_FILER_HOST`, `SEAWEEDFS_FILER_PORT` | Internal filer Service host and HTTP port; do not expose/replace that internal service |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Required KubeBlocks S3 `admin` account Secret |
| `WEED_ADMIN_USER`, `WEED_ADMIN_PASSWORD` | The same S3 `admin` account, referenced by the Admin component |

Pod names need not have contiguous ordinals and DNS suffixes are not hardcoded. The engine runs as UID/GID 1000 with PVC fsGroup 1000. Mounted scripts are read-only executable files; the filer config is read-only and points its LevelDB2 store into the persistent volume. Startup never formats or removes existing data. Startup/liveness use local TCP checks; readiness uses the engine's HTTP health checks.

## Offline checks

These checks start no databases and contact no Kubernetes API:

```sh
helm dependency build addons/seaweedfs --skip-refresh
helm dependency build addons-cluster/seaweedfs --skip-refresh
helm lint addons/seaweedfs
helm lint addons-cluster/seaweedfs
shellcheck addons/seaweedfs/scripts/*.sh
shellspec --load-path ./shellspec addons/seaweedfs/scripts-ut-spec
# Python environment requires PyYAML and jsonschema.
KB_CRD_DIR=/path/to/kubeblocks/config/crd/bases \
  python3 addons/seaweedfs/tests/test_charts.py
```

The CRDs must come from the intended `release-1.0` commit. This offline schema check rejects undeclared fields but does not execute Kubernetes admission, defaulting, CEL or controllers. Live validation must still verify generated objects, account authentication, persisted reads, supported operations, failure recovery and cleanup on both topologies.
