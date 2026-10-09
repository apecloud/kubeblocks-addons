#!/bin/sh

role=${KB_SWITCHOVER_ROLE:-}
current_name=${KB_SWITCHOVER_CURRENT_NAME:-}
candidate_name=${KB_SWITCHOVER_CANDIDATE_NAME:-}
namespace=${CLUSTER_NAMESPACE:-}
component_name=${KB_CLUSTER_COMP_NAME:-}
syncerctl_bin=${MONGODB_SYNCERCTL_BIN:-/tools/syncerctl}
kubectl_bin=${MONGODB_KUBECTL_BIN:-/data/mongodb/tmp/bin/kubectl}

case "$role" in
  primary)
    ;;
  secondary)
    printf 'role=secondary does not require transfer\n'
    exit 0
    ;;
  *)
    printf 'phase: invalid-role\n' >&2
    printf 'observed-role: %s\n' "$role" >&2
    printf 'next-retry-safe: no\n' >&2
    exit 2
    ;;
esac

if [ -z "$current_name" ]; then
  printf 'phase: missing-current-pod\n' >&2
  printf 'next-retry-safe: no\n' >&2
  exit 2
fi

if [ -z "$namespace" ]; then
  printf 'phase: missing-cluster-namespace\n' >&2
  printf 'next-retry-safe: no\n' >&2
  exit 2
fi

if [ -z "$component_name" ]; then
  printf 'phase: missing-cluster-component-name\n' >&2
  printf 'next-retry-safe: no\n' >&2
  exit 2
fi

if [ -n "$candidate_name" ]; then
  timeout 10s "$syncerctl_bin" switchover \
    --primary "$current_name" \
    --candidate "$candidate_name"
else
  timeout 10s "$syncerctl_bin" switchover --primary "$current_name"
fi
rc=$?

case "$rc" in
  0)
    ;;
  124|143)
    printf 'phase: syncerctl-timeout\n' >&2
    printf 'syncerctl-rc: %s\n' "$rc" >&2
    printf 'next-retry-safe: no\n' >&2
    exit "$rc"
    ;;
  *)
    printf 'phase: syncerctl-failed\n' >&2
    printf 'syncerctl-rc: %s\n' "$rc" >&2
    printf 'next-retry-safe: no\n' >&2
    exit "$rc"
    ;;
esac

completion_name="${component_name}-switchover"
completion_object="configmap/${completion_name}"
probe=1

while [ "$probe" -le 6 ]; do
  observed=$(
    timeout 3s "$kubectl_bin" \
      --request-timeout=2s \
      --namespace "$namespace" \
      get configmap "$completion_name" \
      --ignore-not-found -o name
  )
  rc=$?

  case "$rc" in
    0)
      ;;
    124|143)
      printf 'phase: completion-probe-timeout\n' >&2
      printf 'completion-probe-rc: %s\n' "$rc" >&2
      printf 'next-retry-safe: no\n' >&2
      exit "$rc"
      ;;
    *)
      printf 'phase: completion-probe-failed\n' >&2
      printf 'completion-probe-rc: %s\n' "$rc" >&2
      printf 'next-retry-safe: no\n' >&2
      exit "$rc"
      ;;
  esac

  if [ -z "$observed" ]; then
    printf 'phase: completed\n'
    printf 'completion-configmap: %s\n' "$completion_name"
    exit 0
  fi

  if [ "$observed" != "$completion_object" ]; then
    printf 'phase: malformed-completion-probe\n' >&2
    printf 'observed-output: %s\n' "$observed" >&2
    printf 'next-retry-safe: no\n' >&2
    exit 1
  fi

  if [ "$probe" -eq 6 ]; then
    printf 'phase: completion-not-observed\n' >&2
    printf 'completion-configmap: %s\n' "$completion_name" >&2
    printf 'completion-probes: 6\n' >&2
    printf 'next-retry-safe: no\n' >&2
    exit 1
  fi

  sleep 2
  probe=$((probe + 1))
done
