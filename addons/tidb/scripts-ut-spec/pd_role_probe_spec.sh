# shellcheck shell=bash
# shellcheck disable=SC2034,SC2317

Describe "pd_role_probe tests"
    Include ../scripts/pd_role_probe.sh

    setup() {
        HOSTNAME="tidb-cluster-tidb-pd-0"
        PD_POD_FQDN_LIST="tidb-cluster-tidb-pd-0.tidb-cluster-tidb-pd-headless.default.svc.cluster.local,tidb-cluster-tidb-pd-1.tidb-cluster-tidb-pd-headless.default.svc.cluster.local,tidb-cluster-tidb-pd-2.tidb-cluster-tidb-pd-headless.default.svc.cluster.local"
    }

    BeforeEach 'setup'

    Describe "local API success — leader"
        timeout() {
            shift
            echo '{"leader":{"name":"tidb-cluster-tidb-pd-0"},"members":[{"name":"tidb-cluster-tidb-pd-0"},{"name":"tidb-cluster-tidb-pd-1"},{"name":"tidb-cluster-tidb-pd-2"}]}'
        }

        It "returns leader when HOSTNAME matches leader.name"
            When call pd_role_probe
            The status should be success
            The stdout should equal "leader"
        End
    End

    Describe "local API success — follower"
        timeout() {
            shift
            echo '{"leader":{"name":"tidb-cluster-tidb-pd-1"},"members":[{"name":"tidb-cluster-tidb-pd-0"},{"name":"tidb-cluster-tidb-pd-1"},{"name":"tidb-cluster-tidb-pd-2"}]}'
        }

        It "returns follower when HOSTNAME is not leader but is member"
            When call pd_role_probe
            The status should be success
            The stdout should equal "follower"
        End
    End

    Describe "peer fallback success"
        peer_call_count=0

        timeout() {
            shift
            if [ "$1" = "/pd-ctl" ] && [ "${2:-}" != "-u" ]; then
                return 1
            fi
            echo '{"leader":{"name":"tidb-cluster-tidb-pd-1"},"members":[{"name":"tidb-cluster-tidb-pd-0"},{"name":"tidb-cluster-tidb-pd-1"},{"name":"tidb-cluster-tidb-pd-2"}]}'
        }

        It "falls back to peer and returns follower"
            When call pd_role_probe
            The status should be success
            The stdout should equal "follower"
        End
    End

    Describe "current pod absent from member list"
        timeout() {
            shift
            echo '{"leader":{"name":"tidb-cluster-tidb-pd-1"},"members":[{"name":"tidb-cluster-tidb-pd-1"},{"name":"tidb-cluster-tidb-pd-2"}]}'
        }

        It "returns failure when HOSTNAME not in members"
            When call pd_role_probe
            The status should be failure
            The stdout should equal ""
        End
    End

    Describe "no leader in response"
        timeout() {
            shift
            echo '{"members":[{"name":"tidb-cluster-tidb-pd-0"},{"name":"tidb-cluster-tidb-pd-1"}]}'
        }

        It "returns failure when no leader field"
            When call pd_role_probe
            The status should be failure
            The stdout should equal ""
        End
    End

    Describe "invalid JSON"
        timeout() {
            shift
            echo 'not valid json at all'
        }

        It "returns failure on invalid JSON"
            When call pd_role_probe
            The status should be failure
            The stdout should equal ""
        End
    End

    Describe "all endpoints unreachable"
        timeout() {
            shift
            return 1
        }

        It "returns failure when all endpoints fail"
            When call pd_role_probe
            The status should be failure
            The stdout should equal ""
        End
    End

    Describe "empty PD_POD_FQDN_LIST with local failure"
        timeout() {
            shift
            return 1
        }

        It "returns failure when no peers and local fails"
            PD_POD_FQDN_LIST=""
            When call pd_role_probe
            The status should be failure
            The stdout should equal ""
        End
    End
End
