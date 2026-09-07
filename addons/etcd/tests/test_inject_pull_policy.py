#!/usr/bin/env python3
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

"""Check the real chart's independent init and primary image pull policies."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


class InjectPullPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(os.environ.get("CHART_DIR", Path(__file__).resolve().parents[1]))
        cls.helm = os.environ.get("HELM_BIN", "helm")
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.chart = Path(cls.temp.name) / "etcd"
        shutil.copytree(source, cls.chart)
        shutil.copytree(source.parent / "kblib", Path(cls.temp.name) / "kblib")
        subprocess.run(
            [cls.helm, "dependency", "build", str(cls.chart)],
            check=True, capture_output=True, text=True,
        )

    def test_pull_policy(self):
        cases = [
            ("default", [], "IfNotPresent", "IfNotPresent"),
            ("explicit-default", ["--set-string", "images.pullPolicy=IfNotPresent"], "IfNotPresent", "IfNotPresent"),
            ("always", ["--set-string", "images.pullPolicy=Always"], "Always", "IfNotPresent"),
            ("never", ["--set-string", "images.pullPolicy=Never"], "Never", "IfNotPresent"),
            ("empty", ["--set-string", "images.pullPolicy="], "IfNotPresent", "IfNotPresent"),
            ("null", ["--set", "images.pullPolicy=null"], "IfNotPresent", "IfNotPresent"),
            ("primary-only", ["--set-string", "image.pullPolicy=Never"], "IfNotPresent", "Never"),
            ("independent", ["--set-string", "images.pullPolicy=Never,image.pullPolicy=Always"], "Never", "Always"),
        ]
        for mode, mode_args in [("install", []), ("upgrade", ["--is-upgrade"])]:
            for name, values, expected_init, expected_primary in cases:
                result = subprocess.run(
                    [self.helm, "template", "etcd-test", str(self.chart),
                     "--namespace", "default", *mode_args, *values],
                    check=True, capture_output=True, text=True,
                )
                if output := os.environ.get("RENDER_DIR"):
                    directory = Path(output)
                    directory.mkdir(parents=True, exist_ok=True)
                    (directory / f"{mode}-{name}.yaml").write_text(result.stdout)
                documents = [doc for doc in yaml.safe_load_all(result.stdout) if doc]
                definitions = [doc for doc in documents
                               if doc.get("kind") == "ComponentDefinition"
                               and doc.get("spec", {}).get("serviceKind") == "etcd"]
                self.assertEqual(len(definitions), 1)
                runtime = definitions[0]["spec"]["runtime"]
                for group, container_name, expected in [
                    ("initContainers", "inject-bash", expected_init),
                    ("containers", "etcd", expected_primary),
                ]:
                    with self.subTest(mode=mode, case=name, container=container_name):
                        containers = [c for c in runtime[group] if c["name"] == container_name]
                        self.assertEqual(len(containers), 1)
                        self.assertEqual(containers[0]["imagePullPolicy"], expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)
