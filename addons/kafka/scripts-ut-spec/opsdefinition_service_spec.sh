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

Describe "Kafka OpsDefinition service bindings"
  It "uses the declared advertised-listener service for broker and combined components"
    When call validate_opsdefinition_service_names
    The status should be success
    The output should be blank
  End
End
