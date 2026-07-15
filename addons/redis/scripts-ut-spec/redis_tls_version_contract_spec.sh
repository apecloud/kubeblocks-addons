# shellcheck shell=bash

Describe "Redis TLS service-version contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s" "${REDIS_TLS_CONTRACT_CHART_PATH:-$(repo_root)/addons/redis}"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  ruby_not_available() { ! command -v ruby >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available
  Skip if "ruby not available" ruby_not_available

  validate_tls_version_contract() {
    helm template test "$(chart_path)" \
      --dependency-update \
      --show-only templates/cmpd-redis.yaml \
      --show-only templates/cmpd-redis-cluster.yaml \
      --show-only templates/cmpd-redis-sentinel.yaml | ruby -ryaml -e '
        documents = YAML.load_stream($stdin.read).compact
        chart = YAML.load_file(ARGV.fetch(0))
        version = chart.fetch("version")
        definitions = documents.select { |document| document["kind"] == "ComponentDefinition" }

        families = {
          "redis" => "redis",
          "redis-cluster" => "redis-cluster",
          "redis-sentinel" => "redis-sentinel"
        }
        majors = %w[5 6 7 8]
        rows = []
        violations = []

        families.each_key do |family|
          majors.each do |major|
            name = "#{family}-#{major}-#{version}"
            definition = definitions.find { |document| document.dig("metadata", "name") == name }
            abort "missing ComponentDefinition #{name}" unless definition

            tls = definition.dig("spec", "tls")
            rows << "#{name}\ttls=#{tls ? "present" : "absent"}"
            if major == "5"
              violations << "Redis 5 must not advertise TLS: #{name}" if tls
            else
              expected_tls = {
                "volumeName" => "tls",
                "mountPath" => "/etc/pki/tls",
                "caFile" => "ca.crt",
                "certFile" => "tls.crt",
                "keyFile" => "tls.key"
              }
              violations << "TLS contract differs for #{name}: #{tls.inspect}" unless tls == expected_tls
            end
          end
        end

        puts rows
        abort violations.join("\n") unless violations.empty?

        redis5 = definitions.find { |document| document.dig("metadata", "name") == "redis-5-#{version}" }
        cluster5 = definitions.find { |document| document.dig("metadata", "name") == "redis-cluster-5-#{version}" }
        sentinel5 = definitions.find { |document| document.dig("metadata", "name") == "redis-sentinel-5-#{version}" }

        runtime_container = lambda do |definition, container_name|
          containers = definition.dig("spec", "runtime", "containers") || []
          container = containers.find { |entry| entry["name"] == container_name }
          abort "missing runtime container #{container_name}" unless container
          container
        end

        redis5_runtime = runtime_container.call(redis5, "redis")
        cluster5_runtime = runtime_container.call(cluster5, "redis-cluster")
        sentinel5_runtime = runtime_container.call(sentinel5, "redis-sentinel")
        abort "Redis 5 data script route changed" unless redis5_runtime["command"] == ["/scripts/redis5-start.sh"]
        abort "Redis 5 cluster script route changed" unless cluster5_runtime["command"] == ["/scripts/redis-cluster5-server-start.sh"]
        sentinel5_command = [sentinel5_runtime["command"], sentinel5_runtime["args"]].flatten.compact.join("\n")
        abort "Redis 5 sentinel script route changed" unless sentinel5_command.include?("/scripts/redis5-sentinel-start-v2.sh")

        puts "Redis 5 rejects TLS while Redis 6/7/8 retain TLS"
      ' "$(chart_path)/Chart.yaml"
  }

  It "does not advertise TLS for Redis 5 and preserves TLS for Redis 6/7/8"
    When call validate_tls_version_contract
    The status should be success
    The output should include "Redis 5 rejects TLS while Redis 6/7/8 retain TLS"
  End
End
