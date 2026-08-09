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

  render_component_version() {
    helm template test "$(repo_root)/addons/rustfs" \
      --dependency-update \
      --show-only templates/cmpv.yaml
  }

  It "pins beta.10 consistently in both charts and the default release"
    When call read_source_versions
    The status should be success
    The output should eq "0.1.2|0.1.1|1.0.0-beta.10|1.0.0-beta.10|1.0.0-beta.10|1.0.0-beta.10|1.0.0-beta.10|true"
  End

  It "renders the beta.10 service version and runtime image"
    When call render_component_version
    The status should be success
    The output should include "serviceVersion: 1.0.0-beta.10"
    The output should include "rustfs: docker.io/rustfs/rustfs:1.0.0-beta.10"
    The output should not include "1.0.0-beta.8"
  End
End
