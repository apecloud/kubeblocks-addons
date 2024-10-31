# shellcheck shell=bash
# shellcheck disable=SC2034

# Validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "es_prepare_fs_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Elasticsearch Prepare Filesystem Script Tests"
  # Load the script to be tested
  Include ../scripts/prepare-fs.sh

  init() {
    ut_mode="true"
    export ES_HOME="./elasticsearch"
    export LICENSE_FILE="./elasticsearch/LICENSE.txt"
    export MOUNT_LOCAL_CONFIG="./local-config"
    export MOUNT_LOCAL_PLUGINS="./local-plugins"
    export MOUNT_LOCAL_BIN="./local-bin"
    export MOUNT_REMOTE_CONFIG="./remote-config"

    mkdir -p "${ES_HOME}" "${MOUNT_LOCAL_CONFIG}" "${MOUNT_LOCAL_PLUGINS}" "${MOUNT_LOCAL_BIN}" "${MOUNT_REMOTE_CONFIG}"
  }
  BeforeAll "init"

  cleanup() {
    rm -rf "${ES_HOME}" "${MOUNT_LOCAL_CONFIG}" "${MOUNT_LOCAL_PLUGINS}" "${MOUNT_LOCAL_BIN}" "${MOUNT_REMOTE_CONFIG}"
  }
  AfterAll 'cleanup'

  un_setup() {
    # Reset environment variables and state before each test
    unset ES_HOME
    unset LICENSE_FILE
    unset MOUNT_LOCAL_CONFIG
    unset MOUNT_LOCAL_PLUGINS
    unset MOUNT_LOCAL_BIN
    unset MOUNT_REMOTE_CONFIG
  }

  Describe "check_distribution()"
    It "exits with error if license file is missing or invalid"
      touch "${LICENSE_FILE}"  # Create an empty LICENSE file
      When call check_distribution
      The stderr should include "unsupported_distribution"
      The status should be failure
    End

    It "does not exit if license file is valid"
      touch "${LICENSE_FILE}"  # Create an empty LICENSE file
      echo "ELASTIC LICENSE AGREEMENT" > "${LICENSE_FILE}"  # Create a valid LICENSE file
      When run check_distribution
      The status should be success
    End
  End

  Describe "get_duration()"
    It "returns the duration in seconds"
      un_setup
      start_time=$(date +%s)
      sleep 1  # Sleep for 1 second
      When run get_duration "$start_time"
      The output should equal "1"
      The status should be success
    End
  End

  Describe "copy_directory_contents()"
    It "does nothing if source directory is empty"
      un_setup
      export MOUNT_LOCAL_CONFIG="./local-config"
      export MOUNT_LOCAL_PLUGINS="./local-plugins"
      When run copy_directory_contents "${MOUNT_LOCAL_CONFIG}" "${MOUNT_LOCAL_PLUGINS}" "config"
      The output should include "Empty dir ${MOUNT_LOCAL_CONFIG}"
      # capture the output of the ls command
      The stderr should include "No such file or directory"
      The status should be success
    End

#    It "copies files from source to destination"
#      mkdir -p "${ES_HOME}/config"
#      echo "test_config" > "${ES_HOME}/config/test.yml"
#      When run copy_directory_contents "${ES_HOME}" "${MOUNT_LOCAL_CONFIG}" "config"
#      The output should include "Copying ${ES_HOME}/config/* to ${MOUNT_LOCAL_CONFIG}/"
#      The file "${MOUNT_LOCAL_CONFIG}/config/test.yml" should be exist
#      The status should be success
#    End
  End

  Describe "persist_files()"
#    It "copies config, plugins, and bin directories"
#      mkdir -p "${ES_HOME}/config" "${ES_HOME}/plugins" "${ES_HOME}/bin"
#      echo "test_plugin" > "${ES_HOME}/plugins/test_plugin.zip"
#      echo "test_bin" > "${ES_HOME}/bin/test_bin.sh"
#      echo "test_config" > "${ES_HOME}/config/elasticsearch.yml"
#
#      When run persist_files
#      The output should include "Copying ${ES_HOME}/config/* to ${MOUNT_LOCAL_CONFIG}/"
#      The output should include "Copying ${ES_HOME}/plugins/* to ${MOUNT_LOCAL_PLUGINS}/"
#      The output should include "Copying ${ES_HOME}/bin/* to ${MOUNT_LOCAL_BIN}/"
#      The file "${MOUNT_LOCAL_CONFIG}/config/elasticsearch.yml" should be exist
#      The file "${MOUNT_LOCAL_PLUGINS}/plugins/test_plugin.zip" should be exist
#      The file "${MOUNT_LOCAL_BIN}/bin/test_bin.sh" should be exist
#      The status should be success
#    End
  End

  Describe "create_config_links()"
    It "creates symbolic links for configuration files"
      mkdir -p "${MOUNT_REMOTE_CONFIG}"
      echo "test_config" > "${MOUNT_REMOTE_CONFIG}/elasticsearch.yml"
      echo "test_log" > "${MOUNT_REMOTE_CONFIG}/log4j2.properties"

      When run create_config_links
      The stdout should include "Linking ${MOUNT_REMOTE_CONFIG}/elasticsearch.yml to ${MOUNT_LOCAL_CONFIG}/elasticsearch.yml"
      The status should be success
    End
  End
End