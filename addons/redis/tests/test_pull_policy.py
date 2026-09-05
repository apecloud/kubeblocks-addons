"""Render regression: python3 addons/redis/tests/test_pull_policy.py.

Requires Helm and PyYAML. Uses an isolated copy of the Chart and local kblib.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


OFFICIAL_REGISTRY = "apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com"


class RedisPullPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="redis-pull-policy-")
        cls.addClassCleanup(cls.temp.cleanup)
        work = Path(cls.temp.name)
        addons = Path(__file__).resolve().parents[2]
        for name in ("redis", "kblib"):
            shutil.copytree(addons / name, work / name)
        cls.chart = work / "redis"
        cls.env = dict(
            os.environ,
            HELM_CACHE_HOME=str(work / "cache"),
            HELM_CONFIG_HOME=str(work / "config"),
            HELM_DATA_HOME=str(work / "data"),
        )
        subprocess.run(
            ["helm", "dependency", "build", "--skip-refresh", str(cls.chart)],
            env=cls.env,
            check=True,
            capture_output=True,
            text=True,
        )

    def render(self, extra=()):
        command = ["helm", "template", "redis", str(self.chart), *extra]
        return subprocess.check_output(command, env=self.env, text=True)

    def assert_policy(self, value, expected, extra=()):
        command = list(extra)
        if value is not None:
            command.extend(["--set-string", "image.pullPolicy=" + value])
        rendered = self.render(command)
        counts = {"redis": 0, "sentinel": 0, "twemproxy": 0, "init": 0, "metrics": 0}
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
                    elif name in {"redis", "redis-cluster"}:
                        counts["redis"] += 1
                    elif name == "redis-sentinel":
                        counts["sentinel"] += 1
                    elif name == "redis-twemproxy":
                        counts["twemproxy"] += 1
                    elif name == "metrics":
                        counts["metrics"] += 1
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

    def test_official_registry_rewrites_repositories(self):
        rendered = self.render(
            (
                "--set-string",
                "image.pullPolicy=Always",
                "--set",
                "image.registry=" + OFFICIAL_REGISTRY,
            )
        )
        self.assertIn(OFFICIAL_REGISTRY + "/apecloud/redis:7.2.16", rendered)
        self.assertIn(OFFICIAL_REGISTRY + "/apecloud/redis-stack-server:7.2.0-v19", rendered)
        self.assertIn(OFFICIAL_REGISTRY + "/apecloud/redis_exporter:v1.80.1", rendered)
        self.assertIn(OFFICIAL_REGISTRY + "/apecloud/twemproxy:0.5.0", rendered)
        self.assertIn(OFFICIAL_REGISTRY + "/apecloud/busybox:1.36", rendered)
        self.assertNotIn(OFFICIAL_REGISTRY + "/redis:", rendered)
        self.assertNotIn(OFFICIAL_REGISTRY + "/redis/redis-stack-server:", rendered)
        self.assertNotIn(OFFICIAL_REGISTRY + "/malexer/twemproxy:", rendered)
        self.assertNotIn(OFFICIAL_REGISTRY + "/oliver006/redis_exporter:", rendered)

    def test_docker_io_keeps_public_repositories(self):
        rendered = self.render()
        self.assertIn("docker.io/redis:7.2.16", rendered)
        self.assertIn("docker.io/redis/redis-stack-server:7.2.0-v19", rendered)
        self.assertIn("docker.io/malexer/twemproxy:0.5.0", rendered)
        self.assertIn("docker.io/oliver006/redis_exporter:v1.80.1", rendered)


if __name__ == "__main__":
    unittest.main()
