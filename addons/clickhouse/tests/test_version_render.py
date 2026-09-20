#!/usr/bin/env python3
"""Run with python3; requires Helm and PyYAML, with no live cluster access."""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import yaml


def helm(*args):
    return subprocess.run(
        ["helm", *map(str, args)], check=True, capture_output=True, text=True
    ).stdout


def render(chart, *args):
    return [doc for doc in yaml.safe_load_all(helm("template", "test", chart, *args)) if doc]


def main():
    source = Path(__file__).resolve().parents[3]
    with tempfile.TemporaryDirectory(prefix="clickhouse-render-") as directory:
        root = Path(directory)
        for group in ("addons", "addons-cluster"):
            for chart in ("clickhouse", "kblib"):
                shutil.copytree(source / group / chart, root / group / chart)
            helm("dependency", "build", "--skip-refresh", root / group / "clickhouse")
            helm("lint", root / group / "clickhouse")

        addon = root / "addons/clickhouse"
        cluster_chart = root / "addons-cluster/clickhouse"
        assert yaml.safe_load((addon / "Chart.yaml").read_text())["appVersion"] == "25.9.7"
        for registry in ("docker.io", "registry.example.test"):
            resources = render(addon, "--set-string", f"image.registry={registry}")
            cv = next(doc["spec"] for doc in resources if doc["kind"] == "ComponentVersion")
            releases = {release["name"]: release for release in cv["releases"]}
            for version in ("26.3.33", "25.9.7"):
                release = releases[version]
                assert release["serviceVersion"] == version
                for image in ("clickhouse", "role-probe", "switchover", "memberJoin", "memberLeave"):
                    assert release["images"][image] == f"{registry}/apecloud/clickhouse:{version}"
                for kind in ("clickhouse", "clickhouse-keeper"):
                    definition = next(doc for doc in resources
                                      if doc["kind"] == "ComponentDefinition"
                                      and doc["spec"]["serviceKind"] == kind
                                      and "-22-" not in doc["metadata"]["name"])
                    assert any(version in rule["releases"] and any(
                        re.search(pattern, definition["metadata"]["name"])
                        for pattern in rule["compDefs"]
                    ) for rule in cv["compatibilityRules"])
            assert releases["22.3.18"]["images"]["clickhouse"].endswith(":22.3.18-debian-11-r3")

        for version in (None, "26.3.33"):
            for mode in ("standalone", "cluster", "withZookeeper"):
                args = ["--set-string", f"mode={mode}"]
                if version:
                    args += ["--set-string", f"version={version}"]
                if mode == "withZookeeper":
                    args += ["--set-string", "zookeeper.primary.cluster=test-zookeeper"]
                cluster = next(doc["spec"] for doc in render(cluster_chart, *args) if doc["kind"] == "Cluster")
                components = (cluster.get("componentSpecs") or []) + [cluster["shardings"][0]["template"]]
                assert len(components) == (2 if mode == "cluster" else 1)
                assert all(component["serviceVersion"] == (version or "25.9.7") for component in components)
    print("ClickHouse version, image, compatibility and default render checks passed")


if __name__ == "__main__":
    main()
