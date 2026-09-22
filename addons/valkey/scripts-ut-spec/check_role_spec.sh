# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "check_role_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

# Contract under test (roleProbe stdout): exactly ONE role token, `primary` or
# `secondary`, or NOTHING when no Sentinel answered at all.  The controller
# looks the whole stdout up in the ComponentDefinition's roles[] map; a match
# sets the pod's role label, anything else (an extra version token, a sentence,
# an empty string) makes it DELETE the label.
#
# Role resolution order — majority vote over the whole Sentinel fleet:
#   1. `SENTINEL GET-MASTER-ADDR-BY-NAME <VALKEY_COMPONENT_NAME>` on every
#      Sentinel: the address (two lines: host + port) reported by the most
#      Sentinels is the cluster master.  This pod is primary iff that address is
#      its own announced address, else secondary.
#   2. Every Sentinel query failed (unreachable / credentials refused) → print
#      nothing.
#   3. At least one Sentinel answered but none knows a master → local
#      `INFO replication` decides (master → primary, slave → secondary, anything
#      else → non-zero exit so the sample is skipped).
Describe "Valkey Check-Role Bash Script Tests"
  Include $common_library_file
  Include ../scripts/check-role.sh

  check_role_script="../scripts/check-role.sh"

  init() {
    ut_mode="true"
    export SERVICE_PORT="6379"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SERVICE_PORT
  }
  AfterAll "cleanup"

  Describe "build_cli_cmd()"
    _cli_cmd_as_string() {
      build_cli_cmd
      printf '%s' "${cli_cmd[*]}"
    }

    Context "without password or TLS"
      setup() {
        unset VALKEY_DEFAULT_PASSWORD VALKEY_CLI_TLS_ARGS
        export SERVICE_PORT="6379"
      }
      Before "setup"

      It "builds a basic valkey-cli command against loopback"
        When call _cli_cmd_as_string
        The status should be success
        The stdout should include "-h 127.0.0.1"
        The stdout should include "-p 6379"
        The stdout should include "--no-auth-warning"
      End
    End

    Context "with password"
      setup() {
        export VALKEY_DEFAULT_PASSWORD="datapass"
        unset VALKEY_CLI_TLS_ARGS
      }
      Before "setup"

      It "includes -a flag"
        When call _cli_cmd_as_string
        The status should be success
        The stdout should include "-a datapass"
      End
    End

    Context "with TLS"
      setup() {
        unset VALKEY_DEFAULT_PASSWORD
        export VALKEY_CLI_TLS_ARGS="--tls --cacert /etc/pki/tls/ca.crt"
      }
      Before "setup"

      It "appends the TLS flags built by the component vars"
        When call _cli_cmd_as_string
        The status should be success
        The stdout should include "--tls"
        The stdout should include "/etc/pki/tls/ca.crt"
      End
    End

    teardown() {
      unset VALKEY_DEFAULT_PASSWORD VALKEY_CLI_TLS_ARGS
    }
    After "teardown"
  End

  Describe "parse_role_line()"
    It "returns role:master when the server reports master"
      When call parse_role_line $'# Replication\r\nrole:master\r\nconnected_slaves:1\r\n'
      The status should be success
      The stdout should eq "role:master"
    End

    It "returns role:slave when the server reports slave"
      When call parse_role_line $'# Replication\r\nrole:slave\r\nmaster_host:10.0.0.1\r\n'
      The status should be success
      The stdout should eq "role:slave"
    End

    It "returns nothing when INFO is empty (pod startup window)"
      When call parse_role_line ""
      The status should be success
      The stdout should eq ""
    End
  End

  Describe "collect_sentinel_targets() — headless service first, pods after"
    It "asks the Sentinel headless service before the individual pods"
      export SENTINEL_HEADLESS_SVC_HOST="sentinel-headless.ns.svc"
      export SENTINEL_POD_FQDN_LIST="s-0.h.ns.svc,s-1.h.ns.svc"
      When call collect_sentinel_targets
      The status should be success
      The line 1 of stdout should eq "sentinel-headless.ns.svc"
      The line 2 of stdout should eq "s-0.h.ns.svc"
      The line 3 of stdout should eq "s-1.h.ns.svc"
    End

    It "drops empty entries and duplicates"
      export SENTINEL_HEADLESS_SVC_HOST="sentinel-headless.ns.svc"
      export SENTINEL_POD_FQDN_LIST=",s-0.h.ns.svc,,sentinel-headless.ns.svc"
      When call collect_sentinel_targets
      The status should be success
      The line 1 of stdout should eq "sentinel-headless.ns.svc"
      The line 2 of stdout should eq "s-0.h.ns.svc"
      The lines of stdout should eq 2
    End

    It "uses only the pod list when the headless service is not rendered"
      unset SENTINEL_HEADLESS_SVC_HOST
      export SENTINEL_POD_FQDN_LIST="s-0.h.ns.svc"
      When call collect_sentinel_targets
      The status should be success
      The line 1 of stdout should eq "s-0.h.ns.svc"
    End
  End

  Describe "sentinel_query_master_addr() — one Sentinel's answer"
    setup() {
      unset VALKEY_CLI_TLS_ARGS
      export SENTINEL_PASSWORD=""
      sentinel_master_name="mycluster-valkey"
      sentinel_port="26379"
      port="6379"
      # `timeout` is exercised as a pass-through, `valkey-cli` is mocked.
      timeout() { shift; "$@"; }
      valkey-cli() {
        case "${FAKE_SENTINEL_MODE}" in
          good)
            printf '10.0.0.9\n31281\n'
            ;;
          no_master)
            # Verified behaviour of a live Sentinel: an unknown master name
            # yields an EMPTY reply and exit code 0.
            return 0
            ;;
          unreachable)
            return 1
            ;;
          auth_refused)
            printf 'NOAUTH Authentication required.\n'
            ;;
        esac
      }
    }
    Before "setup"

    teardown() {
      unset FAKE_SENTINEL_MODE SENTINEL_PASSWORD
    }
    After "teardown"

    It "exports the host and the port of the reported master"
      export FAKE_SENTINEL_MODE="good"
      When call sentinel_query_master_addr "sentinel-headless.ns.svc"
      The status should be success
      The variable SENTINEL_ADDR_HOST should eq "10.0.0.9"
      The variable SENTINEL_ADDR_PORT should eq "31281"
    End

    It "reports a reachable Sentinel that knows no master as no_master"
      export FAKE_SENTINEL_MODE="no_master"
      When call sentinel_query_master_addr "sentinel-headless.ns.svc"
      The status should be failure
      The variable SENTINEL_ADDR_DROP should eq "no_master"
    End

    It "reports a connection failure as unreachable"
      export FAKE_SENTINEL_MODE="unreachable"
      When call sentinel_query_master_addr "sentinel-headless.ns.svc"
      The status should be failure
      The variable SENTINEL_ADDR_DROP should eq "unreachable"
    End

    It "reports refused credentials as auth_refused"
      export FAKE_SENTINEL_MODE="auth_refused"
      When call sentinel_query_master_addr "sentinel-headless.ns.svc"
      The status should be failure
      The variable SENTINEL_ADDR_DROP should eq "auth_refused"
    End
  End

  Describe "vote_master_addr() — most reported address wins"
    It "picks the address the majority reported"
      votes() { vote_master_addr "${1}"; }
      When call votes $'10.0.0.9:31281\n10.0.0.123:6379\n10.0.0.9:31281\n'
      The status should be success
      The stdout should eq "10.0.0.9:31281"
    End

    It "returns nothing when no Sentinel answered with an address"
      votes() { vote_master_addr "${1}"; }
      When call votes ""
      The status should be success
      The stdout should eq ""
    End

    It "breaks a tie deterministically (lexicographically smallest)"
      votes() { vote_master_addr "${1}"; }
      When call votes $'10.0.0.9:31281\n10.0.0.123:6379\n'
      The status should be success
      The stdout should eq "10.0.0.123:6379"
    End
  End

  Describe "read_own_announce_addr() — this pod's advertised address"
    setup() {
      CONF_DIR="$(mktemp -d)"
      runtime_conf="${CONF_DIR}/valkey.conf"
    }
    Before "setup"

    teardown() {
      rm -rf "${CONF_DIR}"
      runtime_conf="/etc/valkey/valkey.conf"
    }
    After "teardown"

    It "reads the quoted announce pair written by valkey-start.sh"
      printf 'port 0\ntls-port 6379\nreplica-announce-ip "10.0.0.9"\nreplica-announce-port 31281\n' > "${runtime_conf}"
      When call read_own_announce_addr
      The status should be success
      The variable announce_host should eq "10.0.0.9"
      The variable announce_port should eq "31281"
    End

    It "accepts an unquoted announce pair too"
      printf 'replica-announce-ip valkey-0.headless.ns.svc\nreplica-announce-port 6379\n' > "${runtime_conf}"
      When call read_own_announce_addr
      The status should be success
      The variable announce_host should eq "valkey-0.headless.ns.svc"
      The variable announce_port should eq "6379"
    End

    It "leaves the pair empty when the conf has no announce lines"
      printf 'port 6379\n' > "${runtime_conf}"
      When call read_own_announce_addr
      The status should be success
      The variable announce_host should eq ""
      The variable announce_port should eq ""
    End

    It "leaves the pair empty when the conf is missing"
      runtime_conf="${CONF_DIR}/does-not-exist.conf"
      When call read_own_announce_addr
      The status should be success
      The variable announce_host should eq ""
    End
  End

  Describe "is_own_master_addr() — does the voted address belong to this pod?"
    setup() {
      export CURRENT_POD_NAME="mycluster-valkey-1"
      export KB_POD_FQDN="mycluster-valkey-1.mycluster-valkey-headless.default.svc.cluster.local"
      unset announce_host announce_port
    }
    Before "setup"

    teardown() {
      unset CURRENT_POD_NAME KB_POD_FQDN announce_host announce_port
    }
    After "teardown"

    It "matches the pod's own FQDN exactly"
      When call is_own_master_addr "mycluster-valkey-1.mycluster-valkey-headless.default.svc.cluster.local" "6379"
      The status should be success
    End

    It "matches a name derived from <pod>.<component>"
      When call is_own_master_addr "mycluster-valkey-1.mycluster-valkey-headless" "6379"
      The status should be success
    End

    It "matches this pod's announced NodePort pair"
      announce_host="10.0.0.9"
      announce_port="31281"
      When call is_own_master_addr "10.0.0.9" "31281"
      The status should be success
    End

    It "does not match another pod"
      announce_host="10.0.0.9"
      announce_port="31281"
      When call is_own_master_addr "10.0.0.123" "6379"
      The status should be failure
    End

    It "does not match a shared node IP with a different NodePort"
      # Several pods can live on the same node, so the port is what identifies
      # the pod in NodePort mode.
      announce_host="10.0.0.9"
      announce_port="31281"
      When call is_own_master_addr "10.0.0.9" "30584"
      The status should be failure
    End

    It "does not treat an empty pod name as a wildcard"
      # Guard against the `${CURRENT_POD_NAME}.*` pattern degenerating into `.*`
      # when the env var is missing: every pod would call itself the master.
      unset CURRENT_POD_NAME
      When call is_own_master_addr "10.0.0.123" "6379"
      The status should be failure
    End
  End

  Describe "decide_role() — vote result vs local fallback"
    It "is primary when the voted address is this pod's own"
      CURRENT_POD_NAME="mycluster-valkey-1"
      KB_POD_FQDN="mycluster-valkey-1.mycluster-valkey-headless.default.svc.cluster.local"
      voted_host="mycluster-valkey-1.mycluster-valkey-headless.default.svc.cluster.local"
      voted_port="6379"
      When call decide_role "role:slave" "voted" "vote"
      The status should be success
      The stdout should eq "primary"
    End

    It "is secondary when the voted address belongs to another pod"
      # The vote outranks local INFO: this pod's engine still says master, but
      # the fleet elected somebody else.
      CURRENT_POD_NAME="mycluster-valkey-1"
      KB_POD_FQDN=""
      voted_host="10.0.0.123"
      voted_port="6379"
      When call decide_role "role:master" "voted" "vote"
      The status should be success
      The stdout should eq "secondary"
    End

    It "prints exactly one token — a second word would drop the role label"
      CURRENT_POD_NAME="mycluster-valkey-1"
      voted_host="10.0.0.123"
      voted_port="6379"
      single_token() {
        local out
        out=$(decide_role "role:master" "voted" "vote")
        case "${out}" in
          "") printf 'empty' ;;
          *[[:space:]]*) printf 'has-whitespace' ;;
          *) printf 'single:%s' "${out}" ;;
        esac
      }
      When call single_token
      The status should be success
      The stdout should eq "single:secondary"
    End

    It "maps a local master to primary when no Sentinel knows a master"
      When call decide_role "role:master" "local_authority" "no_master"
      The status should be success
      The stdout should eq "primary"
    End

    It "maps a local slave to secondary on that bootstrap path too"
      When call decide_role "role:slave" "local_authority" "no_master"
      The status should be success
      The stdout should eq "secondary"
    End

    It "exits non-zero on an unknown local role in the bootstrap path"
      # `exit 1` must run in a subshell, otherwise it would abort the example.
      decide_role_exit_status() {
        local rc=0
        ( decide_role "$@" ) >/dev/null 2>&1 || rc=$?
        printf '%s' "${rc}"
      }
      When call decide_role_exit_status "role:loading" "local_authority" "no_master"
      The status should be success
      The stdout should eq "1"
    End

    It "prints the unknown-role diagnostic on stderr"
      decide_role_stderr() {
        # `|| true`: the subshell exits 1 on purpose, the example must not.
        ( decide_role "role:loading" "local_authority" "no_master" ) 2>&1 >/dev/null || true
      }
      When call decide_role_stderr
      The status should be success
      The stdout should include "unknown role"
    End

    It "reports secondary when no Sentinel answered"
      # Nobody could tell us who the master is, so this pod must not claim
      # primary.  It reports secondary (rather than printing nothing) because
      # the controller DELETES the role label when the probe output does not
      # match a role name, and a label-less pod blocks the rolling update of the
      # whole component.
      no_authority_role() {
        local out
        out=$(decide_role "role:master" "no_authority" "unreachable" 2>/dev/null)
        printf 'token=[%s]' "${out}"
      }
      When call no_authority_role
      The status should be success
      The stdout should eq "token=[secondary]"
    End

    It "keeps the output a single role token when no Sentinel answered"
      single_token_no_authority() {
        local out
        out=$(decide_role "role:master" "no_authority" "unreachable")
        case "${out}" in
          "") printf 'empty' ;;
          *[[:space:]]*) printf 'has-whitespace' ;;
          *) printf 'single:%s' "${out}" ;;
        esac
      }
      When call single_token_no_authority
      The status should be success
      The stdout should eq "single:secondary"
    End
  End

  Describe "__check_role_main() — end to end"
    # `valkey-cli` is mocked; it runs inside command substitutions, so every
    # answer is derived from the arguments — the host in the args selects
    # reachable / unreachable / disagreeing Sentinels.
    setup() {
      unset VALKEY_CLI_TLS_ARGS
      export SENTINEL_PASSWORD=""
      export VALKEY_DEFAULT_PASSWORD=""
      export VALKEY_COMPONENT_NAME="mycluster-valkey"
      export SERVICE_PORT="6379"
      export SENTINEL_HEADLESS_SVC_HOST=""
      export SENTINEL_POD_FQDN_LIST="sentinel-mine.h.ns.svc"
      export CURRENT_POD_NAME="mycluster-valkey-1"
      export KB_POD_FQDN="mycluster-valkey-1.mycluster-valkey-headless.default.svc.cluster.local"
      export KB_CLUSTER_COMP_NAME="mycluster-valkey"
      export KP_LOCAL_ROLE="role:master"
      export KP_OWN_HOST="10.0.0.9"
      export KP_OWN_PORT="31281"
      # Runtime conf: this pod announces <node-ip>:<NodePort> (NodePort mode).
      # Built in the hook — calling a Describe-scope helper from inside an
      # example body is not supported by shellspec.
      CONF_DIR="$(mktemp -d)"
      runtime_conf="${CONF_DIR}/valkey.conf"
      export VALKEY_CONF_RUNTIME="${runtime_conf}"
      printf 'port 0\nreplica-announce-ip "%s"\nreplica-announce-port %s\n' \
        "${KP_OWN_HOST}" "${KP_OWN_PORT}" > "${runtime_conf}"
      # The script resolves these when it is sourced, so set them here too.
      sentinel_master_name="mycluster-valkey"
      sentinel_port="26379"
      sentinel_max_attempts="0"
      timeout() { shift; "$@"; }
      valkey-cli() {
        case "$*" in
          *"info replication"*) printf '%s\n' "${KP_LOCAL_ROLE}" ;;
          *"get-master-addr-by-name"*)
            case "$*" in
              *"sentinel-down"*) return 1 ;;
              *"sentinel-nil"*)  return 0 ;;
              *"sentinel-mine"*) printf '%s\n%s\n' "${KP_OWN_HOST}" "${KP_OWN_PORT}" ;;
              *"sentinel-fqdn"*) printf '%s\n6379\n' "${KB_POD_FQDN}" ;;
              *) printf '10.0.0.123\n6379\n' ;;
            esac
            ;;
        esac
      }
    }
    Before "setup"

    teardown() {
      rm -rf "${CONF_DIR}"
      unset SENTINEL_PASSWORD VALKEY_DEFAULT_PASSWORD VALKEY_COMPONENT_NAME
      unset SENTINEL_HEADLESS_SVC_HOST SENTINEL_POD_FQDN_LIST
      unset CURRENT_POD_NAME KB_POD_FQDN KB_CLUSTER_COMP_NAME VALKEY_CONF_RUNTIME
      unset KP_LOCAL_ROLE KP_OWN_HOST KP_OWN_PORT
    }
    After "teardown"

    It "is primary when the whole fleet reports this pod's address"
      export SENTINEL_POD_FQDN_LIST="sentinel-mine.h.ns.svc,sentinel-mine-2.h.ns.svc"
      When call __check_role_main
      The status should be success
      The stdout should eq "primary"
    End

    It "is secondary when the fleet reports another pod's address"
      # The regression this rewrite targets: a never-rolled pod whose engine
      # still says master must not claim primary while the fleet elected the
      # already-rolled one.
      export SENTINEL_POD_FQDN_LIST="sentinel-other.h.ns.svc"
      When call __check_role_main
      The status should be success
      The stdout should eq "secondary"
    End

    It "follows the majority when the fleet disagrees"
      export SENTINEL_POD_FQDN_LIST="sentinel-other-a.h.ns.svc,sentinel-other-b.h.ns.svc,sentinel-mine.h.ns.svc"
      When call __check_role_main
      The status should be success
      The stdout should eq "secondary"
    End

    It "recognises this pod when the fleet reports its FQDN"
      # Pod-FQDN announce mode: matched by name, no announce pair needed.
      export SENTINEL_POD_FQDN_LIST="sentinel-fqdn.h.ns.svc"
      export VALKEY_CONF_RUNTIME="${CONF_DIR}/missing.conf"
      When call __check_role_main
      The status should be success
      The stdout should eq "primary"
    End

    It "reports secondary when no Sentinel answered"
      export SENTINEL_POD_FQDN_LIST="sentinel-down.h.ns.svc"
      no_authority_role() {
        local out
        out=$(__check_role_main 2>/dev/null)
        printf 'token=[%s]' "${out}"
      }
      When call no_authority_role
      The status should be success
      The stdout should eq "token=[secondary]"
    End

    It "ignores the local role when no Sentinel answered"
      # The local engine still says master, but without a Sentinel vote this pod
      # has no confirmed role — and it reports a token the controller can map so
      # the pod keeps its role label.
      export SENTINEL_POD_FQDN_LIST="sentinel-down.h.ns.svc"
      export KP_LOCAL_ROLE="role:loading"
      When call __check_role_main
      The status should be success
      The stdout should eq "secondary"
    End

    It "falls back to the local role when every Sentinel answers 'no master'"
      export SENTINEL_POD_FQDN_LIST="sentinel-nil.h.ns.svc"
      When call __check_role_main
      The status should be success
      The stdout should eq "primary"
    End

    It "falls back to secondary for a local slave on that path"
      export SENTINEL_POD_FQDN_LIST="sentinel-nil.h.ns.svc"
      export KP_LOCAL_ROLE="role:slave"
      When call __check_role_main
      The status should be success
      The stdout should eq "secondary"
    End

    It "still falls back locally when only some Sentinels answered without a master"
      # "Answered but knows no master" is stronger evidence than silence, so one
      # reachable Sentinel is enough to use the local fallback.
      export SENTINEL_POD_FQDN_LIST="sentinel-nil.h.ns.svc,sentinel-down.h.ns.svc"
      When call __check_role_main
      The status should be success
      The stdout should eq "primary"
    End

    It "uses the local authority when no Sentinel component is configured"
      export SENTINEL_POD_FQDN_LIST=""
      When call __check_role_main
      The status should be success
      The stdout should eq "primary"
    End

    It "honours the SENTINEL_MAX_ATTEMPTS cap"
      # 1 is enough to test the cap: only the headless service is asked, and it
      # is the unreachable one, so the vote never sees the reachable pod.
      export SENTINEL_HEADLESS_SVC_HOST="sentinel-down.h.ns.svc"
      export SENTINEL_POD_FQDN_LIST="sentinel-mine.h.ns.svc"
      sentinel_max_attempts="1"
      capped() {
        local out
        out=$(__check_role_main 2>/dev/null)
        printf 'token=[%s]' "${out}"
      }
      When call capped
      The status should be success
      The stdout should eq "token=[secondary]"
    End
  End

  Describe "production script structure (Sentinel vote first)"
    It "asks every Sentinel for the master address by our master name"
      When call grep -F 'sentinel get-master-addr-by-name "${sentinel_master_name}"' "${check_role_script}"
      The status should be success
      The stdout should include "get-master-addr-by-name"
    End

    It "uses the Sentinel headless service as the first query target"
      When call grep -F 'SENTINEL_HEADLESS_SVC_HOST' "${check_role_script}"
      The status should be success
      The stdout should include "SENTINEL_HEADLESS_SVC_HOST"
    End

    It "asks all Sentinels by default (the vote wants every answer)"
      When call grep -F 'sentinel_max_attempts="${SENTINEL_MAX_ATTEMPTS:-0}"' "${check_role_script}"
      The status should be success
      The stdout should include "SENTINEL_MAX_ATTEMPTS:-0"
    End

    It "wraps each Sentinel attempt in a timeout"
      When call grep -E 'timeout 1 valkey-cli' "${check_role_script}"
      The status should be success
      The stdout should include "timeout 1"
    End

    It "passes the TLS args through to the Sentinel query"
      When call grep -F '${VALKEY_CLI_TLS_ARGS:-}' "${check_role_script}"
      The status should be success
      The stdout should include "VALKEY_CLI_TLS_ARGS"
    End

    It "adds the Sentinel auth flag only when a password is set"
      When call grep -F 'sentinel_auth_args=(-a "${SENTINEL_PASSWORD}")' "${check_role_script}"
      The status should be success
      The stdout should include "SENTINEL_PASSWORD"
    End

    It "counts the votes of the whole fleet"
      When call grep -F 'vote_master_addr' "${check_role_script}"
      The status should be success
      The stdout should include "vote_master_addr"
    End

    It "keeps no strict-majority quorum logic from the previous design"
      When call grep -E 'min_valid|quorum_keys|split_view' "${check_role_script}"
      The status should be failure
    End

    It "never emits a second (version) token"
      # The controller matches the WHOLE stdout against the role map, so an
      # epoch token would make it delete the pod's role label.
      When call grep -E 'engine_version|config-epoch' "${check_role_script}"
      The status should be failure
    End

    It "reads INFO replication exactly once per probe"
      # Comments mention the command as well, so only count code lines.
      When call bash -c "grep -vE '^[[:space:]]*#' '${check_role_script}' | grep -cE 'info replication'"
      The status should be success
      The stdout should eq "1"
    End
  End

  Describe "fork-safety contract — no pipeline parsing"
    # `valkey-cli ... info replication | grep ... | tr ...` spawns one child
    # per stage. When kbagent SIGKILLs this script for exceeding
    # timeoutSeconds, those children are reparented to kbagent's PID 1 (a Go
    # binary that does not reap unrelated children) and pile up as zombies.
    active_pipeline_count() {
      local count
      count=$(grep -vE '^[[:space:]]*(#|$)' "${check_role_script}" \
                | grep -cE '\|[[:space:]]+(grep|tr|awk|sed|cut)[[:space:]]' \
                2>/dev/null || true)
      printf "%s" "${count:-0}"
    }

    It "has no active code line piping INFO output through grep / tr / awk / sed / cut"
      When call active_pipeline_count
      The status should be success
      The stdout should eq "0"
    End

    It "uses the bash builtin while/read/case parse pattern"
      When call grep -E 'while[[:space:]]+IFS=[[:space:]]*read' "${check_role_script}"
      The status should be success
      The stdout should not eq ""
    End

    It "keeps a single-token output path for the local fallback"
      When call decide_role "role:slave" "local_authority" "no_master"
      The status should be success
      The stdout should eq "secondary"
    End
  End
End
