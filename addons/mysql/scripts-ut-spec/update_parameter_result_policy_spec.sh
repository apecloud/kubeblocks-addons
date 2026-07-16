# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "MySQL update-parameter result policy"
  render_reconfigure_policy_summary() {
    local work_dir rendered
    work_dir=$(mktemp -d)
    rendered="${work_dir}/rendered.yaml"

    cp -R .. "${work_dir}/mysql"
    cp -R ../../kblib "${work_dir}/kblib"
    helm dependency build "${work_dir}/mysql" >/dev/null
    helm template mysql "${work_dir}/mysql" > "${rendered}"

    printf 'reconfigure=%s exit64=%s invalid=%s no_retry=%s exit1=%s\n' \
      "$(grep -c '^      reconfigure:$' "${rendered}")" \
      "$(grep -c '^[[:space:]]*- execExitCode: 64$' "${rendered}")" \
      "$(grep -c '^[[:space:]]*code: InvalidParameter$' "${rendered}")" \
      "$(grep -c '^[[:space:]]*retry: false$' "${rendered}")" \
      "$(grep -c '^[[:space:]]*- execExitCode: 1$' "${rendered}" || true)"

    rm -rf "${work_dir}"
  }

  It "renders one dedicated non-retryable InvalidParameter mapping per reconfigure action"
    When call render_reconfigure_policy_summary
    The status should be success
    The output should equal "reconfigure=7 exit64=7 invalid=7 no_retry=7 exit1=0"
  End
End
