# shellcheck shell=bash
# shellcheck disable=SC2034

role_quorum_value() {
  local role="$1"
  local template_file="$2"

  awk -v role="$role" '
    $0 ~ "^[[:space:]]*- name: " role "$" { in_role = 1; next }
    in_role && $0 ~ "^[[:space:]]*- name:" { exit }
    in_role && $1 == "participatesInQuorum:" { print $2; exit }
  ' "$template_file"
}

Describe "ClickHouse Keeper quorum role contract"
  template_file="../templates/cmpd-keeper.yaml"

  It "marks the leader as a quorum participant"
    When call role_quorum_value leader "$template_file"
    The status should be success
    The output should eq "true"
  End

  It "marks followers as quorum participants"
    When call role_quorum_value follower "$template_file"
    The status should be success
    The output should eq "true"
  End

  It "keeps observers outside the voting quorum"
    When call role_quorum_value observer "$template_file"
    The status should be success
    The output should eq "false"
  End
End
