# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_sentinel_start_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

# Contract under test: valkey-sentinel-start.sh PATCHES the dynamic part of a
# sentinel conf and starts the process.  Registering the monitor stanza is not
# its job (that belongs to valkey-register-to-sentinel.sh /
# valkey-sentinel-member-join.sh / post-restore-sentinel.sh, each covered by its
# own spec), so the cases below cover what this script actually owns:
#   - create_initial_conf_if_needed() — first boot creates an empty conf
#   - rebuild_sentinel_acl()          — (re)writes the default ACL user, keeping
#                                       the other users of the ACL file
#   - append_dynamic_conf()           — announce address, port / TLS, auth lines
#   - extract_lb_host_by_svc_name()   — LoadBalancer announce lookup
Describe "Valkey Sentinel Start Bash Script Tests"
  Include $common_library_file
  Include ../scripts/valkey-sentinel-start.sh

  sentinel_start_script="../scripts/valkey-sentinel-start.sh"

  init() {
    ut_mode="true"
    export SENTINEL_SERVICE_PORT="26379"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SENTINEL_SERVICE_PORT
  }
  AfterAll "cleanup"

  # Every case works on a throw-away conf / ACL pair: the script resolves these
  # globals when it is sourced, so they are reassigned here.
  setup() {
    conf_dir="$(mktemp -d)"
    SENTINEL_CONF_DIR="${conf_dir}"
    SENTINEL_CONF="${conf_dir}/redis-sentinel.conf"
    SENTINEL_ACL="${conf_dir}/users.acl"
    sentinel_port="26379"
    unset TLS_ENABLED TLS_MOUNT_PATH SENTINEL_PASSWORD SENTINEL_USER
    unset VALKEY_SENTINEL_ADVERTISED_PORT VALKEY_SENTINEL_LB_ADVERTISED_HOST
    unset CURRENT_POD_NAME CURRENT_POD_HOST_IP SENTINEL_POD_FQDN_LIST
  }
  Before "setup"

  teardown() {
    rm -rf "${conf_dir}"
    unset SENTINEL_CONF_DIR SENTINEL_CONF SENTINEL_ACL
    unset TLS_ENABLED TLS_MOUNT_PATH SENTINEL_PASSWORD SENTINEL_USER
    unset VALKEY_SENTINEL_ADVERTISED_PORT VALKEY_SENTINEL_LB_ADVERTISED_HOST
    unset CURRENT_POD_NAME CURRENT_POD_HOST_IP SENTINEL_POD_FQDN_LIST
  }
  After "teardown"

  # The FQDN list entries must start with the pod name — that is how
  # get_target_pod_fqdn_from_pod_fqdn_vars() resolves the pod's own address.
  sentinel_fqdn_list="mycluster-valkey-sentinel-0.headless.ns.svc,mycluster-valkey-sentinel-1.headless.ns.svc"

  Describe "create_initial_conf_if_needed()"
    It "creates an empty sentinel conf on first boot"
      create_and_report() {
        # The script logs "First boot — creating empty sentinel conf." on stdout.
        create_initial_conf_if_needed >/dev/null || return 1
        if [ ! -f "${SENTINEL_CONF}" ]; then
          printf 'missing'
        elif [ -s "${SENTINEL_CONF}" ]; then
          printf 'non-empty'
        else
          printf 'empty'
        fi
      }
      When call create_and_report
      The status should be success
      The stdout should eq "empty"
    End

    It "keeps the monitor stanza of an existing conf"
      printf 'sentinel monitor mycluster-valkey 10.0.0.1 6379 2\n' > "${SENTINEL_CONF}"
      When call create_initial_conf_if_needed
      The status should be success
      The contents of file "${SENTINEL_CONF}" should include "sentinel monitor mycluster-valkey 10.0.0.1 6379 2"
    End
  End

  Describe "rebuild_sentinel_acl()"
    It "writes a nopass default user when no sentinel password is configured"
      export SENTINEL_PASSWORD=""
      When call rebuild_sentinel_acl
      The status should be success
      The contents of file "${SENTINEL_ACL}" should include "user default on nopass ~* &* +@all"
    End

    It "keeps the non-default users already present in the ACL file"
      export SENTINEL_PASSWORD=""
      printf 'user app on #deadbeef ~* &* +@all\nuser default on nopass ~* &* +@all\n' > "${SENTINEL_ACL}"
      rebuild_and_report() {
        rebuild_sentinel_acl || return 1
        printf 'default-lines=%s\n' "$(grep -c '^user default on' "${SENTINEL_ACL}")"
        grep -F 'user app on #deadbeef' "${SENTINEL_ACL}"
      }
      When call rebuild_and_report
      The status should be success
      The stdout should include "default-lines=1"
      The stdout should include "user app on #deadbeef ~* &* +@all"
    End

    It "hashes the sentinel password into the default user line"
      # sha256sum is only guaranteed on the Linux CI image; a macOS dev host has
      # shasum instead, so the case is skipped rather than failing there.
      Skip if "sha256sum is unavailable on this host" test -z "$(command -v sha256sum || true)"
      export SENTINEL_PASSWORD="sentinelpass"
      When call rebuild_sentinel_acl
      The status should be success
      The contents of file "${SENTINEL_ACL}" should include "user default on #"
      The contents of file "${SENTINEL_ACL}" should include "~* &* +@all"
    End
  End

  Describe "append_dynamic_conf() — announce address"
    It "announces the pod FQDN and enables hostname resolution without an advertised mapping"
      export SENTINEL_POD_FQDN_LIST="${sentinel_fqdn_list}"
      export CURRENT_POD_NAME="mycluster-valkey-sentinel-1"
      When call append_dynamic_conf
      The status should be success
      The contents of file "${SENTINEL_CONF}" should include "sentinel announce-ip mycluster-valkey-sentinel-1.headless.ns.svc"
      The contents of file "${SENTINEL_CONF}" should include "sentinel resolve-hostnames yes"
      The contents of file "${SENTINEL_CONF}" should include "sentinel announce-hostnames yes"
    End

    It "prefers the per-pod NodePort when the advertised mapping exists"
      export VALKEY_SENTINEL_ADVERTISED_PORT="valkey-sentinel-advertised-0:30584,valkey-sentinel-advertised-1:31294"
      export CURRENT_POD_NAME="mycluster-valkey-sentinel-1"
      export CURRENT_POD_HOST_IP="10.0.0.9"
      When call append_dynamic_conf
      The status should be success
      The contents of file "${SENTINEL_CONF}" should include "sentinel announce-ip 10.0.0.9"
      The contents of file "${SENTINEL_CONF}" should include "sentinel announce-port 31294"
      The contents of file "${SENTINEL_CONF}" should not include "resolve-hostnames"
    End

    It "fails closed when the pod FQDN cannot be resolved"
      # No advertised mapping and no entry for this pod in the FQDN list: an
      # announced sentinel with an empty address breaks the gossip between
      # sentinels, so refusing to start beats starting unaddressable.
      export SENTINEL_POD_FQDN_LIST="mycluster-valkey-sentinel-0.headless.ns.svc"
      export CURRENT_POD_NAME="mycluster-valkey-sentinel-1"
      unresolvable() {
        local rc=0
        ( append_dynamic_conf ) 2>&1 || rc=$?
        printf 'rc=%s' "${rc}"
      }
      When call unresolvable
      The stdout should include "cannot resolve FQDN for mycluster-valkey-sentinel-1"
      The stdout should include "rc=1"
    End
  End

  Describe "append_dynamic_conf() — port, TLS and auth"
    It "writes the plaintext port when TLS is disabled"
      export SENTINEL_POD_FQDN_LIST="${sentinel_fqdn_list}"
      export CURRENT_POD_NAME="mycluster-valkey-sentinel-0"
      export TLS_ENABLED="false"
      When call append_dynamic_conf
      The status should be success
      The contents of file "${SENTINEL_CONF}" should include "port 26379"
      The contents of file "${SENTINEL_CONF}" should not include "tls-port"
    End

    It "switches to a TLS-only listener when TLS_ENABLED is true"
      export SENTINEL_POD_FQDN_LIST="${sentinel_fqdn_list}"
      export CURRENT_POD_NAME="mycluster-valkey-sentinel-0"
      export TLS_ENABLED="true"
      export TLS_MOUNT_PATH="/etc/pki/tls"
      When call append_dynamic_conf
      The status should be success
      The contents of file "${SENTINEL_CONF}" should include "port 0"
      The contents of file "${SENTINEL_CONF}" should include "tls-port 26379"
      The contents of file "${SENTINEL_CONF}" should include "tls-cert-file /etc/pki/tls/tls.crt"
      The contents of file "${SENTINEL_CONF}" should include "tls-key-file /etc/pki/tls/tls.key"
      The contents of file "${SENTINEL_CONF}" should include "tls-ca-cert-file /etc/pki/tls/ca.crt"
      The contents of file "${SENTINEL_CONF}" should include "tls-auth-clients no"
      The contents of file "${SENTINEL_CONF}" should include "tls-replication yes"
    End

    It "writes the sentinel auth lines only when a sentinel password is set"
      export SENTINEL_POD_FQDN_LIST="${sentinel_fqdn_list}"
      export CURRENT_POD_NAME="mycluster-valkey-sentinel-0"
      export SENTINEL_PASSWORD="sentinelpass"
      When call append_dynamic_conf
      The status should be success
      The contents of file "${SENTINEL_CONF}" should include "sentinel sentinel-user default"
      The contents of file "${SENTINEL_CONF}" should include "sentinel sentinel-pass sentinelpass"
      The contents of file "${SENTINEL_CONF}" should include "aclfile ${SENTINEL_ACL}"
    End

    It "omits the sentinel auth lines when no sentinel password is set"
      export SENTINEL_POD_FQDN_LIST="${sentinel_fqdn_list}"
      export CURRENT_POD_NAME="mycluster-valkey-sentinel-0"
      unset SENTINEL_PASSWORD
      When call append_dynamic_conf
      The status should be success
      The contents of file "${SENTINEL_CONF}" should not include "sentinel sentinel-user"
      The contents of file "${SENTINEL_CONF}" should not include "sentinel sentinel-pass"
    End
  End

  Describe "extract_lb_host_by_svc_name()"
    It "returns the LoadBalancer host of the requested service"
      export VALKEY_SENTINEL_LB_ADVERTISED_HOST="s-0:203.0.113.7,s-1:203.0.113.8"
      When call extract_lb_host_by_svc_name "s-1"
      The status should be success
      The stdout should eq "203.0.113.8"
    End

    It "returns nothing for an unknown service"
      export VALKEY_SENTINEL_LB_ADVERTISED_HOST="s-0:203.0.113.7"
      When call extract_lb_host_by_svc_name "s-9"
      The status should be success
      The stdout should eq ""
    End
  End

  Describe "monitor registration contract"
    It "does not register a monitor itself"
      # Registration lives in valkey-register-to-sentinel.sh (data-side
      # postProvision), valkey-sentinel-member-join.sh (scale-out) and
      # post-restore-sentinel.sh; the start script only patches its own conf so
      # the monitor stanza written by Valkey — and the epoch it carries — is
      # never overwritten on restart.
      When call bash -c "grep -vE '^[[:space:]]*#' '${sentinel_start_script}' | grep -cE 'SENTINEL [Mm][Oo][Nn][Ii][Tt][Oo][Rr]'"
      The status should be failure
      The stdout should eq "0"
    End
  End
End
