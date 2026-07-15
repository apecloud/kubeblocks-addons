# shellcheck shell=bash

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_slot_owner_classifier_contract_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis Cluster slot-owner classifier contract"
  contract_fixture=./fixtures/redis_slot_owner_classifier_fixture.sh

  Context "with the slotless target listed first"
    Parameters
      "redis5"  "../redis-cluster-scripts/redis-cluster5-server-start.sh"  "ip-list"
      "redis6"  "../redis-cluster-scripts/redis-cluster6-server-start.sh"  "ip-list"
      "redis7"  "../redis-cluster-scripts/redis-cluster-server-start.sh"   "fqdn"
      "redis8"  "../redis-cluster-scripts/redis-cluster-server-start.sh"   "fqdn"
    End

    It "selects the unique slot owner for ${1}"
      When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$3" classify target-first
      The status should be success
      The stdout should include "family=$3"
      The stdout should include "initialized=true"
      The stdout should include "primary_count=1"
      The stdout should include "primary=10.42.0.227#"
      The stdout should include "fail_count=0"
      The stdout should include "other=10.42.0.228#"
    End
  End

  Context "with an unusable slot owner"
    Parameters
      "redis5"  "../redis-cluster-scripts/redis-cluster5-server-start.sh"  "ip-list"  "disconnected"
      "redis6"  "../redis-cluster-scripts/redis-cluster6-server-start.sh"  "ip-list"  "disconnected"
      "redis7"  "../redis-cluster-scripts/redis-cluster-server-start.sh"   "fqdn"     "disconnected"
      "redis8"  "../redis-cluster-scripts/redis-cluster-server-start.sh"   "fqdn"     "disconnected"
      "redis5"  "../redis-cluster-scripts/redis-cluster5-server-start.sh"  "ip-list"  "failed"
      "redis6"  "../redis-cluster-scripts/redis-cluster6-server-start.sh"  "ip-list"  "failed"
      "redis7"  "../redis-cluster-scripts/redis-cluster-server-start.sh"   "fqdn"     "failed"
      "redis8"  "../redis-cluster-scripts/redis-cluster-server-start.sh"   "fqdn"     "failed"
    End

    It "rejects the ${4} slot owner for ${1}"
      When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$3" classify "$4"
      The status should be success
      The stdout should include "scenario=$4"
      The stdout should include "initialized=true"
      The stdout should include "primary_count=0"
      The stdout should include "fail_count=1"
      The stdout should include "fail=10.42.0.227#"
      The stdout should include "other=10.42.0.228#"
    End
  End

  Context "with an ambiguous initialized view"
    Parameters
      "redis5"  "../redis-cluster-scripts/redis-cluster5-server-start.sh"  "ip-list"
      "redis6"  "../redis-cluster-scripts/redis-cluster6-server-start.sh"  "ip-list"
      "redis7"  "../redis-cluster-scripts/redis-cluster-server-start.sh"   "fqdn"
      "redis8"  "../redis-cluster-scripts/redis-cluster-server-start.sh"   "fqdn"
    End

    It "surfaces multiple slot owners for ${1}"
      When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$3" classify multiple
      The status should be success
      The stdout should include "initialized=true"
      The stdout should include "primary_count=2"
      The stdout should include "primary=10.42.0.227#"
      The stdout should include "10.42.0.230#"
      The stdout should include "fail_count=0"
    End

    It "fails closed before mutation for every ambiguity on ${1}"
      When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$3" guard
      The status should be success
      The stdout should include "family=$3 guard=zero status=1 mutation=0"
      The stdout should include "family=$3 guard=multiple status=1 mutation=0"
      The stdout should include "family=$3 guard=disconnected status=1 mutation=0"
      The stdout should include "family=$3 guard=failed status=1 mutation=0"
    End
  End
End
