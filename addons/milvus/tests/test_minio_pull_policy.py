#!/usr/bin/env python3
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

"""Render the real chart and check both MinIO containers' pull policies."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


class MinioPullPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(os.environ.get("CHART_DIR", Path(__file__).resolve().parents[1]))
        cls.helm = os.environ.get("HELM_BIN", "helm")
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.chart = Path(cls.temp.name) / "milvus"
        shutil.copytree(source, cls.chart)
        shutil.copytree(source.parent / "kblib", Path(cls.temp.name) / "kblib")
        subprocess.run(
            [cls.helm, "dependency", "build", str(cls.chart)],
            check=True, capture_output=True, text=True,
        )

    def test_minio_password_generation(self):
        for mode, flags in [("install", []), ("upgrade", ["--is-upgrade"])]:
            with self.subTest(mode=mode):
                result = subprocess.run(
                    [self.helm, "template", "milvus-test", str(self.chart),
                     "--namespace", "default", *flags],
                    check=True, capture_output=True, text=True,
                )
                documents = [doc for doc in yaml.safe_load_all(result.stdout) if doc]
                definition, = [doc for doc in documents
                               if doc.get("kind") == "ComponentDefinition"
                               and doc.get("spec", {}).get("serviceKind") == "milvus-minio"]
                account, = definition["spec"]["systemAccounts"]
                self.assertEqual(account["name"], "admin")
                self.assertIs(account["initAccount"], True)
                self.assertIn("passwordConfig", account)
                self.assertEqual(account["passwordConfig"], {})
                password, = [var for var in definition["spec"]["vars"]
                             if var["name"] == "MINIO_SECRET_KEY"]
                self.assertEqual(password["valueFrom"]["credentialVarRef"], {
                    "name": "admin", "optional": False, "password": "Required",
                })

    def test_pull_policy(self):
        cases = [
            ("default", [], "IfNotPresent"),
            ("explicit-default", ["--set-string", "images.pullPolicy=IfNotPresent"], "IfNotPresent"),
            ("always", ["--set-string", "images.pullPolicy=Always"], "Always"),
            ("never", ["--set-string", "images.pullPolicy=Never"], "Never"),
            ("empty", ["--set-string", "images.pullPolicy="], "IfNotPresent"),
            ("null", ["--set", "images.pullPolicy=null"], "IfNotPresent"),
        ]
        for mode, mode_args in [("install", []), ("upgrade", ["--is-upgrade"])]:
            for name, values, expected in cases:
                result = subprocess.run(
                    [self.helm, "template", "milvus-test", str(self.chart),
                     "--namespace", "default", *mode_args, *values],
                    check=True, capture_output=True, text=True,
                )
                if output := os.environ.get("RENDER_DIR"):
                    directory = Path(output)
                    directory.mkdir(parents=True, exist_ok=True)
                    (directory / f"{mode}-{name}.yaml").write_text(result.stdout)
                documents = [doc for doc in yaml.safe_load_all(result.stdout) if doc]
                minio = [doc for doc in documents
                         if doc.get("kind") == "ComponentDefinition"
                         and doc.get("spec", {}).get("serviceKind") == "milvus-minio"]
                self.assertEqual(len(minio), 1, "expected exactly one MinIO ComponentDefinition")
                runtime = minio[0]["spec"]["runtime"]
                for group, container_name in [
                    ("initContainers", "volume-permissions"), ("containers", "minio")
                ]:
                    with self.subTest(mode=mode, case=name, container=container_name):
                        containers = [c for c in runtime[group] if c["name"] == container_name]
                        self.assertEqual(len(containers), 1)
                        self.assertEqual(containers[0]["imagePullPolicy"], expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)
