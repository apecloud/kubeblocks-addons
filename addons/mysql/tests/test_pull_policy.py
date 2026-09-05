"""Render regression: python3 addons/mysql/tests/test_pull_policy.py.

Requires Helm and PyYAML. Uses an isolated copy of the Chart and local kblib.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


class MySQLPullPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mysql-pull-policy-")
        cls.addClassCleanup(cls.temp.cleanup)
        work = Path(cls.temp.name)
        addons = Path(__file__).resolve().parents[2]
        for name in ("mysql", "kblib"):
            shutil.copytree(addons / name, work / name)
        cls.chart = work / "mysql"
        cls.env = dict(os.environ, HELM_CACHE_HOME=str(work / "cache"),
                       HELM_CONFIG_HOME=str(work / "config"),
                       HELM_DATA_HOME=str(work / "data"))
        subprocess.run(["helm", "dependency", "build", "--skip-refresh", str(cls.chart)],
                       env=cls.env, check=True, capture_output=True, text=True)

    def assert_policy(self, value, expected, extra=()):
        command = ["helm", "template", "mysql", str(self.chart), *extra]
        if value is not None:
            command.extend(["--set-string", "image.pullPolicy=" + value])
        rendered = subprocess.check_output(command, env=self.env, text=True)
        counts = {"mysql": 0, "init": 0, "exporter": 0}
        for document in yaml.safe_load_all(rendered):
            if not document or document.get("kind") != "ComponentDefinition":
                continue
            runtime = document["spec"]["runtime"]
            for group in ("containers", "initContainers"):
                for container in runtime.get(group, []):
                    name = container["name"]
                    with self.subTest(component=document["metadata"]["name"], container=name):
                        self.assertEqual(container.get("imagePullPolicy"), expected)
                    if group == "initContainers":
                        counts["init"] += 1
                    elif name == "mysql":
                        counts["mysql"] += 1
                    elif "exporter" in name:
                        counts["exporter"] += 1
        for group, count in counts.items():
            self.assertGreater(count, 0, "missing rendered " + group)

    def test_always(self):
        self.assert_policy("Always", "Always")

    def test_never(self):
        self.assert_policy("Never", "Never")

    def test_default(self):
        self.assert_policy(None, "IfNotPresent")

    def test_empty_uses_default(self):
        self.assert_policy("", "IfNotPresent")

    def test_arm64_custom_registry(self):
        self.assert_policy("Always", "Always", ("--set", "architecture=arm64,image.registry=registry.example.test"))


if __name__ == "__main__":
    unittest.main()
