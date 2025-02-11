## Enable KubeBlocks Metrics

KubeBlocks exposes metrics for Prometheus to scrape. You need to enable the feature gate `RUNTIME_METRICS` of KubeBlocks and  create a `ServiceMonitor` resource in the `kb-system` namespace if you are using Prometheus Operator.

### Step 1: Enable the Feature Gate

To enable the `RUNTIME_METRICS` feature gate, add the following configuration along with your settings to deploy `kubeblocks`

```yaml
# values.yaml
serviceMonitor:
  enabled: true
  goRuntime:
    enabled: true
```

And install or upgrade the KubeBlocks helm chart with the following command:

```bash
helm upgrade --install kubeblocks kubeblocks/kubeblocks -n kb-system  -f values.yaml --create-namespace --version <VERSION>
```

After enabling the feature gate, you can fetch the metrics from the `/metrics` endpoint of the controller-manager pod.

```bash
# port-forward the kubeblocks service
kubectl -n kb-system port-forward svc/kubeblocks 8080:8080
# fetch the metrics at http://localhost:8080/metrics
curl http://127.0.0.1:8080/metrics
```

### Step 2: Create a ServiceMonitor Resource

If you are using Prometheus Operator, you can create a `ServiceMonitor` resource in the `kb-system` namespace to scrape the metrics from the KubeBlocks Service.

Make sure the `label` and `namespace` set match the settings in the Prometheus CR `spec.serviceMonitorSelector` and `spec.serviceMonitorNamespaceSelector` respectively.

```yaml
# Prometheus Monitor Service (Metrics)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    control-plane: controller-manager
    release: prometheus  # matching Prometheus CR `spec.serviceMonitorSelector`
  name: kubeblocks-controller-manager
  namespace: kb-system   # matching Prometheus CR `spec.serviceMonitorNamespaceSelector` (if set to `{}`, it will match all namespaces)
spec:
  endpoints:
    - path: /metrics
      port: metrics
      scheme: http
      honorLabels: true
      scrapeTimeout: 30s
  jobLabel: app.kubernetes.io/name  # set the job label from `app.kubernetes.io/name`, which is `kubeblocks`
  namespaceSelector:
    matchNames:
      - kb-system
  selector:
    matchLabels:
      control-plane: controller-manager
      app.kubernetes.io/name: kubeblocks
```

### Step 3. Import a Grafana Dashboard

You can import a Grafana dashboard to visualize the metrics from KubeBlocks. In this example, we will use a sample from [KubeBlocks Grafana Dashboard](./kubeblocks-dashboard.json).