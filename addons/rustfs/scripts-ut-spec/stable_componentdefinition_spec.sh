# shellcheck shell=sh

Describe "RustFS stable ComponentDefinition contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  validate_stable_definition_contract() {
    tmp_dir=$(mktemp -d -t rustfs-stable-cmpd-XXXXXX) || return $?
    mkdir -p "${tmp_dir}/addons" "${tmp_dir}/addons-cluster" || return $?
    cp -R "$(repo_root)/addons/rustfs" "${tmp_dir}/addons/rustfs" || return $?
    cp -R "$(repo_root)/addons/kblib" "${tmp_dir}/addons/kblib" || return $?
    cp -R "$(repo_root)/addons-cluster/rustfs" "${tmp_dir}/addons-cluster/rustfs" || return $?
    cp -R "$(repo_root)/addons-cluster/kblib" "${tmp_dir}/addons-cluster/kblib" || return $?

    addon_rendered="${tmp_dir}/addon-rendered.yaml"
    cluster_rendered="${tmp_dir}/cluster-rendered.yaml"
    helm template rustfs "${tmp_dir}/addons/rustfs" --dependency-update >"$addon_rendered" || return $?
    helm template rustfs-cluster "${tmp_dir}/addons-cluster/rustfs" --dependency-update >"$cluster_rendered" || return $?

    ruby -ryaml -e '
      hash_documents = lambda do |content|
        YAML.load_stream(content).select { |document| document.is_a?(Hash) }
      end
      addon_chart = YAML.load_file(ARGV.fetch(0))
      cluster_chart = YAML.load_file(ARGV.fetch(1))
      addon_documents = hash_documents.call(File.read(ARGV.fetch(2)))
      cluster_documents = hash_documents.call(File.read(ARGV.fetch(3)))

      expected_cmpd = "rustfs-0.1.0"
      expected_service_version = "1.0.0-beta.10"
      abort "cluster chart version must match addon chart version" unless cluster_chart.fetch("version") == addon_chart.fetch("version")
      abort "addon appVersion must pin beta.10" unless addon_chart.fetch("appVersion") == expected_service_version
      abort "cluster appVersion must pin beta.10" unless cluster_chart.fetch("appVersion") == expected_service_version

      cmpd = addon_documents.find { |document| document["kind"] == "ComponentDefinition" }
      abort "missing RustFS ComponentDefinition" unless cmpd
      abort "ComponentDefinition identity must remain #{expected_cmpd}" unless cmpd.dig("metadata", "name") == expected_cmpd
      abort "ComponentDefinition must use beta.10" unless cmpd.dig("spec", "serviceVersion") == expected_service_version
      annotations = cmpd.dig("metadata", "annotations") || {}
      abort "ordinary uninstall must not retain the ComponentDefinition" if annotations["helm.sh/resource-policy"] == "keep"
      abort "stable-name install must not bypass immutable checks" if annotations.key?("apps.kubeblocks.io/skip-immutable-check")

      cmpv = addon_documents.find { |document| document["kind"] == "ComponentVersion" }
      comp_defs = cmpv&.dig("spec", "compatibilityRules", 0, "compDefs")
      abort "ComponentVersion must select only #{expected_cmpd}" unless comp_defs == ["^rustfs-0\\.1\\.0$"]

      cluster = cluster_documents.find { |document| document["kind"] == "Cluster" }
      component = cluster&.dig("spec", "componentSpecs", 0)
      abort "cluster chart must bind #{expected_cmpd}" unless component&.fetch("componentDef", nil) == expected_cmpd
      abort "cluster chart must bind beta.10" unless component&.fetch("serviceVersion", nil) == expected_service_version

      hooks = addon_documents.select { |document| document.dig("metadata", "annotations", "helm.sh/hook") }
      abort "ordinary install must not add migration hooks" unless hooks.empty?
      puts "RustFS stable ComponentDefinition contract passed: #{expected_cmpd} #{expected_service_version}"
    ' "${tmp_dir}/addons/rustfs/Chart.yaml" \
      "${tmp_dir}/addons-cluster/rustfs/Chart.yaml" \
      "$addon_rendered" "$cluster_rendered"
  }

  cleanup_charts() {
    [ -n "${tmp_dir:-}" ] && rm -rf "${tmp_dir}" 2>/dev/null || true
    tmp_dir=""
  }
  AfterEach 'cleanup_charts'

  It "keeps a stable definition identity while pinning beta.10"
    When call validate_stable_definition_contract
    The status should be success
    The output should include "RustFS stable ComponentDefinition contract passed"
  End
End
