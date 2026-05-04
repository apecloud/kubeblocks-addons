# shellcheck shell=sh

Describe "standalone template mapping"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  extract_standalone_cmpd_config_name() {
    awk '
      /^spec:$/ { in_spec=1; next }
      in_spec && /^[[:space:]]+- name: mariadb-standalone-config$/ {
        print "mariadb-standalone-config"
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/cmpd.yaml"
  }

  extract_standalone_pcr_template_name() {
    awk '
      /^# ParamConfigRenderer for standalone MariaDB$/ { in_block=1; next }
      in_block && /^---$/ { exit }
      in_block && /^[[:space:]]+templateName:/ {
        print $2
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/pcr.yaml"
  }

  extract_standalone_paramsdef_template_name() {
    awk '
      /^# ParametersDefinition for standalone MariaDB$/ { in_block=1; next }
      in_block && /^---$/ { exit }
      in_block && /^[[:space:]]+templateName:/ {
        print $2
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/paramsdef.yaml"
  }

  assert_standalone_template_mapping_consistency() {
    cmpd_name=$(extract_standalone_cmpd_config_name)
    pcr_template=$(extract_standalone_pcr_template_name)
    paramsdef_template=$(extract_standalone_paramsdef_template_name)

    printf "cmpd=%s\npcr=%s\nparamsdef=%s\n" \
      "${cmpd_name}" "${pcr_template}" "${paramsdef_template}"

    [ "${cmpd_name}" = "mariadb-standalone-config" ]
    [ "${pcr_template}" = "${cmpd_name}" ]
    [ "${paramsdef_template}" = "${cmpd_name}" ]
  }

  It "keeps standalone cmpd, pcr and paramsdef mapping names aligned"
    When call assert_standalone_template_mapping_consistency
    The status should be success
    The output should include "cmpd=mariadb-standalone-config"
    The output should include "pcr=mariadb-standalone-config"
    The output should include "paramsdef=mariadb-standalone-config"
  End
End
