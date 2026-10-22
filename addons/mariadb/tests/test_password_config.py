"""Check real install/upgrade manifests against the target KubeBlocks CRD."""
import argparse
import copy
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from jsonschema import Draft7Validator
import yaml


def render(chart, upgrade):
    command = ["helm", "template", "mariadb", str(chart), "--namespace", "kb-system"]
    if upgrade:
        command.append("--is-upgrade")
    return subprocess.check_output(command, text=True)


def account(name, length, digits, symbols):
    return {"name": name, "initAccount": True, "passwordConfig": {
        "length": length, "numDigits": digits, "numSymbols": symbols,
        "letterCase": "MixedCases"}}


class PasswordConfiguration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        crd = yaml.safe_load(OPTIONS.crd.read_text())
        version = next(v for v in crd["spec"]["versions"] if v["name"] == "v1")
        cls.schema = copy.deepcopy(version["schema"]["openAPIV3Schema"]
                                   ["properties"]["spec"]["properties"]
                                   ["systemAccounts"]["items"])
        # Kubernetes prunes unknown keys even when JSON Schema permits them.
        cls.schema["additionalProperties"] = False
        cls.schema["properties"]["passwordConfig"]["additionalProperties"] = False
        cls.validator = Draft7Validator(cls.schema)
        version = yaml.safe_load((OPTIONS.chart / "Chart.yaml").read_text())["version"]
        cls.expected = {
            "mariadb-" + version: [account("root", 10, 3, 4),
                                   account("kb_internal_root", 32, 8, 0)],
            "mariadb-replication-merged-" + version: [account("root", 10, 3, 4),
                account("kb_internal_root", 32, 8, 0), account("kb_replicator", 32, 8, 0)],
            "mariadb-galera-" + version: [account("root", 10, 3, 0)],
        }
        cls.components = {}
        with tempfile.TemporaryDirectory(prefix="mariadb-password-") as directory:
            root = Path(directory)
            chart = root / "mariadb"
            shutil.copytree(OPTIONS.chart, chart)
            shutil.copytree(OPTIONS.chart.parent / "kblib", root / "kblib")
            subprocess.run(["helm", "dependency", "build", str(chart)], check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            for upgrade in (False, True):
                mode = "upgrade" if upgrade else "install"
                manifest = render(chart, upgrade)
                if OPTIONS.render_output:
                    OPTIONS.render_output.mkdir(parents=True, exist_ok=True)
                    (OPTIONS.render_output / (mode + ".yaml")).write_text(manifest)
                cls.components[mode] = {d["metadata"]["name"]: d["spec"]
                    for d in yaml.safe_load_all(manifest)
                    if d and d.get("kind") == "ComponentDefinition"}

    def test_all_six_account_settings_are_preserved(self):
        for mode, definitions in self.components.items():
            self.assertEqual(set(definitions), set(self.expected))
            for name, expected in self.expected.items():
                with self.subTest(mode=mode, component=name):
                    self.assertEqual(definitions[name]["systemAccounts"], expected)

    def test_accounts_survive_target_crd_validation_without_pruning(self):
        for mode, definitions in self.components.items():
            for name, spec in definitions.items():
                for value in spec["systemAccounts"]:
                    with self.subTest(mode=mode, component=name, account=value["name"]):
                        self.assertEqual([e.message for e in self.validator.iter_errors(value)], [])

    def test_root_password_still_uses_the_required_managed_credential(self):
        expected = {"name": "MARIADB_ROOT_PASSWORD", "valueFrom": {
            "credentialVarRef": {"name": "root", "optional": False, "password": "Required"}}}
        for mode, definitions in self.components.items():
            for name, spec in definitions.items():
                with self.subTest(mode=mode, component=name):
                    self.assertEqual([v for v in spec["vars"]
                                      if v["name"] == "MARIADB_ROOT_PASSWORD"], [expected])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--crd", type=Path, required=True,
                        help="ComponentDefinition CRD from the exact target KubeBlocks revision")
    parser.add_argument("--chart", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--render-output", type=Path, help="Optional directory for full manifests")
    OPTIONS = parser.parse_args()
    unittest.main(argv=[__file__], verbosity=2)
