#!/bin/bash
set -e
set -o pipefail

result=$(kubectl get configmap kb-signal -n default ) || {
  if [[ "$result" == *"not found"* ]]; then
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kb-signal
  namespace: default
data:
  prepare-date: "true"
EOF
  fi
}
