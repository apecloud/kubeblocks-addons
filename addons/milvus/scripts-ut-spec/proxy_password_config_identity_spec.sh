# shellcheck shell=bash

Describe "Milvus proxy passwordConfig identity contract"
  chart_path() {
    printf '%s' "${SHELLSPEC_CWD:?}/addons/milvus"
  }

  check_proxy() {
    local chart="$1" version
    shift
    version=$(helm show chart "$chart" | ruby -ryaml -e 'puts YAML.safe_load(STDIN.read).fetch("version")') || return
    helm template milvus "$chart" "$@" | ruby -ryaml -e '
      documents = YAML.load_stream(STDIN.read).compact
      document = documents.find do |doc|
        doc["kind"] == "ComponentDefinition" && doc.dig("metadata", "name").start_with?("milvus-proxy-")
      end
      abort "proxy ComponentDefinition is missing" unless document
      name = document.fetch("metadata").fetch("name")
      old_name = "milvus-proxy-1.2.0-alpha.1"
      abort "proxy must not overwrite the old account schema" if name == old_name
      abort "proxy identity must follow Chart.Version" unless name == "milvus-proxy-#{ARGV.fetch(0)}"
      abort "definition must be retained" unless document.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"

      expected = [{"name" => "root", "initAccount" => true, "passwordConfig" => {
        "length" => 16, "numDigits" => 4, "numSymbols" => 0, "letterCase" => "MixedCases"
      }}]
      abort "root password policy changed or uses deprecated field" unless document.dig("spec", "systemAccounts") == expected

      version = documents.find { |doc| doc["kind"] == "ComponentVersion" && doc.dig("metadata", "name") == "milvus" }
      rules = version.fetch("spec").fetch("compatibilityRules")
      releases = version.fetch("spec").fetch("releases").select { |release| release.fetch("name").end_with?("-proxy") }
      abort "proxy releases are missing" if releases.empty?
      releases.each do |release|
        selectors = rules.select { |rule| rule.fetch("releases").include?(release.fetch("name")) }
                         .flat_map { |rule| rule.fetch("compDefs") }
        [old_name, name].each do |definition_name|
          abort "release excludes #{definition_name}" unless selectors.any? { |selector| Regexp.new(selector).match?(definition_name) }
        end
      end
    ' "$version"
  }

  check_future_chart_version() (
    local contract_dir
    contract_dir=$(mktemp -d) || return
    trap 'rm -rf "$contract_dir"' EXIT
    helm package "$(chart_path)" --version 9.9.9-identity-test --destination "$contract_dir" >/dev/null || return
    check_proxy "$contract_dir/milvus-9.9.9-identity-test.tgz"
  )

  It "installs the root policy under a new retained chart-versioned definition"
    When call check_proxy "$(chart_path)"
    The status should be success
  End

  It "keeps old and new proxy definitions compatible during upgrades"
    When call check_proxy "$(chart_path)" --is-upgrade
    The status should be success
  End

  It "follows a subsequent chart version instead of freezing the proxy identity"
    When call check_future_chart_version
    The status should be success
  End
End
