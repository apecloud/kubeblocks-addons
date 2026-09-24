# shellcheck shell=sh

Describe "MySQL Orchestrator role probe contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  verify_orc_role_probe_container() {
    helm template test "$(chart_path)" \
      --show-only templates/cmpd-mysql57-orc.yaml \
      --show-only templates/cmpd-mysql80-orc.yaml |
      awk '
        /^    roleProbe:$/ {
          probes++
          in_probe = 1
          next
        }
        in_probe && /^    [a-zA-Z][a-zA-Z0-9]*:$/ {
          in_probe = 0
        }
        in_probe && /^        container: mysql$/ {
          bindings++
        }
        END {
          if (probes != 2 || bindings != 2) {
            printf "unexpected ORC roleProbe container bindings: probes=%d bindings=%d (want 2/2)\n", probes, bindings > "/dev/stderr"
            exit 1
          }
        }
      '
  }

  verify_mount_dependent_action_containers() {
    helm template test "$(chart_path)" \
      --show-only templates/cmpd-mysql57-orc.yaml \
      --show-only templates/cmpd-mysql57.yaml \
      --show-only templates/cmpd-mysql80-mgr.yaml \
      --show-only templates/cmpd-mysql80-orc.yaml \
      --show-only templates/cmpd-mysql80.yaml \
      --show-only templates/cmpd-mysql84-mgr.yaml \
      --show-only templates/cmpd-mysql84.yaml |
      awk '
        /^    (preTerminate|roleProbe|memberLeave|switchover):$/ {
          actions++
          in_action = 1
          next
        }
        in_action && /^    [a-zA-Z][a-zA-Z0-9]*:$/ {
          in_action = 0
        }
        in_action && /^        container: mysql$/ {
          bindings++
        }
        END {
          if (actions != 18 || bindings != 18) {
            printf "unexpected mount-dependent action bindings: actions=%d bindings=%d (want 18/18)\n", actions, bindings > "/dev/stderr"
            exit 1
          }
        }
      '
  }

  It "shares the mysql container mounts with every ORC role probe"
    When call verify_orc_role_probe_container
    The status should be success
  End

  It "shares the mysql container mounts with every mount-dependent lifecycle action"
    When call verify_mount_dependent_action_containers
    The status should be success
  End
End
