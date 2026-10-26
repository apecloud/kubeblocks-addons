# shellcheck shell=bash

Describe "Elasticsearch passwordConfig migration"
  chart_path() {
    printf '%s' "${ES_PASSWORD_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/elasticsearch}"
  }

  check_accounts() {
    local chart="$1" version
    shift
    version=$(helm show chart "$chart" | ruby -ryaml -e 'puts YAML.load(STDIN.read).fetch("version")') || return
    helm template es-password-config "$chart" "$@" | ruby ./password_config_check.rb "$version"
  }

  check_future_version() (
    local contract_dir
    contract_dir=$(mktemp -d) || return
    trap 'rm -rf "$contract_dir"' EXIT
    helm package "$(chart_path)" --version 9.9.9-password-test --destination "$contract_dir" >/dev/null || return
    check_accounts "$contract_dir/elasticsearch-9.9.9-password-test.tgz"
  )

  check_supported_versions() (
    local contract_dir supported
    contract_dir=$(mktemp -d) || return
    trap 'rm -rf "$contract_dir"' EXIT
    mkdir "$contract_dir/templates" || return
    cat > "$contract_dir/Chart.yaml" <<'YAML'
apiVersion: v2
name: es-password-compatibility-test
version: 0.1.0
YAML
    cat > "$contract_dir/templates/versions.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: es-password-compatibility-test
data:
  {{- range $version := list "1.0.2" "1.0.9" "1.1.0" "1.1.9" "1.2.0" "1.2.1" "1.3.0" }}
  {{ $version | quote }}: {{ semverCompare $.Values.supported $version | quote }}
  {{- end }}
YAML
    supported=$(helm show chart "$(chart_path)" | ruby -ryaml -e 'puts YAML.load(STDIN.read).fetch("annotations").fetch("addon.kubeblocks.io/kubeblocks-version")') || return
    helm template es-password-compatibility-test "$contract_dir" --set-string "supported=$supported" | ruby -ryaml -e '
      data = YAML.load_stream(STDIN.read).compact.first.fetch("data")
      data.each do |version, accepted|
        expected = %w[1.0.2 1.0.9 1.1.0 1.1.9].include?(version) ? "false" : "true"
        abort "incorrect support declaration for #{version}" unless accepted == expected
      end
    '
  )

  It "renders all 18 policies with retained new definitions and valid credential references"
    When call check_accounts "$(chart_path)"
    The status should be success
  End

  It "keeps both old and new definitions selectable during upgrade rendering"
    When call check_accounts "$(chart_path)" --is-upgrade
    The status should be success
  End

  It "preserves policies with a custom registry and namespace"
    When call check_accounts "$(chart_path)" --namespace password-test --set image.registry=registry.example.invalid
    The status should be success
  End

  It "follows later chart versions instead of overwriting the old account identity"
    When call check_future_version
    The status should be success
  End

  It "declares KubeBlocks 1.2 and later as the supported stable product line"
    When call check_supported_versions
    The status should be success
  End
End
