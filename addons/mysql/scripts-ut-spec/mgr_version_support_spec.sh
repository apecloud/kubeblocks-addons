# shellcheck shell=sh

Describe "MySQL MGR version support contract"
  chart_path() {
    printf '%s' "${SHELLSPEC_CWD:?}/addons/mysql"
  }

  render_template() {
    helm template mysql "$(chart_path)" --show-only "templates/$1"
  }

  extract_release_names() {
    render_template "$1" | ruby -ryaml -e '
      document = YAML.safe_load(STDIN.read, aliases: true)
      puts document.fetch("spec").fetch("releases").map { |release| release.fetch("name") }.sort.join(",")
    '
  }

  extract_compatible_releases() {
    render_template "$1" | ruby -ryaml -e '
      document = YAML.safe_load(STDIN.read, aliases: true)
      rules = document.fetch("spec").fetch("compatibilityRules").map do |rule|
        comp_defs = rule.fetch("compDefs")
        major = %w[8.0 8.4].find { |version| comp_defs.any? { |name| name == "mysql-mgr-#{version}" } }
        raise "unexpected MGR compatibility rule: #{comp_defs.join(",")}" unless major
        "#{major}=#{rule.fetch("releases").sort.join(",")}"
      end
      puts rules.sort
    '
  }

  extract_default_service_version() {
    render_template "$1" | ruby -ryaml -e '
      document = YAML.safe_load(STDIN.read, aliases: true)
      puts document.fetch("spec").fetch("serviceVersion")
    '
  }

  assert_mgr_8046_is_selectable() {
    releases=$(extract_release_names cpmv-mgr.yaml) || return
    compatible=$(extract_compatible_releases cpmv-mgr.yaml) || return
    expected_compatible=$(printf '8.0=8.0.45,8.0.46\n8.4=8.4.10,8.4.9')
    printf 'mgr_releases=%s\nmgr_compatible=%s\n' "$releases" "$compatible"
    [ "$releases" = "8.0.45,8.0.46,8.4.10,8.4.9" ] || return
    [ "$compatible" = "$expected_compatible" ] || return
  }

  assert_mgr_default_is_supported() {
    version=$(extract_default_service_version cmpd-mysql80-mgr.yaml) || return
    printf 'mgr_default=%s\n' "$version"
    [ "$version" = "8.0.45" ]
  }

  assert_non_mgr_8046_is_preserved() {
    standalone=$(extract_release_names cpmv.yaml) || return
    orchestrator=$(extract_release_names cpmv-orc.yaml) || return
    printf 'standalone=%s\norchestrator=%s\n' "$standalone" "$orchestrator"
    printf '%s\n' "$standalone" | grep -Eq '(^|,)8\.0\.46(,|$)' || return
    printf '%s\n' "$orchestrator" | grep -Eq '(^|,)8\.0\.46(,|$)' || return
  }

  assert_user_facing_boundary() {
    grep -Fq 'MySQL 8.0.46 can be explicitly selected for MGR validation, but has a known upstream Group Replication defect' "$(chart_path)/README.md" || return
    grep -Fq 'https://github.com/mysql/mysql-server/issues/696' "$(chart_path)/README.md" || return
    grep -Fq 'Selecting this version does not mean that the defect has been fixed' "$(chart_path)/README.md" || return
    grep -Fq 'the MGR 8.0 default remains 8.0.45' "$(chart_path)/README.md" || return
    grep -Fq 'Other MySQL 8.0.46 topologies remain supported' "$(chart_path)/README.md" || return
    grep -Eq '^[[:space:]]*serviceVersion:[[:space:]]*8\.0\.45([[:space:]]|$)' "${SHELLSPEC_CWD}/examples/mysql/cluster-mgr.yaml" || return
  }

  It "makes 8.0.46 selectable only in the MGR 8.0 compatibility rule"
    When call assert_mgr_8046_is_selectable
    The status should be success
    The output should include "mgr_releases=8.0.45,8.0.46,8.4.10,8.4.9"
    The output should include "8.0=8.0.45,8.0.46"
    The output should include "8.4=8.4.10,8.4.9"
  End

  assert_mgr_8046_images() {
    render_template cpmv-mgr.yaml | ruby -ryaml -e '
      d = YAML.safe_load(STDIN.read, aliases: true)
      r = d.fetch("spec").fetch("releases").find { |x| x["name"] == "8.0.46" }
      abort "missing 8.0.46" unless r
      abort "incorrect images" unless %w[mysql accountProvision].all? { |k| r.fetch("images").fetch(k) == "docker.io/mysql:8.0.46" }
      puts "mysql/accountProvision=8.0.46"
    '
  }

  It "uses the existing 8.0.46 image for database and accountProvision"
    When call assert_mgr_8046_images
    The status should be success
    The output should include "mysql/accountProvision=8.0.46"
  End

  It "uses 8.0.45 as the MGR 8.0 default"
    When call assert_mgr_default_is_supported
    The status should be success
    The output should include "mgr_default=8.0.45"
  End

  It "preserves MySQL 8.0.46 for non-MGR topologies"
    When call assert_non_mgr_8046_is_preserved
    The status should be success
    The output should include "8.0.46"
  End

  It "publishes the upstream-defect boundary, restoration condition, migration, and a supported MGR example"
    When call assert_user_facing_boundary
    The status should be success
  End
End
