## Notes
- Grafana dashboards are copied from pingcap repos according to [its doc](https://docs.pingcap.com/tidb/stable/deploy-monitoring-services#step-2-import-a-grafana-dashboard)
    - `tikv_details.json` is minified to make it do not exceed k8s' 1MB size limit. 