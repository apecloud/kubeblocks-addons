# MinIO Image Pull Policy Regression

Requires Helm 3 or 4, Python 3.8+, and PyYAML (`python3 -m pip install PyYAML`).
Run from the repository root:

```sh
python3 addons/milvus/tests/test_minio_pull_policy.py
```

The test copies the actual Milvus chart and local kblib dependency to a temporary
directory, builds dependencies there, and runs `helm template`. It checks both
`volume-permissions` and `minio` by name in the parsed ComponentDefinition.
The 12 render cases cover install and upgrade with the default values, explicit
`IfNotPresent`, `Always`, `Never`, an empty string, and null. Empty values must
fall back to `IfNotPresent`.

Optional environment variables: `HELM_BIN` selects the Helm executable;
`CHART_DIR` selects another Milvus source directory with an adjacent kblib;
`RENDER_DIR` retains the complete rendered YAML for each case.
This test does not contact a Kubernetes cluster.
