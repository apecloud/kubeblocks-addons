# shellcheck shell=sh

Describe "MySQL syncer API contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  render_mysql_8046_release() {
    helm template test "$(chart_path)" \
      --show-only templates/cpmv.yaml "$@" |
      awk '
        /^    - name: 8[.]0[.]46$/ { capture = 1 }
        capture && /^    - name: / && $0 !~ /8[.]0[.]46$/ { exit }
        capture { print }
      '
  }

  It "renders the apps/v1-capable syncer for MySQL 8.0.46"
    When call render_mysql_8046_release
    The status should be success
    The output should include "serviceVersion: 8.0.46"
    The output should include "init-syncer: docker.io/apecloud/syncer:0.7.7"
    The output should not include "apecloud/syncer:0.6.8"
    The output should not include "apecloud/syncer:0.7.6"
  End

  It "keeps a known-bad override observable as a negative control"
    When call render_mysql_8046_release --set image.syncer.tag=0.6.8
    The status should be success
    The output should include "init-syncer: docker.io/apecloud/syncer:0.6.8"
    The output should not include "init-syncer: docker.io/apecloud/syncer:0.7.7"
  End
End
