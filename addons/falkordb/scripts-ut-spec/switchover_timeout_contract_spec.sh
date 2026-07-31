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
          puts "definition=#{component.dig("metadata", "name")},timeout=#{timeout}"
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
      abort "migration must preserve serviceVersion" if component.key?("serviceVersion")
      puts [
        "migration=#{migration.dig("spec", "type")}",
        "component=#{component["componentName"]}",
        "target=#{component["componentDefinitionName"]}",
        "serviceVersion=preserved",
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
        "($old_uids | index($uid)) == null",
        ".metadata.deletionTimestamp == null",
        ".name == \"KB_AGENT_ACTION\"",
        ".timeoutSeconds == -1",
        "--request-timeout=",
        "--kill-after=10s",
        "SECONDS < deadline"
      ]
      missing = required.reject { |contract| verifier.include?(contract) }
      abort "migration verifier missing: #{missing.join(", ")}" unless missing.empty?
      puts "readback=component+pod-uid+ready+kbagent,bounded=true"
    ' "$(chart_path)"
  }

  It "publishes a new definition and an explicit existing-cluster upgrade"
    When call rendered_upgrade_contract
    The status should be success
    The output should equal "definition=falkordb-4-1.2.0-alpha.1,timeout=-1
migration=Upgrade,component=falkordb,target=falkordb-4-1.2.0-alpha.1,serviceVersion=preserved,force=false
readback=component+pod-uid+ready+kbagent,bounded=true"
  End

End
