"""Offline render/reference tests. Set KB_CRD_DIR to a release-1.0 CRD directory.

Requires Helm, PyYAML and jsonschema; never contacts a Kubernetes API.
"""
import copy
import os
from pathlib import Path
import re
import subprocess
import unittest

import yaml
from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[3]
ADDON = ROOT / "addons/seaweedfs"
CLUSTER = ROOT / "addons-cluster/seaweedfs"


def render(chart, *args, release="seaweedfs", namespace="demo"):
    result = subprocess.run(["helm", "template", release, str(chart), "-n", namespace, *args],
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise AssertionError(result.stderr)
    return [doc for doc in yaml.safe_load_all(result.stdout) if doc]


def strict_schema(source):
    """Reject undeclared fields, preserving Kubernetes open maps/IntOrString."""
    schema = copy.deepcopy(source)
    def visit(node):
        if isinstance(node, dict):
            if node.get("x-kubernetes-int-or-string"):
                node.pop("type", None)
                node["anyOf"] = [{"type": "integer"}, {"type": "string"}]
            if node.get("type") == "object" and "properties" in node and "additionalProperties" not in node:
                if not node.get("x-kubernetes-preserve-unknown-fields"):
                    node["additionalProperties"] = False
            for value in node.values():
                visit(value)
        elif isinstance(node, list):
            for value in node:
                visit(value)
    visit(schema)
    return schema


class ChartsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.documents = render(ADDON)
        cls.cmpds = {d["metadata"]["name"]: d for d in cls.documents if d["kind"] == "ComponentDefinition"}
        cls.maps = {d["metadata"]["name"]: d for d in cls.documents if d["kind"] == "ConfigMap"}
        cls.cmpvs = [d for d in cls.documents if d["kind"] == "ComponentVersion"]
        cls.definition = next(d for d in cls.documents if d["kind"] == "ClusterDefinition")
        cls.clusters = [render(CLUSTER, "--set", f"topology={t}")[0] for t in ["standalone", "distributed"]]
        cls.examples = [yaml.safe_load(p.read_text()) for p in (ROOT / "examples/seaweedfs").glob("*.yaml")]

    def test_topology_names_replica_limits_and_storage_close(self):
        topologies = {t["name"]: t for t in self.definition["spec"]["topologies"]}
        self.assertEqual(sum(bool(t.get("default")) for t in topologies.values()), 1)
        for cluster in self.clusters + [x for x in self.examples if x["kind"] == "Cluster"]:
            topology = topologies[cluster["spec"]["topology"]]
            mapping = {c["name"]: c["compDef"] for c in topology["components"]}
            components = cluster["spec"]["componentSpecs"]
            self.assertEqual(set(mapping), {c["name"] for c in components})
            for component in components:
                self.assertNotIn("componentDef", component)
                spec = self.cmpds[mapping[component["name"]]]["spec"]
                limits = spec["replicasLimit"]
                self.assertLessEqual(limits["minReplicas"], component["replicas"])
                self.assertGreaterEqual(limits["maxReplicas"], component["replicas"])
                pvc_names = {v["name"] for v in component.get("volumeClaimTemplates", [])}
                self.assertEqual(pvc_names, {v["name"] for v in spec.get("volumes", [])})
                if component["name"] in {"filer", "admin"}:
                    self.assertEqual(limits, {"minReplicas": 1, "maxReplicas": 1})

    def test_scripts_mounts_credentials_and_service_ports_close(self):
        for definition in self.cmpds.values():
            spec = definition["spec"]
            volumes = {v["name"] for v in spec.get("volumes", [])}
            volumes |= {v["name"] for v in spec["runtime"].get("volumes", [])}
            mounted = {}
            for group in ["scripts", "configs"]:
                for item in spec.get(group, []):
                    volumes.add(item["volumeName"])
                    self.assertIn(item["template"], self.maps)
                    mounted[item["volumeName"]] = self.maps[item["template"]]["data"]
                    self.assertEqual(item["namespace"], "demo")
            container_ports = set()
            containers = {c["name"]: c for c in spec["runtime"]["containers"]}
            for container in containers.values():
                self.assertTrue({m["name"] for m in container.get("volumeMounts", [])} <= volumes)
                container_ports |= {p["name"] for p in container.get("ports", [])}
                self.assertIn(Path(container["command"][-1]).name, mounted["scripts"])
            for action in spec.get("lifecycleActions", {}).values():
                if "exec" in action:
                    self.assertIn(action["exec"]["container"], containers)
                    self.assertIn(Path(action["exec"]["command"][-1]).name, mounted["scripts"])
                    self.assertTrue(action["exec"]["image"].endswith(":4.47"))
            for service in spec["services"]:
                self.assertTrue({p["targetPort"] for p in service["spec"]["ports"]} <= container_ports)
            accounts = {a["name"] for a in spec.get("systemAccounts", [])}
            for var in spec.get("vars", []):
                self.assertFalse(var["name"].startswith("KB_"))
                ref = var.get("valueFrom", {}).get("credentialVarRef")
                if ref:
                    if "compDef" in ref:
                        target = next(d for d in self.cmpds.values()
                                      if re.search(ref["compDef"], d["metadata"]["name"]))
                        accounts = {a["name"] for a in target["spec"].get("systemAccounts", [])}
                    self.assertIn(ref["name"], accounts)
                    for cm in self.maps.values():
                        self.assertNotIn("fixture-secret", str(cm))

    def test_native_metrics_contract_for_all_components(self):
        self.assertEqual(len(self.cmpds), 7)
        for definition in self.cmpds.values():
            spec = definition["spec"]
            if "exporter" not in spec:
                continue
            exporter = spec["exporter"]
            # DisableExporter removes exporter.containerName: native exporters must
            # leave it unset so disabling monitoring never removes the engine.
            self.assertNotIn("containerName", exporter)
            container = spec["runtime"]["containers"][0]
            port = next(p for p in container["ports"] if p["name"] == exporter["scrapePort"])
            self.assertEqual(exporter["scrapePath"], "/metrics")
            self.assertEqual(port["containerPort"], 9327)
            script = next(s for s in spec["scripts"] if s["name"] == "scripts")
            command = self.maps[script["template"]]["data"][Path(container["command"][-1]).name]
            self.assertIn("-metricsPort=9327", command)
            # Metrics use Pod endpoints, not public client Service ports.
            for service in spec["services"]:
                self.assertNotIn(exporter["scrapePort"],
                                 {p["targetPort"] for p in service["spec"]["ports"]})

    def test_admin_reuses_s3_account_and_persists_singleton_state(self):
        admin = next(d["spec"] for d in self.cmpds.values()
                     if d["metadata"]["name"].startswith("seaweedfs-admin-"))
        self.assertNotIn("systemAccounts", admin)
        credentials = {v["name"]: v["valueFrom"]["credentialVarRef"]
                       for v in admin["vars"] if "credentialVarRef" in v["valueFrom"]}
        self.assertEqual(set(credentials), {"WEED_ADMIN_USER", "WEED_ADMIN_PASSWORD"})
        for ref in credentials.values():
            self.assertEqual(ref["compDef"], "^seaweedfs-s3-")
            self.assertEqual(ref["name"], "admin")
            self.assertFalse(ref["optional"])
        self.assertEqual(admin["services"][0]["spec"]["ports"],
                         [{"name": "console", "port": 23646, "targetPort": "console"}])
        self.assertIn({"name": "data", "mountPath": "/data"},
                      admin["runtime"]["containers"][0]["volumeMounts"])
        for topology in self.definition["spec"]["topologies"]:
            self.assertLess(topology["orders"]["provision"].index("s3"),
                            topology["orders"]["provision"].index("admin"))

    def test_filer_static_config_uses_component_template(self):
        filer = next(d for d in self.cmpds.values() if d["metadata"]["name"].startswith("seaweedfs-filer-"))
        config = next(item for item in filer["spec"]["configs"] if item["name"] == "filer-config")
        self.assertNotIn("externalManaged", config)
        self.assertIn("filer.toml", self.maps[config["template"]]["data"])

    def test_cross_component_refs_resolve_once_in_each_topology(self):
        for topology in self.definition["spec"]["topologies"]:
            definitions = [self.cmpds[c["compDef"]] for c in topology["components"]]
            for definition in definitions:
                for var in definition["spec"]["vars"]:
                    for kind, ref in var.get("valueFrom", {}).items():
                        if "compDef" in ref:
                            targets = [d for d in definitions if re.search(ref["compDef"], d["metadata"]["name"])]
                            self.assertEqual(len(targets), 1, var)
                            if kind == "serviceVarRef":
                                service = next(s for s in targets[0]["spec"]["services"] if s["name"] == ref["name"])
                                if "port" in ref:
                                    self.assertIn(ref["port"]["name"], {p["name"] for p in service["spec"]["ports"]})

    def test_every_version_maps_runtime_and_action_images(self):
        covered = set()
        for version in self.cmpvs:
            releases = {r["name"]: r for r in version["spec"]["releases"]}
            for rule in version["spec"]["compatibilityRules"]:
                for name in rule["compDefs"]:
                    covered.add(name)
                    spec = self.cmpds[name]["spec"]
                    needed = {c["name"] for c in spec["runtime"]["containers"]}
                    needed |= {key for key, action in spec.get("lifecycleActions", {}).items() if "exec" in action}
                    for release in rule["releases"]:
                        self.assertEqual(set(releases[release]["images"]), needed)
                        self.assertEqual(releases[release]["serviceVersion"], "4.47.0")
        self.assertEqual(covered, set(self.cmpds))

    def test_definition_names_are_independent_of_install_namespace(self):
        other = render(ADDON, release="different", namespace="other-ns")
        self.assertEqual({(d["kind"], d["metadata"]["name"]) for d in self.documents},
                         {(d["kind"], d["metadata"]["name"]) for d in other})
        for d in other:
            if d["kind"] == "ComponentDefinition":
                for item in d["spec"]["scripts"] + d["spec"].get("configs", []):
                    self.assertEqual(item["namespace"], "other-ns")

    def test_master_rollout_keeps_the_leader_until_last(self):
        for definition in self.cmpds.values():
            spec = definition["spec"]
            if not spec.get("roles"):
                continue
            roles = {r["name"]: r for r in spec["roles"]}
            self.assertLess(roles["follower"]["updatePriority"], roles["leader"]["updatePriority"])
            self.assertEqual(spec["podManagementPolicy"], "Parallel")
            self.assertEqual(spec["updateStrategy"], "Serial")

    def test_registry_override_reaches_all_execution_images(self):
        docs = render(ADDON, "--set", "image.registry=registry.example.org", "--set", "image.repository=mirror/seaweedfs")
        expected = "registry.example.org/mirror/seaweedfs:4.47"
        for d in docs:
            if d["kind"] == "ComponentDefinition":
                for c in d["spec"]["runtime"]["containers"]:
                    self.assertEqual(c["image"], expected)
                for action in d["spec"].get("lifecycleActions", {}).values():
                    self.assertEqual(action["exec"]["image"], expected)
            if d["kind"] == "ComponentVersion":
                for release in d["spec"]["releases"]:
                    self.assertEqual(set(release["images"].values()), {expected})

    def test_unsafe_or_unimplemented_values_are_rejected(self):
        for chart, value in [(CLUSTER, "topology=ha"), (CLUSTER, "volume.replicas=1"),
                             (CLUSTER, "s3.replicas=0"), (CLUSTER, "s3.replicas=33"),
                             (ADDON, "serviceVersion=4.46.0"), (ADDON, "image.tag=latest"),
                             (ADDON, "volumeSizeLimitMB=0")]:
            with self.subTest(value=value), self.assertRaises(AssertionError):
                render(chart, "--set", value)

    def test_rendered_kubeblocks_resources_match_release_10_crds(self):
        location = os.environ.get("KB_CRD_DIR")
        self.assertTrue(location, "Set KB_CRD_DIR to kubeblocks/config/crd/bases on release-1.0")
        schemas = {}
        for filename in ["apps.kubeblocks.io_clusters.yaml", "apps.kubeblocks.io_clusterdefinitions.yaml",
                         "apps.kubeblocks.io_componentdefinitions.yaml", "apps.kubeblocks.io_componentversions.yaml",
                         "operations.kubeblocks.io_opsrequests.yaml"]:
            path = Path(location) / filename
            doc = yaml.load(path.read_text(), Loader=yaml.CSafeLoader)
            if not doc or doc.get("kind") != "CustomResourceDefinition":
                continue
            for version in doc["spec"]["versions"]:
                key = (doc["spec"]["group"] + "/" + version["name"], doc["spec"]["names"]["kind"])
                schemas[key] = strict_schema(version["schema"]["openAPIV3Schema"])
        for obj in self.documents + self.clusters + self.examples:
            if obj["apiVersion"] == "v1":
                continue
            schema = schemas[(obj["apiVersion"], obj["kind"])]
            # ObjectMeta is provided by Kubernetes rather than expanded in CRDs.
            if "metadata" in schema.get("properties", {}):
                schema["properties"]["metadata"] = {"type": "object"}
            errors = list(Draft7Validator(schema).iter_errors(obj))
            self.assertFalse(errors, f"{obj['kind']}/{obj['metadata']['name']}: " + "; ".join(
                f"{list(e.path)}: {e.message}" for e in errors))


if __name__ == "__main__":
    unittest.main()
