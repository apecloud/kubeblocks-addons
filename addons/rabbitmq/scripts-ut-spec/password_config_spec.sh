# shellcheck shell=bash

Describe "RabbitMQ password configuration compatibility"
  chart_path() {
    printf '%s' "${RABBITMQ_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/rabbitmq}"
  }

  cluster_chart_path() {
    printf '%s' "${SHELLSPEC_CWD:?}/addons-cluster/rabbitmq"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null &&
      helm dependency build "$(cluster_chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_rendered_accounts() {
    helm template rabbitmq "$(chart_path)" "$@" | ruby -ryaml -e '
      docs = YAML.load_stream(STDIN.read).compact
      definitions = docs.select { |doc| doc["kind"] == "ComponentDefinition" }
      abort "expected one ComponentDefinition" unless definitions.length == 1
      definition = definitions.first
      name = definition.fetch("metadata").fetch("name")
      abort "definition must be retained" unless definition.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"

      accounts = definition.fetch("spec").fetch("systemAccounts")
      expected = [{"name" => "root", "initAccount" => true, "passwordConfig" => {
        "length" => 16, "numDigits" => 8, "numSymbols" => 0, "letterCase" => "MixedCases"
      }}]
      abort "root password generation policy changed or uses deprecated field" unless accounts == expected

      version = docs.find { |doc| doc["kind"] == "ComponentVersion" && doc.dig("metadata", "name") == "rabbitmq" }
      rules = version.fetch("spec").fetch("compatibilityRules")
      releases = version.fetch("spec").fetch("releases")
      abort "expected supported RabbitMQ releases" if releases.empty?
      releases.each do |release|
        patterns = rules.select { |rule| rule.fetch("releases").include?(release.fetch("name")) }
                        .flat_map { |rule| rule.fetch("compDefs") }
        abort "release #{release.fetch("name")} excludes #{name}" unless patterns.any? { |pattern| Regexp.new(pattern).match?(name) }
      end
    '
  }

  check_cluster_reference() {
    {
      helm template rabbitmq "$(chart_path)" "$@" &&
        helm template rabbitmq-cluster "$(cluster_chart_path)" "$@"
    } | ruby -ryaml -e '
      docs = YAML.load_stream(STDIN.read).compact
      definition = docs.find { |doc| doc["kind"] == "ComponentDefinition" }
      cluster = docs.find { |doc| doc["kind"] == "Cluster" }
      components = cluster.fetch("spec").fetch("componentSpecs")
      abort "expected one RabbitMQ component" unless components.length == 1
      abort "cluster references a different definition" unless components.first.fetch("componentDef") == definition.fetch("metadata").fetch("name")
    '
  }

  check_supported_kubeblocks_versions() (
    contract_dir=$(mktemp -d) || return
    trap 'rm -rf "$contract_dir"' EXIT
    mkdir "$contract_dir/templates" || return
    cat > "$contract_dir/Chart.yaml" <<'YAML'
apiVersion: v2
name: rabbitmq-compatibility-test
version: 0.1.0
YAML
    cat > "$contract_dir/templates/versions.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: rabbitmq-compatibility-test
data:
  {{- range $version := list "1.0.0" "1.0.2" "1.1.0" "1.1.9" "1.2.0" "1.2.1" "1.3.0" }}
  {{ $version | quote }}: {{ semverCompare $.Values.supported $version | quote }}
  {{- end }}
YAML
    supported=$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("annotations").fetch("addon.kubeblocks.io/kubeblocks-version")' "$(chart_path)/Chart.yaml") || return
    helm template rabbitmq-compatibility-test "$contract_dir" --set-string "supported=$supported" | ruby -ryaml -e '
      versions = YAML.load_stream(STDIN.read).compact.first.fetch("data")
      # Check stable releases here. The addon controller normalizes constraints
      # for prerelease runtimes; raw semverCompare does not model that behavior.
      versions.each do |version, accepted|
        expected = %w[1.0.0 1.0.2 1.1.0 1.1.9].include?(version) ? "false" : "true"
        abort "unexpected compatibility for #{version}: #{accepted}" unless accepted == expected
      end
    '
  )

  It "renders the root password policy on installation"
    When call check_rendered_accounts
    The status should be success
  End

  It "renders the root password policy on addon upgrade"
    When call check_rendered_accounts --is-upgrade
    The status should be success
  End

  It "installs a cluster referencing the rendered definition"
    When call check_cluster_reference
    The status should be success
  End

  It "keeps the cluster reference aligned in upgrade templates"
    When call check_cluster_reference --is-upgrade
    The status should be success
  End

  It "limits supported stable KubeBlocks versions to 1.2 or later"
    When call check_supported_kubeblocks_versions
    The status should be success
  End
End
