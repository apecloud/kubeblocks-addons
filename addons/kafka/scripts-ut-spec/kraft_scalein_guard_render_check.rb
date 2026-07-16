# frozen_string_literal: true

require "yaml"

documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
definitions = documents.select { |doc| doc["kind"] == "ComponentDefinition" }
by_name = definitions.to_h { |doc| [doc.dig("metadata", "name"), doc] }

expected_names = %w[
  kafka-combine-1.1.0-alpha.1
  kafka-controller-1.1.0-alpha.1
]

abort "unexpected guarded ComponentDefinition names" unless expected_names.all? { |name| by_name.key?(name) }

expected_names.each do |name|
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
