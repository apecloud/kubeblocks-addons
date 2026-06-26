# shellcheck shell=bash

Describe "Qdrant backup and restore scripts"
  setup() {
    export QDRANT_TEST_DIR="${SHELLSPEC_TMPBASE}/qdrant-${SHELLSPEC_WORKER_ID:-0}"
    mkdir -p "$QDRANT_TEST_DIR"
    export QDRANT_CURL_LOG="${QDRANT_TEST_DIR}/curl.log"
    export QDRANT_EXPECT_API_KEY="test-key"
    export QDRANT__SERVICE__API_KEY="test-key"
    export QDRANT_COMMON_FILE="../scripts/qdrant-common.sh"
    export DP_DATASAFED_BIN_PATH="/mock-datasafed"
    export DP_BACKUP_BASE_PATH="${QDRANT_TEST_DIR}/backup"
    export DP_BACKUP_INFO_FILE="${QDRANT_TEST_DIR}/backup-info.json"
    export DP_DB_HOST="qdrant-cluster-qdrant"
    export DATA_DIR="${QDRANT_TEST_DIR}/data"
    export QDRANT_CONFIG_FILE="${QDRANT_TEST_DIR}/config.yaml"
    mkdir -p "${DATA_DIR}/_dp_snapshots"
    : > "$QDRANT_CURL_LOG"
    cat > "$QDRANT_CONFIG_FILE" <<EOF
service:
  api_key: config-key
EOF
  }

  cleanup() {
    rm -rf "$QDRANT_TEST_DIR"
    unset QDRANT_EXPECT_API_KEY
    unset QDRANT__SERVICE__API_KEY
    unset QDRANT_COMMON_FILE
    unset TLS_ENABLED
  }

  BeforeEach "setup"
  AfterEach "cleanup"

  Mock curl
    printf "%s\n" "$*" >> "$QDRANT_CURL_LOG"
    if [ -n "${QDRANT_EXPECT_API_KEY:-}" ]; then
      case " $* " in
        *" -H api-key: ${QDRANT_EXPECT_API_KEY} "*|*" -H api-key:${QDRANT_EXPECT_API_KEY} "*) ;;
        *)
          echo "missing api key"
          exit 22
          ;;
      esac
    fi

    case "$*" in
      *"/collections/"*"/snapshots/upload"*)
        echo '{"status":"ok"}'
        ;;
      *"-XPOST"*"/snapshots"*)
        echo '{"status":"ok","result":{"name":"collection-a.snapshot"}}'
        ;;
      *"/collections/collection-a/snapshots/collection-a.snapshot"*)
        echo "snapshot-bytes"
        ;;
      *"/collections"*)
        echo '{"result":{"collections":[{"name":"collection-a"}]}}'
        ;;
      *)
        echo '{"status":"ok"}'
        ;;
    esac
  End

  Mock jq
    query=""
    for arg in "$@"; do
      case "$arg" in
        .*) query="$arg" ;;
      esac
    done
    input=$(cat)
    case "$query" in
      ".result.collections[].name"|".result.collections[].name // empty")
        echo "collection-a"
        ;;
      ".status"|".status // empty")
        echo "ok"
        ;;
      ".result.name"|".result.name // empty")
        echo "collection-a.snapshot"
        ;;
      *)
        echo "$input"
        ;;
    esac
  End

  Mock datasafed
    case "$1" in
      stat)
        echo "TotalSize 1024"
        ;;
      push)
        cat >/dev/null
        echo "pushed $3"
        ;;
      list)
        echo "collection-a.snapshot"
        ;;
      pull)
        echo "snapshot-bytes" > "$3"
        ;;
    esac
  End

  It "passes the qdrant API key header to every backup API call"
    When run source ../scripts/qdrant-backup.sh
    The status should be success
    The stdout should include "INFO: snapshot collection collection-a successfully."
    The contents of file "$QDRANT_CURL_LOG" should include "-H api-key: test-key"
    The contents of file "$DP_BACKUP_INFO_FILE" should include "totalSize"
  End

  It "passes the qdrant API key header to restore snapshot upload"
    When run source ../scripts/qdrant-restore.sh
    The status should be success
    The stdout should include "restore collection collection-a successfully"
    The contents of file "$QDRANT_CURL_LOG" should include "-H api-key: test-key"
    The contents of file "$QDRANT_CURL_LOG" should include "/snapshots/upload?priority=snapshot"
  End

  It "uses service api key from qdrant config when env is unset"
    unset QDRANT__SERVICE__API_KEY
    export QDRANT_EXPECT_API_KEY="config-key"

    When run source ../scripts/qdrant-backup.sh
    The status should be success
    The stdout should include "INFO: snapshot collection collection-a successfully."
    The contents of file "$QDRANT_CURL_LOG" should include "-H api-key: config-key"
  End

  It "prefers qdrant API key env over config"
    export QDRANT_EXPECT_API_KEY="test-key"

    When run source ../scripts/qdrant-backup.sh
    The status should be success
    The stdout should include "INFO: snapshot collection collection-a successfully."
    The contents of file "$QDRANT_CURL_LOG" should include "-H api-key: test-key"
  End

  It "renders qdrant probes from scripts mounted by configmap"
    When run sh -c "grep -q '/qdrant/scripts/liveness-probe.sh' ../templates/cmpd.yaml && grep -q '/qdrant/scripts/readiness-probe.sh' ../templates/cmpd.yaml && grep -q '/qdrant/scripts/startup-probe.sh' ../templates/cmpd.yaml"
    The status should be success
  End

  It "keeps qdrant probe script bodies out of the component pod spec"
    When run sh -c "sed -n '/containers:/,/dnsPolicy:/p' ../templates/cmpd.yaml | grep -E -c 'qdrant_curl|consensus_status|QDRANT_CURL_BIN|/qdrant/tools/curl' || true"
    The status should be success
    The output should eq 0
  End

  It "packages qdrant probe scripts in the scripts configmap"
    When run sh -c "grep -q 'liveness-probe.sh' ../templates/script-template.yaml && grep -q 'readiness-probe.sh' ../templates/script-template.yaml && grep -q 'startup-probe.sh' ../templates/script-template.yaml"
    The status should be success
  End

  It "exposes service api key as a qdrant config variable"
    When run grep -c 'service_api_key' ../configs/config.yaml.tpl
    The status should be success
    The output should eq 2
  End

  It "exposes telemetry disabled as a qdrant config variable with telemetry disabled by default"
    When run sh -c "grep -q 'hasKey . \"telemetry_disabled\"' ../configs/config.yaml.tpl && grep -q 'telemetry_disabled: true' ../configs/config.yaml.tpl"
    The status should be success
  End

  It "does not hardcode qdrant telemetry disabled through container env"
    When run sh -c "grep -E -c 'QDRANT__TELEMETRY_DISABLED' ../templates/cmpd.yaml || true"
    The status should be success
    The output should eq 0
  End

  It "loads qdrant config from the standalone configs file"
    When run grep -c 'configs/config.yaml.tpl' ../templates/config-template.yaml
    The status should be success
    The output should eq 1
  End

  It "mounts the qdrant config into backup and restore actions"
    When run grep -c 'mountPath: /qdrant/config' ../templates/backuppolicytemplate.yaml
    The status should be success
    The output should eq 1
  End

  It "declares only qdrant config as backup target volume"
    When run grep -c -- '- qdrant-config' ../templates/backuppolicytemplate.yaml
    The status should be success
    The output should eq 1
  End

  It "does not mount the qdrant data volume for API-based backup and restore"
    When run sh -c "grep -E -c '^[[:space:]]*- data$|mountPath: \\{\\{ .Values.dataMountPath \\}\\}' ../templates/backuppolicytemplate.yaml || true"
    The status should be success
    The output should eq 0
  End

  It "uses a local temporary directory for restore snapshots"
    When run grep -c 'SNAPSHOT_DIR="${TMPDIR:-/tmp}/qdrant-snapshots"' ../scripts/qdrant-restore.sh
    The status should be success
    The output should eq 1
  End

  It "uses backup policy target volume mounts for qdrant config"
    When run sh -c "grep -q 'targetVolumes:' ../templates/backuppolicytemplate.yaml && grep -q 'volumeMounts:' ../templates/backuppolicytemplate.yaml && grep -q 'mountPath: /qdrant/config' ../templates/backuppolicytemplate.yaml"
    The status should be success
  End

  It "keeps target-node scheduling so qdrant target volume mounts are projected"
    When run grep -c 'runOnTargetPodNode: true' ../templates/actionset-datafile.yaml
    The status should be success
    The output should eq 2
  End

  It "renders qdrant TLS settings in the main config template"
    When run sh -c "grep -c 'enable_tls: true' ../configs/config.yaml.tpl"
    The status should be success
    The output should eq 2
  End

  It "renders qdrant TLS certificate paths in the main config template"
    When run sh -c "grep -q 'cert: {{ .TLS_MOUNT_PATH }}/tls.crt' ../configs/config.yaml.tpl && grep -q 'key: {{ .TLS_MOUNT_PATH }}/tls.key' ../configs/config.yaml.tpl && grep -q 'ca_cert: {{ .TLS_MOUNT_PATH }}/ca.crt' ../configs/config.yaml.tpl"
    The status should be success
  End

  It "does not generate a separate qdrant TLS config at startup"
    When run sh -c "grep -E -c '/tmp/tls.yaml|TLS_CONFIG_ARG' ../scripts/qdrant-setup.sh || true"
    The status should be success
    The output should eq 0
  End

  It "keeps the qdrant e2e configurable for TLS and API-key modes"
    When run sh -c "grep -q 'QDRANT_TLS_ENABLED' ../../../examples/qdrant/test/qdrant_api_key_backup_restore_e2e.sh && grep -q 'API_KEY_ENABLED' ../../../examples/qdrant/test/qdrant_api_key_backup_restore_e2e.sh && grep -q 'RUN_LIFECYCLE_CHECK' ../../../examples/qdrant/test/qdrant_api_key_backup_restore_e2e.sh"
    The status should be success
  End

  It "covers qdrant TLS/API-key on and off combinations in e2e"
    When run sh -c "grep -q 'tls-off-api-key-off' ../../../examples/qdrant/test/qdrant_tls_api_key_matrix_e2e.sh && grep -q 'tls-off-api-key-on' ../../../examples/qdrant/test/qdrant_tls_api_key_matrix_e2e.sh && grep -q 'tls-on-api-key-off' ../../../examples/qdrant/test/qdrant_tls_api_key_matrix_e2e.sh && grep -q 'tls-on-api-key-on' ../../../examples/qdrant/test/qdrant_tls_api_key_matrix_e2e.sh"
    The status should be success
  End

  It "removes leaving qdrant peers through the current live peer without bypassing qdrant shard safety"
    When run sh -c "grep -q 'current_peer_uri=' ../scripts/qdrant-member-leave.sh && grep -q '/cluster/peer/' ../scripts/qdrant-member-leave.sh && ! grep -q 'force=true' ../scripts/qdrant-member-leave.sh"
    The status should be success
  End

  It "uses the packaged curl binary for qdrant member leave actions"
    When run grep -c 'QDRANT_CURL_BIN="${QDRANT_CURL_BIN:-/qdrant/tools/curl}"' ../scripts/qdrant-member-leave.sh
    The status should be success
    The output should eq 1
  End

  It "uses a non-leaving qdrant peer as the member leave API endpoint"
    When run sh -c "grep -q 'select_qdrant_api_peer_fqdn' ../scripts/qdrant-member-leave.sh && grep -q 'KB_LEAVE_MEMBER_POD_NAME' ../scripts/qdrant-member-leave.sh && grep -q 'current_peer_uri=.*api_peer_fqdn' ../scripts/qdrant-member-leave.sh"
    The status should be success
  End

  It "serializes concurrent qdrant member leave actions"
    When run grep -c 'flock -n -x 9' ../scripts/qdrant-member-leave.sh
    The status should be success
    The output should eq 1
  End

  It "does not skip different qdrant members during concurrent member leave actions"
    When run sh -c "grep -q 'qdrant-leave-member-.*KB_LEAVE_MEMBER_POD_NAME' ../scripts/qdrant-member-leave.sh && ! grep -q 'qdrant-leave-member-lock' ../scripts/qdrant-member-leave.sh"
    The status should be success
  End

  It "does not report duplicate qdrant member leave success while the peer still exists"
    When run sh -c "grep -q 'is_leaving_peer_removed' ../scripts/qdrant-member-leave.sh && grep -q 'retry member leave later' ../scripts/qdrant-member-leave.sh && grep -q 'exit 1' ../scripts/qdrant-member-leave.sh && ! grep -q 'skip duplicate request' ../scripts/qdrant-member-leave.sh"
    The status should be success
  End

  It "drains qdrant shards before removing the leaving peer"
    When run sh -c "grep -q 'drain_peer_shards' ../scripts/qdrant-member-leave.sh && grep -q 'move_shard' ../scripts/qdrant-member-leave.sh && grep -q 'drop_replica' ../scripts/qdrant-member-leave.sh && grep -q 'wait_for_peer_drain' ../scripts/qdrant-member-leave.sh && sed -n '/remove_peer()/,/^}/p' ../scripts/qdrant-member-leave.sh | awk '/drain_peer_shards/{drain=NR} /-XDELETE/{remove=NR} END{exit !(drain && remove && drain < remove)}'"
    The status should be success
  End

  It "moves qdrant shards only to desired peers when pod variables are available"
    When run sh -c "grep -q 'desired_peer' ../scripts/qdrant-member-leave.sh && grep -q 'map(select(desired_peer(.value.uri)))' ../scripts/qdrant-member-leave.sh && grep -Fq '. as \$pod | \$uri | contains(\"://\" + \$pod + \".\")' ../scripts/qdrant-member-leave.sh"
    The status should be success
  End

  It "prefers lower-ordinal qdrant peers as shard drain targets"
    When run sh -c "grep -q 'def pod_ordinal' ../scripts/qdrant-member-leave.sh && grep -q 'ordinal: pod_ordinal(.value.uri)' ../scripts/qdrant-member-leave.sh && grep -q 'sort_by(if .preferred then 0 else 1 end, .ordinal' ../scripts/qdrant-member-leave.sh"
    The status should be success
  End

  It "counts local qdrant shards on the leaving peer before remove"
    When run sh -c "grep -Fq '(if ((' ../scripts/qdrant-member-leave.sh && grep -Fq 'else empty end),' ../scripts/qdrant-member-leave.sh && grep -Fq 'remote_shards[]?' ../scripts/qdrant-member-leave.sh"
    The status should be success
  End

  It "makes qdrant member leave retry-safe when the leaving pod is already gone"
    When run sh -c "grep -q 'leave_peer_id=.*current_cluster_info' ../scripts/qdrant-member-leave.sh && ! grep -q 'qdrant_curl -s \\${leave_peer_uri}/cluster' ../scripts/qdrant-member-leave.sh"
    The status should be success
  End

  It "injects the current pod name into qdrant member leave actions"
    When run sh -c "sed -n '/memberLeave:/,/logConfigs:/p' ../templates/cmpd.yaml | grep -q 'name: CURRENT_POD_NAME' && sed -n '/memberLeave:/,/logConfigs:/p' ../templates/cmpd.yaml | grep -q 'fieldPath: metadata.name'"
    The status should be success
  End

  It "falls back to HOSTNAME when qdrant member leave action env omits the current pod name"
    When run grep -c 'CURRENT_POD_NAME="${CURRENT_POD_NAME:-${HOSTNAME:-}}"' ../scripts/qdrant-member-leave.sh
    The status should be success
    The output should eq 1
  End

  It "bounds and retries qdrant member leave long enough for shard migration"
    When run sh -c "sed -n '/memberLeave:/,/logConfigs:/p' ../templates/cmpd.yaml | grep -q 'timeoutSeconds: 60' && sed -n '/memberLeave:/,/logConfigs:/p' ../templates/cmpd.yaml | grep -q 'maxRetries: 120' && sed -n '/memberLeave:/,/logConfigs:/p' ../templates/cmpd.yaml | grep -q 'retryInterval: 5'"
    The status should be success
  End

  It "validates qdrant peer count during lifecycle e2e"
    When run grep -c 'wait_for_qdrant_peer_count' ../../../examples/qdrant/test/qdrant_api_key_backup_restore_e2e.sh
    The status should be success
    The output should eq 3
  End

  It "covers qdrant member leave shard-drain success and data consistency in live e2e"
    When run sh -c "test -f ../../../examples/qdrant/test/qdrant_member_leave_shard_safety_e2e.sh && grep -q 'wait_for_leaving_peer_with_shards' ../../../examples/qdrant/test/qdrant_member_leave_shard_safety_e2e.sh && grep -q 'wait_for_scale_in_succeed' ../../../examples/qdrant/test/qdrant_member_leave_shard_safety_e2e.sh && grep -q 'assert_points_consistent' ../../../examples/qdrant/test/qdrant_member_leave_shard_safety_e2e.sh && ! grep -q 'assert_scale_in_not_succeed' ../../../examples/qdrant/test/qdrant_member_leave_shard_safety_e2e.sh && grep -q -- '--wait=false' ../../../examples/qdrant/test/qdrant_member_leave_shard_safety_e2e.sh"
    The status should be success
  End

  It "supports the latest qdrant patch release for every minor after 1.10"
    When run sh -c "grep -q '\"1.11.5\"' ../values.yaml && grep -q '\"1.12.6\"' ../values.yaml && grep -q '\"1.13.6\"' ../values.yaml && grep -q '\"1.14.1\"' ../values.yaml && grep -q '\"1.15.5\"' ../values.yaml && grep -q '\"1.16.3\"' ../values.yaml && grep -q '\"1.17.1\"' ../values.yaml && grep -q '\"1.18.2\"' ../values.yaml"
    The status should be success
  End

  It "does not keep superseded qdrant patch releases after 1.10"
    When run sh -c "! grep -q '\"1.13.4\"' ../values.yaml && ! grep -q '\"1.15.4\"' ../values.yaml"
    The status should be success
  End

  It "provides qdrant TLS and API-key cluster examples"
    When run sh -c "test -f ../../../examples/qdrant/cluster-with-api-key.yaml && test -f ../../../examples/qdrant/cluster-with-tls.yaml && test -f ../../../examples/qdrant/cluster-with-tls-and-api-key.yaml"
    The status should be success
  End

  It "documents qdrant TLS and API-key examples"
    When run sh -c "grep -q 'cluster-with-api-key.yaml' ../../../examples/qdrant/README.md && grep -q 'cluster-with-tls.yaml' ../../../examples/qdrant/README.md && grep -q 'cluster-with-tls-and-api-key.yaml' ../../../examples/qdrant/README.md"
    The status should be success
  End
End
