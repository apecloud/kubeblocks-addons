# shellcheck shell=sh

Describe "MySQL ComponentDefinition image pull policy contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  render_component_definitions() {
    helm template test "$(chart_path)" \
      --show-only templates/cmpd-mysql57-orc.yaml \
      --show-only templates/cmpd-mysql57.yaml \
      --show-only templates/cmpd-mysql80-mgr.yaml \
      --show-only templates/cmpd-mysql80-orc.yaml \
      --show-only templates/cmpd-mysql80.yaml \
      --show-only templates/cmpd-mysql84-mgr.yaml \
      --show-only templates/cmpd-mysql84.yaml \
      --show-only templates/cmpd-proxysql.yaml \
      "$@"
  }

  verify_component_definition_pull_policy() {
    expected=$1
    shift

    render_component_definitions "$@" | awk -v expected="$expected" '
      $1 == "imagePullPolicy:" {
        total++
        if ($2 != expected) {
          printf "unexpected imagePullPolicy at rendered line %d: %s (want %s)\n", NR, $2, expected > "/dev/stderr"
          invalid = 1
        }
      }
      END {
        if (total != 35) {
          printf "unexpected ComponentDefinition imagePullPolicy count: %d (want 35)\n", total > "/dev/stderr"
          invalid = 1
        }
        exit invalid
      }
    '
  }

  It "applies the configured pull policy to every ComponentDefinition image reference"
    When call verify_component_definition_pull_policy Always --set-string image.pullPolicy=Always
    The status should be success
  End

  It "defaults every ComponentDefinition image reference to IfNotPresent"
    When call verify_component_definition_pull_policy IfNotPresent
    The status should be success
  End
End
