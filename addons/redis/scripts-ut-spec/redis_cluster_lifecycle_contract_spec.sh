# shellcheck shell=bash

Describe "Redis Cluster lifecycle action contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/redis" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  ruby_not_available() { ! command -v ruby >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available
  Skip if "ruby not available" ruby_not_available

  render_lifecycle_templates() {
    tmp_render=$(mktemp -t redis-lifecycle-render-XXXXXX)
    helm template test "$(chart_path)" \
      --dependency-update \
      --show-only templates/clusterdefinition.yaml \
      --show-only templates/cmpd-redis-cluster.yaml \
      --show-only templates/paramsdef-redis-cluster.yaml \
      --show-only templates/opsdefinition-shardadd.yaml \
      --show-only templates/redis-cluster-scripts-template.yaml \
      --show-only templates/shardingdefinition.yaml >"$tmp_render"
  }

  validate_versioned_definition_contract() {
    render_lifecycle_templates || return $?
    ruby -ryaml -e '
      documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
      chart = YAML.load_file(ARGV.fetch(1))
      version = chart.fetch("version")
      expected_version = "1.2.0-alpha.8"
      abort "expected Redis chart version #{expected_version}, got #{version}" unless version == expected_version

      expected_cmpds = %w[5 6 7 8].map { |major| "redis-cluster-#{major}-#{version}" }
      actual_cmpds = documents.map do |document|
        next unless document["kind"] == "ComponentDefinition"
        name = document.dig("metadata", "name")
        name if name&.start_with?("redis-cluster-")
      end.compact.sort
      abort "versioned Redis Cluster ComponentDefinitions differ: #{actual_cmpds.inspect}" unless actual_cmpds == expected_cmpds

      sharding = documents.find { |document| document["kind"] == "ShardingDefinition" }
      abort "missing Redis ShardingDefinition" unless sharding
      expected_sharding = "redis-cluster-#{version}"
      actual_sharding = sharding.dig("metadata", "name")
      abort "expected ShardingDefinition #{expected_sharding}, got #{actual_sharding}" unless actual_sharding == expected_sharding
      expected_cmpd_pattern = "^redis-cluster-\\d+-#{version.gsub(".", "\\\\.")}$"
      actual_cmpd_pattern = sharding.dig("spec", "template", "compDef")
      abort "expected ShardingDefinition compDef #{expected_cmpd_pattern}, got #{actual_cmpd_pattern}" unless actual_cmpd_pattern == expected_cmpd_pattern

      actual_parameter_cmpds = documents.map do |document|
        document.dig("spec", "componentDef") if document["kind"] == "ParametersDefinition"
      end.compact.sort
      abort "versioned Redis Cluster ParametersDefinitions differ: #{actual_parameter_cmpds.inspect}" unless actual_parameter_cmpds == expected_cmpds

      cluster = documents.find { |document| document["kind"] == "ClusterDefinition" }
      abort "missing Redis ClusterDefinition" unless cluster
      cluster_topology = cluster.fetch("spec").fetch("topologies").find { |topology| topology["name"] == "cluster" }
      abort "missing Redis cluster topology" unless cluster_topology
      actual_reference = cluster_topology.fetch("shardings").first.fetch("shardingDef")
      abort "expected cluster topology to reference #{expected_sharding}, got #{actual_reference}" unless actual_reference == expected_sharding

      scripts = documents.find do |document|
        document["kind"] == "ConfigMap" &&
          document.dig("metadata", "name") == "redis-cluster-scripts-template-#{version}"
      end
      abort "missing versioned Redis Cluster scripts ConfigMap" unless scripts
      worker = scripts.fetch("data")["redis-cluster-shardadd-worker.sh"]
      abort "missing managed shardAdd worker in versioned scripts ConfigMap" unless worker&.include?("topology_is_converged")

      puts "versioned immutable definition contract passed"
    ' "$tmp_render" "$(chart_path)/Chart.yaml"
  }

  validate_managed_shardadd_contract() {
    render_lifecycle_templates || return $?
    ruby -ryaml -e '
      documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
      chart = YAML.load_file(ARGV.fetch(1))
      version = chart.fetch("version")

      sharding = documents.find { |document| document["kind"] == "ShardingDefinition" }
      abort "missing Redis ShardingDefinition" unless sharding
      annotations = sharding.dig("metadata", "annotations") || {}
      abort "managed shardAdd migration must skip the one-time immutable check" unless
        annotations["apps.kubeblocks.io/skip-immutable-check"] == "true"
      shard_add = sharding.dig("spec", "lifecycleActions", "shardAdd")
      expected_name = "redis-cluster-shardadd-#{version}"
      abort "expected shardAdd to reference #{expected_name}, got #{shard_add.inspect}" unless
        shard_add == {"opsDefinitionName" => expected_name}

      definition = documents.find do |document|
        document["kind"] == "OpsDefinition" && document.dig("metadata", "name") == expected_name
      end
      abort "missing managed shardAdd OpsDefinition #{expected_name}" unless definition
      spec = definition.fetch("spec")
      %w[preConditions componentInfos].each do |field|
        abort "managed shardAdd OpsDefinition must not define #{field}" if spec.key?(field)
      end
      extractors = spec.fetch("podInfoExtractors")
      abort "managed shardAdd requires exactly one PodInfoExtractor" unless extractors.length == 1
      extractor = extractors.first
      extractor_name = "redis-cluster-shardadd-inputs"
      abort "unexpected managed shardAdd PodInfoExtractor name" unless extractor["name"] == extractor_name
      abort "managed shardAdd must select any stable shard Pod" unless
        extractor.dig("podSelector", "multiPodSelectionPolicy") == "Any" &&
        extractor.dig("podSelector").keys == ["multiPodSelectionPolicy"]

      env_ref = lambda do |name, source_name, optional = false|
        value = {
          "name" => name,
          "valueFrom" => {
            "envRef" => {
              "targetContainerName" => "redis-cluster",
              "envName" => source_name
            }
          }
        }
        value["optional"] = true if optional
        value
      end
      expected_env = [
        env_ref.call("REDIS_DEFAULT_USER", "REDIS_DEFAULT_USER"),
        env_ref.call("REDIS_DEFAULT_PASSWORD", "REDIS_DEFAULT_PASSWORD"),
        env_ref.call("REDIS_TLS_ENABLED", "TLS_ENABLED", true),
        {
          "name" => "REDIS_SOURCE_POD_NAME",
          "valueFrom" => {"fieldPath" => {"fieldPath" => "metadata.name"}}
        },
        env_ref.call("REDIS_SOURCE_COMPONENT_NAME", "CURRENT_SHARD_COMPONENT_NAME"),
        env_ref.call("REDIS_CLUSTER_NAMESPACE", "CLUSTER_NAMESPACE"),
        env_ref.call("REDIS_CLUSTER_DOMAIN", "CLUSTER_DOMAIN"),
        env_ref.call("REDIS_SERVICE_PORT", "SERVICE_PORT")
      ]
      abort "managed shardAdd extracted env contract differs: #{extractor["env"].inspect}" unless
        extractor["env"] == expected_env
      expected_mounts = [{"name" => "tls", "mountPath" => "/etc/pki/tls", "readOnly" => true}]
      abort "managed shardAdd TLS mount contract differs: #{extractor["volumeMounts"].inspect}" unless
        extractor["volumeMounts"] == expected_mounts
      expected_parameters = %w[KB_SHARD_ADD_TOKEN KB_SHARDING_NAME KB_SHARD_ADD_SHARDS KB_SHARD_COUNT]
      parameter_schema = spec.dig("parametersSchema", "openAPIV3Schema")
      abort "managed shardAdd parameter schema must be an object" unless parameter_schema["type"] == "object"
      abort "managed shardAdd required parameters differ: #{parameter_schema["required"].inspect}" unless
        parameter_schema["required"] == expected_parameters
      properties = parameter_schema.fetch("properties")
      abort "managed shardAdd parameter properties differ: #{properties.keys.inspect}" unless
        properties.keys == expected_parameters
      expected_parameters.first(3).each do |parameter|
        abort "#{parameter} must be a non-empty string" unless
          properties[parameter] == {"type" => "string", "minLength" => 1}
      end
      abort "KB_SHARD_COUNT must be a positive integer" unless
        properties["KB_SHARD_COUNT"] == {"type" => "integer", "minimum" => 1}
      actions = spec.fetch("actions")
      abort "managed shardAdd requires exactly one action" unless actions.length == 1
      action = actions.first
      abort "managed shardAdd requires failurePolicy=Fail" unless action["failurePolicy"] == "Fail"
      abort "managed shardAdd must not define exec/resourceModifier" if
        action.key?("exec") || action.key?("resourceModifier")
      abort "managed shardAdd parameters differ: #{action["parameters"].inspect}" unless
        action["parameters"] == expected_parameters
      legacy_parameters = %w[shardAddToken shardingName newShardComponentNames targetShardCount]
      rendered = File.read(ARGV.fetch(0))
      leaked_legacy_parameters = legacy_parameters.select { |parameter| rendered.include?(parameter) }
      abort "managed shardAdd render still contains legacy parameters: #{leaked_legacy_parameters.inspect}" unless
        leaked_legacy_parameters.empty?
      workload = action.fetch("workload")
      abort "managed shardAdd requires ManagedJob" unless workload["type"] == "ManagedJob"
      abort "managed shardAdd requires backoffLimit=0" unless workload["backoffLimit"] == 0
      abort "managed shardAdd Job must use the exact PodInfoExtractor" unless
        workload["podInfoExtractorName"] == extractor_name
      pod_spec = workload.fetch("podSpec")
      abort "managed shardAdd Job must never restart its worker Pod" unless
        pod_spec["restartPolicy"] == "Never"
      abort "managed shardAdd Job must have a bounded 3-hour deadline" unless
        pod_spec["activeDeadlineSeconds"] == 10800
      expected_scripts_volume = {
        "name" => "scripts",
        "configMap" => {
          "name" => "redis-cluster-scripts-template-#{version}",
          "defaultMode" => 365
        }
      }
      abort "managed shardAdd Job must mount the versioned scripts ConfigMap" unless
        pod_spec.fetch("volumes") == [expected_scripts_volume]
      containers = workload.dig("podSpec", "containers") || []
      abort "managed shardAdd requires exactly one worker container" unless containers.length == 1
      worker_container = containers.first
      command = Array(worker_container["command"]) + Array(worker_container["args"])
      abort "managed shardAdd Job does not invoke the versioned worker" unless
        command.join(" ").include?("/scripts/redis-cluster-shardadd-worker.sh")
      abort "managed shardAdd worker must mount only the scripts volume directly" unless
        worker_container.fetch("volumeMounts") == [
          {"name" => "scripts", "mountPath" => "/scripts", "readOnly" => true}
        ]
      worker_env = worker_container.fetch("env").to_h { |item| [item.fetch("name"), item.fetch("value")] }
      expected_worker_env = {
        "REDIS_TLS_CA_FILE" => "/etc/pki/tls/ca.crt",
        "REDIS_TLS_CERT_FILE" => "/etc/pki/tls/tls.crt",
        "REDIS_TLS_KEY_FILE" => "/etc/pki/tls/tls.key",
        "REDIS_COMMAND_TIMEOUT_SECONDS" => "7200",
        "REDIS_COMMAND_KILL_GRACE_SECONDS" => "30"
      }
      abort "managed shardAdd worker static env differs: #{worker_env.inspect}" unless
        worker_env == expected_worker_env

      scripts = documents.find do |document|
        document["kind"] == "ConfigMap" &&
          document.dig("metadata", "name") == "redis-cluster-scripts-template-#{version}"
      end
      abort "missing versioned Redis Cluster scripts ConfigMap" unless scripts
      %w[redis-cluster-manage.sh redis-cluster6-manage.sh].each do |script_name|
        source = scripts.fetch("data").fetch(script_name)
        scale_out_body = source.split("scale_out_redis_cluster_shard() {", 2).fetch(1)
          .split("sync_acl_for_redis_cluster_shard() {", 2).fetch(0)
        abort "#{script_name} still owns shardAdd slot migration" if
          scale_out_body.include?("scale_out_shard_reshard")
        abort "#{script_name} does not positively close membership" unless
          scale_out_body.include?("membership converged; slot migration is delegated to the managed shardAdd Job")
      end

      puts "managed shardAdd rendered contract passed"
    ' "$tmp_render" "$(chart_path)/Chart.yaml"
  }

  validate_timeout_contract() {
    render_lifecycle_templates || return $?
    ruby -ryaml -e '
      documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
      post_provision = documents.map do |document|
        next unless document["kind"] == "ComponentDefinition"
        next unless document.dig("metadata", "name").start_with?("redis-cluster-")
        document.dig("spec", "lifecycleActions", "postProvision")
      end.compact
      abort "expected four Redis Cluster postProvision actions, got #{post_provision.length}" unless post_provision.length == 4
      post_timeouts = post_provision.map { |action| action.fetch("timeoutSeconds") }
      abort "postProvision timeoutSeconds must all be 50, got #{post_timeouts.inspect}" unless post_timeouts == [50, 50, 50, 50]

      sharding = documents.select { |document| document["kind"] == "ShardingDefinition" }
      abort "expected one ShardingDefinition, got #{sharding.length}" unless sharding.length == 1
      shard_timeout = sharding.first.dig("spec", "lifecycleActions", "shardRemove", "timeoutSeconds")
      abort "shardRemove timeoutSeconds must be 50, got #{shard_timeout.inspect}" unless shard_timeout == 50

      puts "lifecycle timeout contract passed"
    ' "$tmp_render"
  }

  extract_lifecycle_command() {
    action=$1
    major=${2:-7}
    ruby -ryaml -e '
      documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
      action = ARGV.fetch(1)
      major = ARGV.fetch(2)
      command = if action == "postProvision"
        definition = documents.find do |document|
          document["kind"] == "ComponentDefinition" &&
            document.dig("metadata", "name").start_with?("redis-cluster-#{major}-")
        end
        abort "missing Redis Cluster #{major} ComponentDefinition" unless definition
        definition.dig("spec", "lifecycleActions", "postProvision", "exec", "command", 2)
      else
        definition = documents.find { |document| document["kind"] == "ShardingDefinition" }
        abort "missing Redis ShardingDefinition" unless definition
        definition.dig("spec", "lifecycleActions", "shardRemove", "exec", "command", 2)
      end
      abort "missing #{action} shell command" unless command
      print command
    ' "$tmp_render" "$action" "$major"
  }

  write_fake_manage_script() {
    script=$1
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'printf "manage stdout\\n"' \
      'printf "manage stderr\\n" >&2' \
      'exit "${FAKE_MANAGE_RC:-0}"' >"$script"
    chmod +x "$script"
  }

  run_lifecycle_command() {
    action=$1
    major=${2:-7}
    legacy=${3:-false}
    rc=${4:-0}

    render_lifecycle_templates || return $?
    tmp_scripts=$(mktemp -d -t redis-lifecycle-scripts-XXXXXX)
    write_fake_manage_script "$tmp_scripts/redis-cluster-manage.sh"
    write_fake_manage_script "$tmp_scripts/redis-cluster6-manage.sh"

    command=$(extract_lifecycle_command "$action" "$major") || return $?
    command=${command//\/scripts\//$tmp_scripts/}
    LEGACY_REDIS=$legacy FAKE_MANAGE_RC=$rc /bin/bash -c "$command"
  }

  cleanup_lifecycle_contract() {
    [ -n "${tmp_render:-}" ] && rm -f "$tmp_render" 2>/dev/null || true
    [ -n "${tmp_scripts:-}" ] && rm -rf "$tmp_scripts" 2>/dev/null || true
    rm -f /tmp/post-provision.log /tmp/pre-terminate.log 2>/dev/null || true
  }
  AfterEach 'cleanup_lifecycle_contract'

  It "keeps postProvision and shardRemove inside the kbagent 60-second clamp"
    When call validate_timeout_contract
    The status should be success
    The output should include "lifecycle timeout contract passed"
  End

  It "publishes lifecycle spec changes under new versioned definition identities"
    When call validate_versioned_definition_contract
    The status should be success
    The output should include "versioned immutable definition contract passed"
  End

  It "renders the exact managed shardAdd bridge and Job contract"
    When call validate_managed_shardadd_contract
    The status should be success
    The output should include "managed shardAdd rendered contract passed"
  End

  It "replays postProvision failure diagnostics and preserves the manage rc"
    When call run_lifecycle_command postProvision 7 false 23
    The status should eq 23
    The stderr should include "manage stdout"
    The stderr should include "manage stderr"
  End

  It "keeps successful postProvision output out of stderr"
    When call run_lifecycle_command postProvision 7 false 0
    The status should be success
    The stderr should be blank
  End

  It "replays modern shardRemove failure diagnostics and preserves the manage rc"
    When call run_lifecycle_command shardRemove 7 false 24
    The status should eq 24
    The stderr should include "manage stdout"
    The stderr should include "manage stderr"
  End

  It "replays legacy shardRemove failure diagnostics and preserves the manage rc"
    When call run_lifecycle_command shardRemove 6 true 25
    The status should eq 25
    The stderr should include "manage stdout"
    The stderr should include "manage stderr"
  End

  It "keeps successful modern shardRemove output out of stderr"
    When call run_lifecycle_command shardRemove 7 false 0
    The status should be success
    The stderr should be blank
  End

  It "keeps successful legacy shardRemove output out of stderr"
    When call run_lifecycle_command shardRemove 6 true 0
    The status should be success
    The stderr should be blank
  End
End
