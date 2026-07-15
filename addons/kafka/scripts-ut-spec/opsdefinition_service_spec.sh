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

    if ! grep -Fq '[[ "${KB_COMP_REPLICAS:-}" =~ ^[1-9][0-9]*$ ]]' "$file"; then
      echo "$file: does not reject a missing or invalid KB_COMP_REPLICAS value"
      status=1
    fi

    if grep -q '\${COMPONENT_REPLICAS}' "$file"; then
      echo "$file: uses the runtime pod replica variable COMPONENT_REPLICAS"
      status=1
    fi
  done

  return "$status"
}

validate_opsdefinition_replica_guard_behavior() {
  status=0

  for file in \
    ../templates/opsdefinitions/topic.yaml \
    ../templates/opsdefinitions/quota.yaml \
    ../templates/opsdefinitions/useracl.yaml
  do
    guard=$(sed -n '/\[\[ "${KB_COMP_REPLICAS:-}" =~/,/^[[:space:]]*SERVERS=()/p' "$file" | sed '$d; s/^[[:space:]]*//')

    for value in __UNSET__ "" 0 -1 abc 01 "1 "
    do
      if [ "$value" = "__UNSET__" ]; then
        output=$(env -u KB_COMP_REPLICAS bash -c "$guard" 2>&1)
      else
        output=$(env KB_COMP_REPLICAS="$value" bash -c "$guard" 2>&1)
      fi
      guard_status=$?

      if [ "$guard_status" -eq 0 ] || [ "$output" != "KB_COMP_REPLICAS must be a positive integer" ]; then
        echo "$file: invalid replica value '$value' did not fail with the expected error"
        status=1
      fi
    done

    for value in 1 10
    do
      output=$(env KB_COMP_REPLICAS="$value" bash -c "$guard" 2>&1)
      guard_status=$?

      if [ "$guard_status" -ne 0 ] || [ -n "$output" ]; then
        echo "$file: valid replica value '$value' was rejected"
        status=1
      fi
    done
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

  It "fails fast unless the action pod replica count is a positive integer"
    When call validate_opsdefinition_replica_guard_behavior
    The status should be success
    The output should be blank
  End
End
