# shellcheck shell=sh

# alpha.89 v1 commit 5 (Helen 2026-05-19, C1 path lifecycle wiring) —
# the validate-replication-mode.sh helper must be embedded in the
# replication script ConfigMap so it mounts at /scripts in the
# mariadb container alongside roleprobe / member-join / switchover.
# A future commit can add a kbagent lifecycle action that references
# /scripts/validate-replication-mode.sh without re-touching this
# ConfigMap; this spec locks the mount surface so the wiring stays
# stable.

Describe "alpha.89 validate-replication-mode.sh ConfigMap mount"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  configmap_path() {
    printf "%s/addons/mariadb/templates/configmap-scripts-replication.yaml" "$(repo_root)"
  }

  It "the replication script ConfigMap declares the validate-replication-mode.sh data key"
    When call grep -qE '^[[:space:]]+validate-replication-mode\.sh:[[:space:]]*\|-?' "$(configmap_path)"
    The status should be success
  End

  It "the validate-replication-mode.sh entry pulls its body via Files.Get"
    When call grep -qF 'Files.Get "scripts/validate-replication-mode.sh"' "$(configmap_path)"
    The status should be success
  End

End
