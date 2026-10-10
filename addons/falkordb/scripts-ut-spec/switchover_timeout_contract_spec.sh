#!/bin/bash

Describe "FalkorDB switchover timeout contract"
  chart_path() {
    printf '%s/addons/falkordb\n' "$(cd "${SHELLSPEC_PROJECT_ROOT:-.}" && pwd)"
  }

  rendered_upgrade_contract() {
    helm template test "$(chart_path)" \
      --show-only templates/cmpd-falkordb.yaml \
      | ruby -ryaml -e '
          component = YAML.load_stream($stdin.read).compact.find do |doc|
            doc["kind"] == "ComponentDefinition" &&
              doc.dig("metadata", "name") == "falkordb-4-1.2.0-alpha.1"
          end
          abort "rendered ComponentDefinition not found" unless component
          timeout = component.dig(
            "spec", "lifecycleActions", "switchover", "timeoutSeconds"
          )
          abort "rendered switchover timeout is #{timeout.inspect}" unless timeout == -1
          sentinel_vars = %w[
            SENTINEL_COMPONENT_NAME
            SENTINEL_USER
            SENTINEL_PASSWORD
            SENTINEL_POD_NAME_LIST
            SENTINEL_POD_FQDN_LIST
            SENTINEL_SERVICE_PORT
          ]
          vars = component.dig("spec", "vars").to_h { |var| [var["name"], var] }
          refs = sentinel_vars.map do |name|
            value_from = vars.fetch(name).fetch("valueFrom")
            selector = value_from.values.find { |value| value.is_a?(Hash) }
            selector&.fetch("compDef", nil)
          end
          abort "Sentinel references are #{refs.inspect}" unless refs == Array.new(6, "falkordb-sent-4")
          puts "definition=#{component.dig("metadata", "name")},timeout=#{timeout},sentinelRefs=stable:6"
        '

    ruby -ryaml -e '
      migration = YAML.load_file(
        File.join(ARGV.fetch(0), "examples", "upgrade-switchover-timeout.yaml")
      )
      components = migration.dig("spec", "upgrade", "components")
      abort "expected exactly one upgrade component" unless components&.length == 1
      component = components.first
      force = migration.dig("spec", "force")
      abort "migration must not force the upgrade" unless force.nil? || force == false
      abort "migration must pin serviceVersion" unless component["serviceVersion"] == "4.12.5"
      puts [
        "migration=#{migration.dig("spec", "type")}",
        "component=#{component["componentName"]}",
        "target=#{component["componentDefinitionName"]}",
        "serviceVersion=#{component["serviceVersion"]}",
        "force=false"
      ].join(",")
    ' "$(chart_path)"

    ruby -e '
      verifier = File.read(
        File.join(ARGV.fetch(0), "examples", "upgrade-switchover-timeout.sh")
      )
      required = [
        "old_pod_uids",
        ".items[0].spec.compDef == $target",
        ".items[0].spec.serviceVersion == $service_version",
        "($old_uids | index($uid)) == null",
        ".metadata.deletionTimestamp == null",
        "pod_image_contract",
        "imageID",
        "sentinel_env_contract",
        "expected_sentinel_identity",
        ".name == \"KB_AGENT_ACTION\"",
        ".timeoutSeconds == -1",
        "--request-timeout=",
        "--kill-after=10s",
        "SECONDS < deadline"
      ]
      missing = required.reject { |contract| verifier.include?(contract) }
      abort "migration verifier missing: #{missing.join(", ")}" unless missing.empty?
      puts "readback=component+service-version+pod-uid+ready+images+sentinel+kbagent,bounded=true"
    ' "$(chart_path)"
  }

  It "publishes a new definition and an explicit existing-cluster upgrade"
    When call rendered_upgrade_contract
    The status should be success
    The output should equal "definition=falkordb-4-1.2.0-alpha.1,timeout=-1,sentinelRefs=stable:6
migration=Upgrade,component=falkordb,target=falkordb-4-1.2.0-alpha.1,serviceVersion=4.12.5,force=false
readback=component+service-version+pod-uid+ready+images+sentinel+kbagent,bounded=true"
  End

End
