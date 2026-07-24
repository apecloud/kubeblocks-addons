# shellcheck shell=sh

Describe "PostgreSQL metrics compatibility contract"

  chart_dir() {
    printf '%s' '..'
  }

  render_component_definitions() {
    helm template kb-addon-postgresql "$(chart_dir)" \
      --namespace kb-system \
      --show-only templates/cmpd.yaml
  }

  disabled_bgwriter_majors() {
    render_component_definitions | awk '
      /^---$/ {
        if (disabled && major != "") {
          print major
        }
        major = ""
        disabled = 0
        next
      }
      major == "" && /^[[:space:]]*serviceVersion: [0-9]+\./ {
        split($2, version, ".")
        major = version[1]
      }
      /--no-collector\.stat_bgwriter/ {
        disabled = 1
      }
      END {
        if (disabled && major != "") {
          print major
        }
      }
    '
  }

  check_pg17_plus_bgwriter_queries() {
    for major in 17 18; do
      file="$(chart_dir)/metrics/pg${major}-metrics.yaml"
      for pattern in \
        '^pg_stat_bgwriter:$' \
        'FROM pg_catalog\.pg_stat_bgwriter AS bgwriter' \
        'CROSS JOIN pg_catalog\.pg_stat_checkpointer AS checkpointer' \
        'checkpointer\.num_timed AS checkpoints_timed_total' \
        'checkpointer\.num_requested AS checkpoints_req_total' \
        'checkpointer\.write_time AS checkpoint_write_time_total' \
        'checkpointer\.sync_time AS checkpoint_sync_time_total' \
        'checkpointer\.buffers_written AS buffers_checkpoint_total' \
        'bgwriter\.buffers_clean AS buffers_clean_total' \
        'bgwriter\.maxwritten_clean AS maxwritten_clean_total' \
        'bgwriter\.buffers_alloc AS buffers_alloc_total'
      do
        if ! grep -q "$pattern" "$file"; then
          printf 'pg%s missing %s\n' "$major" "$pattern"
        fi
      done
    done
  }

  It "disables the legacy stat_bgwriter collector only for PostgreSQL 17 and 18"
    When call disabled_bgwriter_majors
    The status should eq 0
    The output should eq "17
18"
  End

  It "maps PostgreSQL 17+ bgwriter and checkpointer catalogs to compatible metrics"
    When call check_pg17_plus_bgwriter_queries
    The status should eq 0
    The output should eq ""
  End
End
