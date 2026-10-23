# shellcheck shell=bash

Describe "Milvus embedded MinIO credential contract"
  render_contract() {
    helm template milvus .. | ruby -ryaml -e '
      documents = YAML.load_stream(ARGF.read).compact
      component = documents.find do |document|
        document["kind"] == "ComponentDefinition" &&
          document.dig("spec", "serviceKind") == "milvus-minio"
      end
      abort "milvus-minio ComponentDefinition not rendered" unless component

      account = component.dig("spec", "systemAccounts").find do |item|
        item["name"] == "root"
      end
      abort "root system account not rendered" unless account
      puts "accounts=#{component.dig("spec", "systemAccounts").map { |item| item["name"] }.join(",")}"

      abort "deprecated password policy still rendered" if account.key?("passwordGenerationPolicy")
      policy = account.fetch("passwordConfig")
      puts "policy=#{policy.values_at("length", "numDigits", "numSymbols", "letterCase").join(",")}"

      vars = component.dig("spec", "vars").to_h { |item| [item["name"], item] }
      user_ref = vars.dig("MINIO_ROOT_USER", "valueFrom", "credentialVarRef") || {}
      password_ref = vars.dig("MINIO_ROOT_PASSWORD", "valueFrom", "credentialVarRef") || {}
      puts "user=#{user_ref.values_at("name", "optional", "username").join(",")}"
      puts "password=#{password_ref.values_at("name", "optional", "password").join(",")}"
      puts "server_legacy=#{vars.key?("MINIO_ACCESS_KEY") || vars.key?("MINIO_SECRET_KEY")}"

      standalone = documents.find do |document|
        document["kind"] == "ComponentDefinition" &&
          document.dig("spec", "serviceKind") == "milvus" &&
          document["metadata"]["name"].include?("standalone")
      end
      abort "milvus standalone ComponentDefinition not rendered" unless standalone

      client_vars = standalone.dig("spec", "vars").to_h { |item| [item["name"], item] }
      access_ref = client_vars.dig("MINIO_ACCESS_KEY", "valueFrom", "credentialVarRef") || {}
      secret_ref = client_vars.dig("MINIO_SECRET_KEY", "valueFrom", "credentialVarRef") || {}
      puts "client_access=#{access_ref.values_at("name", "optional", "username").join(",")}"
      puts "client_secret=#{secret_ref.values_at("name", "optional", "password").join(",")}"
      puts "client_root=#{client_vars.key?("MINIO_ROOT_USER") || client_vars.key?("MINIO_ROOT_PASSWORD")}"

      clients = documents.select do |document|
        document["kind"] == "ComponentDefinition" &&
          document.dig("spec", "serviceKind") == "milvus"
      end
      client_contract = clients.all? do |document|
        names = document.dig("spec", "vars").map { |item| item["name"] }
        names.include?("MINIO_ACCESS_KEY") &&
          names.include?("MINIO_SECRET_KEY") &&
          !names.include?("MINIO_ROOT_USER") &&
          !names.include?("MINIO_ROOT_PASSWORD")
      end
      puts "client_components=#{clients.map { |document| document["metadata"]["name"].sub(/-1[.].*$/, "") }.sort.join(",")}"
      puts "client_contract=#{client_contract}"
    '
  }

  It "renders an explicit non-empty password policy and separates server and client variables"
    When call render_contract
    The output should eq "accounts=root
policy=16,4,0,MixedCases
user=root,false,Required
password=root,false,Required
server_legacy=false
client_access=root,false,Required
client_secret=root,false,Required
client_root=false
client_components=milvus-datanode,milvus-indexnode,milvus-mixcoord,milvus-proxy,milvus-querynode,milvus-standalone
client_contract=true"
    The status should be success
  End

  render_upgrade_contract() {
    addon_version=$(awk '$1 == "version:" { print $2; exit }' ../Chart.yaml)
    cluster_version=$(awk '$1 == "version:" { print $2; exit }' ../../../addons-cluster/milvus/Chart.yaml)
    printf 'versions=%s,%s\n' "$addon_version" "$cluster_version"

    helm template milvus .. | ruby -ryaml -e '
      documents = YAML.load_stream(STDIN.read).compact
      definitions = documents.select { |document| document["kind"] == "ComponentDefinition" }
      names = definitions.map { |definition| definition.dig("metadata", "name") }
      definition_names = names.grep(/milvus-(minio|standalone)-/).sort.join(",")
      puts "definitions=#{definition_names}"

      parameter_definitions = documents.select do |document|
        document["kind"] == "ParametersDefinition" &&
          document.dig("metadata", "name").start_with?("milvus-standalone-pd-")
      end.sort_by { |document| document.dig("metadata", "name") }
      abort "expected two Milvus standalone ParametersDefinitions" unless parameter_definitions.length == 2

      bindings = parameter_definitions.map do |definition|
        [definition.dig("metadata", "name"), definition.dig("spec", "componentDef")]
      end
      binding_names = bindings.map { |name, pattern| "#{name}:#{pattern}" }.join(",")
      puts "parameter_definitions=#{binding_names}"

      component_definitions = [
        "milvus-standalone-1.2.0-alpha.0",
        "milvus-standalone-#{ARGV.fetch(0)}"
      ]
      matrix = bindings.map do |name, pattern|
        matches = component_definitions.select { |component_definition| Regexp.new(pattern).match?(component_definition) }
        abort "#{name} must match exactly one ComponentDefinition" unless matches.length == 1
        "#{name}:#{matches.first}"
      end
      puts "parameter_binding_matrix=#{matrix.join(",")}"
    ' "$addon_version"

    helm dependency build ../../../addons-cluster/milvus >/dev/null
    helm template milvus-cluster ../../../addons-cluster/milvus --set mode=standalone | ruby -ryaml -e '
      cluster = YAML.load_stream(ARGF.read).compact.find { |document| document["kind"] == "Cluster" }
      abort "standalone Cluster not rendered" unless cluster

      components = cluster.dig("spec", "componentSpecs")
      puts "cluster_definition_api=#{components.none? { |item| item.key?("componentDef") } ? "topology" : "direct"}"
    '

    ruby -ryaml -e '
      migration = YAML.load_file("../examples/upgrade-embedded-minio-credential.yaml")
      components = migration.dig("spec", "upgrade", "components").to_h { |item| [item["componentName"], item] }
      forced = migration.dig("spec", "force") == true ? "true" : "false"
      puts "migration=#{migration.dig("metadata", "name")},#{migration.dig("spec", "type")},precondition=#{migration.dig("spec", "preConditionDeadlineSeconds")},force=#{forced},#{components.dig("minio", "componentDefinitionName")},#{components.dig("milvus", "componentDefinitionName")}"
    '
  }

  It "publishes immutable definitions and migrates existing components through Upgrade OpsRequest"
    current_version=$(awk '$1 == "version:" { print $2; exit }' ../Chart.yaml)
    current_pattern=$(printf '%s' "$current_version" | sed 's/\./[.]/g')
    When call render_upgrade_contract
    The output should eq "versions=$current_version,1.2.0-alpha.0
definitions=milvus-minio-$current_version,milvus-standalone-$current_version
parameter_definitions=milvus-standalone-pd-1.2.0-alpha.0:^milvus-standalone-1[.]2[.]0-alpha[.]0$,milvus-standalone-pd-$current_version:^milvus-standalone-$current_pattern$
parameter_binding_matrix=milvus-standalone-pd-1.2.0-alpha.0:milvus-standalone-1.2.0-alpha.0,milvus-standalone-pd-$current_version:milvus-standalone-$current_version
cluster_definition_api=topology
migration=milvus-standalone-minio-root-migrate,Upgrade,precondition=600,force=false,milvus-minio-1.2.0-alpha.1,milvus-standalone-1.2.0-alpha.1"
    The status should be success
  End

  check_minio_identity() {
    local chart="$1" version
    shift
    version=$(helm show chart "$chart" | ruby -ryaml -e 'puts YAML.safe_load(STDIN.read).fetch("version")') || return
    helm template milvus "$chart" "$@" | ruby -ryaml -e '
      document = YAML.load_stream(STDIN.read).compact.find do |doc|
        doc["kind"] == "ComponentDefinition" && doc.dig("spec", "serviceKind") == "milvus-minio"
      end
      abort "embedded MinIO definition is missing" unless document
      name = document.fetch("metadata").fetch("name")
      # These published definitions use the previous immutable account schema.
      old_names = (0..2).map { |revision| "milvus-minio-1.2.0-alpha.#{revision}" }
      abort "must not overwrite a published account schema" if old_names.include?(name)
      abort "identity must follow Chart.Version" unless name == "milvus-minio-#{ARGV.fetch(0)}"
      abort "definition must be retained" unless document.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"
      expected = [{"name" => "root", "initAccount" => true, "passwordConfig" => {
        "length" => 16, "numDigits" => 4, "numSymbols" => 0, "letterCase" => "MixedCases"
      }}]
      abort "root account or password rules changed" unless document.dig("spec", "systemAccounts") == expected
    ' "$version"
  }

  check_future_minio_identity() (
    local contract_dir
    contract_dir=$(mktemp -d) || return
    trap 'rm -rf "$contract_dir"' EXIT
    helm package .. --version 9.9.9-identity-test --destination "$contract_dir" >/dev/null || return
    check_minio_identity "$contract_dir/milvus-9.9.9-identity-test.tgz"
  )

  It "installs the root passwordConfig under a new retained chart-versioned identity"
    When call check_minio_identity ..
    The status should be success
  End

  It "does not overwrite the old MinIO account schema during chart upgrade"
    When call check_minio_identity .. --is-upgrade
    The status should be success
  End

  It "follows later chart versions instead of freezing the MinIO identity"
    When call check_future_minio_identity
    The status should be success
  End

End
