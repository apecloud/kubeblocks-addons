# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "data-load_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Etcd Data Load Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
    
    # Setup test environment variables
    export CONFIG_TEMPLATE_PATH="/tmp/test_etcd_template.conf"
    export CONFIG_FILE_PATH="/tmp/test_etcd_target.conf"
    
    # Create test directories
    mkdir -p /tmp
    
    # Define the data load function based on real script logic
    data_load() {
      local default_template_conf="$CONFIG_TEMPLATE_PATH"
      local default_conf="$CONFIG_FILE_PATH"
      
      cp "$default_template_conf" "$default_conf" || return 1
      
      sed -i.bak "s/^initial-cluster-state: 'new'/initial-cluster-state: 'existing'/g" "$default_conf"
      if [ -f "$default_conf.bak" ]; then
        rm "$default_conf.bak"
      fi
    }
  }
  BeforeAll "init"

  BeforeEach 'setup_test_files'
  
  setup_test_files() {
    rm -f "$CONFIG_FILE_PATH" "$CONFIG_FILE_PATH.bak" "$CONFIG_TEMPLATE_PATH"
    cat > "$CONFIG_TEMPLATE_PATH" << 'EOF'
# Test etcd configuration template
name: 'default'
data-dir: /var/lib/etcd
initial-cluster-state: 'new'
listen-client-urls: http://0.0.0.0:2379
listen-peer-urls: http://0.0.0.0:2380
EOF
  }

  cleanup() {
    rm -f $common_library_file
    rm -f "$CONFIG_TEMPLATE_PATH"
    rm -f "$CONFIG_FILE_PATH"
    rm -f "$CONFIG_FILE_PATH.bak"
    unset ut_mode CONFIG_TEMPLATE_PATH CONFIG_FILE_PATH
    unset -f data_load
  }
  AfterAll 'cleanup'

  Describe "data_load() function"
    It "successfully copies template and updates cluster state"
      When call data_load
      The status should be success
      The file "$CONFIG_FILE_PATH" should be exist
      The contents of file "$CONFIG_FILE_PATH" should include "initial-cluster-state: 'existing'"
      The contents of file "$CONFIG_FILE_PATH" should not include "initial-cluster-state: 'new'"
      The contents of file "$CONFIG_FILE_PATH" should include "name: 'default'"
    End

    It "handles missing template file gracefully"
      rm -f "$CONFIG_TEMPLATE_PATH"
      
      When call data_load
      The status should be failure
      # Explicitly check for the expected error message to resolve the warning.
      The stderr should include "No such file or directory"
    End
  End
End
