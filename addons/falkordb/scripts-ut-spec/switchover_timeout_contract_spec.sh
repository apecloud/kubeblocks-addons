#!/bin/bash

Describe "FalkorDB switchover timeout contract"
  chart_path() {
    printf '%s/addons/falkordb\n' "$(cd "${SHELLSPEC_PROJECT_ROOT:-.}" && pwd)"
  }

  rendered_switchover_timeout() {
    helm template test "$(chart_path)" \
      --show-only templates/cmpd-falkordb.yaml \
      | ruby -ryaml -e '
          component = YAML.load_stream($stdin.read).compact.find do |doc|
            doc["kind"] == "ComponentDefinition" &&
              doc.dig("metadata", "name") == "falkordb-4-1.2.0-alpha.0"
          end
          abort "rendered ComponentDefinition not found" unless component
          timeout = component.dig(
            "spec", "lifecycleActions", "switchover", "timeoutSeconds"
          )
          abort "rendered switchover timeout is #{timeout.inspect}" unless timeout == -1
          puts timeout
        '
  }

  It "renders the negative kbagent timeout on the intended lifecycle action"
    When call rendered_switchover_timeout
    The status should be success
    The output should equal "-1"
  End

End
