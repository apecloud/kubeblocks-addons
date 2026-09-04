# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "render_contract_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

if ! command -v helm >/dev/null 2>&1 || ! command -v ruby >/dev/null 2>&1; then
  echo "render_contract_spec.sh skip cases because helm or ruby is not installed."
  exit 0
fi

# KB main/1.2+ parameters-chain contract (docs/addon-api/08 + the
# pd-to-cmpd migration guide): the chart declares >=1.2.0; the config entry is
# externalManaged with a file-level reconfigure exec reading the changed
# key/value pair from "$1"/"$2" (ActionRequest.Arguments); reconfigure does NOT
# live in lifecycleActions; the ParametersDefinition binds the config entry
# name and fileName exactly.
Describe "yashandb rendered KB main/1.2+ parameters-chain contract"
  render_chart() {
    helm template yashandb .. 2>/dev/null
  }

  It "declares kubeblocks-version >=1.2.0 in Chart.yaml"
    When run grep -E 'kubeblocks-version.*>=1\.2\.0' ../Chart.yaml
    The status should be success
    The output should be present
  End

  It "marks the yashandb-configs entry externalManaged with a file-level reconfigure and no lifecycle reconfigure"
    When run bash -c '
      helm template yashandb .. 2>/dev/null | ruby -ryaml -e "
        docs = YAML.load_stream(STDIN.read)
        cmpd = docs.compact.find { |d| d[\"kind\"] == \"ComponentDefinition\" }
        abort(\"no ComponentDefinition rendered\") unless cmpd
        entry = cmpd.dig(\"spec\", \"configs\")&.find { |c| c[\"name\"] == \"yashandb-configs\" }
        abort(\"no yashandb-configs entry\") unless entry
        abort(\"externalManaged missing/false\") unless entry[\"externalManaged\"] == true
        reconf = entry[\"reconfigure\"]
        abort(\"config-level reconfigure missing\") unless reconf && reconf.dig(\"exec\", \"command\")
        cmd = reconf.dig(\"exec\", \"command\").join(\" \")
        abort(\"reconfigure must consume \\\$1/\\\$2 args, got: #{cmd}\") unless cmd.include?(\"\$1\") && cmd.include?(\"\$2\")
        abort(\"reconfigure must not scan ambient env\") if cmd.include?(\"env |\")
        abort(\"lifecycleActions.reconfigure must be absent\") if cmpd.dig(\"spec\", \"lifecycleActions\", \"reconfigure\")
        puts \"contract-ok\"
      "'
    The status should be success
    The output should include "contract-ok"
  End

  It "binds the ParametersDefinition to the config entry name and install.ini exactly"
    When run bash -c '
      helm template yashandb .. 2>/dev/null | ruby -ryaml -e "
        docs = YAML.load_stream(STDIN.read)
        pd = docs.compact.find { |d| d[\"kind\"] == \"ParametersDefinition\" }
        abort(\"no ParametersDefinition rendered\") unless pd
        abort(\"templateName mismatch: #{pd.dig(\"spec\",\"templateName\")}\") unless pd.dig(\"spec\", \"templateName\") == \"yashandb-configs\"
        abort(\"fileName mismatch: #{pd.dig(\"spec\",\"fileName\")}\") unless pd.dig(\"spec\", \"fileName\") == \"install.ini\"
        puts \"pd-binding-ok\"
      "'
    The status should be success
    The output should include "pd-binding-ok"
  End
End
