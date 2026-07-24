require "yaml"

documents = YAML.load_stream(ARGF.read).compact
by_kind = documents.group_by { |document| document["kind"] }

cluster9 = by_kind.fetch("ClusterDefinition").find { |item| item.dig("metadata", "name") == "elasticsearch-9" }
abort "elasticsearch-9 ClusterDefinition not rendered" unless cluster9
topologies = cluster9.dig("spec", "topologies")
topology_names = topologies.map { |item| item["name"] }
abort "unexpected 9.x topology set: #{topology_names.join(",")}" unless topology_names == %w[single-node multi-node]
puts "topologies=#{topology_names.join(",")}"
patterns = topologies.flat_map { |item| item["components"].map { |component| component["compDef"] } }
expected_patterns = ["^elasticsearch-9-", "^elasticsearch-master-9-", "^elasticsearch-data-9-"]
abort "unexpected 9.x topology patterns: #{patterns.join(",")}" unless patterns == expected_patterns
puts "topology_patterns=#{patterns.join(",")}"

legacy = by_kind.fetch("ClusterDefinition").find { |item| item.dig("metadata", "name") == "elasticsearch" }
abort "legacy ClusterDefinition not rendered" unless legacy
legacy_patterns = legacy.dig("spec", "topologies").flat_map do |topology|
  topology["components"].map { |component| Regexp.new(component["compDef"]) }
end
legacy_names = %w[elasticsearch-9-1.2.0 elasticsearch-master-9-1.2.0 elasticsearch-data-9-1.2.0]
legacy_678_names = (6..8).flat_map do |major|
  ["elasticsearch-#{major}-1.2.0", "elasticsearch-master-#{major}-1.2.0", "elasticsearch-data-#{major}-1.2.0"]
end
puts "legacy_matches_9=#{legacy_patterns.any? { |pattern| legacy_names.any? { |name| pattern.match?(name) } }}"
puts "legacy_covers_678_families=#{legacy_678_names.all? { |name| legacy_patterns.any? { |pattern| pattern.match?(name) } }}"

legacy_bpt = by_kind.fetch("BackupPolicyTemplate").find do |item|
  item.dig("metadata", "name") == "elasticsearch-backup-policy-template"
end
legacy_bpt_patterns = legacy_bpt.dig("spec", "compDefs").map { |pattern| Regexp.new(pattern) }
legacy_bpt_names = (6..8).flat_map do |major|
  ["elasticsearch-#{major}-1.2.0", "elasticsearch-data-#{major}-1.2.0"]
end
legacy_bpt_master_names = (6..8).map { |major| "elasticsearch-master-#{major}-1.2.0" }
legacy_bpt_covers = legacy_bpt_names.all? do |name|
  legacy_bpt_patterns.any? { |pattern| pattern.match?(name) }
end
legacy_bpt_excludes_master = legacy_bpt_master_names.none? do |name|
  legacy_bpt_patterns.any? { |pattern| pattern.match?(name) }
end
legacy_bpt_excludes_9 = legacy_bpt_patterns.none? { |pattern| pattern.match?("elasticsearch-9-1.2.0") }
puts "legacy_bpt_covers_678=#{legacy_bpt_covers}"
puts "legacy_bpt_excludes_master=#{legacy_bpt_excludes_master}"
puts "legacy_bpt_excludes_9=#{legacy_bpt_excludes_9}"

cmpds = by_kind.fetch("ComponentDefinition").select do |item|
  item.dig("metadata", "name").match?(/^(elasticsearch(-master|-data)?|kibana)-9-/)
end
abort "expected four 9.x ComponentDefinitions" unless cmpds.length == 4
puts "cmpds=#{cmpds.map { |item| item.dig("metadata", "name").sub(/-9-.+$/, "-9") }.sort.join(",")}"

es_cmpds = cmpds.reject { |item| item.dig("metadata", "name").start_with?("kibana-") }
role_values = es_cmpds.to_h do |item|
  name = item.dig("metadata", "name").sub(/-9-.+$/, "-9")
  role = item.dig("spec", "vars").find { |var| var["name"] == "ELASTICSEARCH_ROLES" }.fetch("value")
  [name, role]
end
expected_roles = {
  "elasticsearch-9" => "master,data",
  "elasticsearch-master-9" => "master,ingest",
  "elasticsearch-data-9" => "data,ingest"
}
puts "roles_match_8x=#{role_values == expected_roles}"
fail_close = es_cmpds.all? do |item|
  item.dig("spec", "vars").any? { |var| var["name"] == "REQUIRE_VERSIONED_PLUGINS" && var["value"] == "true" }
end
custom_absent = es_cmpds.all? do |item|
  item.dig("spec", "runtime", "initContainers").none? { |container| container["name"] == "prepare-custom-plugins" }
end
collect_images = lambda do |value|
  case value
  when Hash
    value.flat_map do |key, child|
      key == "image" && child.is_a?(String) ? [child] : collect_images.call(child)
    end
  when Array
    value.flat_map { |child| collect_images.call(child) }
  else
    []
  end
end
cmpd_explicit_images = es_cmpds.flat_map { |item| collect_images.call(item.dig("spec", "runtime")) }
cmpd_images_digest_only = cmpd_explicit_images.all? { |image| image.match?(/@sha256:[0-9a-f]{64}$/) }
config_isolated = es_cmpds.all? do |item|
  item.dig("spec", "configs").all? { |config| config["template"].start_with?("elasticsearch-9-config-tpl-") }
end
puts "plugin_fail_close=#{fail_close}"
puts "custom_init_absent=#{custom_absent}"
puts "cmpd_explicit_images_digest_only=#{cmpd_images_digest_only}"
puts "config_isolated=#{config_isolated}"

kibana_config = by_kind.fetch("ConfigMap").find do |item|
  item.dig("metadata", "name") == "kibana-9-config-tpl"
end
abort "9.x Kibana ConfigMap not rendered" unless kibana_config
kibana_config_source = kibana_config.dig("data", "kibana.yml")
kibana_multi_component_credentials =
  kibana_config_source.include?("ELASTICSEARCH_HOST_") &&
  kibana_config_source.include?("KIBANA_SYSTEM_USER_PASSWORD_%s")
puts "kibana_multi_component_credentials=#{kibana_multi_component_credentials}"

es_version = by_kind.fetch("ComponentVersion").find { |item| item.dig("metadata", "name") == "elasticsearch" }
release9 = es_version.dig("spec", "releases").find { |item| item["serviceVersion"] == "9.3.2" }
abort "9.3.2 Elasticsearch release not rendered" unless release9
images = release9.fetch("images")
puts "es_release_images=#{images.keys.sort.join(",")}"
puts "es_release_digest_only=#{images.values.all? { |image| image.match?(/@sha256:[0-9a-f]{64}$/) }}"
puts "custom_image_absent=#{!images.key?("prepare-custom-plugins")}"

kibana_version = by_kind.fetch("ComponentVersion").find { |item| item.dig("metadata", "name") == "kibana" }
kibana9 = kibana_version.dig("spec", "releases").find { |item| item["serviceVersion"] == "9.3.2" }
puts "kibana_digest=#{kibana9.dig("images", "kibana")}"

bpt = by_kind.fetch("BackupPolicyTemplate").find { |item| item.dig("metadata", "name") == "elasticsearch-9-backup-policy-template" }
abort "9.x BackupPolicyTemplate not rendered" unless bpt
methods = bpt.dig("spec", "backupMethods").to_h { |method| [method["name"], method] }
mappings = methods.transform_values do |method|
  env = method.fetch("env").first
  mapping = env.dig("valueFrom", "versionMapping").first
  [env["name"], method["actionSetName"], mapping.fetch("serviceVersions").join(","), mapping["mappedValue"]].join("|")
end
puts "physical_mapping=#{mappings.fetch("full-backup")}"
puts "dump_mapping=#{mappings.fetch("es-dump")}"

actions = by_kind.fetch("ActionSet").select { |item| item.dig("metadata", "name").start_with?("elasticsearch-9-") }
action_images = actions.to_h do |action|
  backup = action.dig("spec", "backup", "backupData", "image")
  restore = action.dig("spec", "restore", "postReady", 0, "job", "image")
  [action.dig("metadata", "name"), "#{backup}|#{restore}"]
end
puts "physical_action=#{action_images.fetch("elasticsearch-9-physical-br")}"
puts "dump_action=#{action_images.fetch("elasticsearch-9-es-dump")}"
