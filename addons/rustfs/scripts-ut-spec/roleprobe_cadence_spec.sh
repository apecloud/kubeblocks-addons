# shellcheck shell=sh

Describe "RustFS roleProbe render contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  prepare_chart() {
    tmp_dir=$(mktemp -d -t rustfs-roleprobe-render-XXXXXX) || return $?
    mkdir -p "${tmp_dir}/addons" || return $?
    cp -R "$(repo_root)/addons/rustfs" "${tmp_dir}/addons/rustfs" || return $?
    cp -R "$(repo_root)/addons/kblib" "${tmp_dir}/addons/kblib" || return $?
  }

  render_cmpd() {
    prepare_chart || return $?
    helm template test "${tmp_dir}/addons/rustfs" \
      --dependency-update \
      --show-only templates/cmpd.yaml
  }

  validate_roleprobe_cadence() {
    render_cmpd | ruby -ryaml -e '
      document = YAML.load_stream($stdin.read).compact.find do |item|
        item.is_a?(Hash) && item["kind"] == "ComponentDefinition"
      end
      abort "ComponentDefinition is missing" unless document
      probe = document.dig("spec", "lifecycleActions", "roleProbe")
      abort "roleProbe is missing" unless probe.is_a?(Hash)
      abort "periodSeconds must be 1, got #{probe["periodSeconds"].inspect}" unless probe["periodSeconds"] == 1
      abort "timeoutSeconds must be 3, got #{probe["timeoutSeconds"].inspect}" unless probe["timeoutSeconds"] == 3
      puts "RustFS roleProbe cadence is 1s/3s"
    '
  }

  cleanup_chart() {
    [ -n "${tmp_dir:-}" ] && rm -rf "${tmp_dir}" 2>/dev/null || true
    tmp_dir=""
  }
  AfterEach 'cleanup_chart'

  It "renders a one-second period and three-second timeout"
    When call validate_roleprobe_cadence
    The status should be success
    The output should include "RustFS roleProbe cadence is 1s/3s"
  End
End
