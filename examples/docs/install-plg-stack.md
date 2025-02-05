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

If you have prometheus and Grafana already installed, you can use the following command to deploy the loki stack:

```bash
# Deploy the Loki stack to namespace logging
helm upgrade --install loki-stack grafana/loki-stack -n logging --create-namespace
```

Otherwise, you can deploy the loki stack with prometheus and Grafana enabled:

```bash
helm upgrade --install loki-stack grafana/loki-stack -n logging --create-namespace --set grafana.enabled=true,prometheus.enabled=true
```

For more details please refer to [loki stack](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack).

The above command will deploy the Loki stack to the `logging` namespace, replace `logging` with the namespace you want to deploy the stack to.

> [!IMPORTANT]
> If you are deploying the stack with loki version 2.6.1, you may encounter the error 'Failed to load log volume for this query'.
> To fix the issue, you should upgrade the loki version to 2.8.10 or higher, as discussed in the [issue](https://github.com/grafana/grafana/issues/84144).

**Step 3.** Check Status:

```bash
kubectl get pods -n logging
```

All the pods should be in the `Running` state.

### Configure Loki with Grafana

If your Grafana and Prometheus are installed together with Loki, you can access the Grafana dashboard using the following command:

```bash
kubectl port-forward svc/loki-stack-grafana 3000:80 -n logging
```

Then open the browser and go to `http://localhost:3000/` and login with the default username `admin` and password retrieved using the following command:

```bash
kubectl get secret --namespace logging loki-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

#### Add Loki Data Source

Go to `Home` -> `Connections` -> `Data Sources` -> `Add new data source` -> `Loki` and fill in the following details:

- **Name**: Loki
- **URL**: `http://loki-stack.logging:3100/`, where `logging` is the namespace where Loki is deployed.

Click on `Save & Test` to save the data source.

Then click on `Home` > `Explore` then choose `Loki` as the data source to filter labels and run queries, say `{namespace="default",stream="stdout"}` to see the logs.

If you encounter the `Failed to load log volume for this query` error, please upgrade the loki version to 2.8.10 or higher, using the following command:

```bash
kubectl -n logging set image sts loki-stack loki=grafana/loki:2.9.3 # replace 2.9.3 with the version you need
```

### Import a Loki Dashboard for Logs

You can import a Loki dashboard to visualize logs in Grafana or create your own dashboard.

More dashboards can be found at [Grafana Dashboards](https://grafana.com/grafana/dashboards).

### Example: Collect Logs from MySQL Cluster

Step 1. Create MySQL Cluster

```bash
kubectl create -f examples/mysql/cluster.yaml
```

Step 2. Open Grafa and import dashboard to visualize logs, for example, you can import the following dashboard:

- https://grafana.com/grafana/dashboards/16966-container-log-dashboard/


Step 3. You may choose the namespace and stream to filter logs and see the logs in the log panel