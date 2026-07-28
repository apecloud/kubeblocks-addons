# shellcheck shell=bash

Describe "mariadb cluster topology replica invariants"
  chart_dir() {
    printf "%s/addons-cluster/mariadb" "${SHELLSPEC_CWD:?}"
  }

  ensure_dependency() {
    chart="$(chart_dir)"
    [ -f "${chart}/charts/kblib-0.1.2.tgz" ] \
      || helm dependency build --skip-refresh "${chart}" >/dev/null
  }

  render_chart() {
    ensure_dependency
    helm template topoinv "$(chart_dir)" \
      --namespace default \
      --set "mode=$1" \
      --set "replicas=$2"
  }

  render_chart_without_schema() {
    ensure_dependency
    helm template topoinv "$(chart_dir)" \
      --namespace default \
      --skip-schema-validation \
      --set "mode=$1" \
      --set "replicas=$2"
  }

  render_chart_with_string_replicas() {
    ensure_dependency
    helm template topoinv "$(chart_dir)" \
      --namespace default \
      --set "mode=$1" \
      --set-string "replicas=$2"
  }

  render_chart_with_string_replicas_without_schema() {
    ensure_dependency
    helm template topoinv "$(chart_dir)" \
      --namespace default \
      --skip-schema-validation \
      --set "mode=$1" \
      --set-string "replicas=$2"
  }

  lint_chart() {
    ensure_dependency
    helm lint "$(chart_dir)" \
      --set "mode=$1" \
      --set "replicas=$2"
  }

  It "renders standalone with one replica"
    When call render_chart standalone 1
    The status should be success
    The output should include "topology: standalone"
    The output should include "replicas: 1"
  End

  It "renders replication with two replicas"
    When call render_chart replication 2
    The status should be success
    The output should include "topology: replication"
    The output should include "replicas: 2"
  End

  It "renders Galera with three replicas"
    When call render_chart galera 3
    The status should be success
    The output should include "topology: galera"
    The output should include "replicas: 3"
  End

  It "renders Galera with five replicas"
    When call render_chart galera 5
    The status should be success
    The output should include "topology: galera"
    The output should include "replicas: 5"
  End

  It "rejects an unknown topology mode through values.schema.json"
    When call render_chart invalid 3
    The status should be failure
    The error should include "mode"
  End

  It "rejects an unknown topology mode in the template even when schema validation is skipped"
    When call render_chart_without_schema invalid 3
    The status should be failure
    The error should include "mode must be one of standalone, replication, or galera"
  End

  It "rejects replicas below the global minimum through values.schema.json"
    When call render_chart standalone 0
    The status should be failure
    The error should include "replicas"
  End

  It "rejects replicas below the global minimum in the template even for standalone"
    When call render_chart_without_schema standalone 0
    The status should be failure
    The error should include "replicas must be an integer between 1 and 5"
  End

  It "rejects replicas above the global maximum through values.schema.json"
    When call render_chart standalone 6
    The status should be failure
    The error should include "replicas"
  End

  It "rejects replicas above the global maximum in the template even for standalone"
    When call render_chart_without_schema standalone 6
    The status should be failure
    The error should include "replicas must be an integer between 1 and 5"
  End

  It "rejects fractional replicas through values.schema.json"
    When call render_chart replication 2.5
    The status should be failure
    The error should include "replicas"
  End

  It "rejects fractional replicas in the template even when schema validation is skipped"
    When call render_chart_without_schema replication 2.5
    The status should be failure
    The error should include "replicas must be an integer between 1 and 5"
  End

  It "rejects non-numeric replicas through values.schema.json"
    When call render_chart replication invalid
    The status should be failure
    The error should include "replicas"
  End

  It "rejects non-numeric replicas in the template even when schema validation is skipped"
    When call render_chart_without_schema replication invalid
    The status should be failure
    The error should include "replicas must be an integer between 1 and 5"
  End

  It "rejects a numeric string replica through values.schema.json"
    When call render_chart_with_string_replicas replication 3
    The status should be failure
    The error should include "replicas"
    The error should include "want integer"
  End

  It "rejects a numeric string replica in the template even when schema validation is skipped"
    When call render_chart_with_string_replicas_without_schema replication 3
    The status should be failure
    The error should include "replicas must be an integer between 1 and 5"
  End

  It "rejects a leading-zero string replica through values.schema.json"
    When call render_chart_with_string_replicas replication 03
    The status should be failure
    The error should include "replicas"
    The error should include "want integer"
  End

  It "rejects a leading-zero string replica in the template even when schema validation is skipped"
    When call render_chart_with_string_replicas_without_schema replication 03
    The status should be failure
    The error should include "replicas must be an integer between 1 and 5"
  End

  It "rejects replication with one replica through values.schema.json"
    When call render_chart replication 1
    The status should be failure
    The error should include "replicas"
  End

  It "rejects replication with one replica in the template even when schema validation is skipped"
    When call render_chart_without_schema replication 1
    The status should be failure
    The error should include "replication mode requires replicas >= 2"
  End

  It "rejects replication above five replicas through values.schema.json"
    When call render_chart replication 6
    The status should be failure
    The error should include "replicas"
  End

  It "rejects replication above five replicas in the template even when schema validation is skipped"
    When call render_chart_without_schema replication 6
    The status should be failure
    The error should include "replicas must be an integer between 1 and 5"
  End

  It "rejects Galera with two replicas through values.schema.json"
    When call render_chart galera 2
    The status should be failure
    The error should include "replicas"
  End

  It "rejects Galera with two replicas in the template even when schema validation is skipped"
    When call render_chart_without_schema galera 2
    The status should be failure
    The error should include "galera mode requires replicas to be one of 3 or 5"
  End

  It "rejects Galera with four replicas through values.schema.json"
    When call render_chart galera 4
    The status should be failure
    The error should include "replicas"
  End

  It "rejects Galera with four replicas during helm lint"
    When call lint_chart galera 4
    The status should be failure
    The output should include "/replicas"
    The error should include "1 chart(s) linted, 1 chart(s) failed"
  End
End
