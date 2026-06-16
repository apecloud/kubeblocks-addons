# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "member_join_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "ZooKeeper Member Join Script Tests"
  setup_mock_zkcli() {
    mock_bin_dir="$(mktemp -d)"
    zkcli_call_file="$mock_bin_dir/zkcli.calls"
    cat > "$mock_bin_dir/zkCli.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

call_file="${ZKCLI_CALL_FILE}"
count=0
if [ -f "$call_file" ]; then
  count="$(cat "$call_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$call_file"

input="$(cat)"
if grep -q "get /zookeeper/config" <<< "$input"; then
  if [ "$count" -eq 1 ]; then
    printf '%b\n' "${ZKCLI_GET_OUTPUT:-}"
  else
    printf '%b\n' "${ZKCLI_GET_OUTPUT_2:-${ZKCLI_GET_OUTPUT:-}}"
  fi
  exit "${ZKCLI_GET_RC:-0}"
fi

if grep -q "reconfig -add" <<< "$input"; then
  printf '%b\n' "${ZKCLI_RECONFIG_OUTPUT:-Committed new configuration}"
  exit "${ZKCLI_RECONFIG_RC:-0}"
fi

printf '%b\n' "${ZKCLI_OTHER_OUTPUT:-OK}"
EOF
    chmod +x "$mock_bin_dir/zkCli.sh"
    export PATH="$mock_bin_dir:$PATH"
    export ZKCLI_CALL_FILE="$zkcli_call_file"
    export ZK_ADMIN_USER="admin"
    export ZK_ADMIN_PASSWORD="password"
  }

  cleanup_mock_zkcli() {
    rm -rf "$mock_bin_dir"
    unset mock_bin_dir zkcli_call_file ZKCLI_CALL_FILE
    unset ZKCLI_GET_OUTPUT ZKCLI_GET_OUTPUT_2 ZKCLI_GET_RC
    unset ZKCLI_RECONFIG_OUTPUT ZKCLI_RECONFIG_RC ZKCLI_OTHER_OUTPUT
    unset ZK_ADMIN_USER ZK_ADMIN_PASSWORD
    unset KB_JOIN_MEMBER_POD_NAME KB_JOIN_MEMBER_POD_FQDN
  }

  BeforeEach "setup_mock_zkcli"
  AfterEach "cleanup_mock_zkcli"

  It "does not treat same endpoint with wrong member type as already joined"
    export KB_JOIN_MEMBER_POD_NAME="zookeeper-3"
    export KB_JOIN_MEMBER_POD_FQDN="zookeeper-3.zookeeper-headless.default.svc.cluster.local"
    export ZKCLI_GET_OUTPUT="server.0=zookeeper-0.zookeeper-headless.default.svc.cluster.local:2888:3888:participant;2181\nserver.3=zookeeper-3.zookeeper-headless.default.svc.cluster.local:2888:3888:participant;2181"

    When run command bash ../scripts/member_join.sh
    The status should be failure
    The stdout should include "Adding ZooKeeper member: server.3="
    The stderr should include "already exists with a different endpoint or member type"
  End

  It "accepts an exact target member state as already joined"
    export KB_JOIN_MEMBER_POD_NAME="zookeeper-3"
    export KB_JOIN_MEMBER_POD_FQDN="zookeeper-3.zookeeper-headless.default.svc.cluster.local"
    export ZKCLI_GET_OUTPUT="server.0=zookeeper-0.zookeeper-headless.default.svc.cluster.local:2888:3888:participant;2181\nserver.3=zookeeper-3.zookeeper-headless.default.svc.cluster.local:2888:3888:observer;2181"

    When run command bash ../scripts/member_join.sh
    The status should be success
    The stdout should include "ZooKeeper member server.3 already exists"
  End
End
