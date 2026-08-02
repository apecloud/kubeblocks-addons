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
    addon_upgrade_rendered="${tmp_dir}/addon-upgrade-rendered.yaml"
    cluster_rendered="${tmp_dir}/cluster-rendered.yaml"

    helm template rustfs "${tmp_dir}/addons/rustfs" --dependency-update >"$addon_rendered" || return $?
    helm template rustfs "${tmp_dir}/addons/rustfs" --dependency-update --is-upgrade >"$addon_upgrade_rendered" || return $?
    helm template rustfs-cluster "${tmp_dir}/addons-cluster/rustfs" --dependency-update >"$cluster_rendered" || return $?

    ruby -ryaml -e '
      addon_chart = YAML.load_file(ARGV.fetch(0))
      cluster_chart = YAML.load_file(ARGV.fetch(1))
      addon_documents = YAML.load_stream(File.read(ARGV.fetch(2))).compact
      cluster_documents = YAML.load_stream(File.read(ARGV.fetch(3))).compact
      upgrade_documents = YAML.load_stream(File.read(ARGV.fetch(4))).compact

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

      legacy_cmpd = "rustfs-0.1.0"
      regular_upgrade_cmpds = upgrade_documents.map do |document|
        document.dig("metadata", "name") if document["kind"] == "ComponentDefinition"
      end.compact
      abort "legacy #{legacy_cmpd} must leave the regular upgrade manifest" if regular_upgrade_cmpds.include?(legacy_cmpd)

      hook_documents = upgrade_documents.select do |document|
        document.dig("metadata", "annotations", "helm.sh/hook") == "pre-upgrade"
      end
      abort "retention hooks must not render during a fresh install" if addon_documents.any? { |document| document.dig("metadata", "annotations", "helm.sh/hook") }
      hook_documents.each do |document|
        delete_policy = document.dig("metadata", "annotations", "helm.sh/hook-delete-policy").to_s.split(",")
        abort "retention hook cleanup policy is incomplete" unless %w[before-hook-creation hook-succeeded].all? { |policy| delete_policy.include?(policy) }
      end
      retention_job = hook_documents.find { |document| document["kind"] == "Job" }
      abort "missing pre-upgrade ComponentDefinition retention Job" unless retention_job
      job_args = retention_job.dig("spec", "template", "spec", "containers", 0, "args") || []
      script = job_args.first.to_s
      abort "retention Job must target removed #{legacy_cmpd}" unless job_args.include?(legacy_cmpd)
      abort "retention Job must fail closed on kubectl errors and explicitly tolerate NotFound" unless script.include?("--ignore-not-found")
      abort "retention Job must distinguish a terminating definition from an absent definition" unless script.include?("deletionTimestamp")
      abort "retention Job must add Helm keep without writing ComponentDefinition spec" unless script.include?("helm.sh/resource-policy=keep") && script.include?("--overwrite")
      abort "retention Job must read back the Helm keep annotation" unless script.include?("metadata.annotations.helm\\.sh/resource-policy")

      service_account = hook_documents.find { |document| document["kind"] == "ServiceAccount" }
      cluster_role = hook_documents.find { |document| document["kind"] == "ClusterRole" }
      cluster_role_binding = hook_documents.find { |document| document["kind"] == "ClusterRoleBinding" }
      abort "retention hook RBAC is incomplete" unless service_account && cluster_role && cluster_role_binding
      rule = cluster_role.fetch("rules").find { |candidate| candidate.fetch("resources", []).include?("componentdefinitions") }
      abort "retention hook needs only get/patch ComponentDefinition access" unless rule && %w[get patch].all? { |verb| rule.fetch("verbs", []).include?(verb) }
      abort "retention Job must use the hook ServiceAccount" unless retention_job.dig("spec", "template", "spec", "serviceAccountName") == service_account.dig("metadata", "name")
      abort "retention binding must reference the hook ClusterRole" unless cluster_role_binding.dig("roleRef", "name") == cluster_role.dig("metadata", "name")
      subject = cluster_role_binding.fetch("subjects", []).find { |candidate| candidate["kind"] == "ServiceAccount" }
      abort "retention binding must reference the hook ServiceAccount" unless subject && subject["name"] == service_account.dig("metadata", "name")
      job_weight = Integer(retention_job.dig("metadata", "annotations", "helm.sh/hook-weight"))
      rbac_weights = [service_account, cluster_role, cluster_role_binding].map do |document|
        Integer(document.dig("metadata", "annotations", "helm.sh/hook-weight"))
      end
      abort "retention RBAC hooks must run before the retention Job" unless rbac_weights.all? { |weight| weight < job_weight }

      puts "RustFS versioned ComponentDefinition contract passed: #{legacy_cmpd} -> #{expected_cmpd} #{expected_service_version}"
    ' "${tmp_dir}/addons/rustfs/Chart.yaml" \
      "${tmp_dir}/addons-cluster/rustfs/Chart.yaml" \
      "$addon_rendered" "$cluster_rendered" "$addon_upgrade_rendered"
  }

  run_retention_hook() {
    scenario=$1
    prepare_charts || return $?
    addon_upgrade_rendered="${tmp_dir}/addon-upgrade-rendered.yaml"
    hook_script="${tmp_dir}/retention-hook.sh"
    fake_log="${tmp_dir}/kubectl.log"
    mkdir -p "${tmp_dir}/bin" || return $?

    helm template rustfs "${tmp_dir}/addons/rustfs" --dependency-update --is-upgrade >"$addon_upgrade_rendered" || return $?
    ruby -ryaml -e '
      job = YAML.load_stream(File.read(ARGV.fetch(0))).compact.find { |document| document["kind"] == "Job" }
      abort "missing retention Job" unless job
      File.write(ARGV.fetch(1), job.dig("spec", "template", "spec", "containers", 0, "args", 0))
    ' "$addon_upgrade_rendered" "$hook_script" || return $?
    cp "$(repo_root)/addons/rustfs/scripts-ut-spec/fixtures/kubectl" "${tmp_dir}/bin/kubectl" || return $?
    chmod +x "${tmp_dir}/bin/kubectl" || return $?

    FAKE_KUBECTL_SCENARIO=$scenario \
      FAKE_KUBECTL_LOG=$fake_log \
      PATH="${tmp_dir}/bin:$PATH" \
      sh -e "$hook_script" rustfs-0.1.0
    status=$?
    [ ! -f "$fake_log" ] || sed -n '1,20p' "$fake_log"
    return "$status"
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


  It "annotates a non-terminating legacy definition before Helm removes it"
    When call run_retention_hook present
    The status should be success
    The output should include "annotate componentdefinition.apps.kubeblocks.io rustfs-0.1.0 helm.sh/resource-policy=keep --overwrite"
  End

  It "explicitly skips an absent legacy definition"
    When call run_retention_hook absent
    The status should be success
    The output should include "ComponentDefinition rustfs-0.1.0 is absent; retention is not needed"
  End

  It "fails closed when the legacy definition is already terminating"
    When call run_retention_hook terminating
    The status should be failure
    The stderr should include "is terminating; refusing to treat it as retained"
  End

  It "fails closed on kubectl errors"
    When call run_retention_hook get-error
    The status should be failure
    The stderr should include "forced kubectl get failure"
  End

  It "fails closed when the keep annotation does not read back"
    When call run_retention_hook annotate-noop
    The status should be failure
    The output should include "annotate componentdefinition.apps.kubeblocks.io rustfs-0.1.0 helm.sh/resource-policy=keep --overwrite"
    The stderr should include "did not converge to a retained non-terminating object"
  End
End
