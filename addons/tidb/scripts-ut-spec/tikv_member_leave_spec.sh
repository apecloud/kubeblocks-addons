# shellcheck shell=bash
# shellcheck disable=SC2034,SC2317,SC2329

Describe "tikv member leave"
    TIDB_SCRIPTS_DIR="../scripts"
    __SOURCED__=true
    Include ../scripts/tikv_member_leave.sh

    setup() {
        export KB_LEAVE_MEMBER_POD_FQDN="tidb-tikv-1.tidb-tikv-headless.default.svc"
        export KB_ENABLE_TLS_BETWEEN_COMPONENTS="false"
        export PD_ADDRESS="tidb-pd.default.svc:2379"
        STATE_CALLS="${SHELLSPEC_TMPBASE}/state-calls"
        : > "$STATE_CALLS"
    }

    BeforeEach 'setup'

    It "closes idempotently when the store is already absent"
        pd_ctl() {
            [ "$*" = "store" ] || return 99
            printf '{"stores":[]}\n'
        }

        When call run_tikv_member_leave
        The status should be success
        The output should include "already absent"
    End

    It "deletes an Up store and defers while it is Offline"
        pd_ctl() {
            case "$*" in
                store)
                    calls=$(wc -l < "$STATE_CALLS")
                    printf 'x\n' >> "$STATE_CALLS"
                    if [ "$calls" -eq 0 ]; then
                        printf '{"stores":[{"store":{"address":"%s","state_name":"Up"}}]}\n' "$TIKV_ADDRESS"
                    else
                        printf '{"stores":[{"store":{"address":"%s","state_name":"Offline"}}]}\n' "$TIKV_ADDRESS"
                    fi
                    ;;
                "store delete addr $TIKV_ADDRESS")
                    printf 'Success!\n'
                    ;;
                *)
                    return 99
                    ;;
            esac
        }

        When call run_tikv_member_leave
        The status should be failure
        The stderr should include "phase: store-offline"
        The stderr should include "next-retry-safe: yes"
    End

    It "removes a Tombstone store and positively verifies absence"
        pd_ctl() {
            case "$*" in
                store)
                    calls=$(wc -l < "$STATE_CALLS")
                    printf 'x\n' >> "$STATE_CALLS"
                    if [ "$calls" -eq 0 ]; then
                        printf '{"stores":[{"store":{"address":"%s","state_name":"Tombstone"}}]}\n' "$TIKV_ADDRESS"
                    else
                        printf '{"stores":[]}\n'
                    fi
                    ;;
                "store remove-tombstone")
                    printf 'Success!\n'
                    ;;
                *)
                    return 99
                    ;;
            esac
        }

        When call run_tikv_member_leave
        The status should be success
        The output should include "member leave success"
    End

    It "fails closed when the store response is not valid JSON"
        pd_ctl() {
            [ "$*" = "store" ] || return 99
            printf 'not-json\n'
        }

        When call run_tikv_member_leave
        The status should be failure
        The stderr should include "phase: store-probe-invalid"
        The stderr should include "next-retry-safe: no"
    End

    It "fails closed when delete is rejected"
        pd_ctl() {
            case "$*" in
                store)
                    printf '{"stores":[{"store":{"address":"%s","state_name":"Up"}}]}\n' "$TIKV_ADDRESS"
                    ;;
                "store delete addr $TIKV_ADDRESS")
                    printf 'permission denied\n'
                    return 1
                    ;;
                *)
                    return 99
                    ;;
            esac
        }

        When call run_tikv_member_leave
        The status should be failure
        The stderr should include "phase: delete-rejected"
        The stderr should include "next-retry-safe: no"
    End
End
