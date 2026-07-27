# shellcheck shell=sh

# KB 1.0 binds ParametersDefinition through ParamConfigRenderer.

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

  extract_standalone_pcr_binding() {
    awk '
      /^[[:space:]]+name: mariadb-standalone-pcr$/ { in_block=1; next }
      in_block && /^---$/ { exit }
      in_block && /^[[:space:]]+- mariadb-standalone-pd$/ {
        print "mariadb-standalone-config"
        exit
      }
    ' "$(repo_root)/addons/mariadb/templates/pcr.yaml"
  }

  assert_standalone_template_mapping_consistency() {
    cmpd_name=$(extract_standalone_cmpd_config_name)
    paramsdef_template=$(extract_standalone_pcr_binding)

    printf "cmpd=%s\nparamsdef=%s\n" \
      "${cmpd_name}" "${paramsdef_template}"

    [ "${cmpd_name}" = "mariadb-standalone-config" ]
    [ "${paramsdef_template}" = "${cmpd_name}" ]
  }

  It "keeps standalone cmpd and paramsdef mapping names aligned"
    When call assert_standalone_template_mapping_consistency
    The status should be success
    The output should include "cmpd=mariadb-standalone-config"
    The output should include "paramsdef=mariadb-standalone-config"
  End
End
