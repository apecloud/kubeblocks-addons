#!/usr/bin/env python3
"""Local TLS regression using disposable PostgreSQL and PgBouncer containers.

Run with: python3 examples/postgresql/test/pgbouncer_test.py
Requires Docker, OpenSSL, and the images named below (or the corresponding env
overrides). No Kubernetes context, host port, or existing database is used.
"""

import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import time
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[3]
ADDON = ROOT / "addons/postgresql"
PG_IMAGE = os.environ.get("PGBOUNCER_TEST_POSTGRES_IMAGE", "postgres:14.12-alpine")
POOL_IMAGE = os.environ.get("PGBOUNCER_TEST_IMAGE", "apecloud/pgbouncer:1.25.2")


class PgBouncerTest(unittest.TestCase):
    def command(self, *args, check=True, timeout=30, env=None):
        result = subprocess.run(args, text=True, capture_output=True,
                                timeout=timeout, env=env)
        if check and result.returncode:
            self.fail(f"{args[0]} failed: {result.stderr[-1200:]}")
        return result

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pgbouncer-tls-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.path.chmod(0o755)
        self.network = "pgbouncer-tls-" + uuid.uuid4().hex[:10]
        self.pg = self.network + "-pg"
        self.pool = self.network + "-pool"
        self.password = secrets.token_urlsafe(24)
        for name in ("ca", "config", "certs"):
            (self.path / name).mkdir(mode=0o755)
        self.certificates("first")
        self.certificates("next")
        self.server_certificate("wrong-host", "first", "another-service")
        for suffix in ("crt", "key"):
            shutil.copyfile(self.path / f"certs/first-server.{suffix}",
                            self.path / f"server.{suffix}")
        self.write_private("password", self.password)
        self.write_private("pool.env", "\n".join([
            "POSTGRESQL_HOST=pg-primary", "POSTGRESQL_PORT=5432",
            "POSTGRESQL_USERNAME=postgres", "POSTGRESQL_PASSWORD=" + self.password,
        ]) + "\n")
        self.configure("disable")
        self.command("docker", "network", "create", "--internal", self.network)
        self.addCleanup(self.remove_network)
        self.addCleanup(self.remove_container, self.pg)
        self.command("docker", "run", "-d", "--name", self.pg,
                     "--network", self.network, "--network-alias", "pg-primary",
                     "--memory", "512m", "--cpus", "1",
                     "--mount", f"type=bind,src={self.path},dst=/fixtures,readonly",
                     "--tmpfs", "/var/lib/postgresql/data", "--tmpfs", "/server-tls",
                     "-e", "POSTGRES_PASSWORD_FILE=/fixtures/password",
                     "--entrypoint", "/bin/sh", PG_IMAGE, "-ec",
                     "cp /fixtures/server.crt /fixtures/server.key /server-tls/; "
                     "chown postgres:postgres /server-tls/*; chmod 600 /server-tls/server.key; "
                     "exec docker-entrypoint.sh postgres "
                     "-c ssl_cert_file=/server-tls/server.crt "
                     "-c ssl_key_file=/server-tls/server.key")
        self.wait_for(lambda: self.command(
            "docker", "exec", self.pg, "pg_isready", "-h", "127.0.0.1",
            "-U", "postgres", check=False).returncode == 0)
        self.pg_sql("ALTER SYSTEM SET ssl = on")
        self.pg_sql("SELECT pg_reload_conf()")
        self.wait_for(lambda: self.pg_sql("SHOW ssl").stdout.strip() == "on")
        self.addCleanup(self.remove_container, self.pool)
        self.command("docker", "run", "-d", "--name", self.pool,
                     "--network", self.network, "--user", "70:70",
                     "--memory", "128m", "--cpus", "0.5",
                     "--env-file", str(self.path / "pool.env"),
                     "--tmpfs", "/etc/pgbouncer:uid=70,gid=70,mode=0700",
                     "--mount", f"type=bind,src={self.path / 'config'},dst=/opt/pgbouncer-template,readonly",
                     "--mount", f"type=bind,src={self.path / 'ca'},dst=/etc/pgbouncer/tls,readonly",
                     "--mount", f"type=bind,src={ADDON / 'scripts'},dst=/kb-scripts,readonly",
                     "--entrypoint", "/kb-scripts/pgbouncer-setup.sh", POOL_IMAGE)
        self.wait_for(lambda: self.pool_sql("SELECT 1", check=False).returncode == 0)
        self.process_identity = self.command(
            "docker", "inspect", "--format", "{{.State.Pid}} {{.State.StartedAt}}",
            self.pool).stdout

    def write_private(self, name, value):
        target = self.path / name
        target.write_text(value)
        target.chmod(0o600)

    def remove_container(self, name):
        self.command("docker", "rm", "-f", "-v", name, check=False)

    def remove_network(self):
        self.command("docker", "network", "rm", self.network, check=False)

    def certificates(self, name):
        base = self.path / f"certs/{name}-ca"
        self.command("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                     "-days", "1", "-subj", f"/CN={name}",
                     "-keyout", str(base) + ".key", "-out", str(base) + ".crt")
        self.server_certificate(name, name, "pg-primary")

    def server_certificate(self, name, issuer, hostname):
        base = self.path / f"certs/{name}-server"
        ca = self.path / f"certs/{issuer}-ca"
        extensions = self.path / f"certs/{name}.ext"
        extensions.write_text(f"subjectAltName=DNS:{hostname}\nextendedKeyUsage=serverAuth\n")
        self.command("openssl", "req", "-newkey", "rsa:2048", "-nodes",
                     "-subj", f"/CN={hostname}", "-keyout", str(base) + ".key",
                     "-out", str(base) + ".csr")
        self.command("openssl", "x509", "-req", "-in", str(base) + ".csr",
                     "-CA", str(ca) + ".crt", "-CAkey", str(ca) + ".key",
                     "-CAcreateserial", "-days", "1", "-extfile", str(extensions),
                     "-out", str(base) + ".crt")

    def configure(self, mode, max_clients=500):
        config = (ADDON / "config/pgbouncer-ini.tpl").read_text()
        config = config.replace("server_tls_sslmode = disable", f"server_tls_sslmode = {mode}")
        config = config.replace("max_client_conn = 500", f"max_client_conn = {max_clients}")
        config = config.replace("query_wait_timeout = 120", "query_wait_timeout = 3")
        (self.path / "config/pgbouncer.ini").write_text(config)

    def pg_sql(self, sql, check=True):
        return self.command("docker", "exec", "--user", "postgres", self.pg,
                            "psql", "-XAt", "-U", "postgres", "-d", "postgres",
                            "-v", "ON_ERROR_STOP=1", "-c", sql, check=check)

    def pool_sql(self, sql, database="postgres", check=True):
        env = dict(os.environ, PGPASSWORD=self.password)
        return self.command("docker", "exec", "-e", "PGPASSWORD", self.pool,
                            "psql", "-XAt", "host=127.0.0.1 port=6432 user=postgres "
                            f"dbname={database} sslmode=disable connect_timeout=3",
                            "-v", "ON_ERROR_STOP=1", "-c", sql,
                            check=check, timeout=8, env=env)

    def wait_for(self, predicate, timeout=35):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if predicate():
                    return
            except subprocess.TimeoutExpired:
                pass
            time.sleep(1)
        self.fail("condition did not converge")

    def reload_pool(self):
        self.command("docker", "kill", "--signal=HUP", self.pool)
        self.pool_sql("RECONNECT", "pgbouncer")

    def assert_backend_tls(self, enabled=True):
        expected = "t" if enabled else "f"
        self.wait_for(lambda: self.pool_sql(
            "SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()", check=False
        ).stdout.strip() == expected)

    def assert_tls_failure(self):
        since = self.command("docker", "exec", self.pool, "date", "-u",
                             "+%Y-%m-%dT%H:%M:%SZ").stdout.strip()
        result = self.pool_sql("SELECT 1", check=False)
        self.assertNotEqual(result.returncode, 0)
        logs = self.command("docker", "logs", "--since", since, self.pool)
        self.assertRegex(logs.stdout + logs.stderr,
                         r"(?i)(certificate verify failed|TLS handshake|server refused SSL|failed to load CA)")

    def replace_server_certificate(self, name):
        self.command("docker", "exec", self.pg, "/bin/sh", "-ec",
                     f"cp /fixtures/certs/{name}-server.crt /server-tls/server.crt; "
                     f"cp /fixtures/certs/{name}-server.key /server-tls/server.key; "
                     "chown postgres:postgres /server-tls/*; chmod 600 /server-tls/server.key")
        self.pg_sql("SELECT pg_reload_conf()")
        time.sleep(1)

    def test_backend_tls_and_reload(self):
        self.assert_backend_tls(False)
        shutil.copyfile(self.path / "certs/first-ca.crt", self.path / "ca/ca.pem")
        self.configure("verify-full")
        self.reload_pool()
        self.assert_backend_tls()

        self.pg_sql("CREATE TABLE tls_probe(value integer); INSERT INTO tls_probe VALUES (42)")
        self.assertEqual(self.pool_sql("SELECT value FROM tls_probe").stdout.strip(), "42")
        self.configure("verify-full", max_clients=700)
        self.reload_pool()
        self.assertIn("max_client_conn|700|", self.pool_sql("SHOW CONFIG", "pgbouncer").stdout)
        self.assert_backend_tls()

        # verify-full rejects a plaintext-only backend instead of downgrading.
        self.pg_sql("ALTER SYSTEM SET ssl = off")
        self.pg_sql("SELECT pg_reload_conf()")
        self.wait_for(lambda: self.pg_sql("SHOW ssl").stdout.strip() == "off")
        self.reload_pool()
        self.assert_tls_failure()
        self.pg_sql("ALTER SYSTEM SET ssl = on")
        self.pg_sql("SELECT pg_reload_conf()")
        self.wait_for(lambda: self.pg_sql("SHOW ssl").stdout.strip() == "on")
        self.reload_pool()
        self.assert_backend_tls()

        # A trusted CA does not excuse a hostname mismatch with verify-full.
        self.replace_server_certificate("wrong-host")
        self.reload_pool()
        self.assert_tls_failure()
        self.replace_server_certificate("first")
        self.reload_pool()
        self.assert_backend_tls()

        # A different trusted CA must reject the current PostgreSQL certificate.
        shutil.copyfile(self.path / "certs/next-ca.crt", self.path / "ca/ca.pem")
        self.reload_pool()
        self.assert_tls_failure()

        # Rotate with an overlapping CA bundle, then retire the previous CA.
        (self.path / "ca/ca.pem").write_text(
            (self.path / "certs/first-ca.crt").read_text()
            + (self.path / "certs/next-ca.crt").read_text())
        self.reload_pool()
        self.assert_backend_tls()
        self.replace_server_certificate("next")
        self.reload_pool()
        self.assert_backend_tls()
        shutil.copyfile(self.path / "certs/next-ca.crt", self.path / "ca/ca.pem")
        self.reload_pool()
        self.assert_backend_tls()

        self.configure("verify-ca")
        self.reload_pool()
        self.assert_backend_tls()
        self.configure("require")
        self.reload_pool()
        self.assert_backend_tls()
        self.configure("disable")
        self.reload_pool()
        self.assert_backend_tls(False)
        self.assertEqual(self.process_identity, self.command(
            "docker", "inspect", "--format", "{{.State.Pid}} {{.State.StartedAt}}",
            self.pool).stdout)

        # A fresh instance without the CA rejects backend connections.
        (self.path / "ca/ca.pem").unlink()
        self.configure("verify-full")
        self.command("docker", "restart", self.pool)
        self.assert_tls_failure()


if __name__ == "__main__":
    unittest.main(verbosity=2)
