# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "postgres_setup_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "PostgreSQL Initialization Script Tests"

  Include ../scripts/postgres-setup.sh
  Include $common_library_file

  cleanup() {
    rm -f $common_library_file
    rm -f ./tmp_patroni.yaml
  }
  AfterAll 'cleanup'

  Describe "init_etcd_dcs_config_if_needed()"
    Context "when PATRONI_DCS_ETCD_SERVICE_ENDPOINT is set"
      setup() {
        PATRONI_DCS_ETCD_SERVICE_ENDPOINT="http://etcd-cluster:2379"
      }
      Before 'setup'

      un_setup() {
        unset PATRONI_DCS_ETCD_SERVICE_ENDPOINT
        unset ETCDCTL_API
        unset DCS_ENABLE_KUBERNETES_API
        unset ETCD3_HOSTS
        unset ETCD_HOSTS
      }
      After 'un_setup'

      It "sets the etcd configuration"
        When call init_etcd_dcs_config_if_needed
        The variable ETCDCTL_API should equal "2"
        The variable DCS_ENABLE_KUBERNETES_API should equal ""
        The variable ETCD_HOSTS should equal "http://etcd-cluster:2379"
        The variable ETCD3_HOSTS should be undefined
        The output should include "PATRONI_DCS_ETCD_SERVICE_ENDPOINT is set. Use etcd as DCS backend and unset DCS_ENABLE_KUBERNETES_API"
      End
    End

    Context "when PATRONI_DCS_ETCD_VERSION is set to 3"
      setup() {
        PATRONI_DCS_ETCD_VERSION="3"
        PATRONI_DCS_ETCD_SERVICE_ENDPOINT="http://etcd-cluster:2380"
      }
      Before 'setup'

      un_setup() {
        unset PATRONI_DCS_ETCD_VERSION
        unset PATRONI_DCS_ETCD_SERVICE_ENDPOINT
        unset ETCDCTL_API
        unset DCS_ENABLE_KUBERNETES_API
        unset ETCD3_HOSTS
        unset ETCD_HOSTS
      }
      After 'un_setup'

      It "sets the etcd configuration for version 3"
        When call init_etcd_dcs_config_if_needed
        The variable ETCDCTL_API should equal "3"
        The variable DCS_ENABLE_KUBERNETES_API should equal ""
        The variable ETCD3_HOSTS should equal "http://etcd-cluster:2380"
        The variable ETCD_HOSTS should be undefined
        The output should include "PATRONI_DCS_ETCD_SERVICE_ENDPOINT is set. Use etcd as DCS backend and unset DCS_ENABLE_KUBERNETES_API"
      End
    End
  End

  Describe "regenerate_spilo_configuration_and_start_postgres()"
    setup() {
      tmp_patroni_yaml="./tmp_patroni.yaml"
      touch $tmp_patroni_yaml
    }
    Before 'setup'

    un_setup() {
      unset RESTORE_DATA_DIR
      unset SPILO_CONFIGURATION
      rm -f $tmp_patroni_yaml
    }
    After 'un_setup'

    It "regenerates the Spilo configuration and starts PostgreSQL"
      # mock python3 /kb-scripts/generate_patroni_yaml.py tmp_patroni.yaml
      python3() {
        echo "bootstrap:
                initdb:
                - auth-host: md5
                - auth-local: trust" > "$tmp_patroni_yaml"
      }
      exec() {
        :
      }
      When call regenerate_spilo_configuration_and_start_postgres
      # with the ">> file 2>&1" redirect order, failed redirections report on stderr only
      The stderr should include "/home/postgres/.kb_set_up.log: No such file or directory"
      The status should be success
      The file "tmp_patroni.yaml" should be exist
      The contents of file "tmp_patroni.yaml" should include "bootstrap:"
      The contents of file "tmp_patroni.yaml" should include "auth-host: md5"
      The variable SPILO_CONFIGURATION should not be undefined
      The variable SPILO_CONFIGURATION should include "bootstrap:"
      The variable SPILO_CONFIGURATION should include "auth-host: md5"
    End

    It "propagates restore replica configuration when the restore signal exists"
      RESTORE_DATA_DIR="$(mktemp -d -t pg-restore-data-XXXXXX)"
      touch "${RESTORE_DATA_DIR}/kb_restore.signal"
      export RESTORE_DATA_DIR
      python3() {
        echo "postgresql:
                create_replica_methods:
                - restore_data
                - basebackup
                restore_data:
                  command: bash /home/postgres/pgdata/kb_restore/kb_restore.sh --replica" > "$tmp_patroni_yaml"
      }
      chown() {
        :
      }
      exec() {
        :
      }
      When call regenerate_spilo_configuration_and_start_postgres
      The stderr should include "/home/postgres/.kb_set_up.log: No such file or directory"
      The status should be success
      The variable SPILO_CONFIGURATION should include "create_replica_methods:"
      The variable SPILO_CONFIGURATION should include "restore_data"
      The variable SPILO_CONFIGURATION should include "kb_restore.sh --replica"
      rm -rf "${RESTORE_DATA_DIR}"
    End
  End

  Describe "pending restart candidate selection"
    setup() {
      CURRENT_POD_NAME="pg-cluster-postgresql-0"
    }
    Before 'setup'

    un_setup() {
      unset CURRENT_POD_NAME
    }
    After 'un_setup'

    It "selects a pending leader before replicas"
      cluster_state='{"members":[{"name":"pg-cluster-postgresql-2","role":"replica","state":"streaming","pending_restart":true},{"name":"pg-cluster-postgresql-0","role":"leader","state":"running","pending_restart":true},{"name":"pg-cluster-postgresql-1","role":"replica","state":"streaming","pending_restart":true}]}'
      When call pending_restart_candidate "$cluster_state"
      The output should equal "pg-cluster-postgresql-0"
      The status should be success
    End

    It "selects one pending replica by stable member name order"
      cluster_state='{"members":[{"name":"pg-cluster-postgresql-2","role":"replica","state":"streaming","pending_restart":true},{"name":"pg-cluster-postgresql-0","role":"leader","state":"running","pending_restart":false},{"name":"pg-cluster-postgresql-1","role":"replica","state":"streaming","pending_restart":true}]}'
      When call pending_restart_candidate "$cluster_state"
      The output should equal "pg-cluster-postgresql-1"
      The status should be success
    End

    It "selects no candidate while a member is restarting"
      cluster_state='{"members":[{"name":"pg-cluster-postgresql-0","role":"leader","state":"running","pending_restart":false},{"name":"pg-cluster-postgresql-1","role":"replica","state":"restarting","pending_restart":true},{"name":"pg-cluster-postgresql-2","role":"replica","state":"streaming","pending_restart":true}]}'
      When call pending_restart_candidate "$cluster_state"
      The output should equal ""
      The status should be success
    End

    It "restarts only when the current pod is the selected candidate"
      When call need_restart_for_pending "true" "pg-cluster-postgresql-0"
      The status should be success
    End

    It "does not restart when another pod is the selected candidate"
      When call need_restart_for_pending "true" "pg-cluster-postgresql-1"
      The status should be failure
    End

    It "does not restart without a candidate"
      When call need_restart_for_pending "true" ""
      The status should be failure
    End

    It "does not restart when not pending"
      When call need_restart_for_pending "false" "pg-cluster-postgresql-0"
      The status should be failure
    End
  End
End
