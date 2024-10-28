# shellcheck shell=bash
# shellcheck disable=SC2034

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Etcd Start Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/start.sh
  Include $common_library_file

  init() {
    # mock template configuration file
    default_template_conf="./default_etcd.conf"
    # mock real etcd configuration file
    real_conf="./etcd.conf"
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
  }

  check_requirements() {
    if [[ $(uname) == "Darwin" || $(uname) == *"BSD"* ]] && ! which gsed > /dev/null 2>&1; then
      echo "cannot find gsed (required on BSD/Darwin systems)" >&2
      return 1
    fi
    return 0
  }

  universal_sed() {
    if [[ $(uname) == "Darwin" || $(uname) == *"BSD"* ]]; then
      gsed "$@"
    else
      sed "$@"
    fi
  }

  BeforeAll "init"

  cleanup() {
    rm -f "$real_conf";
    rm -f $common_library_file;
    rm -f $default_template_conf
  }

  AfterAll 'cleanup'

  Describe "get_my_endpoint()"
    It "exits with error when PEER_FQDNS or CURRENT_POD_NAME is empty"
      export CURRENT_POD_NAME=""
      export PEER_FQDNS=""
      When run get_my_endpoint ""
      The status should be failure
      The stderr should include "Error: PEER_FQDNS or CURRENT_POD_NAME is empty. Exiting."
    End

    It "gets my endpoint correctly when PEER_ENDPOINT is empty"
      export CURRENT_POD_NAME="etcd-0"
      export PEER_FQDNS="etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local"
      When call get_my_endpoint ""
      The status should be success
      The stdout should include "etcd-0.etcd-headless.default.svc.cluster.local"
    End

    It "gets my endpoint correctly when PEER_ENDPOINT is not empty and in LoadBalancer mode1"
      export CURRENT_POD_NAME="etcd-1"
      export PEER_FQDNS="etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local"
      export PEER_ENDPOINT="etcd-0:127.0.0.1,etcd-1:127.0.0.2"
      When call get_my_endpoint "$PEER_ENDPOINT"
      The status should be success
      The stdout should include "127.0.0.2"
      The stderr should include "LoadBalancer mode detected. Adapting pod FQDN to balance IP."
    End

    It "gets my endpoint correctly when PEER_ENDPOINT is not empty and in LoadBalancer mode2"
      export CURRENT_POD_NAME="etcd-1"
      export PEER_FQDNS="etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local"
      export PEER_ENDPOINT="etcd-0,etcd-1"
      When call get_my_endpoint "$PEER_ENDPOINT"
      The status should be success
      The stdout should include "etcd-1"
      The stderr should include "LoadBalancer mode detected. Adapting pod FQDN to balance IP."
    End

    It "exits with error when failed to get current pod fqdn"
      export CURRENT_POD_NAME="etcd-2"
      export PEER_FQDNS="etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local"
      When run get_my_endpoint ""
      The status should be failure
      The stderr should include "Failed to get current pod: etcd-2 fqdn from peer fqdn list: etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local. Exiting."
    End
  End

  Describe "update_etcd_conf()"
    BeforeAll "check_requirements"

    It "updates the etcd configuration file correctly without tls"
      current_pod_name="etcd-0"
      my_endpoint="etcd-0.etcd-headless.default.svc.cluster.local"

      echo "name: default" > "$default_template_conf"
      echo "initial-advertise-peer-urls: http://default:2380" >> "$default_template_conf"
      echo "advertise-client-urls: http://default:2379" >> "$default_template_conf"

      When call update_etcd_conf "$default_template_conf" "$real_conf" "$current_pod_name" "$my_endpoint"
      The status should be success
      The file "$real_conf" should be exist
      The contents of file "$real_conf" should include "name: etcd-0"
      The contents of file "$real_conf" should include "initial-advertise-peer-urls: http://etcd-0.etcd-headless.default.svc.cluster.local:2380"
      The contents of file "$real_conf" should include "advertise-client-urls: http://etcd-0.etcd-headless.default.svc.cluster.local:2379"
    End

    It "updates the etcd configuration file correctly with tls"
      current_pod_name="etcd-0"
      my_endpoint="etcd-0.etcd-headless.default.svc.cluster.local"

      echo "name: etcd-0" > "$default_template_conf"
      echo "initial-advertise-peer-urls: https://default:2380" >> "$default_template_conf"
      echo "advertise-client-urls: https://default:2379" >> "$default_template_conf"

      When call update_etcd_conf "$default_template_conf" "$real_conf" "$current_pod_name" "$my_endpoint"
      The status should be success
      The file "$real_conf" should be exist
      The contents of file "$real_conf" should include "name: etcd-0"
      The contents of file "$real_conf" should include "initial-advertise-peer-urls: https://etcd-0.etcd-headless.default.svc.cluster.local:2380"
      The contents of file "$real_conf" should include "advertise-client-urls: https://etcd-0.etcd-headless.default.svc.cluster.local:2379"
    End
  End

  Describe "rebuild_etcd_conf()"
    BeforeAll "check_requirements"

    It "rebuilds the etcd configuration successfully"
      export CURRENT_POD_NAME="etcd-0"
      export PEER_FQDNS="etcd-0.etcd-headless.default.svc.cluster.local,etcd-1.etcd-headless.default.svc.cluster.local"
      export PEER_ENDPOINT="etcd-0:172.0.0.1,etcd-1:172.0.0.2"
      default_template_conf="./default_etcd.conf"
      real_conf="./etcd.conf"

      echo "name: default" > "$default_template_conf"
      echo "initial-advertise-peer-urls: http://default:2380" >> "$default_template_conf"
      echo "advertise-client-urls: http://default:2379" >> "$default_template_conf"

      When call rebuild_etcd_conf
      The status should be success
      The file "$real_conf" should be exist
      The stdout should include "name: etcd-0"
      The stderr should include "LoadBalancer mode detected. Adapting pod FQDN to balance IP."
      The contents of file "$real_conf" should include "name: etcd-0"
      The contents of file "$real_conf" should include "initial-advertise-peer-urls: http://172.0.0.1:2380"
      The contents of file "$real_conf" should include "advertise-client-urls: http://172.0.0.1:2379"
    End

    It "fails to rebuild the etcd configuration when get_my_endpoint fails"
      export CURRENT_POD_NAME=""
      export PEER_FQDNS=""

      When run rebuild_etcd_conf
      The status should be failure
      The stdout should include "start to rebuild etcd configuration..."
      The stderr should include "Failed to get my endpoint. Exiting."
    End
  End
End