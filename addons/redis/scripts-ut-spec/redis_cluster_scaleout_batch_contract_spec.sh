# shellcheck shell=bash

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_cluster_scaleout_batch_contract_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis Cluster scale-out bounded batch contract"
  contract_fixture=./fixtures/redis_cluster_scaleout_batch_fixture.sh

  Parameters
    "redis5"   "../redis-cluster-scripts/redis-cluster-manage.sh"
    "redis6+"  "../redis-cluster-scripts/redis-cluster6-manage.sh"
  End

  It "moves only one bounded batch for a new shard on ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" large
    The status should be success
    The stdout should include "family=$1 scenario=large status=1 mutation=1 fix=0"
    The stdout should include "reshard_slots=128"
    The stdout should include "action: scale_out_redis_cluster_shard"
    The stdout should include "phase: reshard-progress"
    The stdout should include "current_slots: 128"
    The stdout should include "target_slots: 4096"
    The stdout should include "next-retry-safe: yes"
    The stdout should not include "reshard_slots=4096"
  End

  It "recomputes progress on every invocation for ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" reentry
    The status should be success
    The stdout should include "family=$1 scenario=reentry status=1 mutation=1 fix=0"
    The stdout should include "reshard_slots=128"
    The stdout should include "current_slots: 256"
    The stdout should include "remaining_slots: 3840"
  End

  It "moves the exact final remainder and positively closes for ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" final
    The status should be success
    The stdout should include "family=$1 scenario=final status=0 mutation=1 fix=0"
    The stdout should include "reshard_slots=96"
    The stdout should include "Redis cluster scale out shard owns 4096 slots and cluster is stable"
  End

  It "defers full-coverage view disagreement without mutation or fix on ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" views
    The status should be success
    The stdout should include "family=$1 scenario=views status=1 mutation=0 fix=0"
    The stdout should include "phase: cluster-views-not-converged"
    The stdout should include "next-retry-safe: yes"
  End

  It "fails closed on an unknown cluster-check failure for ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" probe-error
    The status should be success
    The stdout should include "family=$1 scenario=probe-error status=1 mutation=0 fix=0"
    The stdout should include "phase: cluster-check-failed"
    The stdout should include "next-retry-safe: no"
  End

  It "keeps the existing open-slot repair-and-defer behavior for ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" open
    The status should be success
    The stdout should include "family=$1 scenario=open status=1 mutation=0 fix=1"
    The stdout should include "phase: cluster-slots-repair-applied"
    The stdout should include "next-retry-safe: yes"
  End

  It "fails closed when the batch size is invalid for ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" invalid-batch
    The status should be success
    The stdout should include "family=$1 scenario=invalid-batch status=1 mutation=0 fix=0"
    The stdout should include "phase: invalid-reshard-batch-size"
    The stdout should include "batch_size: 0"
    The stdout should include "next-retry-safe: no"
  End

  It "fails closed when the bounded reshard command is rejected for ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" mutation-failure
    The status should be success
    The stdout should include "family=$1 scenario=mutation-failure status=1 mutation=1 fix=0"
    The stdout should include "phase: reshard-command-failed"
    The stdout should include "batch_slots: 128"
    The stdout should include "next-retry-safe: no"
  End

  It "fails closed when the post-reshard slot count cannot be observed for ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" post-count-error
    The status should be success
    The stdout should include "family=$1 scenario=post-count-error status=1 mutation=1 fix=0"
    The stdout should include "phase: post-reshard-slot-count-failed"
    The stdout should include "next-retry-safe: no"
  End

  It "surfaces an unsuccessful open-slot repair as operator attention for ${1}"
    When run "$SHELLSPEC_SHELL" "$contract_fixture" "$2" "$1" repair-failure
    The status should be success
    The stdout should include "family=$1 scenario=repair-failure status=1 mutation=0 fix=1"
    The stdout should include "phase: cluster-slots-repair-failed"
    The stdout should include "next-retry-safe: no"
  End
End
