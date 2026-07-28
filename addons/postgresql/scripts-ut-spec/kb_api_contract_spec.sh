# shellcheck shell=sh

Describe "PostgreSQL KubeBlocks API contract"

  chart_dir() {
    printf '%s' '..'
  }

  render_chart() {
    helm template kb-addon-postgresql "$(chart_dir)" --namespace kb-system
  }

  kubeblocks_floor() {
    sed -n 's/.*addon.kubeblocks.io\/kubeblocks-version: *"\([^"]*\)".*/\1/p' "$(chart_dir)/Chart.yaml"
  }

  chart_version() {
    awk '$1 == "version:" { print $2; exit }' "$(chart_dir)/Chart.yaml"
  }

  render_count() {
    pattern="$1"
    render_chart | grep -c "$pattern" || true
  }

  component_definitions_with_pod_list_rbac() {
    render_chart | ruby -ryaml -e '
      definitions = YAML.load_stream(ARGF.read).compact.select do |document|
        document["kind"] == "ComponentDefinition"
      end
      count = definitions.count do |definition|
        rules = definition.dig("spec", "policyRules") || []
        rules.any? do |rule|
          (rule["apiGroups"] || []).include?("") &&
            (rule["resources"] || []).include?("pods") &&
            (rule["verbs"] || []).include?("list")
        end
      end
      puts count
    '
  }

  It "declares the KB 1.2 floor required by the rendered API fields"
    When call kubeblocks_floor
    The status should eq 0
    The output should eq ">=1.2.0"
  End

  It "advances the chart identity when immutable ComponentDefinitions change"
    When call chart_version
    The status should eq 0
    The output should eq "1.2.0-alpha.1"
  End

  It "publishes every ComponentDefinition under the advanced immutable identity"
    When call render_count '^  name: postgresql-\(12\|14\|15\|16\|17\|18\)-1.2.0-alpha.1$'
    The status should eq 0
    The output should eq "6"
  End

  It "does not project a create-time pod-name list into the runtime"
    When call render_count '^[[:space:]]*- name: POSTGRES_POD_NAME_LIST$'
    The status should eq 0
    The output should eq "0"
  End

  It "grants every ComponentDefinition the pod-list permission used by live arbitration"
    When call component_definitions_with_pod_list_rbac
    The status should eq 0
    The output should eq "6"
  End

  It "renders exactly one CmpD reconfigure action per PostgreSQL major"
    When call render_count '^[[:space:]]*reconfigure:$'
    The status should eq 0
    The output should eq "6"
  End

  It "does not render the legacy PD reloadAction path"
    When call render_count '^[[:space:]]*reloadAction:$'
    The status should eq 0
    The output should eq "0"
  End

  It "binds every PD to the KB 1.2 config entry"
    When call render_count '^[[:space:]]*templateName: postgresql-configuration$'
    The status should eq 0
    The output should eq "6"
  End

  It "uses the projected KB scripts path for all CmpD actions"
    When call render_count '/kb-scripts/update-parameter.sh "\$1" "\$2"'
    The status should eq 0
    The output should eq "6"
  End

  It "publishes PG 18.4 in the CmpD, PD, and ComponentVersion"
    When call render_count '^[[:space:]]*serviceVersion: 18.4.0$'
    The status should eq 0
    The output should eq "3"
  End

  It "publishes the PG 18.4 image for runtime and lifecycle actions"
    When call render_count 'docker.io/apecloud/spilo:18.4'
    The status should eq 0
    The output should eq "3"
  End
End
