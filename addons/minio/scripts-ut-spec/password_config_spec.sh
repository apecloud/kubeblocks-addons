# shellcheck shell=bash

Describe "MinIO password configuration compatibility"
  chart_path() {
    printf '%s' "${MINIO_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/minio}"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_rendered_accounts() {
    helm template minio "$(chart_path)" "$@" | ruby -ryaml -e '
      docs = YAML.load_stream(STDIN.read).compact
      definitions = docs.select { |doc| doc["kind"] == "ComponentDefinition" }
      abort "expected one ComponentDefinition" unless definitions.length == 1
      definition = definitions.first
      name = definition.fetch("metadata").fetch("name")
      old_name = "minio-1.2.0-alpha.0"
      abort "must not overwrite immutable systemAccounts on #{old_name}" if name == old_name
      abort "definition must be retained" unless definition.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"

      accounts = definition.fetch("spec").fetch("systemAccounts")
      expected = [{"name" => "root", "initAccount" => true, "passwordConfig" => {
        "length" => 16, "numDigits" => 8, "letterCase" => "MixedCases"
      }}]
      abort "root password generation policy changed or uses deprecated field" unless accounts == expected

      version = docs.find { |doc| doc["kind"] == "ComponentVersion" && doc.dig("metadata", "name") == "minio" }
      rules = version.fetch("spec").fetch("compatibilityRules")
      version.fetch("spec").fetch("releases").each do |release|
        patterns = rules.select { |rule| rule.fetch("releases").include?(release.fetch("name")) }
                        .flat_map { |rule| rule.fetch("compDefs") }
        [old_name, name].each do |definition_name|
          abort "release #{release.fetch("name")} excludes #{definition_name}" unless patterns.any? { |pattern| Regexp.new(pattern).match?(definition_name) }
        end
      end
    '
  }

  check_supported_kubeblocks_versions() (
    contract_dir=$(mktemp -d) || return
    trap 'rm -rf "$contract_dir"' EXIT
    mkdir "$contract_dir/templates" || return
    cat > "$contract_dir/Chart.yaml" <<'YAML'
apiVersion: v2
name: minio-compatibility-test
version: 0.1.0
YAML
    cat > "$contract_dir/templates/versions.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio-compatibility-test
data:
  {{- range $version := list "1.0.0" "1.1.0-beta.8" "1.1.0-beta.9" "1.1.0" "1.2.0-alpha.0" "1.2.0" }}
  {{ $version | quote }}: {{ semverCompare $.Values.supported $version | quote }}
  {{- end }}
YAML
    supported=$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("annotations").fetch("addon.kubeblocks.io/kubeblocks-version")' "$(chart_path)/Chart.yaml") || return
    helm template minio-compatibility-test "$contract_dir" --set-string "supported=$supported" | ruby -ryaml -e '
      versions = YAML.load_stream(STDIN.read).compact.first.fetch("data")
      # v1.1.0-beta.9 is the first published v1 CRD accepting passwordConfig.
      versions.each do |version, accepted|
        expected = %w[1.0.0 1.1.0-beta.8].include?(version) ? "false" : "true"
        abort "unexpected compatibility for #{version}: #{accepted}" unless accepted == expected
      end
    '
  )

  It "installs the root password policy under a new retained definition"
    When call check_rendered_accounts
    The status should be success
  End

  It "keeps old and new definitions compatible during addon upgrades"
    When call check_rendered_accounts --is-upgrade
    The status should be success
  End

  It "excludes KubeBlocks versions whose v1 CRD cannot accept passwordConfig"
    When call check_supported_kubeblocks_versions
    The status should be success
  End
End
