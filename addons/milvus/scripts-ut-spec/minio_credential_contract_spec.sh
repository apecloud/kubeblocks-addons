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

      policy = account["passwordGenerationPolicy"] || {}
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
      definitions = YAML.load_stream(ARGF.read).compact.select { |document| document["kind"] == "ComponentDefinition" }
      names = definitions.map { |definition| definition.dig("metadata", "name") }
      puts "definitions=#{names.grep(/milvus-(minio|standalone)-/).sort.join(",")}"
    '

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
      puts "migration=#{migration.dig("spec", "type")},#{components.dig("minio", "componentDefinitionName")},#{components.dig("milvus", "componentDefinitionName")}"
    '
  }

  It "publishes immutable definitions and migrates existing components through Upgrade OpsRequest"
    When call render_upgrade_contract
    The output should eq "versions=1.2.0-alpha.1,1.2.0-alpha.0
definitions=milvus-minio-1.2.0-alpha.1,milvus-standalone-1.2.0-alpha.1
cluster_definition_api=topology
migration=Upgrade,milvus-minio-1.2.0-alpha.1,milvus-standalone-1.2.0-alpha.1"
    The status should be success
  End
End
