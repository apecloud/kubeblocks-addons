# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Elasticsearch versioned plugin fail-close contract"
  setup() {
    fixture=$(mktemp -d)
    mkdir -p "${fixture}/source" "${fixture}/target" "${fixture}/bin"
    cat >"${fixture}/bin/elasticsearch-plugin" <<'SCRIPT'
#!/usr/bin/env bash
if [ "${1:-}" = "list" ]; then
  printf '%s\n' ${PLUGIN_LIST_OUTPUT:-analysis-ik analysis-pinyin}
  exit 0
fi
exit 1
SCRIPT
    chmod +x "${fixture}/bin/elasticsearch-plugin"
  }

  cleanup() {
    rm -rf "${fixture}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  run_installer() {
    ES_PLUGIN_SOURCE_DIR="${fixture}/source" \
    ES_PLUGIN_TARGET_DIR="${fixture}/target" \
    ELASTICSEARCH_PLUGIN_BIN="${fixture}/bin/elasticsearch-plugin" \
    ELASTICSEARCH_VERSION=9.3.2 \
    REQUIRE_VERSIONED_PLUGINS=true \
    REQUIRED_PLUGIN_DIRS="ik pinyin" \
    REQUIRED_PLUGIN_NAMES="analysis-ik analysis-pinyin" \
      bash ../scripts/install-plugins.sh
  }

  run_legacy_installer() {
    env -u ELASTICSEARCH_VERSION \
      ES_PLUGIN_SOURCE_DIR="${fixture}/source" \
      ES_PLUGIN_TARGET_DIR="${fixture}/target" \
      ELASTICSEARCH_PLUGIN_BIN="${fixture}/bin/elasticsearch-plugin" \
      bash ../scripts/install-plugins.sh
  }

  make_plugin() {
    name=$1
    version=$2
    mkdir -p "${fixture}/source/9.3.2/${name}"
    printf 'elasticsearch.version=%s\n' "${version}" >"${fixture}/source/9.3.2/${name}/plugin-descriptor.properties"
  }

  It "fails when the required version directory is absent"
    When call run_installer
    The status should be failure
    The error should include "required plugin directory is missing"
  End

  It "fails when one required plugin is absent"
    make_plugin ik 9.3.2
    When call run_installer
    The status should be failure
    The output should include "Installing plugins for Elasticsearch version 9.3.2"
    The error should include "required plugin pinyin is missing"
  End

  It "fails when a plugin descriptor targets another Elasticsearch version"
    make_plugin ik 9.3.2
    make_plugin pinyin 8.19.0
    When call run_installer
    The status should be failure
    The output should include "Installing plugins for Elasticsearch version 9.3.2"
    The error should include "pinyin descriptor targets 8.19.0, expected 9.3.2"
  End

  It "copies and verifies the complete required plugin set"
    make_plugin ik 9.3.2
    make_plugin pinyin 9.3.2
    When call run_installer
    The status should be success
    The output should include "verified required Elasticsearch plugins: analysis-ik analysis-pinyin"
    The path "${fixture}/target/ik/plugin-descriptor.properties" should be file
    The path "${fixture}/target/pinyin/plugin-descriptor.properties" should be file
  End

  It "fails when Elasticsearch does not list every required plugin after installation"
    make_plugin ik 9.3.2
    make_plugin pinyin 9.3.2
    PLUGIN_LIST_OUTPUT=analysis-ik
    export PLUGIN_LIST_OUTPUT
    When call run_installer
    The status should be failure
    The output should include "successfully installed plugin pinyin"
    The error should include "required Elasticsearch plugin analysis-pinyin is not installed"
  End

  It "keeps the legacy no-source path successful without requiring a version"
    rm -rf "${fixture}/source"
    When call run_legacy_installer
    The status should be success
    The output should eq "no plugins to install"
  End

  It "keeps the legacy source-without-version path failing"
    When call run_legacy_installer
    The status should be failure
    The error should include "ELASTICSEARCH_VERSION is not set"
  End

  It "keeps a missing legacy version directory fail-open"
    When run env \
      ES_PLUGIN_SOURCE_DIR="${fixture}/source" \
      ES_PLUGIN_TARGET_DIR="${fixture}/target" \
      ELASTICSEARCH_PLUGIN_BIN="${fixture}/bin/elasticsearch-plugin" \
      ELASTICSEARCH_VERSION=8.19.0 \
      bash ../scripts/install-plugins.sh
    The status should be success
    The output should eq "No plugin directory found for version 8.19.0"
  End
End
