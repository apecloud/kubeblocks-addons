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

  render_count() {
    pattern="$1"
    render_chart | grep -c "$pattern" || true
  }

  It "declares the KB 1.2 floor required by the rendered API fields"
    When call kubeblocks_floor
    The status should eq 0
    The output should eq ">=1.2.0"
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
