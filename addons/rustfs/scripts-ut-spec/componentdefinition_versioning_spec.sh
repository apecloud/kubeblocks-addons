# shellcheck shell=sh

Describe "RustFS versioned ComponentDefinition contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  prepare_charts() {
    tmp_dir=$(mktemp -d -t rustfs-versioned-cmpd-XXXXXX) || return $?
    mkdir -p "${tmp_dir}/addons" "${tmp_dir}/addons-cluster" || return $?
    cp -R "$(repo_root)/addons/rustfs" "${tmp_dir}/addons/rustfs" || return $?
    cp -R "$(repo_root)/addons/kblib" "${tmp_dir}/addons/kblib" || return $?
    cp -R "$(repo_root)/addons-cluster/rustfs" "${tmp_dir}/addons-cluster/rustfs" || return $?
    cp -R "$(repo_root)/addons-cluster/kblib" "${tmp_dir}/addons-cluster/kblib" || return $?
  }

  validate_versioned_definition_contract() {
    prepare_charts || return $?
    addon_rendered="${tmp_dir}/addon-rendered.yaml"
    cluster_rendered="${tmp_dir}/cluster-rendered.yaml"

    helm template rustfs "${tmp_dir}/addons/rustfs" --dependency-update >"$addon_rendered" || return $?
    helm template rustfs-cluster "${tmp_dir}/addons-cluster/rustfs" --dependency-update >"$cluster_rendered" || return $?

    ruby -ryaml -e '
      addon_chart = YAML.load_file(ARGV.fetch(0))
      cluster_chart = YAML.load_file(ARGV.fetch(1))
      addon_documents = YAML.load_stream(File.read(ARGV.fetch(2))).compact
      cluster_documents = YAML.load_stream(File.read(ARGV.fetch(3))).compact

      chart_version = addon_chart.fetch("version")
      abort "RustFS addon chart version must advance past immutable baseline 0.1.0" if chart_version == "0.1.0"
      abort "RustFS cluster chart version must match addon chart version" unless cluster_chart.fetch("version") == chart_version

      expected_cmpd = "rustfs-#{chart_version}"
      expected_service_version = "1.0.0-beta.10"
      abort "addon appVersion must pin #{expected_service_version}" unless addon_chart.fetch("appVersion") == expected_service_version
      abort "cluster appVersion must pin #{expected_service_version}" unless cluster_chart.fetch("appVersion") == expected_service_version
      cmpd = addon_documents.find { |document| document["kind"] == "ComponentDefinition" }
      abort "missing RustFS ComponentDefinition" unless cmpd
      abort "expected #{expected_cmpd}, got #{cmpd.dig("metadata", "name").inspect}" unless cmpd.dig("metadata", "name") == expected_cmpd
      abort "expected serviceVersion #{expected_service_version}" unless cmpd.dig("spec", "serviceVersion") == expected_service_version
      annotations = cmpd.dig("metadata", "annotations") || {}
      abort "new ComponentDefinition must not bypass immutable checks" if annotations.key?("apps.kubeblocks.io/skip-immutable-check")
      abort "versioned ComponentDefinitions must be retained across Helm upgrades" unless annotations["helm.sh/resource-policy"] == "keep"

      cmpv = addon_documents.find { |document| document["kind"] == "ComponentVersion" }
      comp_defs = cmpv&.dig("spec", "compatibilityRules", 0, "compDefs")
      expected_pattern = "^#{expected_cmpd.gsub(".", "\\\\.")}$"
      abort "ComponentVersion must select only #{expected_cmpd}" unless comp_defs == [expected_pattern]

      cluster = cluster_documents.find { |document| document["kind"] == "Cluster" }
      component = cluster&.dig("spec", "componentSpecs", 0)
      abort "cluster chart must pin #{expected_cmpd}" unless component&.fetch("componentDef", nil) == expected_cmpd
      abort "cluster chart must pin #{expected_service_version}" unless component&.fetch("serviceVersion", nil) == expected_service_version

      puts "RustFS versioned ComponentDefinition contract passed: #{expected_cmpd} #{expected_service_version}"
    ' "${tmp_dir}/addons/rustfs/Chart.yaml" \
      "${tmp_dir}/addons-cluster/rustfs/Chart.yaml" \
      "$addon_rendered" "$cluster_rendered"
  }

  cleanup_charts() {
    [ -n "${tmp_dir:-}" ] && rm -rf "${tmp_dir}" 2>/dev/null || true
    tmp_dir=""
  }
  AfterEach 'cleanup_charts'

  It "creates a fresh chart-versioned definition and pins the beta.10 cluster reference"
    When call validate_versioned_definition_contract
    The status should be success
    The output should include "RustFS versioned ComponentDefinition contract passed"
  End
End
