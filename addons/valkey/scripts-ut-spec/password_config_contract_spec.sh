# shellcheck shell=bash

Describe "Valkey system account password configuration"
  build_chart_dependency() {
    helm dependency build .. >/dev/null
  }
  BeforeAll "build_chart_dependency"

  # KubeBlocks #10537 reads SystemAccount.passwordConfig; an absent config
  # intentionally creates a passwordless account. Check the rendered account,
  # including the generation policy, rather than only a template substring.
  rendered_password_policies() {
    local rendered
    rendered=$(helm template password-contract .. --show-only "templates/$1") || return 1
    printf '%s\n' "$rendered" | awk '
      function emit() {
        if (kind != "ComponentDefinition") return
        if (!name || account != "default" || init != "true" || !config || legacy ||
            password_length != 16 || digits != 8 || symbols != "0" || letters != "MixedCases") {
          print "invalid default account passwordConfig: " name > "/dev/stderr"
          failed=1
          return
        }
        print name "|" password_length "|" digits "|" symbols "|" letters
        count++
      }
      /^---$/ {
        emit()
        kind=name=account=init=password_length=digits=symbols=letters=""
        metadata=accounts=config=legacy=0
        next
      }
      /^kind: / {kind=$2}
      /^metadata:/ {metadata=1; next}
      /^spec:/ {metadata=0}
      metadata && /^  name:/ {name=$2}
      /^  systemAccounts:/ {accounts=1; next}
      accounts && /^  [^ ]/ {accounts=0}
      accounts && /^    - name:/ {account=$3}
      accounts && /^      initAccount:/ {init=$2}
      accounts && /^      passwordConfig:/ {config=1}
      accounts && /^      passwordGenerationPolicy:/ {legacy=1}
      accounts && /^        length:/ {password_length=$2}
      accounts && /^        numDigits:/ {digits=$2}
      accounts && /^        numSymbols:/ {symbols=$2}
      accounts && /^        letterCase:/ {letters=$2}
      END {emit(); if (failed || count == 0) exit 1}
    '
  }

  It "renders explicit password generation for both data component versions"
    When call rendered_password_policies cmpd.yaml
    The status should be success
    The stdout should eq "valkey-8|16|8|0|MixedCases
valkey-9|16|8|0|MixedCases"
  End

  It "renders explicit password generation for both Sentinel component versions"
    When call rendered_password_policies cmpd-valkey-sentinel.yaml
    The status should be success
    The stdout should eq "valkey-sentinel-8|16|8|0|MixedCases
valkey-sentinel-9|16|8|0|MixedCases"
  End
End
