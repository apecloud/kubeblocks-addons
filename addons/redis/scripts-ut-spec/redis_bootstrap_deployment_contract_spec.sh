# shellcheck shell=bash

Describe "Redis bootstrap deployment contract"
  cmpd_file="../templates/cmpd-redis.yaml"
  cmpv_file="../templates/cmpv-redis.yaml"
  values_file="../values.yaml"
  policy_file="../../kblib/templates/_common.tpl"
  restore_file="../dataprotection/restore.sh"
  pitr_restore_file="../dataprotection/pitr-restore.sh"
  post_provision_file="../scripts/redis-register-to-sentinel.sh"

  It "keeps ordered pod creation and supplies an in-cluster kubectl client"
    When run sh -c 'grep -Fq "podManagementPolicy: OrderedReady" "$1" && grep -Fq "name: init-kubectl" "$1" && grep -Fq "/opt/bitnami/kubectl/bin/kubectl" "$1" && grep -Fq "init-kubectl:" "$2" && grep -Fq "kubectlImage:" "$3"' sh "$cmpd_file" "$cmpv_file" "$values_file"
    The status should be success
  End

  It "grants only namespaced PVC reads for bootstrap state verification"
    When run sh -c 'grep -Fq '\''include "kblib.syncer.policyRulesWithPersistentVolumeClaims"'\'' "$1" && awk '\''/persistentvolumeclaims/{found=1} found && /verbs:/{getline; first=$0; getline; second=$0; exit} END{exit !(found && first ~ /- get$/ && second ~ /- list$/)}'\'' "$2"' sh "$cmpd_file" "$policy_file"
    The status should be success
  End

  It "creates restore authorization and clears it only after Sentinel registration"
    When run sh -c 'grep -Fq ".kb-redis-restore-bootstrap-authorized" "$1" && grep -Fq ".kb-redis-restore-bootstrap-authorized" "$2" && grep -Fq ".kb-redis-fresh-bootstrap-pending" "$3" && grep -Fq "clear_bootstrap_authorization_marker" "$3"' sh "$restore_file" "$pitr_restore_file" "$post_provision_file"
    The status should be success
  End
End
