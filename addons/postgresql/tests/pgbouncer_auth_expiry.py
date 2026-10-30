#!/usr/bin/env python3
"""Verify rendered PgBouncer authentication SQL on an isolated PostgreSQL server.

Requires helm, ruby with YAML support, and PostgreSQL server/client binaries.
Run as a non-root user with PG_BIN pointing to the PostgreSQL bin directory:
  PG_BIN=/path/to/pg/bin python3 addons/postgresql/tests/pgbouncer_auth_expiry.py
The server accepts only a private temporary Unix socket; it is always stopped.
"""
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
import time


def run(args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, check=True, **kwargs)


def main():
    chart = Path(__file__).resolve().parents[1]
    pg = Path(os.environ["PG_BIN"]).resolve()
    rendered = run(["helm", "template", "auth-test", str(chart)]).stdout
    configuration = run(["ruby", "-ryaml", "-e", '''
      docs = YAML.load_stream(STDIN.read).compact
      config = docs.find { |d| d["kind"] == "ConfigMap" && d.dig("data", "pgbouncer.ini") }
      puts config.dig("data", "pgbouncer.ini")
    '''], input=rendered).stdout
    auth_query = re.search(r"^auth_query = (.+)$", configuration, re.MULTILINE).group(1)
    assert "pg_catalog.pg_authid" in auth_query
    password = secrets.token_hex(24)
    rows = []
    with tempfile.TemporaryDirectory(prefix="pg-auth-expiry-") as directory:
        temp = Path(directory)
        data, sock = temp / "data", temp / "sock"
        sock.mkdir()
        server = None

        def sql(query):
            return run([str(pg / "psql"), "-X", "-h", str(sock), "-U", "postgres",
                        "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"], input=query).stdout.strip()

        with (temp / "server.log").open("w") as log:
            try:
                run([str(pg / "initdb"), "-D", str(data), "-U", "postgres", "-A", "trust", "--no-locale"])
                (data / "pg_hba.conf").write_text("local all postgres trust\nlocal all all scram-sha-256\n")
                server = subprocess.Popen([str(pg / "postgres"), "-D", str(data), "-c", "listen_addresses=",
                                           "-c", f"unix_socket_directories={sock}"], stdout=log, stderr=log)
                for _ in range(100):
                    if subprocess.run([str(pg / "pg_isready"), "-h", str(sock)], capture_output=True).returncode == 0:
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError("temporary PostgreSQL server failed to start")
                cases = [("expired_probe", "LOGIN", "2000-01-01", False),
                         ("future_probe", "LOGIN", "2099-01-01", True),
                         ("unlimited_probe", "LOGIN", None, True),
                         ("nologin_probe", "NOLOGIN", None, False)]
                for name, login, until, expected in cases:
                    validity = f" VALID UNTIL '{until}'" if until else ""
                    sql(f"CREATE ROLE {name} {login} PASSWORD '{password}'{validity};")
                    # PgBouncer uses the existing postgres account, as in release-1.0.
                    # PREPARE exercises the $1 parameter exactly as auth_query does.
                    result = sql(f"PREPARE auth_lookup(text) AS {auth_query}; EXECUTE auth_lookup('{name}');")
                    records = [line.split("|", 1) for line in result.splitlines() if "|" in line]
                    verifier = any(len(row) == 2 and bool(row[1]) for row in records)
                    direct = subprocess.run([str(pg / "psql"), "-X", "-h", str(sock), "-U", name,
                                             "-d", "postgres", "-Atc", "SELECT 1"], text=True,
                                            capture_output=True, env=dict(os.environ, PGPASSWORD=password))
                    assert verifier == expected, (name, "unexpected verifier availability", verifier)
                    assert (direct.returncode == 0) == expected, (name, "unexpected direct login result")
                    rows.append({"case": name, "verifierAvailable": verifier, "directLogin": direct.returncode == 0})
            finally:
                if server is not None and server.poll() is None:
                    try:
                        run([str(pg / "pg_ctl"), "-D", str(data), "stop", "-m", "fast", "-w"], timeout=15)
                    finally:
                        if server.poll() is None:
                            server.terminate()
                        server.wait(timeout=10)
    print(json.dumps({"cases": rows, "temporaryServerStopped": True, "temporaryDirectoryRemoved": True}, indent=2))


if __name__ == "__main__":
    main()
