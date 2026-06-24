# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "dataprotection common script tests"
    Include ../dataprotection/common.sh

    setup() {
        unset PD_ADDRESS
        unset PD_POD_FQDN_LIST
    }

    BeforeEach 'setup'

    Describe "ensurePDAddress"
        It "keeps an explicit PD_ADDRESS"
            PD_ADDRESS="tidb-pd.default.svc.cluster.local:2379"
            PD_POD_FQDN_LIST="tidb-pd-0.tidb-pd-headless.default.svc.cluster.local"

            When call ensurePDAddress

            The status should be success
            The variable PD_ADDRESS should equal "tidb-pd.default.svc.cluster.local:2379"
            The stdout should equal ""
        End

        It "derives PD_ADDRESS from PD_POD_FQDN_LIST"
            PD_POD_FQDN_LIST="tidb-pd-0.tidb-pd-headless.default.svc.cluster.local,tidb-pd-1.tidb-pd-headless.default.svc.cluster.local"

            When call ensurePDAddress

            The status should be success
            The variable PD_ADDRESS should equal "tidb-pd-0.tidb-pd-headless.default.svc.cluster.local:2379"
            The stdout should equal "PD_ADDRESS is empty; derived PD_ADDRESS=tidb-pd-0.tidb-pd-headless.default.svc.cluster.local:2379 from PD_POD_FQDN_LIST"
        End

        It "keeps an explicit port from PD_POD_FQDN_LIST"
            PD_POD_FQDN_LIST="tidb-pd-0.tidb-pd-headless.default.svc.cluster.local:2379"

            When call ensurePDAddress

            The status should be success
            The variable PD_ADDRESS should equal "tidb-pd-0.tidb-pd-headless.default.svc.cluster.local:2379"
            The stdout should equal "PD_ADDRESS is empty; derived PD_ADDRESS=tidb-pd-0.tidb-pd-headless.default.svc.cluster.local:2379 from PD_POD_FQDN_LIST"
        End

        It "fails when no PD endpoint source exists"
            When call ensurePDAddress

            The status should be failure
            The stderr should equal "PD_ADDRESS is required but empty; set PD_ADDRESS or PD_POD_FQDN_LIST"
        End
    End
End
