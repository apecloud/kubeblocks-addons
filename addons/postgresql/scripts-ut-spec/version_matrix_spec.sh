# shellcheck shell=sh
# shellcheck disable=SC2016 # Ruby snippets are intentionally single-quoted.

Describe "PostgreSQL version matrix contract"

  chart_dir() {
    printf '%s' '..'
  }

  cluster_chart_dir() {
    printf '%s' '../../../addons-cluster/postgresql'
  }

  render_chart() {
    helm dependency build "$(chart_dir)" --skip-refresh >/dev/null || return
    helm template kb-addon-postgresql "$(chart_dir)" --namespace kb-system
  }

  chart_version() {
    awk '$1 == "version:" { print $2; exit }' "$1/Chart.yaml"
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

  service_roles_contract() {
    render_chart | RUBYOPT=-W0 ruby -ryaml -e '
      docs = YAML.load_stream(ARGF.read).compact
      topology = docs.find { |doc| doc["kind"] == "ClusterDefinition" }.dig("spec", "topologies", 0)
      abort unless topology["components"] == [{"name" => "postgresql", "compDef" => "postgresql-"}]
      docs.select { |doc| doc["kind"] == "ComponentDefinition" }.each do |definition|
        services = definition.fetch("spec").fetch("services")
        abort unless services.size == 1
        service = services.fetch(0)
        abort unless service["name"] == "postgresql" && service["roleSelector"] == "primary" && service["serviceName"] == "postgresql"
        abort unless service.dig("spec", "ports", 0, "name") == "tcp-postgresql"
        abort unless service.dig("spec", "ports", 0, "port") == 5432
      end
      puts "ok"
    '
  }

  render_count() {
    pattern="$1"
    render_chart | grep -c "$pattern" || true
  }



  pg13_config_contract() {
    config="$(chart_dir)/config/pg13-config.tpl"
    schema="$(chart_dir)/config/pg13-config-constraint.cue"
    effect_scope="$(chart_dir)/config/pg13-config-effect-scope.yaml"

    grep -q "^wal_keep_size =" "$config" || return 1
    grep -q "^enable_incremental_sort =" "$config" || return 1
    grep -q "^vacuum_cleanup_index_scale_factor =" "$config" || return 1
    grep -q "^[[:space:]]*operator_precedence_warning?:" "$schema" || return 1
    grep -q "^[[:space:]]*vacuum_cleanup_index_scale_factor?:" "$schema" || return 1

    while IFS= read -r expected; do
      grep -Fqx "$expected" "$schema" || return 1
    done <<'EOF'
	archive_timeout: int & >=0 & <=1073741823 | *300 @timeDurationResource(1s)
	autovacuum_max_workers?: int & >=1 & <=262143
	autovacuum_multixact_freeze_max_age?: int & >=10000 & <=2000000000
	autovacuum_vacuum_cost_delay?: float & >=-1 & <=100 @timeDurationResource()
	checkpoint_timeout?: int & >=30 & <=86400 @timeDurationResource(1s)
	force_parallel_mode?: string & "off" | "on" | "regress" | "true" | "false" | "1" | "0"
	geqo_pool_size?: int & >=0 & <=2147483647
	log_file_mode?: int & >=0 & <=511
	log_min_messages?: string & "debug5" | "debug4" | "debug3" | "debug2" | "debug1" | "info" | "notice" | "warning" | "error" | "log" | "fatal" | "panic"
	log_parameter_max_length?: int & >=-1 & <=1073741823 @storeResource()
	log_parameter_max_length_on_error?: int & >=-1 & <=1073741823 @storeResource()
	log_rotation_age: int & >=0 & <=35791394 | *60 @timeDurationResource(1min)
	max_connections?: int & >=1 & <=262143
	max_prepared_transactions: int & >=0 & <=262143 | *0
	max_replication_slots: int & >=0 & <=262143 | *20
	max_wal_senders: int & >=0 & <=262143 | *20
	operator_precedence_warning?: bool & false | true
	ssl_max_protocol_version?: string & "" | "TLSv1" | "TLSv1.1" | "TLSv1.2" | "TLSv1.3"
	ssl_min_protocol_version?: string & "TLSv1" | "TLSv1.1" | "TLSv1.2" | "TLSv1.3"
	vacuum_cost_delay?: float & >=0 & <=100 @timeDurationResource()
	wal_receiver_timeout: int & >=0 & <=2147483647 | *30000 @timeDurationResource()
	wal_sender_timeout: int & >=0 & <=2147483647 | *30000 @timeDurationResource()
	wal_init_zero?: bool & false | true
EOF

    for unsupported in \
      archive_library \
      client_connection_check_interval \
      compute_query_id \
      default_toast_compression \
      enable_async_append \
      enable_memoize \
      huge_page_size \
      idle_session_timeout \
      log_recovery_conflict_waits \
      log_startup_progress_interval \
      min_dynamic_shared_memory \
      min_parallel_relation_size \
      recovery_init_sync_method \
      remove_temp_files_after_crash \
      track_wal_io_timing \
      vacuum_failsafe_age \
      vacuum_multixact_failsafe_age \
      wal_decode_buffer_size
    do
      if grep -q "^${unsupported} =" "$config"; then
        return 1
      fi
      if grep -q "^[[:space:]]*${unsupported}[?:]" "$schema"; then
        return 1
      fi
      if grep -q "^[[:space:]]*- ${unsupported}$" "$effect_scope"; then
        return 1
      fi
    done

    for unavailable_extension_parameter in \
      index_adviser.enable_log \
      index_adviser.max_aggregation_column_count \
      index_adviser.max_candidate_index_count \
      sql_firewall.firewall
    do
      if grep -Fq "${unavailable_extension_parameter}" "$config"; then
        return 1
      fi
      if grep -Fq "\"${unavailable_extension_parameter}\"?:" "$schema"; then
        return 1
      fi
    done

    grep -Fq "pglogical.batch_inserts = 'True'" "$config" || return 1
    grep -Fq '"pglogical.batch_inserts"?:' "$schema" || return 1
  }

  pg13_metrics_contract() {
    metrics="$(chart_dir)/metrics/pg13-metrics.yaml"

    grep -q "total_exec_time / 1000 as exec_time_seconds" "$metrics" || return 1
    grep -q "n_ins_since_vacuum" "$metrics" || return 1
    if grep -q "FROM pg_stat_wal" "$metrics"; then
      return 1
    fi
    if grep -q "waitstart" "$metrics"; then
      return 1
    fi
  }

  It "provides only the PostgreSQL component and its primary service by default"
    When call service_roles_contract
    The status should be success
    The output should eq "ok"
  End

  It "advances the definition chart version to 1.0.8"
    When call chart_version "$(chart_dir)"
    The status should eq 0
    The output should eq "1.0.8"
  End

  It "publishes the latest PostgreSQL 14-18 minors and preserves existing versions"
    When call minor_versions_contract
    The status should eq 0
    The output should eq "ok"
  End

  It "keeps the cluster chart version aligned at 1.0.8"
    When call chart_version "$(cluster_chart_dir)"
    The status should eq 0
    The output should eq "1.0.8"
  End



  It "publishes PostgreSQL 13.23 in the ComponentDefinition, ParametersDefinition, and ComponentVersion"
    When call render_count '^[[:space:]]*serviceVersion: 13.23.0$'
    The status should eq 0
    The output should eq "3"
  End

  It "publishes the PostgreSQL 13.23 image for runtime and lifecycle actions"
    When call render_count 'docker.io/apecloud/spilo:13.23'
    The status should eq 0
    The output should eq "3"
  End

  It "publishes the PostgreSQL 13 immutable ComponentDefinition identity"
    When call render_count '^  name: postgresql-13-1.0.8$'
    The status should eq 0
    The output should eq "1"
  End

  It "uses only PostgreSQL 13-compatible default parameters"
    When call pg13_config_contract
    The status should eq 0
  End

  It "uses PostgreSQL 13-compatible statistics views"
    When call pg13_metrics_contract
    The status should eq 0
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
