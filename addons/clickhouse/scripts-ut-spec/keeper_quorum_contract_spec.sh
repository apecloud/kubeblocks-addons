# shellcheck shell=bash
# shellcheck disable=SC2034

render_clickhouse_template() {
  helm template clickhouse .. --show-only "$1"
}

rendered_metadata_name() {
  local rendered
  rendered=$(render_clickhouse_template "$1") || return

  printf '%s\n' "$rendered" | awk '
    $0 == "metadata:" { in_metadata = 1; next }
    in_metadata && $1 == "name:" && name == "" { name = $2; in_metadata = 0 }
    END { print name }
  '
}

rendered_role_quorum_value() {
  local role="$1"
  local rendered
  rendered=$(render_clickhouse_template templates/cmpd-keeper.yaml) || return

  printf '%s\n' "$rendered" | awk -v role="$role" '
    $0 ~ "^[[:space:]]*- name: " role "$" { in_role = 1; next }
    in_role && $0 ~ "^[[:space:]]*- name:" { in_role = 0 }
    in_role && $1 == "participatesInQuorum:" && value == "" { value = $2; in_role = 0 }
    END { print value }
  '
}

rendered_component_def_reference() {
  local rendered
  rendered=$(render_clickhouse_template "$1") || return

  printf '%s\n' "$rendered" |
    awk '$1 == "componentDef:" && value == "" { value = $2 } END { print value }'
}

rendered_keeper_selector_contract() {
  local cluster_definition component_version cluster_selector version_selector
  cluster_definition=$(render_clickhouse_template templates/clusterdefinition.yaml) || return
  component_version=$(render_clickhouse_template templates/cmpv.yaml) || return

  cluster_selector=$(printf '%s\n' "$cluster_definition" |
    awk '$1 == "compDef:" && $2 ~ /^\^clickhouse-keeper-/ && value == "" { value = $2 } END { print value }')
  version_selector=$(printf '%s\n' "$component_version" |
    awk '$1 == "-" && $2 ~ /^\^clickhouse-keeper-/ && value == "" { value = $2 } END { print value }')
  printf '%s|%s\n' "$cluster_selector" "$version_selector"
}

rendered_keeper_bypass_count() {
  local rendered
  rendered=$(render_clickhouse_template templates/cmpd-keeper.yaml) || return
  printf '%s\n' "$rendered" | grep -cF 'apps.kubeblocks.io/skip-immutable-check:' || true
}

rendered_old_version_reference_count() {
  local rendered
  rendered=$(helm template clickhouse ..) || return
  printf '%s\n' "$rendered" | grep -cF '1.2.0-alpha.0' || true
}

Describe "ClickHouse Keeper quorum role contract"
  It "marks the leader as a quorum participant"
    When call rendered_role_quorum_value leader
    The status should be success
    The output should eq "true"
  End

  It "marks followers as quorum participants"
    When call rendered_role_quorum_value follower
    The status should be success
    The output should eq "true"
  End

  It "keeps observers outside the voting quorum"
    When call rendered_role_quorum_value observer
    The status should be success
    The output should eq "false"
  End

  It "publishes a new versioned Keeper ComponentDefinition"
    When call rendered_metadata_name templates/cmpd-keeper.yaml
    The status should be success
    The output should eq "clickhouse-keeper-1.2.0-alpha.1"
  End

  It "moves the ClickHouse ComponentDefinition to the same chart version"
    When call rendered_metadata_name templates/cmpd-ch.yaml
    The status should be success
    The output should eq "clickhouse-1.2.0-alpha.1"
  End

  It "moves the Keeper ParametersDefinition reference to the new name"
    When call rendered_component_def_reference templates/paramsdef-keeper.yaml
    The status should be success
    The output should eq "clickhouse-keeper-1.2.0-alpha.1"
  End

  It "moves the ClickHouse config ParametersDefinition reference to the new name"
    When call rendered_component_def_reference templates/paramsdef-config.yaml
    The status should be success
    The output should eq "clickhouse-1.2.0-alpha.1"
  End

  It "moves the ClickHouse user ParametersDefinition reference to the new name"
    When call rendered_component_def_reference templates/paramsdef-user.yaml
    The status should be success
    The output should eq "clickhouse-1.2.0-alpha.1"
  End

  It "keeps topology and ComponentVersion selectors compatible with the new Keeper name"
    When call rendered_keeper_selector_contract
    The status should be success
    The output should eq "^clickhouse-keeper-1.*|^clickhouse-keeper-1.*"
  End

  It "does not retain the immutable-check bypass on the new Keeper definition"
    When call rendered_keeper_bypass_count
    The status should be success
    The output should eq "0"
  End

  It "does not render references to the old chart version"
    When call rendered_old_version_reference_count
    The status should be success
    The output should eq "0"
  End
End
