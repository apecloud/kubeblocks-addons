# PgBouncer Cluster chart

Creates an independent PgBouncer Cluster referencing an existing PostgreSQL
Cluster in the same namespace. Set `postgresql.cluster` and choose
`backend.role=rw` or `backend.role=ro`. See the
[Addon guide](../../addons/pgbouncer/README.md) for prerequisites and examples.
