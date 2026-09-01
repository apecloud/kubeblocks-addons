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
    helm template kb-addon-postgresql "$(chart_dir)" --namespace kb-system --dependency-update
  }

  chart_version() {
    awk '$1 == "version:" { print $2; exit }' "$1/Chart.yaml"
  }

  render_count() {
    pattern="$1"
    render_chart | grep -c "$pattern" || true
  }

  pgbouncer_component_contract() {
    render_chart | RUBYOPT=-W0 ruby -ryaml -e '
      documents = YAML.load_stream(ARGF.read).compact
      cluster_definition = documents.find { |document| document["kind"] == "ClusterDefinition" }
      topologies = cluster_definition.dig("spec", "topologies")
      abort unless topologies.map { |topology| topology["name"] } == ["replication"]
      replication = topologies.first
      abort unless replication["components"] == [
        {"name" => "postgresql", "compDef" => "postgresql-"},
        {"name" => "pgbouncer", "compDef" => "pgbouncer-1.0.6"}
      ]

      definitions = documents.select { |document| document["kind"] == "ComponentDefinition" }
      postgres = definitions.find { |definition| definition.dig("metadata", "name") == "postgresql-14-1.0.6" }
      pgbouncer = definitions.find { |definition| definition.dig("metadata", "name") == "pgbouncer-1.0.6" }
      abort unless pgbouncer.dig("spec", "replicasLimit") == {"minReplicas" => 0, "maxReplicas" => 64}
      abort unless pgbouncer.dig("spec", "serviceVersion") == "1.25.2"
      abort unless pgbouncer.dig("spec", "services", 0, "spec", "ports", 0, "port") == 6432
      abort if pgbouncer.dig("spec", "services", 0).key?("serviceName")
      resources = pgbouncer.dig("spec", "runtime", "containers", 0, "resources")
      abort unless resources == {
        "requests" => {"cpu" => "100m", "memory" => "128Mi"},
        "limits" => {"cpu" => "500m", "memory" => "512Mi"}
      }
      refs = pgbouncer.dig("spec", "vars").map do |var|
        var.dig("valueFrom", "serviceVarRef", "compDef") || var.dig("valueFrom", "credentialVarRef", "compDef")
      end.compact
      abort unless refs == Array.new(4, "postgresql-")
      abort if pgbouncer.dig("spec", "vars").any? { |var| var["name"].start_with?("PGBOUNCER_") }
      configs = pgbouncer.dig("spec", "configs")
      abort unless configs.map { |config| config["name"] } == ["pgbouncer-configuration"]
      abort unless configs.all? { |config| config["externalManaged"] == true && config["defaultMode"] == 0444 }
      abort if configs.any? { |config| config.key?("restartOnFileChange") }
      abort unless configs.map { |config| config["volumeName"] } == ["pgbouncer-config"]

      postgres_ports = postgres.dig("spec", "services", 0, "spec", "ports").map { |port| port["port"] }
      abort unless postgres_ports == [5432]
      postgres_containers = postgres.dig("spec", "runtime", "containers").map { |container| container["name"] }
      abort if postgres_containers.include?("pgbouncer")
      postgres_pcr = documents.find do |document|
        document["kind"] == "ParamConfigRenderer" && document.dig("metadata", "name") == "postgresql14-pcr-1.0.6"
      end
      abort unless postgres_pcr.dig("spec", "configs").map { |config| config["name"] } == ["postgresql.conf"]
      pgbouncer_pcr = documents.find do |document|
        document["kind"] == "ParamConfigRenderer" &&
          document.dig("metadata", "name") == "pgbouncer-pcr-1.0.6"
      end
      abort unless pgbouncer_pcr.dig("spec", "componentDef") == "pgbouncer-1.0.6"
      abort unless pgbouncer_pcr.dig("spec", "serviceVersion") == "1.25.2"
      abort unless pgbouncer_pcr.dig("spec", "parametersDefs") == ["pgbouncer-pd-1.0.6"]
      pgbouncer_format = pgbouncer_pcr.dig("spec", "configs", 0)
      abort unless pgbouncer_format["name"] == "pgbouncer.ini"
      abort unless pgbouncer_format.dig("fileFormatConfig", "format") == "ini"
      abort unless pgbouncer_format.dig("fileFormatConfig", "iniConfig", "sectionName") == "pgbouncer"

      pgbouncer_pd = documents.find do |document|
        document["kind"] == "ParametersDefinition" &&
          document.dig("metadata", "name") == "pgbouncer-pd-1.0.6"
      end
      exposed = %w[
        pool_mode max_client_conn default_pool_size min_pool_size
        reserve_pool_size max_db_connections max_user_connections
      ]
      abort unless pgbouncer_pd.dig("spec", "fileName") == "pgbouncer.ini"
      abort unless pgbouncer_pd.dig("spec", "dynamicParameters") == exposed
      abort unless pgbouncer_pd.dig("spec", "parametersSchema", "topLevelKey") == "PgBouncerParameter"
      reload_action = pgbouncer_pd.dig("spec", "reloadAction", "unixSignalTrigger")
      abort unless reload_action == {"signal" => "SIGHUP", "processName" => "pgbouncer"}
      abort if pgbouncer_pd.dig("spec").key?("staticParameters")
      pgbouncer_schema = pgbouncer_pd.dig("spec", "parametersSchema", "cue")
      exposed.each { |parameter| abort unless pgbouncer_schema.include?(parameter) }
      abort unless pgbouncer_schema.include?(%q{pool_mode?: "session" | "transaction" | "statement" | *"session"})
      abort unless pgbouncer_schema.include?("max_client_conn?: int & >=1 & <=999999 | *500")
      abort unless pgbouncer_schema.include?("max_db_connections?: int & >=0 & <=999999 | *80")
      abort unless pgbouncer_schema.include?("#PgBouncerConfiguration: {\n\tpgbouncer: #PgBouncerConfig\n}")
      abort unless pgbouncer_schema.include?("configuration: #PgBouncerConfiguration")
      abort unless pgbouncer_schema.include?(%q{auth_type:                 "md5"})
      abort if pgbouncer_schema.match?(/^\s*\.\.\.\s*$/)
      account_refs = pgbouncer.dig("spec", "vars").map { |var| var.dig("valueFrom", "credentialVarRef", "name") }.compact
      abort unless account_refs == ["postgres", "postgres"]
      probe = pgbouncer.dig("spec", "runtime", "containers", 0, "readinessProbe", "exec", "command", -1)
      abort unless probe.include?("--port=6432") && probe.include?("$POSTGRESQL_USERNAME")
      abort unless probe.include?("$CURRENT_POD_IP") && probe.include?("NOT pg_is_in_recovery()")
      abort if probe.include?("budget-ready") || probe.include?("budget-sync")
      readiness = pgbouncer.dig("spec", "runtime", "containers", 0, "readinessProbe")
      abort unless readiness["failureThreshold"] == 1 && readiness["periodSeconds"] == 5
      pod_security = pgbouncer.dig("spec", "runtime", "securityContext")
      abort unless pod_security == {
        "runAsUser" => 70, "runAsGroup" => 70,
        "fsGroup" => 70, "fsGroupChangePolicy" => "OnRootMismatch"
      }
      volumes = pgbouncer.dig("spec", "runtime", "volumes")
      abort unless volumes == [{"name" => "pgbouncer-state", "emptyDir" => {}}]
      container = pgbouncer.dig("spec", "runtime", "containers", 0)
      container_security = container["securityContext"]
      abort unless container_security["runAsNonRoot"] == true
      abort unless container_security["runAsUser"] == 70 && container_security["runAsGroup"] == 70
      abort unless container_security["allowPrivilegeEscalation"] == false
      abort unless container_security.dig("capabilities", "drop") == ["ALL"]
      config_mount = container["volumeMounts"].find { |mount| mount["name"] == "pgbouncer-config" }
      abort unless config_mount["mountPath"] == "/opt/pgbouncer-template"
      state_mount = container["volumeMounts"].find { |mount| mount["name"] == "pgbouncer-state" }
      abort unless state_mount["mountPath"] == "/etc/pgbouncer"
      abort if container["volumeMounts"].any? { |mount| mount["mountPath"] == "/var/run/pgbouncer" }
      env = pgbouncer.dig("spec", "runtime", "containers", 0, "env")
      pod_ip = env.find { |entry| entry["name"] == "CURRENT_POD_IP" }
      abort unless pod_ip.dig("valueFrom", "fieldRef", "fieldPath") == "status.podIP"
      abort unless env.map { |entry| entry["name"] } == [
        "CURRENT_POD_IP", "POSTGRESQL_HOST", "POSTGRESQL_PORT", "POSTGRESQL_USERNAME", "POSTGRESQL_PASSWORD"
      ]
      pgbouncer_config = documents.find do |document|
        document["kind"] == "ConfigMap" &&
          document.dig("metadata", "name") == "pgbouncer-configuration-1.0.6"
      end.dig("data", "pgbouncer.ini")
      abort unless pgbouncer_config.lines.any? { |line| line.match?(/^\s*listen_addr\s*=\s*\*\s*$/) }
      abort unless pgbouncer_config.lines.any? { |line| line.match?(/^\s*client_tls_sslmode\s*=\s*disable\s*$/) }
      abort unless pgbouncer_config.lines.any? { |line| line.match?(/^\s*server_tls_sslmode\s*=\s*disable\s*$/) }
      abort unless pgbouncer_config.include?("auth_file = /etc/pgbouncer/userlist.txt")
      abort unless pgbouncer_config.include?("FROM pg_catalog.pg_authid")
      abort unless pgbouncer_config.include?("rolvaliduntil") && pgbouncer_config.include?("rolcanlogin")
      abort if pgbouncer_config.match?(/^\s*pidfile\s*=/)
      abort if pgbouncer_config.include?("{{")
      abort unless pgbouncer_config.include?("pool_mode = session")
      abort unless pgbouncer_config.include?("max_client_conn = 500")
      abort unless pgbouncer_config.include?("default_pool_size = 20")
      abort unless pgbouncer_config.include?("min_pool_size = 5")
      abort unless pgbouncer_config.include?("reserve_pool_size = 5")
      abort unless pgbouncer_config.include?("max_db_connections = 80")
      abort unless pgbouncer_config.include?("max_user_connections = 80")
      abort if pgbouncer_config.lines.any? { |line| line.match?(/^\s*logfile\s*=\s*\/dev\/stderr\s*$/) }
      main_config = documents.find do |document|
        document["kind"] == "ConfigMap" && document.dig("metadata", "name") == "pgbouncer-configuration-1.0.6"
      end
      abort unless main_config["data"].keys == ["pgbouncer.ini"]
      abort if documents.any? do |document|
        document["kind"] == "ConfigMap" && document.dig("metadata", "name").to_s.include?("pgbouncer-budget")
      end

      version = documents.find do |document|
        document["kind"] == "ComponentVersion" && document.dig("metadata", "name") == "pgbouncer"
      end
      abort unless version.dig("spec", "compatibilityRules", 0, "compDefs") == ["pgbouncer-"]
      release = version.dig("spec", "releases", 0)
      abort unless release["name"] == "1.25.2" && release["serviceVersion"] == "1.25.2"
      abort unless release.dig("images", "pgbouncer") == "docker.io/apecloud/pgbouncer:1.25.2"
      postgres_version = documents.find do |document|
        document["kind"] == "ComponentVersion" && document.dig("metadata", "name") == "postgresql"
      end
      abort unless postgres_version["spec"]["releases"].all? do |postgres_release|
        postgres_release.dig("images", "pgbouncer") == "docker.io/apecloud/pgbouncer:1.19.0"
      end
      puts "ok"
    '
  }

  pgbouncer_runtime_script_contract() {
    script="$(chart_dir)/scripts/pgbouncer-setup.sh"

    test "$(sed -n '1p' "$script")" = '#!/bin/sh' || return 1
    grep -Fq 'exec "$pgbouncer_bin" "$pgbouncer_conf_file"' "$script" || return 1
    grep -Fq 'pgbouncer_backend_host="${POSTGRESQL_HOST:-}"' "$script" || return 1
    grep -Fq 'pgbouncer_backend_port="${POSTGRESQL_PORT:-}"' "$script" || return 1
    grep -Fq 'mktemp "${pgbouncer_conf_dir}/.pgbouncer.ini.XXXXXX"' "$script" || return 1
    grep -Fq "printf '%%include %s\\n\\n[databases]\\n'" "$script" || return 1

    for dynamic in pgbouncer-budget PGBOUNCER_MEMORY_BYTES PGBOUNCER_DESIRED_REPLICAS \
      current_setting sync_backend_budget 'SHOW CONFIG' 'RELOAD;'; do
      if grep -Fq "$dynamic" "$script"; then
        return 1
      fi
    done

    for sidecar_artifact in /opt/bitnami /etc/passwd /etc/group useradd 'su pgbouncer' CURRENT_POD_IP; do
      if grep -Fq "$sidecar_artifact" "$script"; then
        return 1
      fi
    done
  }

  pgbouncer_image_and_pull_policy_contract() {
    helm template kb-addon-postgresql "$(chart_dir)" --namespace kb-system --dependency-update \
      --set pgbouncer.componentImage.tag=1.25.2-test \
      --set pgbouncer.componentImage.pullPolicy=Always | RUBYOPT=-W0 ruby -ryaml -e '
        documents = YAML.load_stream(ARGF.read).compact
        version = documents.find { |document| document["kind"] == "ComponentVersion" && document.dig("metadata", "name") == "pgbouncer" }
        abort unless version.dig("spec", "releases", 0, "images", "pgbouncer") == "docker.io/apecloud/pgbouncer:1.25.2-test"
        definition = documents.find { |document| document["kind"] == "ComponentDefinition" && document.dig("metadata", "name") == "pgbouncer-1.0.6" }
        abort unless definition.dig("spec", "runtime", "containers", 0, "imagePullPolicy") == "Always"
        puts "ok"
      '
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

  It "advances the definition chart version to 1.0.6"
    When call chart_version "$(chart_dir)"
    The status should eq 0
    The output should eq "1.0.6"
  End

  It "keeps the cluster chart version aligned at 1.0.6"
    When call chart_version "$(cluster_chart_dir)"
    The status should eq 0
    The output should eq "1.0.6"
  End

  It "keeps one replication topology and adds a zero-capable PgBouncer component"
    When call pgbouncer_component_contract
    The status should eq 0
    The output should eq "ok"
  End

  It "honors the PgBouncer component image tag and pull policy"
    When call pgbouncer_image_and_pull_policy_contract
    The status should eq 0
    The output should eq "ok"
  End

  It "uses the PgBouncer component image's non-root POSIX runtime contract"
    When call pgbouncer_runtime_script_contract
    The status should eq 0
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
    When call render_count '^  name: postgresql-13-1.0.6$'
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
End
