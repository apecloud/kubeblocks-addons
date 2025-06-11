set -e
set -o pipefail

trap handle_exit EXIT

kubectl apply -f <<EOF
apiVersion: apps.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: $KB_CLUSTER_NAME-restart-$(date +%s)
  namespace: default
spec:
  clusterName: $KB_CLUSTER_NAME
  type: Restart
  restart:
  - componentName: config-server
  - componentName: mongos
  - componentName: mongo-shard
EOF