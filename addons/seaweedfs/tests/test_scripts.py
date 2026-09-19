"""Offline process-contract tests: no database or Kubernetes is started."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


class ScriptsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.stub("weed", '#!/bin/sh\nprintf "%s\\n" "$@"\n')
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        SEAWEEDFS_DATA_DIR=str(self.root / "data"),
                        POD_NAME="demo-master-7", SEAWEEDFS_MASTER_REPLICAS="3",
                        SEAWEEDFS_POD_FQDNS="demo-master-2.m.ns.svc.corp,demo-master-7.m.ns.svc.corp,demo-master-11.m.ns.svc.corp",
                        SEAWEEDFS_MASTER_FQDNS="demo-master-2.m.ns.svc.corp,demo-master-7.m.ns.svc.corp,demo-master-11.m.ns.svc.corp",
                        SEAWEEDFS_REPLICATION="001", SEAWEEDFS_VOLUME_SIZE_MB="1024",
                        SEAWEEDFS_FILER_HOST="demo-filer.ns.svc", SEAWEEDFS_FILER_PORT="8888")
        self.env.pop("AWS_ACCESS_KEY_ID", None)
        self.env.pop("AWS_SECRET_ACCESS_KEY", None)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)

    def run_script(self, name, **overrides):
        env = self.env | overrides
        return subprocess.run(["/bin/sh", str(SCRIPTS / name)], env=env,
                              capture_output=True, text=True, timeout=5)

    def test_master_uses_actual_fqdns_and_preserves_data(self):
        data = Path(self.env["SEAWEEDFS_DATA_DIR"])
        data.mkdir()
        marker = data / "raft-state"
        marker.write_text("existing state")
        for _ in range(2):
            result = self.run_script("start-master.sh")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("-ip=demo-master-7.m.ns.svc.corp\n", result.stdout)
            self.assertIn("-peers=demo-master-2.m.ns.svc.corp:9333,demo-master-7.m.ns.svc.corp:9333,demo-master-11.m.ns.svc.corp:9333\n", result.stdout)
            self.assertEqual(marker.read_text(), "existing state")

    def test_single_master_explicitly_disables_peer_discovery(self):
        result = self.run_script("start-master.sh", SEAWEEDFS_MASTER_REPLICAS="1",
                                 SEAWEEDFS_POD_FQDNS="demo-master-7.m.ns.svc.corp")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-peers=none\n", result.stdout)

    def test_master_rejects_wrong_membership_and_identity(self):
        for changes in [dict(SEAWEEDFS_MASTER_REPLICAS="2"), dict(POD_NAME="missing-0"),
                        dict(SEAWEEDFS_POD_FQDNS=""),
                        dict(SEAWEEDFS_POD_FQDNS="a.m,b.m,"),
                        dict(SEAWEEDFS_POD_FQDNS="demo-master-7.m,demo-master-7.m,demo-master-11.m")]:
            with self.subTest(changes=changes):
                result = self.run_script("start-master.sh", **changes)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_volume_registers_with_all_masters(self):
        result = self.run_script("start-volume.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-master=demo-master-2.m.ns.svc.corp:9333,demo-master-7.m.ns.svc.corp:9333,demo-master-11.m.ns.svc.corp:9333\n", result.stdout)
        self.assertIn("-max=0\n", result.stdout)

    def test_missing_master_list_stops_volume_and_filer(self):
        for name in ["start-volume.sh", "start-filer.sh"]:
            result = self.run_script(name, SEAWEEDFS_MASTER_FQDNS="")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")

    def test_filer_uses_persistent_store(self):
        result = self.run_script("start-filer.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"-defaultStoreDir={self.env['SEAWEEDFS_DATA_DIR']}\n", result.stdout)

    def test_s3_fails_closed_without_both_credentials(self):
        for changes in [{}, {"AWS_ACCESS_KEY_ID": "fixture-user"}, {"AWS_SECRET_ACCESS_KEY": "fixture-secret"}]:
            result = self.run_script("start-s3.sh", **changes)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertNotIn("fixture-secret", result.stderr)

    def test_s3_keeps_secrets_out_of_command_and_output(self):
        result = self.run_script("start-s3.sh", AWS_ACCESS_KEY_ID="fixture-user",
                                 AWS_SECRET_ACCESS_KEY='fixture-$-"-secret')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-filer=demo-filer.ns.svc:8888\n", result.stdout)
        self.assertIn("-port.iceberg=0\n", result.stdout)
        self.assertIn("-port.lance=0\n", result.stdout)
        self.assertNotIn("fixture", result.stdout + result.stderr)

    def test_volume_leave_is_always_rejected(self):
        result = self.run_script("member-leave-volume.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("migrate", result.stderr)

    def test_master_role_handles_omitted_false_field(self):
        samples = [('{"IsLeader":true,"Leader":"host:9333","Peers":["peer:9333"]}', "leader"),
                   ('{ "Leader": "host:9333", "MaxVolumeId": 8 }', "follower"),
                   ('{"IsLeader":false,"Leader":"host:9333"}', "follower"),
                   ('{"IsLeader":true}', "unknown"), ('{}', "unknown"),
                   ('garbage', "unknown"), ('{"Leader":""}', "unknown"),
                   ('{"IsLeader":"true","Leader":"host:9333"}', "unknown")]
        self.stub("curl", '#!/bin/sh\nprintf "%s" "$PROBE_RESPONSE"\nexit "${PROBE_EXIT:-0}"\n')
        for response, role in samples:
            with self.subTest(response=response):
                result = self.run_script("role-probe-master.sh", PROBE_RESPONSE=response)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), role)
        result = self.run_script("role-probe-master.sh", PROBE_RESPONSE=samples[0][0], PROBE_EXIT="28")
        self.assertEqual(result.stdout.strip(), "unknown")

    def test_master_role_accepts_optional_grpc_port(self):
        # SeaweedFS 4.47 serializes ServerAddress as host:httpPort[.grpcPort].
        self.stub("curl", '#!/bin/sh\nprintf "%s" "$PROBE_RESPONSE"\n')
        for address in ["master-0.m.ns.svc.corp:9333",
                        "master-0.m.ns.svc.corp:9333.19333",
                        "10.0.0.7:9333.19333", "master-0:9333.29333"]:
            for is_leader, role in [(True, "leader"), (False, "follower"),
                                    (None, "follower")]:
                with self.subTest(address=address, is_leader=is_leader):
                    body = {"Leader": address, "Peers": ["master-1:9333.19333"]}
                    if is_leader is not None:
                        body["IsLeader"] = is_leader
                    result = self.run_script("role-probe-master.sh",
                                             PROBE_RESPONSE=json.dumps(body))
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, role + "\n")

    def test_master_role_rejects_invalid_leader_addresses(self):
        self.stub("curl", '#!/bin/sh\nprintf "%s" "$PROBE_RESPONSE"\n')
        for address in ["", ":9333", ":9333.19333", "master-0:19333",
                        "master-0:9333.", "master-0:9333.grpc",
                        "master-0:9333.19333extra", "master-0:9333.19333.1"]:
            with self.subTest(address=address):
                body = {"IsLeader": True, "Leader": address}
                result = self.run_script("role-probe-master.sh",
                                         PROBE_RESPONSE=json.dumps(body))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "unknown\n")


if __name__ == "__main__":
    unittest.main()
