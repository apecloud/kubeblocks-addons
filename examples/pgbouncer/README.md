# Standalone PgBouncer examples

Create `demo/pg-cluster` with the PostgreSQL Addon first, then install
PgBouncer Addon 1.0.0. Apply `cluster.yaml` for a primary connection pool.

For a replica connection pool, first apply `expose-readonly.yaml` and wait for
its OpsRequest to succeed, then apply `cluster-readonly.yaml`. The expose
operation adds the `postgresql-internal-ro` ClusterIP service on demand; it
selects only replicas and does not fall back to the primary. PostgreSQL does
not create this service by default.

Both pools use PostgreSQL business accounts and database names. They have
independent lifecycle, resources, configuration and addresses.

Apply `configure.yaml` to change the read/write pool's parameters. See the
[Addon guide](../../addons/pgbouncer/README.md) for authentication, TLS, role
changes and connection-lifetime behavior.
