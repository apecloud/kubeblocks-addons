# shellcheck shell=sh

# Lock that the merged CmpD's configspec name is consistent across
# the two files that bind on it:
#   - cmpd-replication.yaml `spec.configs[].name`
#   - paramsdef.yaml `mariadb-replication-merged-pd` `spec.templateName`
#
# KB 1.2 addon API uses ParametersDefinition exclusively;
# ParamConfigRenderer (pcr.yaml) is deprecated and removed.

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

  merged_pd_template_name() {
    awk '
      /^[[:space:]]+name:[[:space:]]+mariadb-replication-pd[[:space:]]*$/ { in_block=1; next }
      in_block && /^---[[:space:]]*$/ { in_block=0; next }
      in_block && /^[[:space:]]+templateName:[[:space:]]+/ {
        sub(/^[[:space:]]+templateName:[[:space:]]+/, "", $0)
        sub(/[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/paramsdef.yaml"
  }

  It "the merged CmpD configspec name is the expected unified name"
    When call cmpd_configspec_name
    The output should equal "$EXPECTED_NAME"
  End

  It "the merged PD templateName matches the configspec name"
    When call merged_pd_template_name
    The output should equal "$EXPECTED_NAME"
  End

End
