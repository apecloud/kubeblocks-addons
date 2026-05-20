# Valkey Addon

> **Status**: draft
> **Applies to**: KubeBlocks 1.0+
> **Audience**: addon dev/test, reviewer, operator

Valkey is a Redis-compatible in-memory data store. This addon ships
KubeBlocks support for two topologies:

- **standalone**: single-node Valkey (no failover)
- **replication**: Valkey + Sentinel for primary/secondary HA with
  automatic failover

## Topologies

| Topology | Components | HA | Notes |
|---|---|---|---|
| `standalone` (default) | `valkey` | none | single pod; suitable for dev/cache |
| `replication` | `valkey-sentinel` + `valkey` (deployed in that order) | sentinel-managed primary election | requires ≥3 sentinel pods for quorum |

## Supported versions

The `valkey` ComponentVersion bundles:

| Major | Patch versions |
|---|---|
| 8.x | 8.0.0, 8.0.1, 8.1.0, 8.1.3 (default for major 8) |
| 9.x | 9.0.0 (default for major 9) |

Sentinel versions track the corresponding Valkey major (`valkey-sentinel-8`,
`valkey-sentinel-9`).

## Lifecycle actions

Declared lifecycle actions (see ComponentDefinition):

| Action | Scope | Notes |
|---|---|---|
| `roleProbe` | per pod | sentinel topology emits GlobalRoleSnapshot JSON (authoritative term); standalone emits plain `primary` |
| `postProvision` | primary only | registers primary with sentinel after first ready |
| `accountProvision` | per account | initializes default account via ACL SETUSER |
| `switchover` | cluster level | sentinel `FAILOVER` (or manual `REPLICAOF NO ONE` when sentinel absent); outer `OpsRequest` 5-minute deadline is the timeout authority |
| `memberJoin` | per pod | syncs ACL state to the new member |
| `memberLeave` | per pod | triggers sentinel failover if leaving primary |
| `reconfigure` | All pods | runs `reload-parameter.sh` for each changed parameter; dynamic params reload in place, static params require restart |

## Day-2 operations support

| Operation | Supported | Path |
|---|---|---|
| restart / stop / start | yes | KB controller drives standard pod lifecycle |
| horizontal scale-out | yes | `memberJoin` syncs ACL; sentinel discovers new replica |
| horizontal scale-in | yes | `memberLeave` triggers sentinel failover if needed |
| vertical scaling | yes | KB controller restarts pods with new requests/limits |
| volume expansion | yes | uses `volumeClaimTemplates` standard path |
| reconfigure | yes | via `reconfigure` lifecycle action; static params trigger restart, dynamic params hot-reload |
| switchover | yes (sentinel topology) | sentinel `FAILOVER`; candidate and fallback paths both covered |
| expose (NodePort / LoadBalancer) | yes | `replica-announce-ip` / `replica-announce-port` set in `valkey-start.sh:build_announce_addr` |
| upgrade | yes | ComponentVersion drives per-serviceVersion image pinning |
| rebuild instance | yes | KB controller creates a new pod with the same PVC; restore unaffected |
| backup (physical) | yes | see Backup section |
| restore | partial | see Backup compatibility matrix |
| PITR / incremental | **not supported** | not declared in BackupPolicyTemplate |
| sharding | **not supported** | not declared in ComponentDefinition |
| proxy | **not supported** | not declared |

## Backup methods

| Method | Type | ActionSet | Notes |
|---|---|---|---|
| `datafile` | physical (Valkey AOF/RDB) | `valkey-physical-br` | streams `/data` to BackupRepo |
| `volume-snapshot` | CSI snapshot | none (declares `snapshotVolumes: true`) | requires snapshot-capable CSI in the cluster |

Scheduled backup is **disabled by default** for both methods. Operators
enable scheduling at the Cluster level after confirming retention policy.

## Backup / restore compatibility matrix

Verified paths are marked ✓. Paths marked ⚠ are supported by construction
but lack a recorded end-to-end test; treat them as untested. Paths marked
✗ are declared out of scope.

| Source → Target | Same serviceVersion | Cross-patch (e.g. 8.0.0 → 8.1.3) | Cross-major (8.x → 9.x) |
|---|---|---|---|
| new-cluster restore (`datafile`) | ✓ | ⚠ untested | ✗ not supported |
| new-cluster restore (`volume-snapshot`) | ✓ | ⚠ untested | ✗ not supported |
| rebuild-instance (KB rebuilds a pod in place) | ✓ | n/a | n/a |
| scaleOut.fromBackup | ⚠ untested | ⚠ untested | ✗ not supported |
| cross-topology (standalone → replication, or vice versa) | ⚠ untested | n/a | n/a |

Cross-major restore is unsupported because Valkey 9 introduces wire-format
and persistence changes that the addon does not validate.

### Restore caveats

The post-restore `restore-sentinel-acl.sh` and `post-restore-sentinel.sh`
hooks re-register the restored primary with the **existing** Sentinel
pods. Behavior depends on Sentinel state:

- **Sentinel pods healthy at restore time** — the restored Valkey primary
  re-registers and resumes normal failover. ✓
- **Sentinel PVC lost at restore time** — Sentinel boots empty, has no
  prior knowledge of the master. Re-registration runs, but Sentinel must
  rebuild its master/replica view from scratch and quorum must
  re-converge before failover works. ⚠ This is **not** automatically
  recovered by the addon today; operator may need to:
  - delete and recreate the affected Sentinel pods, or
  - manually `SENTINEL MONITOR <name> <ip> <port> <quorum>` from one
    Sentinel pod to seed the topology
- **Both Valkey and Sentinel PVCs lost** — a fresh Cluster from backup
  recovers data, but sentinel state is rebuilt by the addon's
  `valkey-register-to-sentinel.sh` postProvision step. ✓

The current backup methods cover only the Valkey `/data` volume.
Sentinel state (sentinel.conf with master config) is NOT backed up. A
future enhancement may add a Sentinel volume to the backup target; until
then, operate Sentinel pods with adequate replicas (≥3) and assume
Sentinel state is reconstructible from the data plane.

## TLS

TLS is declared in ComponentDefinition (`tls` volume mounts `/etc/pki/tls`,
ca/cert/key files exposed). End-to-end paths exercised:

| Path | Status |
|---|---|
| Valkey server startup with TLS port | ✓ |
| Client connection from `valkey-cli` with TLS | ✓ (via `VALKEY_CLI_TLS_ARGS`) |
| roleProbe (`check-role.sh`) with TLS | ✓ (reuses `VALKEY_CLI_TLS_ARGS`) |
| Sentinel ↔ master TLS | ⚠ untested at addon level |
| Backup / restore over TLS | ⚠ not exercised; backup script uses local Unix-socket pattern, restore reads from BackupRepo |

## Parameters

Parameter behavior is split between two classes in
`templates/paramsdef.yaml`:

- **staticParameters** (require restart): `bind`, `port`, `tls-port`,
  `daemonize`, `databases`, `dir`, `logfile`, `aclfile`, `tcp-backlog`
- **dynamicParameters** (~60 keys, hot-reload via `CONFIG SET`):
  `maxmemory`, `maxclients`, `loglevel`, `appendonly`, etc.

The `reconfigure` lifecycle action calls `reload-parameter.sh` for each
changed parameter. Static parameters trigger a rolling restart through
the KB Component controller's reconfigure pipeline.

## Known limitations

- **PITR / continuous backup**: not supported in this addon version
- **Sharded deployment**: not supported (Valkey Cluster mode not declared)
- **Proxy front-end**: not bundled (use the redis-proxy addon if needed)
- **Sentinel state in backup**: not included; see "Restore caveats" above
- **Cross-major restore**: blocked by Valkey persistence/wire format
  changes; operator should drain and reload at the application layer
- **`hostAliases` / `dnsConfig` / hostNetwork advertised address**: not
  exercised end-to-end; the `replica-announce-ip` path covers NodePort
  and LoadBalancer, host-network deployments may need additional flags
- **`replicas: 0` (component-level pause)**: not exercised; KB controller
  behavior may interact with sentinel quorum in unexpected ways

## References

- API contract: <https://github.com/apecloud/kubeblocks-addon-docs/tree/main/docs/addon-api>
- Acceptance discipline: `docs/addon-api/12a-minimum-acceptance.md` and
  `docs/addon-api/12b-claimed-only-acceptance.md`
