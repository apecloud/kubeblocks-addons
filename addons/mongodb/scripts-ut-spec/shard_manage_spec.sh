# shellcheck shell=bash

Describe "MongoDB shard lifecycle polling"
  setup() {
    TEST_DIR=$(mktemp -d)
    export TEST_DIR
    export SYNCERCTL_BIN="$TEST_DIR/syncerctl"
    export SYNCER_SHARD_POLL_INTERVAL_SECONDS=1
    export SYNCER_ADD_SHARD_TIMEOUT_SECONDS=10
    export SYNCER_REMOVE_SHARD_TIMEOUT_SECONDS=10
  }
  BeforeEach 'setup'

  cleanup() {
    rm -rf "$TEST_DIR"
    unset TEST_DIR SYNCERCTL_BIN SYNCER_SHARD_POLL_INTERVAL_SECONDS
    unset SYNCER_ADD_SHARD_TIMEOUT_SECONDS SYNCER_REMOVE_SHARD_TIMEOUT_SECONDS
  }
  AfterEach 'cleanup'

  It "polls Running until add-shard succeeds"
    cat > "$SYNCERCTL_BIN" <<'MOCK'
#!/bin/bash
count_file="$TEST_DIR/count"
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
echo "$count" > "$count_file"
if [ "$count" -lt 2 ]; then
  echo "add shard is Running" >&2
  exit 1
fi
echo "add shard success"
MOCK
    chmod +x "$SYNCERCTL_BIN"

    When run bash ../scripts/mongodb-shard-manage.sh add-shard
    The status should be success
    The output should include "add shard is Running"
    The output should include "add shard success"
    The contents of file "$TEST_DIR/count" should equal 2
  End

  It "retries transient remove-shard errors"
    cat > "$SYNCERCTL_BIN" <<'MOCK'
#!/bin/bash
count_file="$TEST_DIR/count"
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
echo "$count" > "$count_file"
if [ "$count" -lt 2 ]; then
  echo "remove shard failed: temporary mongos connection error" >&2
  exit 1
fi
echo "remove shard success"
MOCK
    chmod +x "$SYNCERCTL_BIN"

    When run bash ../scripts/mongodb-shard-manage.sh remove-shard
    The status should be success
    The output should include "temporary mongos connection error"
    The output should include "remove shard success"
  End

  It "fails immediately on a permanent remove-shard error"
    cat > "$SYNCERCTL_BIN" <<'MOCK'
#!/bin/bash
echo "remove shard failed: shard demo has 1 jumbo chunks" >&2
exit 1
MOCK
    chmod +x "$SYNCERCTL_BIN"

    When run bash ../scripts/mongodb-shard-manage.sh remove-shard
    The status should be failure
    The output should include "jumbo chunks"
    The error should include "failed permanently"
  End
End
