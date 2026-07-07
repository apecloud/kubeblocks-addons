# MariaDB Replication Manual Recovery Interface

This document defines the manual operation entry for a MariaDB replication
member that roleProbe marks as `recoveryPending`.

The addon does not choose or trigger recovery automatically. A user or external
system must verify the seed, choose the target instance, submit the operation,
and validate the result.

## Required Boundaries

- A healthy roleProbe result must not automatically clear
  `.replication-divergence-pending`.
- The divergence marker has higher priority than replication health.
- Only a manual or external recovery flow that has handled forked data may
  remove the divergence marker.
- The default RebuildInstance template omits `force`. Use `force: true` only as
  a separately approved manual exception after confirming the target can be
  destructively rebuilt.

## Preflight

`archive_verified` must be true:

- divergent local binlog/data evidence has been archived outside the target
  datadir;
- the archive has a manifest and checksum;
- local-only GTID ranges are recorded.

`seed_verified` must be true:

- the seed backup GTID covers the current primary's current GTID position; or
- any GTID gap between the seed backup and current primary can be filled from
  retained binlogs;
- old backups with purged or missing binlog coverage are not valid seeds.

Re-sample the current primary immediately before submitting the operation:

- current primary pod name;
- current primary GTID position;
- key table and row-count baseline;
- target instance is not the current primary.

Stop before submitting if any preflight item is missing.

## RebuildInstance Template

```yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  generateName: mariadb-rebuildinstance-
  namespace: <namespace>
spec:
  type: RebuildInstance
  clusterName: <cluster-name>
  rebuildFrom:
    - componentName: mariadb
      backupName: <verified-seed-backup-name>
      inPlace: true
      instances:
        - name: <cluster-name>-mariadb-<ordinal>
          targetNodeName: <optional-node-name>
```

## Post Validation

`OpsRequest` reaching `Succeed` is necessary but not sufficient. Validate all
items below with bounded retry:

- target pod SQL is reachable;
- `SHOW SLAVE STATUS` has `Slave_IO_Running=Yes`,
  `Slave_SQL_Running=Yes`, `Last_IO_Errno=0`, and `Last_SQL_Errno=0`;
- target pod has `read_only=1`;
- key tables and row counts match the current primary baseline;
- GTID has no unexpected local-only segment;
- role label returns to `secondary`;
- `.replication-manual-intervention-required` and
  `.replication-terminal-count` are absent.

Do not mark recovery successful if any validation item fails.
