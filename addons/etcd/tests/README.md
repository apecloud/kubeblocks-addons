# Inject Image Pull Policy Regression

Requires Helm 3 or 4, Python 3.8+, and PyYAML (`python3 -m pip install PyYAML`).
Run from the repository root:

```sh
python3 addons/etcd/tests/test_inject_pull_policy.py
```

The test copies the actual etcd chart and local kblib dependency to a temporary
directory and uses `helm template` to render the complete chart. YAML assertions
find `inject-bash` and `etcd` by name. The 16 render cases cover installation and
upgrade with default, explicit `IfNotPresent`, `Always`, `Never`, empty, and null
init policies, plus primary-only and differing primary/init policies.
`images.pullPolicy` controls the init container; `image.pullPolicy` independently
controls the primary container. Empty init policies fall back to `IfNotPresent`.

Optional environment variables: `HELM_BIN` selects the Helm executable,
`CHART_DIR` selects another etcd chart with adjacent kblib, and `RENDER_DIR`
retains full rendered YAML for each case. No cluster is contacted.
