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
    statement = run(["ruby", "-ryaml", "-e", '''
      docs = YAML.load_stream(STDIN.read).compact
      definition = docs.find { |d| d["kind"] == "ComponentDefinition" && d.dig("metadata", "name").start_with?("postgresql-pooler-17-") }
      account = definition.dig("spec", "systemAccounts").find { |a| a["name"] == "pgbouncer" }
      puts account.dig("statement", "create")
    '''], input=rendered).stdout
    assert re.search(r"CREATE OR REPLACE FUNCTION public\.pgbouncer_auth", statement)
    password = secrets.token_hex(24)
    statement = statement.replace("${KB_ACCOUNT_NAME}", "lookup_probe")
    statement = statement.replace("${KB_ACCOUNT_PASSWORD}", password)
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
                sql(statement)
                cases = [("expired_probe", "LOGIN", "2000-01-01", False),
                         ("future_probe", "LOGIN", "2099-01-01", True),
                         ("unlimited_probe", "LOGIN", None, True),
                         ("nologin_probe", "NOLOGIN", None, False)]
                for name, login, until, expected in cases:
                    validity = f" VALID UNTIL '{until}'" if until else ""
                    sql(f"CREATE ROLE {name} {login} PASSWORD '{password}'{validity};")
                    query = (f"SELECT EXISTS (SELECT 1 FROM public.pgbouncer_auth('{name}') "
                             "WHERE password IS NOT NULL AND length(password)>0)")
                    # Execute as the restricted auth account, not as a superuser.
                    verifier = run([str(pg / "psql"), "-X", "-h", str(sock), "-U", "lookup_probe",
                                    "-d", "postgres", "-Atc", query],
                                   env=dict(os.environ, PGPASSWORD=password)).stdout.strip() == "t"
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
