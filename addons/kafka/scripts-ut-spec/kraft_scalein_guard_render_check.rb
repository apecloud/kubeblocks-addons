# frozen_string_literal: true

require "yaml"

documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
definitions = documents.select { |doc| doc["kind"] == "ComponentDefinition" }
by_name = definitions.to_h { |doc| [doc.dig("metadata", "name"), doc] }

expected_definition_names = %w[
  kafka27-broker-1.1.0-alpha.2
  kafka-broker-1.1.0-alpha.2
  kafka-combine-1.1.0-alpha.2
  kafka-controller-1.1.0-alpha.2
  kafka-exporter-1.1.0-alpha.2
]
expected_guarded_names = %w[
  kafka-combine-1.1.0-alpha.2
  kafka-controller-1.1.0-alpha.2
]
expected_renderer_targets = {
  "kafka-broker-pcr-1.1.0-alpha.2" => "kafka-broker-1.1.0-alpha.2",
  "kafka2-broker-pcr-1.1.0-alpha.2" => "kafka27-broker-1.1.0-alpha.2",
  "kafka-combine-pcr-1.1.0-alpha.2" => "kafka-combine-1.1.0-alpha.2",
  "kafka-controller-pcr-1.1.0-alpha.2" => "kafka-controller-1.1.0-alpha.2"
}
expected_kafka27_config = "kafka27-configuration-tpl-1.1.0-alpha.2"
expected_chart_label = "kafka-1.1.0-alpha.2"

rendered_strings = []
collect_strings = lambda do |value|
  case value
  when Hash
    value.each_value { |nested| collect_strings.call(nested) }
  when Array
    value.each { |nested| collect_strings.call(nested) }
  when String
    rendered_strings << value
  end
end
documents.each { |document| collect_strings.call(document) }
abort "rendered object identity or reference still uses alpha.1" if rendered_strings.any? do |value|
  value.include?("1.1.0-alpha.1")
end

definition_names = definitions.map { |definition| definition.dig("metadata", "name") }
abort "unexpected ComponentDefinition identity set" unless definition_names.sort == expected_definition_names.sort

renderers = documents.select { |doc| doc["kind"] == "ParamConfigRenderer" }
renderer_names = renderers.map { |renderer| renderer.dig("metadata", "name") }
abort "unexpected ParamConfigRenderer identity set" unless renderer_names.sort == expected_renderer_targets.keys.sort
renderer_targets = renderers.to_h do |renderer|
  [renderer.dig("metadata", "name"), renderer.dig("spec", "componentDef")]
end
abort "ParamConfigRenderer identity or componentDef reference mismatch" unless renderer_targets == expected_renderer_targets

kafka27_configs = documents.select do |doc|
  doc["kind"] == "ConfigMap" && doc.dig("metadata", "name")&.start_with?("kafka27-configuration-tpl-")
end
abort "Kafka 2.7 configuration template identity mismatch" unless kafka27_configs.map do |config|
  config.dig("metadata", "name")
end == [expected_kafka27_config]
kafka27_config = kafka27_configs.fetch(0)

versioned_objects = definitions + renderers + [kafka27_config]
abort "version-derived object chart label mismatch" unless versioned_objects.all? do |object|
  object.dig("metadata", "labels", "helm.sh/chart") == expected_chart_label
end

kafka27_definition = by_name.fetch("kafka27-broker-1.1.0-alpha.2")
kafka27_templates = Array(kafka27_definition.dig("spec", "configs")).map { |config| config["template"] }
versioned_kafka27_templates = kafka27_templates.grep(/^kafka27-configuration-tpl-/)
abort "Kafka 2.7 ComponentDefinition config reference mismatch" unless versioned_kafka27_templates == [expected_kafka27_config]

expected_guarded_names.each do |name|
  definition = by_name.fetch(name)
  action = definition.dig("spec", "lifecycleActions", "memberLeave")
  abort "#{name}: memberLeave action mismatch" unless action == {
    "exec" => {
      "command" => ["/bin/sh", "/scripts/kafka-kraft-controller-member-leave.sh"],
      "container" => "kafka"
    }
  }

  script = definition.dig("spec", "scripts").find { |entry| entry["volumeName"] == "scripts" }
  abort "#{name}: script volume mismatch" unless script["defaultMode"] == 0o755

  kafka = definition.dig("spec", "runtime", "containers").find { |container| container["name"] == "kafka" }
  mount = kafka.fetch("volumeMounts").find do |volume_mount|
    volume_mount["mountPath"] == "/scripts/kafka-kraft-controller-member-leave.sh"
  end
  abort "#{name}: guard mount mismatch" unless mount == {
    "mountPath" => "/scripts/kafka-kraft-controller-member-leave.sh",
    "name" => "scripts",
    "subPath" => "kafka-kraft-controller-member-leave.sh"
  }
end

broker_definitions = definitions.select { |doc| doc.dig("metadata", "name")&.start_with?("kafka-broker-") }
abort "broker ComponentDefinition must not define memberLeave" if broker_definitions.any? do |doc|
  doc.dig("spec", "lifecycleActions", "memberLeave")
end

scripts = documents.find do |doc|
  doc["kind"] == "ConfigMap" && doc.dig("metadata", "name") == "kafka-server-scripts-tpl"
end
guard = scripts.dig("data", "kafka-kraft-controller-member-leave.sh")
source_guard = File.read("../scripts/kafka-kraft-controller-member-leave.sh").chomp
abort "rendered guard script mismatch" unless guard == source_guard
