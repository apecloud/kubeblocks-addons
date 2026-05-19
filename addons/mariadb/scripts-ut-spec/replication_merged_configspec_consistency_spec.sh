# shellcheck shell=sh

# Lock that the merged CmpD's configspec name is consistent across
# the three files that bind on it:
#   - cmpd-replication-merged.yaml `spec.configs[].name`
#   - paramsdef.yaml `mariadb-replication-merged-pd` `spec.templateName`
#   - pcr.yaml merged CmpD PCR `spec.configs[].templateName`
#
# alpha.89 v1 commit 2 (Helen 2026-05-19) renamed all three from
# `mariadb-semisync-config` (inherited from cmpd-semisync.yaml's
# original configspec name) to `mariadb-replication-config`. KB
# Configure resolves these references by name, so a mismatch at any
# of the three sites would silently break the merged CmpD's
# parameter / config rendering pipeline. This spec encodes the
# three-way invariant.

Describe "alpha.89 merged CmpD configspec name three-way consistency"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  EXPECTED_NAME='mariadb-replication-config'

  # Extract the configspec name from the merged CmpD file.
  # Looks for the first `- name:` under `spec.configs:`.
  cmpd_configspec_name() {
    awk '
      $0 ~ /^[[:space:]]*configs:[[:space:]]*$/ { in_configs=1; next }
      in_configs && $0 ~ /^[[:space:]]*-[[:space:]]+name:[[:space:]]+/ {
        sub(/^[[:space:]]*-[[:space:]]+name:[[:space:]]+/, "", $0)
        sub(/[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/cmpd-replication-merged.yaml"
  }

  # Extract the templateName from the merged PD block in paramsdef.yaml.
  # The merged PD's metadata.name is `mariadb-replication-merged-pd`.
  merged_pd_template_name() {
    awk '
      /^[[:space:]]+name:[[:space:]]+mariadb-replication-merged-pd[[:space:]]*$/ { in_block=1; next }
      in_block && /^---[[:space:]]*$/ { in_block=0; next }
      in_block && /^[[:space:]]+templateName:[[:space:]]+/ {
        sub(/^[[:space:]]+templateName:[[:space:]]+/, "", $0)
        sub(/[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/paramsdef.yaml"
  }

  # Extract the templateName from the merged CmpD PCR block in pcr.yaml.
  # The merged PCR's metadata.name uses the merged CmpD name helper.
  merged_pcr_template_name() {
    awk '
      /^# ParamConfigRenderer for the merged replication CmpD$/ { in_block=1; next }
      in_block && /^---[[:space:]]*$/ { in_block=0; next }
      in_block && /^[[:space:]]+templateName:[[:space:]]+/ {
        sub(/^[[:space:]]+templateName:[[:space:]]+/, "", $0)
        sub(/[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/pcr.yaml"
  }

  It "the merged CmpD configspec name is the expected unified name"
    When call cmpd_configspec_name
    The output should equal "$EXPECTED_NAME"
  End

  It "the merged PD templateName matches the configspec name"
    When call merged_pd_template_name
    The output should equal "$EXPECTED_NAME"
  End

  It "the merged PCR templateName matches the configspec name"
    When call merged_pcr_template_name
    The output should equal "$EXPECTED_NAME"
  End

End
