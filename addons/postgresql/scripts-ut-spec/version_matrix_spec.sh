# shellcheck shell=sh
# shellcheck disable=SC2016

Describe "PostgreSQL version matrix contract"
  render_chart() {
    helm dependency build .. --skip-refresh >/dev/null || return
    helm template kb-addon-postgresql .. --namespace kb-system
  }

  minor_versions_contract() {
    render_chart | RUBYOPT=-W0 ruby -ryaml -e '
      documents = YAML.load_stream(ARGF.read).compact
      component_version = documents.find { |doc| doc["kind"] == "ComponentVersion" && doc.dig("metadata", "name") == "postgresql" }
      releases = component_version.fetch("spec").fetch("releases")
      versions = releases.map { |release| release.fetch("serviceVersion") }
      abort "duplicate service version" unless versions.uniq == versions
      %w[12.22.0 13.23.0 14.23.0 15.18.0 16.14.0 17.10.0 18.4.0].each do |version|
        abort "missing existing #{version}" unless versions.include?(version)
      end
      %w[14.24 15.19 16.15 17.11 18.6].each do |version|
        service_version = "#{version}.0"
        release = releases.find { |entry| entry["serviceVersion"] == service_version }
        abort "missing #{service_version}" unless release
        %w[postgresql switchover accountProvision].each do |container|
          abort "wrong #{container} image" unless release.dig("images", container) == "docker.io/apecloud/spilo:#{version}"
        end
        definition = documents.find { |doc| doc["kind"] == "ComponentDefinition" && doc.dig("spec", "serviceVersion") == service_version }
        abort "missing default definition for #{service_version}" unless definition
        rule = component_version.dig("spec", "compatibilityRules").find { |entry| entry.fetch("releases").include?(service_version) }
        abort "wrong major compatibility" unless rule && rule.fetch("compDefs").all? { |name| name.start_with?("postgresql-#{version.split(".").first}-") }
      end
      puts "ok"
    '
  }

  It "publishes the latest PostgreSQL 14-18 minors and preserves existing versions"
    When call minor_versions_contract
    The status should eq 0
    The output should eq "ok"
  End
End
