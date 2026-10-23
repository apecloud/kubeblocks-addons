# shellcheck shell=bash

Describe "RustFS password configuration compatibility"
  chart_path() {
    printf '%s' "${RUSTFS_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/rustfs}"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_rendered_accounts() {
    helm template rustfs "$(chart_path)" "$@" | ruby -ryaml -e '
      docs = YAML.load_stream(STDIN.read).compact
      definitions = docs.select { |doc| doc["kind"] == "ComponentDefinition" }
      abort "expected one ComponentDefinition" unless definitions.length == 1
      definition = definitions.first
      name = definition.fetch("metadata").fetch("name")
      abort "definition identity changed" unless name == "rustfs-0.1.2"
      abort "default resource retention changed" if definition.dig("metadata", "annotations", "helm.sh/resource-policy")

      accounts = definition.fetch("spec").fetch("systemAccounts")
      expected = [{"name" => "root", "initAccount" => true, "passwordConfig" => {
        "length" => 16, "numDigits" => 8, "letterCase" => "MixedCases"
      }}]
      abort "root password generation policy changed or uses deprecated field" unless accounts == expected

      version = docs.find { |doc| doc["kind"] == "ComponentVersion" && doc.dig("metadata", "name") == "rustfs" }
      rules = version.fetch("spec").fetch("compatibilityRules")
      version.fetch("spec").fetch("releases").each do |release|
        patterns = rules.select { |rule| rule.fetch("releases").include?(release.fetch("name")) }
                        .flat_map { |rule| rule.fetch("compDefs") }
        abort "release #{release.fetch("name")} excludes #{name}" unless patterns.any? { |pattern| Regexp.new(pattern).match?(name) }
      end
    '
  }

  check_supported_kubeblocks_versions() (
    contract_dir=$(mktemp -d) || return
    trap 'rm -rf "$contract_dir"' EXIT
    mkdir "$contract_dir/templates" || return
    cat > "$contract_dir/Chart.yaml" <<'YAML'
apiVersion: v2
name: rustfs-compatibility-test
version: 0.1.0
YAML
    cat > "$contract_dir/templates/versions.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: rustfs-compatibility-test
data:
  {{- range $version := list "1.0.0" "1.0.2" "1.1.0" "1.1.9" "1.2.0" "1.2.1" "1.3.0" }}
  {{ $version | quote }}: {{ semverCompare $.Values.supported $version | quote }}
  {{- end }}
YAML
    supported=$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("annotations").fetch("addon.kubeblocks.io/kubeblocks-version")' "$(chart_path)/Chart.yaml") || return
    helm template rustfs-compatibility-test "$contract_dir" --set-string "supported=$supported" | ruby -ryaml -e '
      versions = YAML.load_stream(STDIN.read).compact.first.fetch("data")
      # Check stable releases here. The addon controller normalizes constraints
      # for prerelease runtimes; raw semverCompare does not model that behavior.
      versions.each do |version, accepted|
        expected = %w[1.0.0 1.0.2 1.1.0 1.1.9].include?(version) ? "false" : "true"
        abort "unexpected compatibility for #{version}: #{accepted}" unless accepted == expected
      end
    '
  )

  It "renders passwordConfig with the existing definition identity and retention default"
    When call check_rendered_accounts
    The status should be success
  End

  It "preserves the definition identity and password policy in upgrade rendering"
    When call check_rendered_accounts --is-upgrade
    The status should be success
  End

  It "limits supported stable KubeBlocks versions to 1.2 or later"
    When call check_supported_kubeblocks_versions
    The status should be success
  End
End
