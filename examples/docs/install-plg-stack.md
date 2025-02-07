## How to Deploy PLG Stack on Kubernetes

**PLG stack** here refers to Promtail, Loki and Grafana, where Promtail extracts and collects logs from docker containers log files and pushes them to the Loki service which then Grafana uses to show logs in the log panel.

### Install Loki Stack

In this tutorial, we will show how to deploy them using loki-stack helm chart.
The Loki stack is a lightweight log aggregation solution from Grafana.

**Step 1.** Add the Grafana Helm Chart repository and Update repo:

```bash
# Add Grafana's Helm Chart repository and Update repo :
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

**Step 2.** Install Loki Stack:

If you have prometheus and Grafana already installed, you may deploy the loki stack with values as follows:

```yaml
# cat values.yaml
loki:
  enabled: true
  url: http://loki-stack.logging:3100
  image:
    tag: 2.9.3  # set image tag to 2.8.10 or higher to fix the issue 'Failed to load log volume for this query'
  persistence:
    enabled: true # set to true to persist logs

promtail:
  enabled: true
  config:
    clients:
      - url: http://loki-stack.logging:3100/loki/api/v1/push # set loki url, don't forget the `namespace` of loki service
```

```bash
# Deploy the Loki stack to namespace logging. customize the values.yaml as needed.
helm upgrade --install loki-stack grafana/loki-stack -n logging --create-namespace -f values.yaml
```

For more details please refer to [loki stack](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack).

> [!IMPORTANT]
> If you are deploying the stack with loki version 2.6.1, you may encounter the error 'Failed to load log volume for this query'.
> To fix the issue, you should upgrade the loki version to 2.8.10 or higher, as discussed in the [issue](https://github.com/grafana/grafana/issues/84144).

**Step 3.** Check Status:

```bash
kubectl get pods -n logging
```

All the pods should be in the `Running` state.

### Configure Loki in Grafana

#### Step 1. Add Loki Data Source to Grafana

Visit Grafana Dashboard in your browser and Go to `Home` -> `Connections` -> `Data Sources` -> `Add new data source` -> `Loki` and fill in the following details:

- **Name**: Loki
- **URL**: `http://loki-stack.logging:3100/`, where `logging` is the namespace where Loki is deployed.

Click on `Save & Test` to save the data source.

Then click on `Home` > `Explore` then choose `Loki` as the data source to filter labels and run queries, say `{namespace="default",stream="stdout"}` to see the logs.

If you encounter the `Failed to load log volume for this query` error, please upgrade the loki version to 2.8.10 or higher.

### Step 2. Import a Loki Dashboard for Logs

You can import a Loki dashboard to visualize logs in Grafana or create your own dashboard.

More dashboards can be found at [Grafana Dashboards](https://grafana.com/grafana/dashboards).

### Example: Collect Logs for MySQL Cluster

1. Create MySQL Cluster

```bash
kubectl create -f examples/mysql/cluster.yaml
```

2. Open Grafa and import dashboard to visualize logs, for example, you can import the following dashboard:

- <https://grafana.com/grafana/dashboards/16966-container-log-dashboard/>

3. You may choose the namespace and stream to filter logs and see the logs in the log panel