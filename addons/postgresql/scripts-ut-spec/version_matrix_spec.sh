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

  output_plugins_contract() {
    RUBYOPT=-W0 ruby -ryaml -rtmpdir -rfileutils -ropen3 <<'RUBY'
      Dir.mktmpdir("postgresql-output-plugins") do |dir|
        FileUtils.mkdir_p("#{dir}/templates")
        File.write("#{dir}/Chart.yaml", "apiVersion: v2\nname: config-test\nversion: 0.1.0\n")
        File.write("#{dir}/templates/config.yaml", <<~YAML)
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: config-test
          data:
            postgresql.conf: |-
              {{- tpl (.Files.Get "postgresql.tpl") .Values | nindent 4 }}
        YAML
        {14 => 24, 15 => 19, 16 => 15, 17 => 11, 18 => 6}.each do |major, minor|
          template = File.read("../config/pg#{major}-config.tpl")
          # Stub only resource helpers; execute the real version gates with Helm/Sprig.
          template = template.gsub(/getContainer(?:Memory|CPU) \( index \$\.podSpec.containers 0 \)/, "0")
          template = template.gsub(/getComponentPVCSizeByName \$\.component "data"/, "0")
          File.write("#{dir}/postgresql.tpl", template)
          schema = File.read("../config/pg#{major}-config-constraint.cue")
          abort "missing optional schema for PG#{major}" unless schema.match?(/^\s*output_plugin_libraries\?: string$/)
          [minor - 1, minor, minor + 1].each do |patch|
            version = "#{major}.#{patch}.0"
            # Cluster may omit its version or retain a request different from the resolved Component.
            [nil, "#{major}.0.0"].each do |requested|
              spec = {"name" => "postgresql"}
              spec["serviceVersion"] = requested if requested
              values = {"component" => {"serviceVersion" => version}, "cluster" => {"spec" => {"componentSpecs" => [spec]}}}
              File.write("#{dir}/values.yaml", values.to_yaml)
              output, error, status = Open3.capture3("helm", "template", "config-test", dir)
              abort error unless status.success?
              config = YAML.load_stream(output).compact.first.fetch("data").fetch("postgresql.conf")
              expected = "output_plugin_libraries = 'pgoutput,test_decoding,wal2json,decoderbufs,pglogical,pglogical_output'"
              lines = config.lines.map(&:strip).grep(/^output_plugin_libraries\s*=/)
              abort "wrong output plugin configuration for #{version}" unless lines == (patch >= minor ? [expected] : [])
            end
          end
        end
      end
      puts "ok"
RUBY
  }

  It "renders trusted output plugins only for supported resolved minor versions"
    When call output_plugins_contract
    The status should eq 0
    The output should eq "ok"
  End

End
