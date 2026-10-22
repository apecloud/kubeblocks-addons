# shellcheck shell=bash

Describe "StarRocks-CE root passwordConfig"
  chart_path() {
    printf '%s' "${STARROCKS_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/starrocks-ce}"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_rendered_accounts() {
    helm template starrocks-ce "$(chart_path)" --show-only templates/cmpd-fe.yaml "$@" | ruby -ryaml -e '
      definition = YAML.load_stream(STDIN.read).compact.fetch(0)
      abort "FE definition identity changed" unless definition.dig("metadata", "name") == "starrocks-ce-fe-1.2.0-alpha.0"
      accounts = definition.fetch("spec").fetch("systemAccounts")
      expected = [{"name" => "root", "initAccount" => true, "passwordConfig" => {
        "length" => 10, "numDigits" => 5, "numSymbols" => 0, "letterCase" => "MixedCases"
      }}]
      abort "root password generation policy changed or uses deprecated field" unless accounts == expected
    '
  }

  check_supported_kubeblocks_versions() (
    contract_dir=$(mktemp -d) || return
    trap 'rm -rf "$contract_dir"' EXIT
    mkdir "$contract_dir/templates" || return
    cat > "$contract_dir/Chart.yaml" <<'YAML'
apiVersion: v2
name: starrocks-compatibility-test
version: 0.1.0
YAML
    cat > "$contract_dir/templates/versions.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: starrocks-compatibility-test
data:
  {{- range $version := list "1.0.0" "1.0.2" "1.1.0" "1.1.9" "1.2.0" "1.2.1" "1.3.0" }}
  {{ $version | quote }}: {{ semverCompare $.Values.supported $version | quote }}
  {{- end }}
YAML
    supported=$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("annotations").fetch("addon.kubeblocks.io/kubeblocks-version")' "$(chart_path)/Chart.yaml") || return
    helm template starrocks-compatibility-test "$contract_dir" --set-string "supported=$supported" | ruby -ryaml -e '
      versions = YAML.load_stream(STDIN.read).compact.first.fetch("data")
      # The controller normalizes prerelease constraints; raw semverCompare
      # only models its stable-version behavior here.
      versions.each do |version, accepted|
        expected = %w[1.0.0 1.0.2 1.1.0 1.1.9].include?(version) ? "false" : "true"
        abort "unexpected compatibility for #{version}: #{accepted}" unless accepted == expected
      end
    '
  )

  It "renders the complete root policy without changing the FE definition name"
    When call check_rendered_accounts
    The status should be success
  End

  # Rendering does not exercise the controller immutable-field check.
  It "renders the same root policy in upgrade mode"
    When call check_rendered_accounts --is-upgrade
    The status should be success
  End

  It "limits supported stable KubeBlocks versions to 1.2 or later"
    When call check_supported_kubeblocks_versions
    The status should be success
  End
End
