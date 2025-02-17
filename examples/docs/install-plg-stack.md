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

#### Step 2. Import a Loki Dashboard for Logs

You can import a Loki dashboard to visualize logs in Grafana or create your own dashboard.

- [Container Log Dashboard](https://grafana.com/grafana/dashboards/16966-container-log-dashboard/) from Grafana Dashboards
- [Container Log Trends](./misc/loki-container-logs.json) from the `docs/misc` folder.

More dashboards can be found at [Grafana Dashboards](https://grafana.com/grafana/dashboards).

#### Step 3. [Optional] Configure Promtail to Collect MySQL Error Logs

In this section, we will show how to configure Promtail to collect MySQL error logs.

MySQL will write its error logs to a file, say `/var/log/mysql/error.log`. We will configure Promtail to collect these logs and push them to Loki.

> [!IMPORTANT]
> Please check the path of the MySQL error log file on the host node w.r.t your Storage Provider.

In this example, we use `rancher.io/local-path` as the storage provider, and the MySQL error log file is located at `/var/local-path-provisioner/*/log/mysqld-error.log*` on host node.

```yaml
# cat values.yaml
loki:
  enabled: true
  url: http://loki-stack.logging:3100
  image:
    tag: 2.9.3
  persistence:
    enabled: true

promtail:
  enabled: true
  podSecurityContext:
    runAsUser: 0
    runAsGroup: 0
    fsGroup: 999  # add fsGroup to allow promtail to read logs from the host. Set to the group id of the user that has access to the log files

  extraVolumes:  # mount the local-path-provisioner volume to promtail. Set the path to the directory where the MySQL error logs are stored.
    - name: localpv
      hostPath:
        path: "/var/local-path-provisioner"
  extraVolumeMounts:
    - name: localpv
      mountPath: "/var/local-path-provisioner"
      readOnly: true
  config:
    clients:
      - url: http://loki-stack.logging:3100/loki/api/v1/push
    snippets:
      scrapeConfigs: |
        # This is an example of how to scrape MySQL error logs
        - job_name: mysql-logs
          static_configs:
            - targets:
                - localhost
              labels:
                job: mysql-logs
                __path__: /var/local-path-provisioner/*/log/mysqld-error.log*  # Specify the path pattern for MySQL error logs w.r.t your Storage Provider

          # Define processing stages for the collected logs
          pipeline_stages:
            - match:
                selector: '{job="mysql-logs"}'
                stages:
                  - regex:  # Extract metadata from the log file path using regex, must set source to filename
                      expression: '/var/local-path-provisioner/(?P<pvcName>pvc-[^_]+)_(?P<namespace>[^_]+)_data-(?P<podName>[^/]+)/log/mysqld-error.log.*'
                      source: filename
                  - labels:
                      namespace:
                      podName:
            - regex:  # Parse the log line content using regex
                expression: '^(?P<timestamp>[^ ]+) (?P<thread_id>\d+) \[(?P<level>[^\]]+)\] \[(?P<error_code>[^\]]+)\] \[(?P<source>[^\]]+)\] (?P<message>.*)$'
            - timestamp:  # Extract and format the timestamp from the log
                source: timestamp
                format: RFC3339Nano
            - labels:  # Add additional labels from the parsed log content
                level:
                error_code:
            - output:  # Define the final output of the log processing
                source: message
```

Please update the `__path__` field in the `scrapeConfigs` section to match the path pattern of the MySQL error logs on your host node and tune the `pipeline_stages` section as needed.

Then deploy the updated Promtail configuration:

```bash
helm upgrade --install loki-stack grafana/loki-stack -n logging --create-namespace -f values.yaml
```

Now you can see the MySQL error logs in Grafana, and explore them using the Loki query language.

1. Open Grafana in your browser (Loki has been added as a data source in previous steps)
1. Go to `Home` -> `Explore` -> `Loki` and run the query `{job="mysql-logs"}` to see the logs.
1. Filter the logs by namespace, pod name, or other labels as needed.
1. You can also create a dashboard to visualize the logs
1. Customize the `pipeline_stages` section in the `values.yaml` file to collect and parse the logs as needed.
