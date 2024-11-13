# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "pd start script tests"
    Include ../scripts/pd_start.sh

    setup() {
        DATA_DIR=/tmp/mock_data
        mkdir -p $DATA_DIR
        PD_POD_FQDN_LIST="tidb-cluster-tidb-pd-0.tidb-cluster-tidb-pd-headless.default.svc.cluster.local,tidb-cluster-tidb-pd-1.tidb-cluster-tidb-pd-headless.default.svc.cluster.local"
        ARGS=""
        unset PD_LEADER_POD_NAME
        unset CURRENT_POD_NAME
    }

    cleanup() {
        rm -r "$DATA_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    Describe "get_current_pod_fqdn test"
        It "should work"
            CURRENT_POD_NAME=tidb-cluster-tidb-pd-1
            When call get_current_pod_fqdn
            The stdout should equal "tidb-cluster-tidb-pd-1.tidb-cluster-tidb-pd-headless.default.svc.cluster.local"
        End
    End

    Describe "set_join_args test"
        Example "with join file"
            echo "demo-pd-0=http://demo-pd-0.demo-pd-peer.demo.svc:2380,demo-pd-1=http://demo-pd-1.demo-pd-peer.demo.svc:2380" > "$DATA_DIR/join"
            When call set_join_args
            The variable ARGS should equal " --join=http://demo-pd-0.demo-pd-peer.demo.svc:2380,http://demo-pd-1.demo-pd-peer.demo.svc:2380"
            The stdout should equal "restarted pod, join cluster"
        End

        Example "with data"
            mkdir -p "$DATA_DIR/member/wal"
            When call set_join_args
            The variable ARGS should equal ""
        End

        Example "without data, join"
            PD_LEADER_POD_NAME="tidb-cluster-tidb-pd-0"
            When call set_join_args
            The variable ARGS should equal " --join=http://tidb-cluster-tidb-pd-0.tidb-cluster-tidb-pd-headless.default.svc.cluster.local:2380,http://tidb-cluster-tidb-pd-1.tidb-cluster-tidb-pd-headless.default.svc.cluster.local:2380"
            The line 2 of stdout should equal "joining an existing cluster"
        End

        Example "without data, initialize"
            When call set_join_args
            The variable ARGS should equal " --initial-cluster=tidb-cluster-tidb-pd-0=http://tidb-cluster-tidb-pd-0.tidb-cluster-tidb-pd-headless.default.svc.cluster.local:2380,tidb-cluster-tidb-pd-1=http://tidb-cluster-tidb-pd-1.tidb-cluster-tidb-pd-headless.default.svc.cluster.local:2380"
            The line 2 of stdout should equal "initializing a cluster"
        End
    End
End
