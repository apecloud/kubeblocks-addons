# shellcheck shell=bash

Describe "MongoDB shard postProvision readiness contract"

  run_post_provision() {
    local ping_stdout="$1"
    local ping_rc="$2"
    local shard_stdout="${3-shard-present}"
    local shard_rc="${4:-0}"
    local shard_after_add_stdout="${5-shard-present}"
    local add_rc="${6:-0}"
    local add_stdout="${7-}"
    local temp_dir
    local script_file
    local rc

    if [ "$#" -lt 7 ]; then
      add_stdout='{ "ok": 1 }'
    fi

    temp_dir=$(mktemp -d)
    script_file="$temp_dir/mongodb-shard-manage.sh"
    sed "s|\\. \"/scripts/mongodb-common.sh\"|. \"$temp_dir/mongodb-common.sh\"|" \
      ../scripts/mongodb-shard-manage.sh > "$script_file"

    cat > "$temp_dir/mongodb-common.sh" <<'MOCK'
get_mongodb_client_name() {
  echo "$MOCK_BIN_DIR/mongosh"
}

generate_endpoints() {
  echo "mongodb-0.mongodb-headless:27017"
}
MOCK

    mkdir -p "$temp_dir/bin"
    cat > "$temp_dir/bin/mongosh" <<'MOCK'
#!/usr/bin/env bash
query=""
for argument in "$@"; do
  query="$argument"
done

case "$query" in
  *ping*)
    echo "PING" >> "$MOCK_CALL_LOG"
    printf '%s\n' "$MOCK_PING_STDOUT"
    exit "$MOCK_PING_RC"
    ;;
  *config*shards.find*)
    echo "EXISTS" >> "$MOCK_CALL_LOG"
    if grep -q '^ADD$' "$MOCK_CALL_LOG"; then
      printf '%s\n' "$MOCK_SHARD_AFTER_ADD_STDOUT"
    else
      printf '%s\n' "$MOCK_SHARD_STDOUT"
    fi
    exit "$MOCK_SHARD_RC"
    ;;
  *sh.addShard*)
    echo "ADD" >> "$MOCK_CALL_LOG"
    printf '%s\n' "$MOCK_ADD_STDOUT"
    exit "$MOCK_ADD_RC"
    ;;
  *)
    echo "unexpected query: $query" >&2
    exit 64
    ;;
esac
MOCK
    cat > "$temp_dir/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    cat > "$temp_dir/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
shift
"$@"
MOCK
    chmod +x "$temp_dir/bin/mongosh" "$temp_dir/bin/sleep" "$temp_dir/bin/timeout"

    export MOCK_BIN_DIR="$temp_dir/bin"
    export MOCK_CALL_LOG="$temp_dir/calls.log"
    export MOCK_PING_STDOUT="$ping_stdout"
    export MOCK_PING_RC="$ping_rc"
    export MOCK_SHARD_STDOUT="$shard_stdout"
    export MOCK_SHARD_AFTER_ADD_STDOUT="$shard_after_add_stdout"
    export MOCK_SHARD_RC="$shard_rc"
    export MOCK_ADD_RC="$add_rc"
    export MOCK_ADD_STDOUT="$add_stdout"
    export PATH="$temp_dir/bin:$PATH"
    export CLUSTER_COMPONENT_NAME=mongodb-shard-0
    export MONGOS_INTERNAL_HOST=mongodb-mongos
    export MONGOS_INTERNAL_PORT=27017
    export MONGODB_ADMIN_USER=root
    export MONGODB_ADMIN_PASSWORD=password
    export MONGODB_POD_FQDN_LIST=mongodb-0.mongodb-headless
    export KB_SERVICE_PORT=27017
    : > "$MOCK_CALL_LOG"

    bash "$script_file" --post-provision
    rc=$?
    echo "TEST:ping-count=$(grep -c '^PING$' "$MOCK_CALL_LOG" 2>/dev/null || true)"
    echo "TEST:exists-count=$(grep -c '^EXISTS$' "$MOCK_CALL_LOG" 2>/dev/null || true)"
    echo "TEST:add-count=$(grep -c '^ADD$' "$MOCK_CALL_LOG" 2>/dev/null || true)"
    rm -rf "$temp_dir"
    return "$rc"
  }

  It "preserves a failed mongos probe status and ignores stale ready output"
    When call run_post_provision '{ "ok": 1 }' 17
    The status should equal 17
    The output should include "TEST:ping-count=1"
    The output should include "TEST:exists-count=0"
    The output should include "TEST:add-count=0"
    The stderr should include "postProvision diagnosis:"
    The stderr should include "phase: mongos-probe-failed"
    The stderr should include "next-retry-safe: no"
  End

  It "defers after one successful probe that positively reports not ready"
    When call run_post_provision '{ "ok": 0 }' 0
    The status should be failure
    The output should include "TEST:ping-count=1"
    The output should include "TEST:exists-count=0"
    The output should include "TEST:add-count=0"
    The stderr should include "postProvision diagnosis:"
    The stderr should include "phase: mongos-not-ready"
    The stderr should include "next-retry-safe: yes"
  End

  It "does not loop inside one invocation when the mongos probe has no output"
    When call run_post_provision '' 19
    The status should equal 19
    The output should include "TEST:ping-count=1"
    The output should include "TEST:exists-count=0"
    The output should include "TEST:add-count=0"
  End

  It "continues when one successful probe positively reports ready"
    When call run_post_provision '{ "ok": 1 }' 0
    The status should be success
    The output should include "TEST:ping-count=1"
    The output should include "TEST:exists-count=1"
    The output should include "TEST:add-count=0"
  End

  It "propagates one shard-add failure without retrying inside the invocation"
    When call run_post_provision '{ "ok": 1 }' 0 '' 0 '' 23
    The status should equal 23
    The output should include "TEST:ping-count=1"
    The output should include "TEST:exists-count=1"
    The output should include "TEST:add-count=1"
    The stderr should include "postProvision diagnosis:"
    The stderr should include "phase: shard-add-failed"
    The stderr should include "next-retry-safe: no"
  End

  It "defers after one add when the shard is not yet positively visible"
    When call run_post_provision '{ "ok": 1 }' 0 '' 0 '' 0
    The status should be failure
    The output should include "TEST:ping-count=1"
    The output should include "TEST:exists-count=2"
    The output should include "TEST:add-count=1"
    The stderr should include "postProvision diagnosis:"
    The stderr should include "phase: shard-not-visible-after-add"
    The stderr should include "next-retry-safe: yes"
  End

  It "fails closed when addShard returns ok zero with process status zero"
    When call run_post_provision '{ "ok": 1 }' 0 '' 0 '' 0 '{ "ok": 0 }'
    The status should be failure
    The output should include "TEST:ping-count=1"
    The output should include "TEST:exists-count=1"
    The output should include "TEST:add-count=1"
    The stderr should include "postProvision diagnosis:"
    The stderr should include "phase: shard-add-rejected"
    The stderr should include "next-retry-safe: no"
  End

  It "closes after one add is positively visible"
    When call run_post_provision '{ "ok": 1 }' 0 '' 0 shard-present 0
    The status should be success
    The output should include "TEST:ping-count=1"
    The output should include "TEST:exists-count=2"
    The output should include "TEST:add-count=1"
  End
End
