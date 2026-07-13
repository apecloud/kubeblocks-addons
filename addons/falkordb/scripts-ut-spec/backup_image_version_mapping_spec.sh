#!/bin/bash
# shellcheck disable=SC2016

Describe "FalkorDB backup image version mapping"
  chart_path() {
    printf '%s/addons/falkordb\n' "$(cd "${SHELLSPEC_PROJECT_ROOT:-.}" && pwd)"
  }

  render_template() {
    helm template test "$(chart_path)" \
      --set image.registry=registry.example.com \
      --set image.repository=team/falkordb \
      --show-only "templates/$1"
  }

  It "defers all FalkorDB ActionSet jobs to the backup policy version mapping"
    When call render_template backupactionset.yaml
    The status should be success
    The output should include 'image: $(FALKORDB_IMAGE)'
    The output should not include 'registry.example.com/team/falkordb:'
    The output should satisfy awk '
      /image: \$\(FALKORDB_IMAGE\)/ { mapped++ }
      END { exit mapped == 9 ? 0 : 1 }
    '
  End

  It "maps standalone datafile and PITR jobs to every service version image"
    When call render_template backuppolicytemplate.yaml
    The status should be success
    The output should satisfy awk '
      /name: FALKORDB_IMAGE/ { names++ }
      /mappedValue: registry.example.com\/team\/falkordb:v4.12.5/ { v412++ }
      /mappedValue: registry.example.com\/team\/falkordb:v4.14.12/ { v414++ }
      END { exit names == 2 && v412 == 2 && v414 == 2 ? 0 : 1 }
    '
  End

  It "maps cluster datafile jobs to every service version image"
    When call render_template backuppolicytemplateforcluster.yaml
    The status should be success
    The output should satisfy awk '
      /name: FALKORDB_IMAGE/ { names++ }
      /mappedValue: registry.example.com\/team\/falkordb:v4.12.5/ { v412++ }
      /mappedValue: registry.example.com\/team\/falkordb:v4.14.12/ { v414++ }
      END { exit names == 1 && v412 == 1 && v414 == 1 ? 0 : 1 }
    '
  End
End
