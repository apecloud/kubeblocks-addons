# shellcheck shell=sh

validate_opsdefinition_service_names() {
  status=0

  for file in \
    ../templates/opsdefinitions/topic.yaml \
    ../templates/opsdefinitions/quota.yaml \
    ../templates/opsdefinitions/useracl.yaml
  do
    advertised_count=$(grep -c '^    serviceName: advertised-listener$' "$file" || true)
    if [ "$advertised_count" -ne 2 ]; then
      echo "$file: expected both kafka-broker and kafka-combine to use advertised-listener"
      status=1
    fi

    if grep -q '^    serviceName: broker$' "$file"; then
      echo "$file: references missing broker service"
      status=1
    fi
  done

  return "$status"
}

validate_opsdefinition_replica_vars() {
  status=0

  for file in \
    ../templates/opsdefinitions/topic.yaml \
    ../templates/opsdefinitions/quota.yaml \
    ../templates/opsdefinitions/useracl.yaml
  do
    if ! grep -q 'KB_COMP_REPLICAS' "$file"; then
      echo "$file: does not use the action pod replica variable KB_COMP_REPLICAS"
      status=1
    fi

    if grep -q '\${COMPONENT_REPLICAS}' "$file"; then
      echo "$file: uses the runtime pod replica variable COMPONENT_REPLICAS"
      status=1
    fi
  done

  return "$status"
}

Describe "Kafka OpsDefinition service bindings"
  It "uses the declared advertised-listener service for broker and combined components"
    When call validate_opsdefinition_service_names
    The status should be success
    The output should be blank
  End


  It "uses the replica count injected into the action pod"
    When call validate_opsdefinition_replica_vars
    The status should be success
    The output should be blank
  End
End
