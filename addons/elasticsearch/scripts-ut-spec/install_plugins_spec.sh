# shellcheck shell=bash
# shellcheck disable=SC2034

# Validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "es_install_plugins_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Elasticsearch Install Plugins Script Tests"
  # Load the scripts to be tested and dependencies
  Include ../scripts/install-plugins.sh

  init() {
    ut_mode="true"
    tmp_dir="./plugins"
    mkdir -p $tmp_dir
    dst_plugins_dir="./dst_plugins"
    mkdir -p $dst_plugins_dir
    es_plugin_cmd="echo '/usr/share/elasticsearch/bin/elasticsearch-plugin'"
  }
  BeforeAll "init"

  cleanup() {
    rm -fr $tmp_dir
    rm -fr $dst_plugins_dir
  }
  AfterAll 'cleanup'

  un_setup() {
    # Reset environment variables and state before each test
    unset SRC_PLUGINS_DIR
    unset DST_PLUGINS_DIR
    unset ES_PLUGIN_CMD
    mkdir -p /tmp/plugins
  }

  Describe "init_vars()"
    It "initializes the plugin directories"
      un_setup
      When call init_vars
      The variable SRC_PLUGINS_DIR should equal "/tmp/plugins"
      The variable DST_PLUGINS_DIR should equal "/usr/share/elasticsearch/plugins"
      The variable ES_PLUGIN_CMD should equal "/usr/share/elasticsearch/bin/elasticsearch-plugin"
      The status should be success
    End
  End

  Describe "check_src_dir()"
    It "exits with message if source directory does not exist"
      un_setup
      When run check_src_dir
      The output should include "no plugins to install"
      The status should be success
    End

    It "does not exit if source directory exists"
      un_setup
      SRC_PLUGINS_DIR="$tmp_dir"
      touch $SRC_PLUGINS_DIR/sample_plugin.zip
      When run check_src_dir
      The status should be success
    End
  End

  Describe "is_archive_file()"
    It "returns true for valid archive files"
      example_file1="plugin.zip"
      When run is_archive_file "$example_file1"
      The status should be success
    End

    It "returns true for valid archive files"
      example_file2="plugin.tar.gz"
      When run is_archive_file "$example_file2"
      The status should be success
    End

    It "returns true for valid archive files"
      example_file3="plugin.gz"
      When run is_archive_file "$example_file3"
      The status should be success
    End

    It "returns false for non-archive files"
      example_file="plugin.txt"
      When run is_archive_file "$example_file"
      The status should be failure
    End
  End

  Describe "native_install_plugin()"
    It "successfully installs a plugin"
      un_setup
      ES_PLUGIN_CMD="echo"  # Mock the install command
      When run native_install_plugin "/tmp/plugins/sample_plugin.zip"
      The output should include "successfully installed plugin sample_plugin.zip"
      The status should be success
    End

    It "handles already existing plugin"
      un_setup
      ES_PLUGIN_CMD="echo already exists"  # Mock the already exists output
      When run native_install_plugin "/tmp/plugins/sample_plugin.zip"
      The output should include "plugin sample_plugin.zip already exists"
      The status should be success
    End

    It "handles failed installation"
      un_setup
      ES_PLUGIN_CMD="echo error"  # Mock the error output
      When run native_install_plugin "/tmp/plugins/sample_plugin.zip"
      The output should include "failed to install plugin sample_plugin.zip"
      The output should include "error"
      The status should be failure
    End
  End

  Describe "copy_install_plugin()"
    It "copies the plugin to the destination directory"
      un_setup
      SRC_PLUGINS_DIR="$tmp_dir"
      DST_PLUGINS_DIR="$dst_plugins_dir"
      touch $tmp_dir/sample_plugin  # Create a sample plugin directory
      When run copy_install_plugin "$tmp_dir/sample_plugin"
      The output should include "successfully installed plugin sample_plugin"
      The status should be success
      The file $dst_plugins_dir/sample_plugin should be exist
    End

    It "handles already existing plugin in destination"
      un_setup
      SRC_PLUGINS_DIR="$tmp_dir"
      DST_PLUGINS_DIR="$dst_plugins_dir"
      rm -f $dst_plugins_dir/sample_plugin  # Simulate existing plugin
      mkdir $dst_plugins_dir/sample_plugin  # Simulate existing plugin
      When run copy_install_plugin "$SRC_PLUGINS_DIR/sample_plugin"
      The output should include "plugin sample_plugin already exists"
      The status should be success
    End
  End
End