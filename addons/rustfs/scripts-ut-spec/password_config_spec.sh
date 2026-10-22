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
      old_name = "rustfs-0.1.2"
      abort "must not overwrite immutable systemAccounts on #{old_name}" if name == old_name
      abort "definition must be retained" unless definition.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"

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

  check_legacy_retention_step() (
    legacy_dir=$(mktemp -d) || return
    trap 'rm -rf "$legacy_dir"' EXIT
    cp -R "$(chart_path)/." "$legacy_dir/" || return
    ruby -e '
      chart, definition = ARGV
      File.write(chart, File.read(chart).sub(/^version: .*$/, "version: 0.1.2"))
      File.write(definition, File.read(definition).sub("passwordConfig:", "passwordGenerationPolicy:"))
    ' "$legacy_dir/Chart.yaml" "$legacy_dir/templates/cmpd.yaml" || return
    helm template rustfs "$legacy_dir" --set extra.keepResource=false >"$legacy_dir/before.yaml" || return
    helm template rustfs "$legacy_dir" --is-upgrade --set extra.keepResource=true >"$legacy_dir/retained.yaml" || return
    ruby -ryaml -e '
      before, retained = ARGV.map do |path|
        YAML.load_stream(File.read(path)).compact.find { |doc| doc["kind"] == "ComponentDefinition" }
      end
      abort "retention must not change immutable spec" unless before.fetch("spec") == retained.fetch("spec")
      abort "legacy name changed" unless [before, retained].all? { |doc| doc.dig("metadata", "name") == "rustfs-0.1.2" }
      abort "legacy fixture must start without retention" if before.dig("metadata", "annotations", "helm.sh/resource-policy")
      abort "retention step failed" unless retained.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"
    ' "$legacy_dir/before.yaml" "$legacy_dir/retained.yaml"
  )

  It "adds retention to the original chart without changing its immutable spec"
    When call check_legacy_retention_step
    The status should be success
  End

  It "installs the root password policy under a new retained definition"
    When call check_rendered_accounts
    The status should be success
  End

  It "keeps old and new definitions compatible during addon upgrades"
    When call check_rendered_accounts --is-upgrade
    The status should be success
  End

  It "limits supported stable KubeBlocks versions to 1.2 or later"
    When call check_supported_kubeblocks_versions
    The status should be success
  End
End
