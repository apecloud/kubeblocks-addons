#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
from pyhive import hive
import sasl
import socket
import os
import thrift_sasl
from thrift.transport.TSocket import TSocket


def create_hive_plain_transport(auth, host, port, username, password, timeout=60):
    socket = TSocket(host, port)
    socket.setTimeout(timeout * 1000)

    def sasl_factory():
        sasl_client = sasl.Client()
        sasl_client.setAttr('host', host)
        sasl_client.setAttr('username', username)
        sasl_client.setAttr('password', password)
        sasl_client.init()
        return sasl_client

    return thrift_sasl.TSaslClientTransport(sasl_factory, auth, socket)

def check_hive_health(
    host,
    port=10000,
    username='hive',
    password=None,
    auth='PLAIN',
    database='default',
    timeout=5
):
    conn = None
    try:
        print(f"Connecting to HiveServer2 at {host}:{port}, auth={auth}, user={username}...")
        conn = hive.Connection(thrift_transport=create_hive_plain_transport(
            auth=auth,
            host=host,
            port=port,
            username=username,
            password=password,
            timeout=timeout
        ), database=database)

        cursor = conn.cursor()
        cursor.execute("show databases")
        result = cursor.fetchone()
        if result and len(result) > 0:
            print("HiveServer2 is healthy.")
            return True
        else:
            return False
    except Exception as e:
        print(f"Error checking HiveServer2 health: {e}")
        return False
    finally:
        if conn:
            try:
                conn.close()
            except:
                pass

if __name__ == '__main__':
    port = int(os.getenv("THRIFT_PORT", "10000"))
    host = socket.gethostname()
    password = os.getenv("ADMIN_PASSWORD", "admin")
    username = os.getenv("ADMIN_USER", "admin")
    timeout = int(os.getenv("PROBE_TIMEOUT", "5"))
    success = check_hive_health(
        host=host,
        port=port,
        username=username,
        password=password,
        auth="PLAIN",
        timeout=timeout
    )

    sys.exit(0 if success else 1)