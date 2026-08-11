# shellcheck shell=sh

Describe "RustFS beta.10 version pin"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  read_source_versions() {
    ruby -ryaml -e '
      root = ARGV.fetch(0)
      addon_chart = YAML.load_file(File.join(root, "addons/rustfs/Chart.yaml"))
      cluster_chart = YAML.load_file(File.join(root, "addons-cluster/rustfs/Chart.yaml"))
      values = YAML.load_file(File.join(root, "addons/rustfs/values.yaml"))
      releases = values.fetch("versions")
      abort "expected exactly one RustFS release" unless releases.length == 1
      release = releases.fetch(0)
      puts [
        addon_chart.fetch("version"),
        cluster_chart.fetch("version"),
        addon_chart.fetch("appVersion"),
        cluster_chart.fetch("appVersion"),
        release.fetch("version"),
        release.fetch("tag"),
        release.fetch("serviceVersion"),
        release.fetch("isDefault")
      ].join("|")
    ' "$(repo_root)"
  }

  prepare_chart() {
    tmp_dir=$(mktemp -d -t rustfs-version-pin-XXXXXX) || return $?
    mkdir -p "${tmp_dir}/addons" || return $?
    cp -R "$(repo_root)/addons/rustfs" "${tmp_dir}/addons/rustfs" || return $?
    cp -R "$(repo_root)/addons/kblib" "${tmp_dir}/addons/kblib" || return $?
    helm dependency build "${tmp_dir}/addons/rustfs" >/dev/null || return $?
  }

  cleanup_chart() {
    chart_dir=${tmp_dir:-}
    tmp_dir=
    [ -n "${chart_dir}" ] || return 0
    "${cleanup_rm:-rm}" -rf "${chart_dir}" || return $?
    [ ! -e "${chart_dir}" ]
  }

  render_component_version() {
    helm template test "${tmp_dir}/addons/rustfs" \
      --show-only templates/cmpv.yaml
  }

  validate_rendered_release() {
    render_component_version | ruby -ryaml -e '
      document = YAML.load_stream($stdin.read).find { |item| item.is_a?(Hash) && item["kind"] == "ComponentVersion" }
      abort "ComponentVersion is missing" unless document
      releases = document.dig("spec", "releases")
      abort "expected exactly one ComponentVersion release" unless releases.is_a?(Array) && releases.length == 1
      release = releases.fetch(0)
      expected_image = "docker.io/rustfs/rustfs:1.0.0-beta.10"
      images = release.fetch("images")
      actual = [
        release.fetch("serviceVersion"),
        images["rustfs"],
        images["roleProbe"]
      ]
      expected = ["1.0.0-beta.10", expected_image, expected_image]
      abort "unexpected rendered release: #{actual.join("|")}" unless actual == expected
      puts actual.join("|")
    '
  }

  delete_role_probe_image() {
    ruby -e '
      path = ARGV.fetch(0)
      source = File.read(path)
      abort "roleProbe image line is missing" unless source.sub!(/^\s+roleProbe:.*\n/, "")
      File.write(path, source)
    ' "${tmp_dir}/addons/rustfs/templates/cmpv.yaml"
  }

  replace_role_probe_with_beta9() {
    ruby -e '
      path = ARGV.fetch(0)
      source = File.read(path)
      replacement = "        roleProbe: docker.io/rustfs/rustfs:1.0.0-beta.9\n"
      abort "roleProbe image line is missing" unless source.sub!(/^\s+roleProbe:.*\n/, replacement)
      File.write(path, source)
    ' "${tmp_dir}/addons/rustfs/templates/cmpv.yaml"
  }

  validate_without_role_probe_image() {
    delete_role_probe_image || return $?
    validate_rendered_release
  }

  validate_with_beta9_role_probe_image() {
    replace_role_probe_with_beta9 || return $?
    validate_rendered_release
  }

  validate_cleanup_rejects_false_success() {
    chart_dir=${tmp_dir:?}
    fake_rm="${chart_dir}/fake-rm"
    printf '%s\n' '#!/bin/sh' 'exit 0' >"${fake_rm}" || return $?
    chmod +x "${fake_rm}" || return $?

    cleanup_rm=${fake_rm}
    cleanup_chart
    cleanup_status=$?
    cleanup_rm=
    tmp_dir=${chart_dir}

    [ "${cleanup_status}" -ne 0 ] || return 1
    [ -d "${chart_dir}" ] || return 1

    command rm -rf "${chart_dir}" || return $?
    [ ! -e "${chart_dir}" ] || return 1
    tmp_dir=
    printf '%s\n' "cleanup false-success rejected; trusted teardown removed one root"
  }

  BeforeEach 'prepare_chart'
  AfterEach 'cleanup_chart'

  It "pins beta.10 consistently in both charts and the default release"
    When call read_source_versions
    The status should be success
    The output should eq "0.1.2|0.1.1|1.0.0-beta.10|1.0.0-beta.10|1.0.0-beta.10|1.0.0-beta.10|1.0.0-beta.10|true"
  End

  It "renders the beta.10 service version and runtime and roleProbe images"
    When call validate_rendered_release
    The status should be success
    The output should eq "1.0.0-beta.10|docker.io/rustfs/rustfs:1.0.0-beta.10|docker.io/rustfs/rustfs:1.0.0-beta.10"
  End

  It "rejects a release without the roleProbe image mapping"
    When call validate_without_role_probe_image
    The status should be failure
    The stderr should include "unexpected rendered release"
  End

  It "rejects a roleProbe image pinned to another release"
    When call validate_with_beta9_role_probe_image
    The status should be failure
    The stderr should include "unexpected rendered release"
  End

  It "rejects cleanup success while the chart tree still exists"
    When call validate_cleanup_rejects_false_success
    The status should be success
    The output should eq "cleanup false-success rejected; trusted teardown removed one root"
  End
End
