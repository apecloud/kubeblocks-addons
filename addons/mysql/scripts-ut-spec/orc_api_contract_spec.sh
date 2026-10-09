# shellcheck shell=bash

Describe "Orchestrator API contract"
  Describe "init alias endpoint"
    Include ../scripts/init-mysql-instance-for-orc.sh

    It "normalizes a host endpoint with the API port"
      ORCHESTRATOR_API=""
      ORC_ENDPOINTS="mysql-orchestrator"
      ORC_PORTS="3000"
      When call orchestrator_api_base
      The output should equal "http://mysql-orchestrator:3000"
      The status should be success
    End

    It "does not double-prefix a configured URL"
      ORCHESTRATOR_API="http://mysql-orchestrator:3000/api"
      When call orchestrator_api_base
      The output should equal "http://mysql-orchestrator:3000"
      The status should be success
    End

    It "uses the normalized API endpoint for alias registration"
      ORCHESTRATOR_API=""
      ORC_ENDPOINTS="mysql-orchestrator:9999"
      ORC_PORTS="3000"
      curl() { printf '%s\n' "$*"; }
      When call set_cluster_alias "mysql-0:3306" "mysql"
      The output should include "--max-time 4"
      The output should include "http://mysql-orchestrator:3000/api/set-cluster-alias/mysql-0:3306?alias=mysql"
      The status should be success
    End
  End

  Describe "client HTTP response"
    setup_client() {
      export __SOURCED__=1
      export ORCHESTRATOR_API="http://orchestrator:3000/api"
    }
    Before "setup_client"
    Include ../scripts/orchestrator-client.sh

    It "rejects an HTTP error even when the body is JSON"
      curl() { printf '%s\n' '{"Code":"OK"}'; return 22; }
      sleep() { :; }
      When run api "clusters-info"
      The status should be failure
      The stderr should include "Cannot access orchestrator"
    End

    It "rejects a JSON null response"
      curl() { printf '%s\n' 'null'; }
      sleep() { :; }
      When run api "clusters-info"
      The status should be failure
      The stderr should include "Cannot access orchestrator"
    End
  End
End
