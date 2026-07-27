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

  render_without_default_syncer_digest() (
    chart=$(chart_path)
    values=$(mktemp)
    trap 'rm -f "$values"' EXIT
    awk "
      !/^[[:space:]]*\\\"0[.]7[.]7\\\":[[:space:]]*sha256:2cf5d059a029f06372c615ddf79b2fc7ff1876934811932f049e8e7977d224dd[[:space:]]*$/
    " "$chart/values.yaml" >"$values"
    helm template test "$chart" --show-only templates/cpmv.yaml \
      --values "$values" >/dev/null
  )

  render_with_malformed_default_syncer_digest() (
    chart=$(chart_path)
    values=$(mktemp)
    trap 'rm -f "$values"' EXIT
    sed \
      's/sha256:2cf5d059a029f06372c615ddf79b2fc7ff1876934811932f049e8e7977d224dd/sha256:not-a-digest/' \
      "$chart/values.yaml" >"$values"
    helm template test "$chart" --show-only templates/cpmv.yaml \
      --values "$values" >/dev/null
  )

  It "renders the apps/v1-capable syncer for MySQL 8.0.46"
    When call render_mysql_8046_release
    The status should be success
    The output should include "serviceVersion: 8.0.46"
    The output should include "init-syncer: docker.io/apecloud/syncer:0.7.7@sha256:2cf5d059a029f06372c615ddf79b2fc7ff1876934811932f049e8e7977d224dd"
    The output should not include "apecloud/syncer:0.6.8"
    The output should not include "apecloud/syncer:0.7.6"
  End

  It "keeps a known-bad override observable as a negative control"
    When call render_mysql_8046_release --set image.syncer.tag=0.6.8
    The status should be success
    The output should include "init-syncer: docker.io/apecloud/syncer:0.6.8"
    The output should not include "@sha256:2cf5d059a029f06372c615ddf79b2fc7ff1876934811932f049e8e7977d224dd"
  End

  It "fails closed when the default tag loses its immutable digest"
    When call render_without_default_syncer_digest
    The status should be failure
    The stderr should include "image.syncer.digests[0.7.7] is required"
  End

  It "fails closed when a configured syncer digest is malformed"
    When call render_with_malformed_default_syncer_digest
    The status should be failure
    The stderr should include "image.syncer.digests[0.7.7] must be sha256:<64 lowercase hex>"
  End
End
