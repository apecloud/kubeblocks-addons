# RustFS Addon

This chart defines RustFS `1.0.0-beta.10`. The runtime and role-probe images use
`docker.io/rustfs/rustfs:1.0.0-beta.10`; the init image uses
`docker.io/apecloud/kubeblocks-tools:1.0.0`.

The companion `addons-cluster/rustfs` chart creates 4 replicas. Its Cluster
does not set `serviceVersion`, so KubeBlocks resolves the version from the
matching ComponentDefinition and ComponentVersion. Verify the resolved
serviceVersion and images in the installed Component and Pods.

## KubeBlocks compatibility

Chart 0.1.2 targets KubeBlocks 1.2 and later and uses `passwordConfig` for
root password generation. The compatibility annotation describes support for
the whole addon, not just field availability in the CRD.

The chart version and ComponentDefinition name remain `0.1.2` and
`rustfs-0.1.2`. This chart does not provide an in-place migration for an existing
definition that still uses `passwordGenerationPolicy`: its `systemAccounts`
field is immutable, so that installation needs a separate migration plan.

## Scaling Boundary

The ComponentDefinition accepts 1 through 32 replicas, but RustFS distributed
erasure-coding pools do not support removing nodes. Scale-in is rejected by the
`memberLeave` action to avoid data loss. Do not interpret `minReplicas: 1` as
scale-in support.
