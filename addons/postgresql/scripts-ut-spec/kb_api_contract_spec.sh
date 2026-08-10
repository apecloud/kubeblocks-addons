# shellcheck shell=sh

Describe "PostgreSQL KubeBlocks API contract"

  chart_dir() {
    printf '%s' '..'
  }

  render_chart() {
    helm template kb-addon-postgresql "$(chart_dir)" --namespace kb-system --dependency-update
  }

  kubeblocks_floor() {
    sed -n 's/.*addon.kubeblocks.io\/kubeblocks-version: *"\([^"]*\)".*/\1/p' "$(chart_dir)/Chart.yaml"
  }

  chart_version() {
    awk '$1 == "version:" { print $2; exit }' "$(chart_dir)/Chart.yaml"
  }

  render_count() {
    pattern="$1"
    render_chart | grep -c "$pattern" || true
  }

  component_definitions_with_pod_list_rbac() {
    render_chart | ruby -ryaml -e '
      definitions = YAML.load_stream(ARGF.read).compact.select do |document|
        document["kind"] == "ComponentDefinition"
      end
      count = definitions.count do |definition|
        rules = definition.dig("spec", "policyRules") || []
        rules.any? do |rule|
          (rule["apiGroups"] || []).include?("") &&
            (rule["resources"] || []).include?("pods") &&
            (rule["verbs"] || []).include?("list")
        end
      end
      puts count
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
	force_parallel_mode?: string & =~"(?i)^(off|on|regress|true|false|1|0)$"
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
	operator_precedence_warning?: #PgBool
	ssl_max_protocol_version?: string & "" | "TLSv1" | "TLSv1.1" | "TLSv1.2" | "TLSv1.3"
	ssl_min_protocol_version?: string & "TLSv1" | "TLSv1.1" | "TLSv1.2" | "TLSv1.3"
	vacuum_cost_delay?: float & >=0 & <=100 @timeDurationResource()
	wal_receiver_timeout: int & >=0 & <=2147483647 | *30000 @timeDurationResource()
	wal_sender_timeout: int & >=0 & <=2147483647 | *30000 @timeDurationResource()
	wal_init_zero?: #PgBool
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

  It "declares the KB 1.2 floor required by the rendered API fields"
    When call kubeblocks_floor
    The status should eq 0
    The output should eq ">=1.2.0"
  End

  It "advances the chart identity when immutable ComponentDefinitions change"
    When call chart_version
    The status should eq 0
    The output should eq "1.2.0-alpha.2"
  End

  It "publishes every ComponentDefinition under the advanced immutable identity"
    When call render_count '^  name: postgresql-\(12\|13\|14\|15\|16\|17\|18\)-1.2.0-alpha.2$'
    The status should eq 0
    The output should eq "7"
  End

  It "does not project a create-time pod-name list into the runtime"
    When call render_count '^[[:space:]]*- name: POSTGRES_POD_NAME_LIST$'
    The status should eq 0
    The output should eq "0"
  End

  It "grants every ComponentDefinition the pod-list permission used by live arbitration"
    When call component_definitions_with_pod_list_rbac
    The status should eq 0
    The output should eq "7"
  End

  It "renders exactly one CmpD reconfigure action per PostgreSQL major"
    When call render_count '^[[:space:]]*reconfigure:$'
    The status should eq 0
    The output should eq "7"
  End

  It "does not render the legacy PD reloadAction path"
    When call render_count '^[[:space:]]*reloadAction:$'
    The status should eq 0
    The output should eq "0"
  End

  It "binds every PD to the KB 1.2 config entry"
    When call render_count '^[[:space:]]*templateName: postgresql-configuration$'
    The status should eq 0
    The output should eq "7"
  End

  It "uses the projected KB scripts path for all CmpD actions"
    When call render_count '/kb-scripts/update-parameter.sh "\$1" "\$2"'
    The status should eq 0
    The output should eq "7"
  End

  It "publishes PG 18.4 in the CmpD, PD, and ComponentVersion"
    When call render_count '^[[:space:]]*serviceVersion: 18.4.0$'
    The status should eq 0
    The output should eq "3"
  End

  It "publishes the PG 18.4 image for runtime and lifecycle actions"
    When call render_count 'docker.io/apecloud/spilo:18.4'
    The status should eq 0
    The output should eq "3"
  End

  It "publishes PG 13.23 in the CmpD, PD, and ComponentVersion"
    When call render_count '^[[:space:]]*serviceVersion: 13.23.0$'
    The status should eq 0
    The output should eq "3"
  End

  It "publishes the PG 13.23 image for runtime and lifecycle actions"
    When call render_count 'docker.io/apecloud/spilo:13.23'
    The status should eq 0
    The output should eq "3"
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
