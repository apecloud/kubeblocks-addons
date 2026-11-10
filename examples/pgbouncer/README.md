# Standalone PgBouncer examples

Create `demo/pg-cluster` using PostgreSQL Addon 1.0.8 first, then install
PgBouncer Addon 1.0.0. Apply `cluster.yaml` for a primary connection pool and
`cluster-readonly.yaml` for a replica connection pool. Both use PostgreSQL
business accounts and database names. The pools have independent lifecycle,
resources, configuration and addresses.

Apply `configure.yaml` to change the read/write pool's parameters. See the
[Addon guide](../../addons/pgbouncer/README.md) for authentication, TLS, role
changes and connection-lifetime behavior.
