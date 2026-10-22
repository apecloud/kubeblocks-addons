"""Regression tests for issue #3564; run with python3 -m unittest discover -s addons/mysql/tests."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'


class AliasTests(unittest.TestCase):
    def run_shell(self, script, body, mock, **env):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client = root / 'client'
            client.write_text('#!/bin/bash\n' + mock)
            client.chmod(0o755)
            source = (SCRIPTS / script).read_text()
            source = source.replace('/scripts/orchestrator-client', str(client))
            source = source.replace('/kubeblocks/orchestrator-client', str(client))
            path = root / 'script'
            path.write_text(source)
            return subprocess.run(['bash', '-c', 'sleep() { :; }; source "$1"; ' + body,
                                   'test', str(path)], text=True, capture_output=True,
                                  env={**os.environ, 'TEST_STATE': str(root / 'discovered'), 'CLUSTER_NAME': 'business',
                                       'POD_NAME': 'mysql-2', 'MYSQL_POD_FQDN_LIST': 'mysql-0,mysql-1,mysql-2',
                                       **env})

    def test_alias_lookup_does_not_repair_healthy_alias(self):
        result = self.run_shell('init-mysql-instance-for-orc.sh', 'find_cluster_master', '''
if [[ "$*" == '-c which-cluster-master -alias business' ]]; then echo mysql-1:3306; else exit 99; fi
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'mysql-1:3306')

    def test_missing_alias_uses_peer_and_repairs_without_reset(self):
        result = self.run_shell('init-mysql-instance-for-orc.sh', '''
mysql() { echo 'UNEXPECTED SQL' >&2; exit 99; }
find_cluster_master
''', '''
case "$*" in
  '-c which-cluster-master -alias business') echo 'invalid result'; exit 1;;
  '-c which-cluster-master -i mysql-0') echo mysql-1:3306;;
  '-c set-cluster-alias -i mysql-0 -alias business') echo REPAIRED;;
  *) exit 99;;
esac
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'mysql-1:3306')
        self.assertIn('REPAIRED', result.stderr)
        self.assertNotIn('UNEXPECTED SQL', result.stderr)

    def test_missing_peer_and_null_alias_are_not_primary(self):
        result = self.run_shell('init-mysql-instance-for-orc.sh', 'find_cluster_master', '''
if [[ "$*" == *'-alias business' ]]; then echo null; else exit 1; fi
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_peer_lookup_survives_alias_repair_failure(self):
        result = self.run_shell('init-mysql-instance-for-orc.sh', 'find_cluster_master', '''
case "$*" in
  '-c which-cluster-master -i mysql-1') echo mysql-1:3306;;
  *) exit 1;;
esac
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'mysql-1:3306')

    def test_switchover_persists_alias_after_takeover(self):
        result = self.run_shell('orc-switchover.sh', '', '''
case "$*" in
  '-c which-cluster-master -i mysql-0') echo mysql-0:3306;;
  '-c which-cluster-instances -i mysql-0') printf 'mysql-0:3306\\nmysql-1:3306\\n';;
  '-c graceful-master-takeover-auto -i mysql-0 -d mysql-1') echo TAKEN_OVER;;
  '-c set-cluster-alias -i mysql-0 -alias business') echo REPAIRED;;
  *) exit 99;;
esac
''', KB_SWITCHOVER_ROLE='primary', KB_SWITCHOVER_CURRENT_NAME='mysql-0',
            KB_SWITCHOVER_CANDIDATE_NAME='mysql-1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('REPAIRED', result.stdout)


    def test_switchover_retry_repairs_alias_without_another_takeover(self):
        result = self.run_shell('orc-switchover.sh', '', """
case "$*" in
  '-c which-cluster-master -i mysql-0') echo mysql-1:3306;;
  '-c set-cluster-alias -i mysql-0 -alias business') echo REPAIRED;;
  *) exit 99;;
esac
""", KB_SWITCHOVER_ROLE='primary', KB_SWITCHOVER_CURRENT_NAME='mysql-0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('REPAIRED', result.stdout)

    def test_switchover_reports_failed_alias_persistence(self):
        result = self.run_shell('orc-switchover.sh', '', """
case "$*" in
  '-c which-cluster-master -i mysql-0') echo mysql-1:3306;;
  *) exit 1;;
esac
""", KB_SWITCHOVER_ROLE='primary', KB_SWITCHOVER_CURRENT_NAME='mysql-0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('failed to persist the cluster alias', result.stderr)

    def test_bootstrap_rediscovers_forgotten_replica(self):
        result = self.run_shell('init-mysql-instance-for-orc.sh', """
mysql_note() { :; }
create_mysql_user() { :; }
change_master() { :; }
setup_master_slave
""", """
case "$*" in
  '-c which-cluster-master -alias business') echo mysql-1:3306;;
  '-c which-cluster -i mysql-2') [[ -f "$TEST_STATE" ]] && echo mysql-1:3306;;
  '-c discover -i mysql-2') touch "$TEST_STATE";;
  *) exit 99;;
esac
""")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_client_persists_current_cluster_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'gsed').symlink_to(shutil.which('sed'))
            curl = root / 'curl'
            curl.write_text("#!/bin/bash\n" + r"""
[[ "$*" == *--head* ]] && exit 0
case "${!#}" in
  */cluster-info/mysql-0) echo '{"ClusterName":"mysql-1:3306"}';;
  */set-cluster-alias/mysql-1%3A3306?alias=business%20name) echo '{"Code":"OK"}';;
  *) echo '{"Code":"ERROR","Message":"unexpected URL"}';;
esac
""")
            curl.chmod(0o755)
            result = subprocess.run(['bash', str(SCRIPTS / 'orchestrator-client.sh'),
                                     '-c', 'set-cluster-alias', '-i', 'mysql-0',
                                     '-alias', 'business name'], text=True, capture_output=True,
                                    env={**os.environ, 'PATH': str(root) + ':' + os.environ['PATH'],
                                         'ORCHESTRATOR_API': 'http://test/api'})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['Code'], 'OK')


if __name__ == '__main__':
    unittest.main()
