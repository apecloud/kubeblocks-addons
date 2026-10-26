# shellcheck shell=bash

Describe "apecloud-mysql passwordConfig migration"
  check_accounts() (
    set -o pipefail
    local chart="$1" version
    shift
    version=$(helm show chart "$chart" | ruby -ryaml -e 'puts YAML.load(STDIN.read).fetch("version")') || return
    helm template password-config "$chart" "$@" | ruby ./password_config_check.rb "$version" "$chart"
  )

  check_future_version() (
    local tmp_chart
    tmp_chart=$(mktemp -d) || return
    trap 'rm -rf "$tmp_chart"' EXIT
    cp -R "${SHELLSPEC_CWD:?}/addons/apecloud-mysql/." "$tmp_chart/" || return
    ruby -e 'p = ARGV.fetch(0); File.write(p, File.read(p).sub(/^version: .+$/, "version: 9.9.9-password-test"))' "$tmp_chart/Chart.yaml" || return
    check_accounts "$tmp_chart"
  )

  It "preserves all account policies and credential consumers"
    When call check_accounts "${SHELLSPEC_CWD:?}/addons/apecloud-mysql"
    The status should be success
  End

  It "retains definitions and matches old and new identities on upgrade rendering"
    When call check_accounts "${SHELLSPEC_CWD:?}/addons/apecloud-mysql" --is-upgrade
    The status should be success
  End

  It "preserves credentials with a custom registry and namespace"
    When call check_accounts "${SHELLSPEC_CWD:?}/addons/apecloud-mysql" --namespace password-test --set image.registry=registry.example.invalid
    The status should be success
  End

  It "keeps policies and version selectors valid after a later chart version bump"
    When call check_future_version
    The status should be success
  End
End
