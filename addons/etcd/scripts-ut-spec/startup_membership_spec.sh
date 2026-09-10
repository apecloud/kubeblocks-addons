# shellcheck shell=bash
# shellcheck disable=SC2034,SC2286
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "startup_membership_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe 'Etcd startup registration barrier'
  Include ../scripts/startup-membership.sh
  setup() {
    test_dir=$(mktemp -d)
    DATA_DIR="$test_dir/data"
    default_conf="$test_dir/etcd.conf"
    CURRENT_POD_NAME=etcd-3
    PEER_FQDNS=etcd-0.headless,etcd-3.headless
    PEER_ENDPOINT=''
    scenario=present
    printf '%s\n' 'initial-cluster-state: existing' 'initial-advertise-peer-urls: http://etcd-3.headless:2380' 'initial-cluster: stale=from-pod-list' > "$default_conf"
    parse_config_value() { grep "^$1:" "$2" | cut -d: -f2- | xargs; }
    log() { echo "$1"; }
    error_exit() { echo "$1"; return 1; }
    get_endpoint_adapt_lb() { echo "$3"; }
    get_protocol() { echo http; }
    exec_etcdctl() {
      echo QUERY >> "$test_dir/queries"
      [ "$1" = http://etcd-0.headless:2379 ] || return 2
      [ "$2" = --dial-timeout=3s ] || return 2
      [ "$3" = --command-timeout=5s ] || return 2
      case "$scenario" in
        unavailable) return 1;;
        empty) return 0;;
        present|absent|registered_peer_missing)
          echo '1, started, etcd-0, http://etcd-0.headless:2380, http://etcd-0.headless:2379, false'
          if [ "$scenario" = present ]; then
            echo '3, unstarted, , http://etcd-3.headless:2380, , false'
          fi
          return 0
          ;;
        *) echo "Unknown membership mock scenario: $scenario" >&2; return 2;;
      esac
    }
    sleep() {
      case "$scenario" in
        absent) scenario=present;;
        *) SECONDS=$((SECONDS + 120));;
      esac
    }
  }
  cleanup() { rm -rf "$test_dir"; }
  BeforeEach setup
  AfterEach cleanup

  It 'waits for registration and builds the authoritative peer list'
    scenario=absent
    When call wait_for_member_registration
    The status should be success
    The output should include 'not ready'
    The output should include 'registration confirmed'
    The contents of file "$default_conf" should include 'initial-cluster: etcd-0=http://etcd-0.headless:2380,etcd-3=http://etcd-3.headless:2380'
    The contents of file "$default_conf" should not include stale
  End

  It 'does not mistake an empty partial WAL directory for a restart'
    mkdir -p "$DATA_DIR/member/wal"
    When call wait_for_member_registration
    The status should be success
    The output should include 'registration confirmed'
  End

  It 'bypasses the barrier for an initial new cluster'
    echo 'initial-cluster-state: new' > "$default_conf"
    When call wait_for_member_registration
    The status should be success
    The file "$test_dir/queries" should not be exist
  End

  It 'bypasses the barrier when persistent or restored WAL exists'
    mkdir -p "$DATA_DIR/member/wal"
    touch "$DATA_DIR/member/wal/0000000000000000-0000000000000000.wal"
    When call wait_for_member_registration
    The status should be success
    The output should include 'Existing WAL detected'
    The file "$test_dir/queries" should not be exist
  End

  It 'fails with a bounded timeout when membership is unavailable'
    scenario=unavailable
    When call wait_for_member_registration
    The status should be failure
    The output should include 'Timed out waiting'
    The output should include 'Last observed membership (query failed): <not observed>'
    The contents of file "$default_conf" should include 'stale=from-pod-list'
  End

  Context 'startup timeout diagnostics'
    Parameters
      registered_peer_missing '1, started, etcd-0, http://etcd-0.headless:2380'
      empty '<(empty)>'
    End
    It 'includes the last successful query even when registration is missing'
      scenario="$1"
      When call wait_for_member_registration
      The status should be failure
      The output should include 'Timed out waiting'
      The output should include "$2"
    End
  End

  It 'rejects an existing-mode join with no remote peer'
    PEER_FQDNS=etcd-3.headless
    When call wait_for_member_registration
    The status should be failure
    The output should include 'No existing peer'
  End

  Context 'unsafe membership snapshots'
    Parameters
      '3, started, wrong, http://etcd-3.headless:2380, http://wrong:2379, false'
      '3, started, etcd-3, http://wrong:2380, http://wrong:2379, false'
      '3, unstarted, , http://etcd-3.headless:2380, , true'
      '1, unstarted, , http://etcd-0.headless:2380, , false'
      'malformed'
      ''
    End
    It 'does not generate startup configuration'
      When call registered_initial_cluster "$1" http://etcd-3.headless:2380
      The status should be failure
      The output should be blank
    End
  End
End
