# shellcheck shell=sh

expected_guard_error='Kafka KRaft controller scale-in is unsupported: this addon uses static controller.quorum.voters; keep controller replicas unchanged and scale only brokers in separated topology'

validate_guard_templates() {
  status=0

  for file in ../templates/cmpd-combine.yaml ../templates/cmpd-controller.yaml
  do
    member_leave_count=$(grep -c '^    memberLeave:$' "$file" || true)
    container_count=$(grep -c '^        container: kafka$' "$file" || true)
    shell_count=$(grep -c '^          - /bin/sh$' "$file" || true)
    command_count=$(grep -c '^          - /scripts/kafka-kraft-controller-member-leave.sh$' "$file" || true)
    mount_count=$(grep -c '^            mountPath: /scripts/kafka-kraft-controller-member-leave.sh$' "$file" || true)

    if [ "$member_leave_count" -ne 1 ] || [ "$container_count" -ne 1 ] || \
       [ "$shell_count" -ne 1 ] || \
       [ "$command_count" -ne 1 ] || [ "$mount_count" -ne 1 ]; then
      echo "$file: expected one kafka-container memberLeave action and one guard-script mount"
      status=1
    fi
  done

  if grep -q '^    memberLeave:$' ../templates/cmpd-broker.yaml; then
    echo '../templates/cmpd-broker.yaml: broker-only component must not define memberLeave'
    status=1
  fi

  if ! grep -q '^#!/bin/sh$' ../scripts/kafka-kraft-controller-member-leave.sh || \
     grep -q '/bin/bash' ../scripts/kafka-kraft-controller-member-leave.sh; then
    echo '../scripts/kafka-kraft-controller-member-leave.sh: guard must use the target image POSIX shell'
    status=1
  fi

  if ! grep -q '^  kafka-kraft-controller-member-leave.sh: |-$' ../templates/script-template.yaml; then
    echo '../templates/script-template.yaml: guard script is not registered'
    status=1
  fi

  if ! grep -q 'does not automatically restore the requested replica count' ../README.md || \
     ! grep -q 'Do not treat timeout as cancellation' ../README.md || \
     ! grep -q 'does not retrofit the guard into existing Components' ../README.md || \
     ! grep -q 'Updating replicas through the Cluster API does not bypass' ../README.md; then
    echo '../README.md: timeout and recovery boundaries are missing'
    status=1
  fi

  if [ -e ../../../examples/kafka/scale-in.yaml ] || \
     grep -q 'Scale-in.*scale-in.yaml' ../../../examples/kafka/README.md || \
     grep -q 'desired non-zero number' ../../../examples/kafka/README.md || \
     grep -q 'Combined/Separated.*Yes' ../../../examples/kafka/README.md; then
    echo '../../../examples/kafka: unsafe controller scale-in example is still published'
    status=1
  fi

  return "$status"
}

validate_guard_has_no_side_effects() {
  guard_dir=$(mktemp -d)
  guard_script=$(cd ../scripts && pwd)/kafka-kraft-controller-member-leave.sh
  output=$(cd "$guard_dir" && "$guard_script" 2>&1)
  guard_status=$?
  entries=$(find "$guard_dir" -mindepth 1 -print)
  rm -rf "$guard_dir"

  if [ "$guard_status" -ne 1 ] || [ "$output" != "$expected_guard_error" ] || [ -n "$entries" ]; then
    echo "guard must fail once with the stable diagnostic and leave its working directory unchanged"
    return 1
  fi
}

validate_rendered_guard_contract() {
  chart_dir=$(cd .. && pwd)
  addons_dir=$(cd ../.. && pwd)
  render_root=$(mktemp -d)
  render_chart="$render_root/kafka"
  render_kblib="$render_root/kblib"
  rendered="$render_root/rendered.yaml"
  status=0

  cp -R "$chart_dir" "$render_chart" || status=1
  cp -R "$addons_dir/kblib" "$render_kblib" || status=1
  if [ "$status" -eq 0 ]; then
    rm -rf "$render_chart/charts"
    helm dependency build "$render_chart" >/dev/null 2>&1 || status=1
  fi

  if [ "$status" -eq 0 ]; then
    helm template kafka "$render_chart" >"$rendered" || status=1
  fi
  if [ "$status" -eq 0 ]; then
    ruby ./kraft_scalein_guard_render_check.rb "$rendered" || status=1
  fi
  rm -rf "$render_root"
  return "$status"
}

Describe "Kafka KRaft controller scale-in guard"
  It "is valid for the POSIX shell used by the action execution environment"
    When run sh -n ../scripts/kafka-kraft-controller-member-leave.sh
    The status should be success
    The output should be blank
  End

  It "fails once with a stable diagnostic and no stdout"
    When run /bin/sh ../scripts/kafka-kraft-controller-member-leave.sh
    The status should equal 1
    The stdout should be blank
    The stderr should equal "$expected_guard_error"
  End

  It "wires the guard only into controller-bearing components"
    When call validate_guard_templates
    The status should be success
    The output should be blank
  End

  It "leaves its working directory unchanged"
    When call validate_guard_has_no_side_effects
    The status should be success
    The output should be blank
  End


  It "preserves the guard contract in rendered Kubernetes objects"
    When call validate_rendered_guard_contract
    The status should be success
    The output should be blank
  End
End
