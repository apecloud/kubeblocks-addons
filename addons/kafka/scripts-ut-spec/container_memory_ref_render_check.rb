# frozen_string_literal: true

require "yaml"

documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
definitions = documents.select { |doc| doc["kind"] == "ComponentDefinition" }

expected = %w[
  kafka27-broker-1.1.0-alpha.2
  kafka-broker-1.1.0-alpha.2
  kafka-combine-1.1.0-alpha.2
  kafka-controller-1.1.0-alpha.2
]

actual = []
definitions.each do |definition|
  kafka = Array(definition.dig("spec", "runtime", "containers")).find do |container|
    container["name"] == "kafka"
  end
  next unless kafka

  memory_env = Array(kafka["env"]).select do |entry|
    entry["name"] == "KB_KAFKA_CONTAINER_MEMORY_LIMIT_MIB"
  end
  next if memory_env.empty?

  name = definition.dig("metadata", "name")
  abort "#{name}: expected exactly one container memory env" unless memory_env.length == 1

  resource_ref = memory_env.fetch(0).dig("valueFrom", "resourceFieldRef")
  abort "#{name}: container memory ref must resolve against the executing container" unless resource_ref == {
    "resource" => "limits.memory",
    "divisor" => "1Mi"
  }
  actual << name
end

abort "unexpected ComponentDefinition container memory ref set" unless actual.sort == expected.sort
