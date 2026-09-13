"""Offline Helm regressions. Requires helm and PyYAML; no Kubernetes access."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


class ImagePullPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(os.environ.get("VALKEY_CHART", Path(__file__).resolve().parents[1]))
        scratch = tempfile.TemporaryDirectory(prefix="valkey-policy-")
        cls.addClassCleanup(scratch.cleanup)
        cls.chart = Path(scratch.name) / "valkey"
        shutil.copytree(source, cls.chart)
        shutil.copytree(source.parent / "kblib", cls.chart.parent / "kblib")
        subprocess.run(["helm", "dependency", "build", "--skip-refresh", str(cls.chart)],
                       check=True, capture_output=True, text=True)

    def render(self, *settings):
        command = ["helm", "template", "valkey", str(self.chart), "--namespace", "kb-system"]
        for setting in settings:
            command.extend(["--set", setting])
        result = subprocess.run(command, check=True, capture_output=True, text=True)
        return [doc for doc in yaml.safe_load_all(result.stdout)
                if doc and doc.get("kind") == "ComponentDefinition"]

    def assert_policies(self, documents, engine, metrics, metrics_enabled=True):
        self.assertEqual(len(documents), 4, "both Valkey majors and both Sentinel majors")
        seen = []
        for doc in documents:
            for container in doc["spec"]["runtime"]["containers"]:
                name = container["name"]
                self.assertIn(name, ("valkey", "valkey-sentinel", "metrics"))
                expected = metrics if name == "metrics" else engine
                self.assertEqual(container["imagePullPolicy"], expected,
                                 f'{doc["metadata"]["name"]}/{name}')
                seen.append(name)
        self.assertEqual(seen.count("valkey"), 2)
        self.assertEqual(seen.count("valkey-sentinel"), 2)
        self.assertEqual(seen.count("metrics"), 2 if metrics_enabled else 0)

    def test_default_remains_if_not_present(self):
        self.assert_policies(self.render(), "IfNotPresent", "IfNotPresent")

    def test_all_supported_kubernetes_policies(self):
        for policy in ("Always", "IfNotPresent", "Never"):
            with self.subTest(policy=policy):
                self.assert_policies(self.render(f"image.pullPolicy={policy}",
                                                 f"metrics.image.pullPolicy={policy}"),
                                     policy, policy)

    def test_engine_override_does_not_change_metrics(self):
        self.assert_policies(self.render("image.pullPolicy=Always"), "Always", "IfNotPresent")

    def test_metrics_override_does_not_change_engine(self):
        self.assert_policies(self.render("metrics.image.pullPolicy=Always"), "IfNotPresent", "Always")

    def test_metrics_disabled_preserves_engine_policy(self):
        self.assert_policies(self.render("metrics.enabled=false", "image.pullPolicy=Always"),
                             "Always", None, metrics_enabled=False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
