#!/bin/sh
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set -eu

readonly resource="opsdefinition.operations.kubeblocks.io"
readonly name="mssql-dynamic-remove-ag"
readonly max_attempts=8
readonly poll_interval_seconds=2
readonly default_service_account_dir="/var/run/secrets/kubernetes.io/serviceaccount"

service_account_dir="${REMOVE_AG_SERVICE_ACCOUNT_DIR:-$default_service_account_dir}"
service_host="${KUBERNETES_SERVICE_HOST:-}"
service_port="${KUBERNETES_SERVICE_PORT_HTTPS:-${KUBERNETES_SERVICE_PORT:-}}"
kubeconfig=""

# shellcheck disable=SC2329  # Invoked by the EXIT trap.
cleanup() {
  if [ -n "$kubeconfig" ]; then
    rm -f "$kubeconfig"
  fi
}

# shellcheck disable=SC2329  # Invoked by signal traps.
on_signal() {
  cleanup
  exit 1
}

trap cleanup 0
trap on_signal HUP INT TERM

case "$service_account_dir" in
  ""|*[!A-Za-z0-9_./-]*)
    echo "ERROR: invalid service account directory" >&2
    exit 1
    ;;
esac

case "$service_host" in
  ""|*[!A-Za-z0-9.:-]*)
    echo "ERROR: invalid Kubernetes service host" >&2
    exit 1
    ;;
esac

case "$service_port" in
  ""|*[!0-9]*)
    echo "ERROR: invalid Kubernetes service port" >&2
    exit 1
    ;;
esac
if [ "$service_port" -lt 1 ] || [ "$service_port" -gt 65535 ]; then
  echo "ERROR: Kubernetes service port is out of range" >&2
  exit 1
fi

if [ ! -s "$service_account_dir/token" ]; then
  echo "ERROR: projected service account token is missing or empty" >&2
  exit 1
fi
if [ ! -s "$service_account_dir/ca.crt" ]; then
  echo "ERROR: projected service account CA is missing or empty" >&2
  exit 1
fi

case "$service_host" in
  *:*) api_server="https://[$service_host]:$service_port" ;;
  *) api_server="https://$service_host:$service_port" ;;
esac

umask 077
kubeconfig="$(mktemp "${TMPDIR:-/tmp}/mssql-remove-ag-kubeconfig.XXXXXX")"
cat >"$kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: in-cluster
    cluster:
      server: "$api_server"
      certificate-authority: "$service_account_dir/ca.crt"
users:
  - name: hook
    user:
      tokenFile: "$service_account_dir/token"
contexts:
  - name: hook
    context:
      cluster: in-cluster
      user: hook
current-context: hook
EOF
chmod 600 "$kubeconfig"
export KUBECONFIG="$kubeconfig"

kubectl delete "$resource" "$name" \
  --ignore-not-found=true \
  --wait=false \
  --request-timeout=10s

# Poll the exact name so least-privilege RBAC does not require list/watch.
attempt=1
while [ "$attempt" -le "$max_attempts" ]; do
  if remaining="$(
    kubectl get "$resource" "$name" \
      --ignore-not-found=true \
      --request-timeout=3s \
      -o name
  )"; then
    if [ -z "$remaining" ]; then
      echo "Legacy OpsDefinition is absent: $name"
      exit 0
    fi
  else
    echo "ERROR: unable to verify legacy OpsDefinition absence: $name" >&2
    exit 1
  fi

  if [ "$attempt" -lt "$max_attempts" ]; then
    sleep "$poll_interval_seconds"
  fi
  attempt=$((attempt + 1))
done

echo "ERROR: legacy OpsDefinition still exists after bounded deletion checks: $name" >&2
exit 1
