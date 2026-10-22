# RustFS Addon

This chart defines RustFS `1.0.0-beta.10`. The runtime and role-probe images use
`docker.io/rustfs/rustfs:1.0.0-beta.10`; the init image uses
`docker.io/apecloud/kubeblocks-tools:1.0.0`.

The companion `addons-cluster/rustfs` chart creates 4 replicas. Its Cluster
does not set `serviceVersion`, so KubeBlocks resolves the version from the
matching ComponentDefinition and ComponentVersion. Verify the resolved
serviceVersion and images in the installed Component and Pods.

## Addon upgrades

Chart 0.1.3 targets KubeBlocks 1.2 and later and uses `passwordConfig` for
root password generation. Upgrade KubeBlocks before installing this chart on
older clusters. The compatibility annotation describes support for the whole
addon; it is not just a statement about field availability in the CRD.

The chart creates `rustfs-0.1.3` instead of changing the immutable
`systemAccounts` of `rustfs-0.1.2`. The ComponentVersion remains compatible with both definitions. New installs
retain their ComponentDefinition with `helm.sh/resource-policy: keep` by default. An addon upgrade does not migrate
existing Components or rotate their root credentials. This also applies to
0.1.2 installations made before the field was renamed to `passwordConfig`.

**Existing releases need a retention step first.** RustFS 0.1.2 defaulted to
`extra.keepResource: false`, unlike MinIO. Before upgrading, use the exact chart
archive originally installed for that release and enable retention:

```bash
helm upgrade <release> <original-chart-archive> --namespace <release-namespace> \
  --reuse-values --set extra.keepResource=true
```

Check that `helm get manifest` now includes `helm.sh/resource-policy: keep` on
`rustfs-0.1.2`, then upgrade to 0.1.3 with `--set extra.keepResource=true` (also
when using `--reuse-values`). Use the original archive without changing its
account fields; a newer 0.1.2 archive containing only the field rename can hit the
same immutability error. Annotating only the live object does not update Helm's
stored manifest. Do not delete the old definition while Components reference it.

## Scaling Boundary

The ComponentDefinition accepts 1 through 32 replicas, but RustFS distributed
erasure-coding pools do not support removing nodes. Scale-in is rejected by the
`memberLeave` action to avoid data loss. Do not interpret `minReplicas: 1` as
scale-in support.
