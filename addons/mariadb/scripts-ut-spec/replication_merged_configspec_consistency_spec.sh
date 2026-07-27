# shellcheck shell=sh

# Lock that the merged CmpD's configspec name is consistent across
# the two files that bind on it:
#   - cmpd-replication.yaml `spec.configs[].name`
#   - pcr.yaml `mariadb-replication-pcr` binding to the replication PD
#
# KB 1.0 binds ParametersDefinition through ParamConfigRenderer.

Describe "alpha.89 merged CmpD configspec name two-way consistency"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  EXPECTED_NAME='mariadb-replication-config'

  cmpd_configspec_name() {
    awk '
      $0 ~ /^[[:space:]]*configs:[[:space:]]*$/ { in_configs=1; next }
      in_configs && $0 ~ /^[[:space:]]*-[[:space:]]+name:[[:space:]]+/ {
        sub(/^[[:space:]]*-[[:space:]]+name:[[:space:]]+/, "", $0)
        sub(/[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/cmpd-replication.yaml"
  }

  replication_pcr_binding() {
    awk '
      /^[[:space:]]+name:[[:space:]]+mariadb-replication-pcr[[:space:]]*$/ { in_block=1; next }
      in_block && /^---[[:space:]]*$/ { in_block=0; next }
      in_block && /^[[:space:]]+- mariadb-replication-pd[[:space:]]*$/ {
        print "mariadb-replication-config"
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/pcr.yaml"
  }

  It "the merged CmpD configspec name is the expected unified name"
    When call cmpd_configspec_name
    The output should equal "$EXPECTED_NAME"
  End

  It "the release-1.0 PCR binds the replication parameters definition"
    When call replication_pcr_binding
    The output should equal "$EXPECTED_NAME"
  End

End
