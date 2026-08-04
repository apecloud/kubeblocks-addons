#!/bin/bash
# shellcheck disable=SC2016

Describe "FalkorDB rebalance config handoff contract"
  chart_path() {
    printf '%s/addons/falkordb\n' "$(cd "${SHELLSPEC_PROJECT_ROOT:-.}" && pwd)"
  }

  validate_rendered_handoff() {
    helm template test "$(chart_path)" \
      --show-only templates/opsdefinition-rebalance.yaml \
      | ruby -ryaml -e '
          ops = YAML.load_stream($stdin.read).compact.find do |doc|
            doc["kind"] == "OpsDefinition" &&
              doc.dig("metadata", "name") == "falkordb-cluster-rebalance"
          end
          abort "rendered OpsDefinition not found" unless ops

          workload = ops.dig("spec", "actions", 0, "workload")
          abort "rebalance workload type changed" unless \
            workload.fetch("type") == "Job"
          abort "rebalance extractor binding changed" unless \
            workload.fetch("podInfoExtractorName") == "falkordbUrl"

          extractors = ops.dig("spec", "podInfoExtractors")
          extractor = extractors.find { |item| item["name"] == "falkordbUrl" }
          abort "rebalance extractor missing" unless extractor
          expected_env_names = [
            "REDIS_DEFAULT_USER",
            "REDIS_DEFAULT_PASSWORD",
            "CLUSTER_DOMAIN",
            "CURRENT_POD_NAME",
            "CURRENT_SHARD_COMPONENT_NAME",
            "CLUSTER_NAMESPACE"
          ]
          extractor_env = extractor.fetch("env")
          abort "rebalance extractor env names changed" unless \
            extractor_env.map { |item| item.fetch("name") } ==
              expected_env_names
          abort "rebalance extractor envRef mapping changed" unless \
            extractor_env.all? do |item|
              item.dig("valueFrom", "envRef", "envName") == item.fetch("name")
            end

          pod_spec = workload.fetch("podSpec")
          abort "rebalance restart policy changed" unless \
            pod_spec.fetch("restartPolicy") == "Never"
          containers = pod_spec.fetch("containers")
          abort "rebalance containers changed" unless \
            containers.map { |c| c.fetch("name") } ==
              ["busybox-init", "falkordb-rebalance"]
          abort "rebalance producer must remain a regular container" unless \
            Array(pod_spec["initContainers"]).empty?

          by_name = containers.to_h { |c| [c.fetch("name"), c] }
          producer = by_name.fetch("busybox-init")
          consumer = by_name.fetch("falkordb-rebalance")

          abort "producer shell command changed" unless \
            producer.fetch("command") == ["/bin/sh", "-c"]
          expected_mount = [{"name" => "reshard-config", "mountPath" => "/tmp"}]
          abort "producer shared mount changed" unless \
            producer.fetch("volumeMounts") == expected_mount
          abort "consumer shared mount changed" unless \
            consumer.fetch("volumeMounts") == expected_mount
          expected_volume = [{"name" => "reshard-config", "emptyDir" => {}}]
          abort "shared emptyDir changed" unless \
            pod_spec.fetch("volumes") == expected_volume

          abort "ape-dts image changed" unless \
            consumer.fetch("image") ==
              "docker.io/apecloud/ape-dts:2.0.26-alpha.16"
          abort "ape-dts shell command changed" unless \
            consumer.fetch("command") == ["/busybox/sh", "-c"]

          producer_args = producer.fetch("args")
          abort "producer script must be one shell argument" unless \
            producer_args.is_a?(Array) && producer_args.length == 1 &&
              producer_args.first.is_a?(String)
          producer_script = producer_args.first
          expected_producer_script = <<~SCRIPT
            set -e
            POD_FQDN=$CURRENT_POD_NAME.$CURRENT_SHARD_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN
            REDIS_URL="redis://${REDIS_DEFAULT_USER}:${REDIS_DEFAULT_PASSWORD}@${POD_FQDN}"
            echo ${REDIS_URL}
            cat <<EOF > /tmp/reshard.ini.tmp
            [extractor]
            db_type=redis
            extract_type=reshard
            url=${REDIS_URL}
            [sinker]
            sink_type=dummy
            EOF
            mv /tmp/reshard.ini.tmp /tmp/reshard.ini
          SCRIPT
          abort "producer script contract changed" unless \
            producer_script == expected_producer_script

          consumer_args = consumer.fetch("args")
          abort "consumer script must be one shell argument" unless \
            consumer_args.is_a?(Array) && consumer_args.length == 1 &&
              consumer_args.first.is_a?(String)
          consumer_script = consumer_args.first
          expected_consumer_script = <<~SCRIPT
            wait_seconds=0
            while [ ! -s /tmp/reshard.ini ]; do
              if [ "$wait_seconds" -ge 120 ]; then
                echo "timed out waiting for /tmp/reshard.ini" >&2
                exit 1
              fi
              sleep 1
              wait_seconds=$((wait_seconds + 1))
            done
            exec /ape-dts /tmp/reshard.ini
          SCRIPT
          abort "consumer script contract changed" unless \
            consumer_script == expected_consumer_script

          puts "contract-ok"
        '
  }

  It "renders the complete ordered producer-consumer contract"
    When call validate_rendered_handoff
    The status should be success
    The output should equal "contract-ok"
  End
End
