# YashanDB Fixed-Address HA Limitations

`cluster-fixed-ha-2.yaml` and `cluster-fixed-ha-3.yaml` document the fixed-address HA route only. In this PR, they are examples and template wiring; current-head runtime evidence is not attached.

This mode is not ordinary Pod-IP HA.

The examples use KubeBlocks per-instance templates to describe the intended topology:

- exactly one `YASDB_HA_NODE_ROLE=primary`;
- one or two `YASDB_HA_NODE_ROLE=standby` nodes;
- stable `YASDB_HA_NODE_IP` values;
- per-instance node affinity to fixed worker hostnames.

## Required Conditions

- Install the addon with `ha.fixedAddress.enabled=true`.
- Use a HA-capable YashanDB/yasboot image that contains the YashanDB package and yasboot package under the validated paths. The validated lab tag is not an official source promise; the image contract is the required runtime contents.
- Run the database Pods on workers whose node addresses are stable.
- Keep one database instance per worker node.
- Ensure the database port does not conflict on any hostNetwork node.
- Provide a Kubernetes Secret-backed SSH identity for yasboot bootstrap. `YASHANDB_SSH_PRIVATE_KEY` is required on the primary bootstrap node, and `YASHANDB_AUTHORIZED_KEY` is required on every fixed-address node.
- Use a fixed-address component definition version that is installed fresh. KubeBlocks marks `ComponentDefinition` runtime, service, config, script, and image contracts as immutable after creation, so fixed-address changes must be shipped as a new component definition version instead of patching an existing one in place.
- Use a fixed-address component definition that includes the empty-PVC yasboot bootstrap script.
- Replace the documentation-only `192.0.2.x` addresses and `worker-a/b/c` hostnames before applying the examples.
- Keep `YASDB_HA_CLUSTER_NAME` yasboot-safe, such as `kbfh2` or `kbfh3`. Do not copy a Kubernetes `Cluster` name with hyphens into this value.
- Keep a writer Service/Endpoint that points to the current primary. The optional addon writer Endpoint reconciler can maintain this Endpoint after a primary role change in fixed-address mode.
- Keep writer Endpoint switching conservative. The optional reconciler should move the writer Endpoint only after the candidate primary is `open/normal/primary` and passes a lightweight SQL write probe.

Create the SSH Secret before applying the fixed-address examples:

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ./yashandb-fixed-ha-id_rsa

kubectl -n demo create secret generic yashandb-fixed-ha-ssh \
  --from-file=id_rsa=./yashandb-fixed-ha-id_rsa \
  --from-file=authorized_key=./yashandb-fixed-ha-id_rsa.pub
```

The fixed-address HA image must provide at least:

- a supported YashanDB aarch64 runtime package;
- `/opt/yasboot-package/bin/yasboot`;
- OpenSSH server/client utilities;
- a writable `/home/yashan/mydb` mount owned or prepared for `yashan`;
- compatibility with the addon `fixed-ha-bootstrap.sh`, `check_alive.sh`, and `check_role.sh` scripts.

The current `ComponentDefinition` revision is `yashandb-1.2.0-alpha.1`. Earlier alpha revisions remain development history only. This revision keeps fixed-address HA opt-in and restores the default image to the standalone image, so fixed-address HA installs must explicitly override the image with a yasboot-capable image. Do not patch immutable `ComponentDefinition` runtime, script, config, service, or image fields in place.

## Not Claimed

- Generic `replicas: 2` or `replicas: 3` Pod-IP HA without fixed-address per-instance templates.
- Automatic database failover owned by a KubeBlocks controller.
- Native MySQL/PostgreSQL switchover parity.
- Pod migration to arbitrary nodes.
- Automatic repair of yasboot metadata after Pod IP changes.
- HA bootstrap without a Secret-provided SSH identity.

## Historical Lab Notes

The following notes are historical lab findings from development iterations. They are not current-head runtime evidence attached to this PR.

On 2026-06-23, a KubeBlocks `Cluster` using `yashandb-1.1.0-alpha.4` and the fixed-address two-node example created the first per-instance Pod on `172.16.90.245` with hostNetwork and the expected HA ports. The Pod stayed `1/2 Ready`, and KubeBlocks did not create the second ordered instance.

`yashandb-1.1.0-alpha.17` adds the empty-PVC bootstrap contract for this route: fixed-address mode renders `podManagementPolicy: Parallel` and starts `fixed-ha-bootstrap.sh` instead of the standalone install script. This lets all fixed-address Pods exist before the primary node runs the yasboot multi-node deployment.

`yashandb-1.1.0-alpha.27` is a historical recovery validation contract for this route: after a Pod is rebuilt with its PVC preserved, `fixed-ha-bootstrap.sh` reconstructs `/home/yashan/.yasboot`, writes the probe environment, starts local OM when that node owns OM metadata, starts the local agent through `yasboot process yasagent start -t <hosts.toml>`, starts only the local database node through `yasboot node start`, and waits for `check_alive.sh` plus `check_role.sh` before declaring the Pod ready. Later development revisions carried that contract forward and added the opt-in exporter sidecar runtime wiring. The current chart still uses versioned script/config template ConfigMaps to avoid mixed-revision KubeBlocks status drift.

Empty-PVC bootstrap also requires an SSH identity supplied by Secret. The private key must be available as `YASHANDB_SSH_PRIVATE_KEY` on the primary bootstrap node, and the public key must be available as `YASHANDB_AUTHORIZED_KEY` on every fixed-address node.

Evidence:

- `yashandb-kb-fixed-ha-2-yashan-comp-node1-0` was scheduled to `k8s-worker-1` with Pod IP `172.16.90.245`.
- The data PVC contained only `lost+found`; it did not contain `23.4.1.109/` or `yasdb_data/`.
- The container process was `bash /usr/local/bin/yasboot-sshd-entrypoint.sh`, which started sshd but did not initialize the empty PVC.
- `check_alive.sh` and `check_role.sh` failed because `.temp.ini`, `conf/yasdb.bashrc`, and `yasql` were absent under the mounted data directory.

Follow-up validation on 2026-06-23 using `yashandb-1.1.0-alpha.17` completed the empty-PVC bootstrap path:

- `yashandb-kb-fixed-ha-2`: 1 primary plus 1 standby, both `open/normal`, both Pods `2/2 Running`, Cluster `Running`.
- `yashandb-kb-fixed-ha-3`: 1 primary plus 2 standbys, all `open/normal`, all Pods `2/2 Running`, Cluster `Running`.

P1 clean validation on 2026-06-23 using `yashandb-1.1.0-alpha.27` also passed from empty PVCs:

- `yashandb-pr-clean-ha-3`: 1 primary plus 2 standbys, all Pods `2/2 Running`, Cluster `Running`, Component `Running`, InstanceSet `READY 3 / DESIRED 3 / UP-TO-DATE 3 / AVAILABLE 3`.
- KubeBlocks role labels showed node1 `primary`, node2 `secondary`, and node3 `secondary`.
- SQL `select status from v$instance` returned `OPEN` on the primary.
- The first clean attempt failed before this pass because `YASDB_HA_CLUSTER_NAME` copied the Kubernetes name `yashandb-pr-clean-ha-3`; yasboot rejected the hyphenated logical name. The examples now use yasboot-safe names such as `kbfh3`.

Conclusion from the historical lab notes: the fixed-address per-instance topology can be expressed, scheduled, and bootstrapped from empty PVCs when the addon fixed-address mode and SSH identity Secret are provided. Re-run this validation against the current PR head before promotion.

Native KubeBlocks switchover follow-up validation on 2026-06-23 also passed on `yashandb-kb-fixed-ha-3`:

- `OpsRequest/kbfh3-switchover-node2` targeted `yashandb-kb-fixed-ha-3-yashan-comp-node2-0`, reached `Succeed`, and KubeBlocks role label `kubeblocks.io/role` moved primary to node2.
- `OpsRequest/kbfh3-switchover-node3-p0` targeted `yashandb-kb-fixed-ha-3-yashan-comp-node3-0`, reached `Succeed`, and KubeBlocks role label `kubeblocks.io/role` moved primary to node3.
- A validation writer Endpoint named `yashandb-kbfh3-writer` was reconciled from `172.16.90.246:3688` to `172.16.90.247:3688` after the node3 switchover.
- Historical observation: native KubeBlocks switchover plus writer Endpoint following worked for that fixed-address empty-PVC route. Re-run against the current PR head before promotion. It still does not validate ordinary Pod-IP HA.
- Old-primary rebuild remains an operator-controlled action in this route. The reconciler can log `rebuild manual action required`, but it does not automatically run rebuild.

## Current-Head Validation Required Before Promotion

- One primary and one standby are `open/normal`.
- One primary and two standby nodes are `open/normal`.
- Planned switchover changes roles and updates the writer endpoint.
- Primary failure promotes a standby and updates the writer endpoint.
- The old primary is rebuilt as standby.
- Rolling restart does not leave yasboot metadata pointing at stale addresses.

## Historical Traffic Notes

The following traffic notes are historical development records. Re-run them against the current PR head before treating the writer endpoint reconciler or fixed-address HA path as runtime validated.

The fixed-address hostNetwork proof had one traffic failover validation record:

- Date: 2026-06-22.
- Run ID: `hostnet3_auto_failover_20260622T091645Z`.
- Fault: deleted the active primary Pod during continuous read/write traffic.
- Result: new primary `172.16.90.245:2688`; writer Endpoint updated to `172.16.90.245:2688`.
- Load result: `write_ok=57300`, `write_fail=8480`, `read_ok=438150`, `read_fail=600`.
- Final topology: one primary plus two standbys, all `open/normal`.

The addon writer Endpoint reconciler has also been validated with traffic:

- Run ID: `hostnet3_controller_failover_20260622T094544Z`.
- Fault: deleted the active primary Pod during continuous read/write traffic.
- Result: new primary `172.16.90.247:2688`; the reconciler updated writer Endpoint to `172.16.90.247:2688`.
- Load result: `write_ok=48500`, `write_fail=13320`, `read_ok=438500`, `read_fail=0`.
- Final topology: one primary plus two standbys, all `open/normal`.

The addon writer Endpoint reconciler has also been validated during planned switchover with traffic:

- Run ID: `controller_switchover_20260622T095815Z`.
- Action: ran `yasboot node switchover` from `1-1 / 172.16.90.245:2688` to `1-2 / 172.16.90.246:2688` during continuous read/write traffic.
- Result: switchover returned `rc=0`; the reconciler updated writer Endpoint to `172.16.90.246:2688`.
- Load result: `write_ok=52560`, `write_fail=4540`, `read_ok=423600`, `read_fail=0`.
- Observed write interruption: first write failure at `2026-06-22T09:58:42.045Z`, first recovered write at `2026-06-22T09:58:47.457Z`.

This reconciler follows the database primary. It does not execute database failover.
