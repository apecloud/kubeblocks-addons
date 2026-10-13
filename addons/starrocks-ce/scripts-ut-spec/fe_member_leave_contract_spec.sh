# shellcheck shell=bash
# shellcheck disable=SC1091,SC2034,SC2329

Describe "StarRocks FE memberLeave deployment contract"
  cmpd="../templates/cmpd-fe.yaml"
  scripts_template="../templates/scripts-template.yaml"
  member_leave_script="../scripts/fe-member-leave.sh"

  verify_member_leave_image_stream() {
    awk '
        function finish_release() {
          if (release == "") return
          count++
          if (!(release in supported) || fe == "" || member_leave == "" ||
              member_leave != fe || checked[release]++) {
            invalid=1
            return
          }
          print release "=" fe
        }
        BEGIN {
          supported["3.2.2"]=1
          supported["3.3.0"]=1
        }
        /^[[:space:]]*-[[:space:]]+name:/ {
          finish_release()
          release=$3
          fe=""
          member_leave=""
          next
        }
        /^[[:space:]]+fe:/ {
          fe=$2
          next
        }
        /^[[:space:]]+memberLeave:/ {
          member_leave=$2
        }
        END {
          finish_release()
          if (invalid || count != 2 || checked["3.2.2"] != 1 ||
              checked["3.3.0"] != 1) exit 1
        }
      '
  }

  It "declares the truthful 50 second kbagent action budget"
    When call grep -A 3 "memberLeave:" "${cmpd}"
    The status should be success
    The stdout should include "timeoutSeconds: 50"
  End

  It "executes through the FE container and mounted script path"
    member_leave_exec_contract() {
      grep -A 14 "memberLeave:" "${cmpd}" | grep -F "container: fe" >/dev/null &&
        grep -A 14 "memberLeave:" "${cmpd}" | grep -F -- "- /bin/bash" >/dev/null &&
        grep -A 14 "memberLeave:" "${cmpd}" | grep -F "/scripts/fe-member-leave.sh" >/dev/null &&
        grep -F "fe-member-leave.sh" "${scripts_template}" >/dev/null
    }
    When call member_leave_exec_contract
    The status should be success
  End

  It "binds memberLeave to the exact FE image for every supported release"
    verify_rendered_member_leave_images() {
      helm template starrocks-ce .. --show-only templates/cmpv-fe.yaml |
        verify_member_leave_image_stream
    }
    When call verify_rendered_member_leave_images
    The status should be success
    The stdout should include "3.2.2=docker.io/starrocks/fe-ubuntu:3.2.2"
    The stdout should include "3.3.0=docker.io/starrocks/fe-ubuntu:3.3.0"
  End

  It "rejects an unsupported release that omits memberLeave"
    unsupported_release_stream() {
      printf '%s\n' \
        '  - name: 3.2.2' \
        '      fe: docker.io/starrocks/fe-ubuntu:3.2.2' \
        '      memberLeave: docker.io/starrocks/fe-ubuntu:3.2.2' \
        '  - name: 3.3.0' \
        '      fe: docker.io/starrocks/fe-ubuntu:3.3.0' \
        '      memberLeave: docker.io/starrocks/fe-ubuntu:3.3.0' \
        '  - name: 9.9.9' \
        '      fe: docker.io/starrocks/fe-ubuntu:9.9.9' |
        verify_member_leave_image_stream
    }
    When call unsupported_release_stream
    The status should be failure
    The stdout should include "3.2.2=docker.io/starrocks/fe-ubuntu:3.2.2"
    The stdout should include "3.3.0=docker.io/starrocks/fe-ubuntu:3.3.0"
  End

  It "checks mysql, java, timeout, and the BDB JE jar before changing membership"
    runtime_tool_contract() {
      grep -F 'require_command "mysql"' "${member_leave_script}" >/dev/null &&
        grep -F 'require_command "java"' "${member_leave_script}" >/dev/null &&
        grep -F 'require_command "timeout"' "${member_leave_script}" >/dev/null &&
        grep -F 'BDB_JE_JAR_PATH' "${member_leave_script}" >/dev/null
    }
    When call runtime_tool_contract
    The status should be success
  End

  It "defers convergence after one observation instead of polling in-process"
    single_shot_contract() {
      ! grep -Eq 'while[[:space:]]+:' "${member_leave_script}" &&
        ! grep -Eq 'sleep[[:space:]]+' "${member_leave_script}"
    }
    When call single_shot_contract
    The status should be success
  End

  It "reserves timeout launch and kill escalation inside the global action deadline"
    bounded_budget_contract() {
      # shellcheck source=../scripts/fe-member-leave.sh
      . "${member_leave_script}"
      SECONDS=0
      ACTION_DEADLINE=45
      bounded_command_budget 999
      printf '%s\n' "${BOUNDED_COMMAND_BUDGET}"
    }
    When call bounded_budget_contract
    The status should be success
    The stdout should equal "43"
  End

  It "recomputes the TERM budget at command launch after a clock rollover"
    rollover_budget_contract() {
      # shellcheck source=../scripts/fe-member-leave.sh
      . "${member_leave_script}"
      local tmp_dir rc
      tmp_dir=$(mktemp -d)
      timeout() {
        printf '%s\n' "$3"
      }
      SECONDS=1
      ACTION_DEADLINE=45
      run_bounded_command 999 "${tmp_dir}/stdout" "${tmp_dir}/stderr" /bin/true
      rc=$?
      printf 'rc=%s term=%s\n' "${rc}" "$(cat "${tmp_dir}/stdout")"
      rm -rf "${tmp_dir}"
    }
    When call rollover_budget_contract
    The status should be success
    The stdout should equal "rc=0 term=42s"
  End

  It "does not start a command when the global deadline has at most the kill grace left"
    exhausted_budget_contract() {
      # shellcheck source=../scripts/fe-member-leave.sh
      . "${member_leave_script}"
      local tmp_dir rc remaining
      tmp_dir=$(mktemp -d)
      for remaining in 1 0; do
        SECONDS=0
        ACTION_DEADLINE="${remaining}"
        run_bounded_command 999 \
          "${tmp_dir}/stdout" "${tmp_dir}/stderr" \
          /bin/sh -c "touch '${tmp_dir}/started-${remaining}'"
        rc=$?
        printf 'remaining=%s budget=%s rc=%s started=%s\n' \
          "${remaining}" "${BOUNDED_COMMAND_BUDGET}" "${rc}" \
          "$([ -e "${tmp_dir}/started-${remaining}" ] && printf true || printf false)"
      done
      rm -rf "${tmp_dir}"
    }
    When call exhausted_budget_contract
    The status should be success
    The line 1 of stdout should equal "remaining=1 budget=0 rc=124 started=false"
    The line 2 of stdout should equal "remaining=0 budget=0 rc=124 started=false"
  End
End
