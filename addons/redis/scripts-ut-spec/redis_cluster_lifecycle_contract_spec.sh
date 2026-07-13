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
      --show-only templates/cmpd-redis-cluster.yaml \
      --show-only templates/shardingdefinition.yaml >"$tmp_render"
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
