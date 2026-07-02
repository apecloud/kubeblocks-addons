# shellcheck shell=sh
#
# alpha.86 v1 (Helen 2026-05-19) — focused source-level contract tests
# for the persisted reconfigureAction variant on the semisync topology
# (Jack peer review 5-guard list, msg a13b8850).
#
# 5 guard groups, mapped to test gates below:
#   G1 init-syncer creates loader file + dir with correct group/mode
#   G2 --defaults-extra-file is the FIRST mariadbd option in
#      start_mariadbd_process (positional assertion, not just grep)
#   G3 reconfigureAction.persisted has injection defense on param
#      name (^[A-Za-z0-9_.-]+$) and value (no newline / NUL / control
#      char / section header [mysqld])
#   G4 fail-closed sentinels on mkdir / tmp write / mv / parse smoke
#   G5 loader file content is exactly `!includedir <dir>` (no key=value
#      would crash mariadbd at startup)
#
# Plus base contracts kept from alpha.84 v1 / alpha.85:
#   - persisted variant is SEMISYNC ONLY (other cmpds use base helper)
#   - base reconfigureAction helper has NO persistence shell code
#   - KB-managed config (config/mariadb-semisync.tpl) has NO !includedir
#     (that was the alpha.84 v1 INI parser failure mode)

Describe "alpha.86 reconfigureAction.persisted semisync gates"
  ADDON_ROOT="${SHELLSPEC_CWD:?}/addons/mariadb"
  HELPERS_TPL="${ADDON_ROOT}/templates/_helpers.tpl"
  CMPD_SEMISYNC="${ADDON_ROOT}/templates/cmpd-replication.yaml"
  CMPD_ENTRYPOINT="${ADDON_ROOT}/scripts/replication-entrypoint.sh"
  CMPD_STANDALONE="${ADDON_ROOT}/templates/cmpd.yaml"
  CMPD_REPLICATION="${ADDON_ROOT}/templates/cmpd-replication.yaml"
  CMPD_GALERA="${ADDON_ROOT}/templates/cmpd-galera.yaml"
  SEMISYNC_CFG="${ADDON_ROOT}/config/mariadb-semisync.tpl"
  EFFECT_SCOPE="${ADDON_ROOT}/config/mariadb-config-effect-scope.yaml"

  extract_persisted_helper_body() {
    awk '
      /^{{- define "mariadb.config.reconfigureAction.persisted" -}}/ { in_helper = 1; next }
      in_helper && /^{{- end -}}/ { exit }
      in_helper { print }
    ' "${HELPERS_TPL}"
  }

  extract_base_helper_body() {
    awk '
      /^{{- define "mariadb.config.reconfigureAction" -}}/ { in_helper = 1; next }
      in_helper && /^{{- end -}}/ { exit }
      in_helper { print }
    ' "${HELPERS_TPL}"
  }

  extract_start_mariadbd_function_body() {
    awk '
      /^[[:space:]]*start_mariadbd_process\(\) \{/ { in_func = 1; print; next }
      in_func && /^[[:space:]]*\}[[:space:]]*$/ { print; exit }
      in_func { print }
    ' "${CMPD_ENTRYPOINT}"
  }

  extract_init_syncer_command_body() {
    # Init container "init-syncer" body; the third occurrence of the
    # bash -c heredoc-style block in cmpd-replication.yaml. We use the
    # marker line "cp -r /bin/syncer /bin/syncerctl /tools/" to locate
    # it; that line is unique to this init container.
    awk '
      /cp -r \/bin\/syncer \/bin\/syncerctl \/tools\// { in_init = 1 }
      in_init { print }
      in_init && /touch.*\.replication-pending/ { in_init = 0 }
    ' "${CMPD_SEMISYNC}"
  }

  Describe "B2 regression — main container chown -R does not strip runtime-overrides permissions"
    # Jack 07:03 peer review B2: main container body executes
    # `chown -R mysql:mysql {{ .Values.dataMountPath }}` which would
    # reset the gid=1000 + g+rwx that init-syncer set on
    # runtime-overrides.d and the loader file. Re-applying gid=1000 +
    # 0770/0660 must happen AFTER the chown -R, otherwise kbagent
    # (gid 1000) cannot write override files at runtime.

    main_container_bash_script() {
      # Extract the main container bash -c body (between line marker
      # "chown -R mysql:mysql" and the "rm -f .replication-ready"
      # signal further down).
      awk '
        /chown -R mysql:mysql / { in_block = 1 }
        in_block { print }
        /^[[:space:]]*rm -f .* .replication-ready/ { in_block = 0 }
      ' "${CMPD_ENTRYPOINT}"
    }

    It "main container re-applies chgrp 1000 on runtime-overrides.d AFTER chown -R"
      When call main_container_bash_script
      The status should be success
      The output should include "chown -R mysql:mysql"
      The output should include 'chgrp 1000 ${DATA_DIR}/runtime-overrides.d'
    End

    It "main container re-applies chmod 0770 (g+rwx) on runtime-overrides.d AFTER chown -R"
      When call main_container_bash_script
      The status should be success
      The output should include 'chmod 0770 ${DATA_DIR}/runtime-overrides.d'
    End

    It "main container re-applies chgrp 1000 on runtime-overrides.cnf loader AFTER chown -R"
      When call main_container_bash_script
      The status should be success
      The output should include 'chgrp 1000 ${DATA_DIR}/runtime-overrides.cnf'
    End

    It "main container re-applies chmod 0660 on runtime-overrides.cnf loader AFTER chown -R"
      When call main_container_bash_script
      The status should be success
      The output should include 'chmod 0660 ${DATA_DIR}/runtime-overrides.cnf'
    End

    It "main container always overwrites loader to canonical content (recovers from corruption; Jack 07:03 B2 follow-up)"
      # Idempotent canonical write — not a `[ -f ] || write` guard.
      # If a previous generation left a corrupted loader file, the
      # main container rewrites it to the canonical content on every
      # startup.
      When call main_container_bash_script
      The status should be success
      The output should include "printf '!includedir %s/runtime-overrides.d/"
    End

    It "main container chown -R is followed (in source order) by a runtime-overrides chgrp re-fixup line"
      # Source-order assert: at least ONE `chgrp 1000 runtime-overrides.d`
      # line must appear AFTER the chown -R line. The init-syncer
      # already had a chgrp on that path BEFORE the main container's
      # chown -R (which would clobber it), so the existence of an
      # AFTER-chown-R chgrp is what protects the kbagent permission
      # contract.
      When run sh -c '
        chown_line=$(grep -n "chown -R mysql:mysql" "'${CMPD_ENTRYPOINT}'" | head -1 | cut -d: -f1)
        # Find all chgrp 1000 lines for the runtime-overrides dir and
        # take the LAST one (assumed to be the main container re-fixup).
        chgrp_line=$(grep -n "chgrp 1000 \${DATA_DIR}/runtime-overrides\.d" "'${CMPD_ENTRYPOINT}'" | tail -1 | cut -d: -f1)
        if [ -n "${chown_line}" ] && [ -n "${chgrp_line}" ] && [ "${chgrp_line}" -gt "${chown_line}" ]; then
          echo "OK"
        else
          echo "FAIL: chown -R at line ${chown_line:-none}, last runtime-overrides chgrp at line ${chgrp_line:-none}"
        fi
      '
      The status should be success
      The output should equal "OK"
    End
  End

  Describe "Guard 1: init-syncer creates persistence layer with correct group/mode"
    It "creates runtime-overrides.d directory"
      When call extract_init_syncer_command_body
      The status should be success
      The output should include "mkdir -p {{ .Values.dataMountPath }}/runtime-overrides.d"
    End

    It "chgrp the runtime-overrides.d directory to gid 1000 (kbagent group)"
      When call extract_init_syncer_command_body
      The status should be success
      The output should include "chgrp 1000 {{ .Values.dataMountPath }}/runtime-overrides.d"
    End

    It "chmod 0770 (g+rwx) on the runtime-overrides.d directory"
      # g+rwx is required because dir writes need traverse (execute) bit;
      # Jack 06:49 design follow-up.
      When call extract_init_syncer_command_body
      The status should be success
      The output should include "chmod 0770 {{ .Values.dataMountPath }}/runtime-overrides.d"
    End

    It "creates the loader file runtime-overrides.cnf with !includedir directive"
      When call extract_init_syncer_command_body
      The status should be success
      The output should include "!includedir"
      The output should include "runtime-overrides.cnf"
    End

    It "chgrp the loader file to gid 1000 (kbagent group)"
      When call extract_init_syncer_command_body
      The status should be success
      The output should include "chgrp 1000 {{ .Values.dataMountPath }}/runtime-overrides.cnf"
    End

    It "chmod 0660 on the loader file (mariadbd readable, kbagent writable, no execute needed)"
      When call extract_init_syncer_command_body
      The status should be success
      The output should include "chmod 0660 {{ .Values.dataMountPath }}/runtime-overrides.cnf"
    End
  End

  Describe "Guard 2: --defaults-extra-file is the FIRST mariadbd option"
    It "start_mariadbd_process function body includes the --defaults-extra-file flag"
      When call extract_start_mariadbd_function_body
      The status should be success
      The output should include '--defaults-extra-file=${DATA_DIR}/runtime-overrides.cnf'
    End

    It "the --defaults-extra-file flag appears immediately after the mariadbd command (positional first arg)"
      # MariaDB requires --defaults-* flags to be the first option.
      # We assert by source-order: the line containing
      # `docker-entrypoint.sh mariadbd \` must be IMMEDIATELY followed
      # by the `--defaults-extra-file=...` line (allowing only
      # whitespace and line-continuation markers).
      When run sh -c '
        awk "
          /docker-entrypoint\.sh mariadbd \\\\/ { found_mariadbd = NR; next }
          found_mariadbd && NR == found_mariadbd + 1 {
            if (\$0 ~ /--defaults-extra-file=/) {
              print \"OK\"
            } else {
              print \"FAIL: line after mariadbd is not --defaults-extra-file: \" \$0
            }
            exit
          }
        " "'${CMPD_ENTRYPOINT}'"
      '
      The status should be success
      The output should equal "OK"
    End

    It "the --defaults-extra-file flag precedes --server-id in source order"
      When run sh -c '
        defaults_line=$(grep -n "defaults-extra-file=" "'${CMPD_ENTRYPOINT}'" | head -1 | cut -d: -f1)
        server_id_line=$(grep -n -- "--server-id=" "'${CMPD_ENTRYPOINT}'" | head -1 | cut -d: -f1)
        if [ -n "${defaults_line}" ] && [ -n "${server_id_line}" ] && [ "${defaults_line}" -lt "${server_id_line}" ]; then
          echo "OK"
        else
          echo "FAIL: defaults-extra-file at line ${defaults_line:-none}, server-id at line ${server_id_line:-none}"
        fi
      '
      The status should be success
      The output should equal "OK"
    End
  End

  Describe "Guard 3: injection defense on param name and value"
    # Jack 07:03 peer review B1 lesson: grep-only tests miss shell
    # command-substitution semantics. These tests EXECUTE the actual
    # is_safe_param_name / is_safe_param_value function definitions
    # extracted from _helpers.tpl in a real /bin/sh subshell with the
    # same shell context the cmpd-semisync runtime uses. Behavioral
    # tests, not pattern grep.

    safety_function_definitions() {
      # Extract just the function defs from the persisted helper body.
      # Order matters: the setters must run before the print rule
      # otherwise the opening `func() {` line is missed when entering
      # a new function block.
      awk '
        /^[[:space:]]*is_safe_param_name\(\)/  { in_fn = 1; print; next }
        /^[[:space:]]*is_safe_param_value\(\)/ { in_fn = 1; print; next }
        in_fn { print }
        in_fn && /^[[:space:]]*\}[[:space:]]*$/ { in_fn = 0 }
      ' "${HELPERS_TPL}"
    }

    It "function defs source-extractable from _helpers.tpl"
      # Sanity check: both functions present in the helper body.
      When call safety_function_definitions
      The status should be success
      The output should include "is_safe_param_name()"
      The output should include "is_safe_param_value()"
    End

    It "is_safe_param_value accepts the T6 reconfigure target 'ON'"
      # B1 regression: the broken newline check rejected ALL values,
      # including the T6 target 'ON' for slow_query_log.
      When run sh -c "$(safety_function_definitions); is_safe_param_value 'ON'"
      The status should equal 0
    End

    It "is_safe_param_value accepts the T6 reconfigure target '3'"
      When run sh -c "$(safety_function_definitions); is_safe_param_value '3'"
      The status should equal 0
    End

    It "is_safe_param_value accepts a typical Valkey enum value 'volatile-lru'"
      When run sh -c "$(safety_function_definitions); is_safe_param_value 'volatile-lru'"
      The status should equal 0
    End

    It "is_safe_param_value accepts a quoted string with whitespace"
      When run sh -c "$(safety_function_definitions); is_safe_param_value 'a b c'"
      The status should equal 0
    End

    It "is_safe_param_value rejects a value containing a literal newline"
      When run sh -c "$(safety_function_definitions); is_safe_param_value \"$(printf 'ON\nINJECT')\""
      The status should equal 1
    End

    It "is_safe_param_value rejects a value containing a literal carriage return"
      When run sh -c "$(safety_function_definitions); is_safe_param_value \"$(printf 'ON\rINJECT')\""
      The status should equal 1
    End

    It "is_safe_param_value rejects a value containing a bracketed section header"
      When run sh -c "$(safety_function_definitions); is_safe_param_value '[mysqld]'"
      The status should equal 1
    End

    It "is_safe_param_value rejects a value containing an embedded bracketed section header"
      When run sh -c "$(safety_function_definitions); is_safe_param_value 'abc[evil_section]def'"
      The status should equal 1
    End

    It "is_safe_param_value rejects a tab character (\\x09 is in \\x00-\\x1f range)"
      When run sh -c "$(safety_function_definitions); is_safe_param_value \"$(printf 'AB\tCD')\""
      The status should equal 1
    End

    It "is_safe_param_name accepts the T6 reconfigure target 'slow_query_log'"
      When run sh -c "$(safety_function_definitions); is_safe_param_name 'slow_query_log'"
      The status should equal 0
    End

    It "is_safe_param_name accepts the T6 reconfigure target 'long_query_time'"
      When run sh -c "$(safety_function_definitions); is_safe_param_name 'long_query_time'"
      The status should equal 0
    End

    It "is_safe_param_name accepts a dotted name (mariadb allows .)"
      When run sh -c "$(safety_function_definitions); is_safe_param_name 'innodb.flush_method'"
      The status should equal 0
    End

    It "is_safe_param_name rejects an empty name"
      When run sh -c "$(safety_function_definitions); is_safe_param_name ''"
      The status should equal 1
    End

    It "is_safe_param_name rejects a name with whitespace"
      When run sh -c "$(safety_function_definitions); is_safe_param_name 'name with space'"
      The status should equal 1
    End

    It "is_safe_param_name rejects a name with shell metacharacters"
      When run sh -c "$(safety_function_definitions); is_safe_param_name 'evil; DROP TABLE'"
      The status should equal 1
    End

    It "is_safe_param_name rejects a name with newline injection attempt"
      When run sh -c "$(safety_function_definitions); is_safe_param_name \"$(printf 'name\nINJECT')\""
      The status should equal 1
    End

    It "persisted helper calls is_safe_param_name before applying any SQL (source-level guard, not just function existence)"
      When call extract_persisted_helper_body
      The status should be success
      The output should include "Refusing to apply parameter with unsafe name"
    End

    It "persisted helper calls is_safe_param_value before applying any SQL (source-level guard)"
      When call extract_persisted_helper_body
      The status should be success
      The output should include "Refusing to apply parameter"
      The output should include "unsafe value"
    End

    It "is_safe_param_value uses tr -d for control-char detection (no command-substitution case-pattern; B1 regression guard)"
      # The first draft tried to detect newline via
      #   case "${val}" in *"$(printf '\n')"*) ;; esac
      # POSIX command substitution strips trailing newlines, so the
      # pattern collapsed to `**` and rejected every value including
      # "ON" / "3". We assert the live is_safe_param_value uses
      # `tr -d` (the correct mechanism) and that the function body
      # does not have any *"$(...)"* style pattern that would suffer
      # from the same trailing-newline-stripping bug.
      When call safety_function_definitions
      The status should be success
      The output should include "tr -d "
      The output should not include "*\"\$(printf"
    End
  End

  Describe "Guard 4: fail-closed sentinels on persistence failure paths (parse-smoke removed in alpha.88)"
    It "mkdir of OVERRIDES_DIR exits 1 on failure"
      When call extract_persisted_helper_body
      The status should be success
      The output should include 'Failed to mkdir ${OVERRIDES_DIR}'
    End

    It "tmp file write failure exits 1"
      When call extract_persisted_helper_body
      The status should be success
      The output should include "Failed to write tmp override file"
    End

    It "rename (atomic mv) failure exits 1"
      When call extract_persisted_helper_body
      The status should be success
      The output should include "Failed to rename tmp override into place"
    End

    It "no WARN-only path remains for any persistence failure (regression guard)"
      When call extract_persisted_helper_body
      The status should be success
      The output should not include "WARN: failed to persist"
      The output should not include "runtime overrides will not persist"
    End
  End

  Describe "Guard 5 — REMOVED in alpha.88 (kbagent context bug per Jack msg e6afaa1a)"
    # Background (kept here for future archeology + regression guard):
    # alpha.86 + alpha.87 dry-runs by Jack showed the parse smoke
    # `smoke_out=$(mariadbd --print-defaults 2>&1)` line caused the
    # action to exit 127 with NO stderr output, because:
    #   1. kbagent action runtime PATH does NOT include `mariadbd`
    #      (it lives in /usr/sbin/ etc., not the kbagent /tools/
    #      synthesized PATH).
    #   2. `set -e` in combination with `var=$(failing_cmd)` causes
    #      the shell to exit immediately on the failed substitution,
    #      so the subsequent `smoke_rc=$?` check, stderr print, and
    #      bad-file cleanup never ran. Orphan `.cnf` files were left
    #      in /var/lib/mysql/runtime-overrides.d/ as evidence.
    # Remaining defenses (Guards 1-4) cover the threat model:
    # injection defense rejects unsafe names/values, and mariadbd's
    # own error log on next restart is the authoritative validation
    # surface for engine-side option-file parsing.

    It "init-syncer writes loader file with only the !includedir directive (no key=value)"
      # Loader file must NOT contain key=value pairs; mariadbd would
      # interpret them as global options. We assert via the printf
      # source: format string is '!includedir %s/runtime-overrides.d/\\n'
      # and only one argument is substituted.
      When call extract_init_syncer_command_body
      The status should be success
      The output should include "printf '!includedir %s/runtime-overrides.d/"
    End

    It "persisted helper does NOT call mariadbd for parse smoke (alpha.88 regression guard)"
      # Live helper must not contain the failed parse-smoke invocation
      # pattern that caused the alpha.86 + alpha.87 dry-run failures.
      When call extract_persisted_helper_body
      The status should be success
      The output should not include "mariadbd --defaults-extra-file="
      The output should not include "--print-defaults"
      The output should not include "smoke_out=\$("
      The output should not include "Parse smoke failed"
    End
  End

  Describe "Cross-topology scope: persisted variant presence"
    # After CMPD consolidation (PR #2933), cmpd-replication.yaml is the
    # single canonical CMPD. It includes the persisted variant (merged
    # from the former semisync CMPD). Other topologies still do not.
    It "cmpd-replication.yaml includes the persisted variant"
      When call grep -c 'mariadb.config.reconfigureAction.persisted' "${CMPD_SEMISYNC}"
      The status should be success
      The output should be present
    End

    It "cmpd.yaml (standalone) does NOT include the persisted variant"
      When call grep -c 'mariadb.config.reconfigureAction.persisted' "${CMPD_STANDALONE}"
      The status should be failure
      The output should equal "0"
    End

    It "cmpd-galera.yaml does NOT include the persisted variant"
      When call grep -c 'mariadb.config.reconfigureAction.persisted' "${CMPD_GALERA}"
      The status should be failure
      The output should equal "0"
    End

    It "shared base helper mariadb.config.reconfigureAction does NOT contain persistence shell code"
      When call extract_base_helper_body
      The status should be success
      The output should not include "OVERRIDES_DIR"
      The output should not include "override_file="
      The output should not include "override_tmp="
      The output should not include "LOADER_FILE"
    End
  End

  Describe "Reconfigure action execution surface"
    # `exec.container` shares the MariaDB container resources, but the
    # action process itself runs in the action runtime. The reconfigure
    # script calls the `mariadb` CLI, so pin the action image to the
    # MariaDB image while keeping `container: mariadb` for shared mounts.
    It "base reconfigureAction declares the MariaDB exec image"
      When call extract_base_helper_body
      The status should be success
      The output should include 'container: mariadb'
      The output should include 'image: {{ include "mariadb.image" . }}'
    End

    It "persisted reconfigureAction declares the MariaDB exec image"
      When call extract_persisted_helper_body
      The status should be success
      The output should include 'container: mariadb'
      The output should include 'image: {{ include "mariadb.image" . }}'
    End

    It "base reconfigureAction consumes KB runtime key/value arguments"
      When call extract_base_helper_body
      The status should be success
      The output should include 'emit_action_parameters "$@"'
      The output should include '- reconfigure'
      The output should include 'Reconfigure action expects key/value arguments'
    End

    It "base reconfigureAction falls back to mounted config when kbagent drops runtime arguments"
      When call extract_base_helper_body
      The status should be success
      The output should include 'fill_config_parameters_or_defer "${parameter_file}" || exit 1'
      The output should include '/etc/mysql/conf.d/my.cnf'
      The output should include 'config_value_is_current "${param_name}" "${param_value}"'
      The output should include 'SELECT IF(@@GLOBAL.\`${param_name}\` <=> ${sql_value}, 1, 0);'
      The output should include 'reconfigure_diagnose_not_ready'
      The output should include 'phase: ${phase}'
      The output should include 'next-retry-safe: ${retry_safe}'
      The output should include 'projected-config-not-ready'
      The output should not include 'sleep 2'
      The output should include '{{- range (get $pd "dynamicParameters") }}'
      The output should include 'printf "%s=%s\n" "${param_name}" "${param_value}"'
    End

    It "persisted reconfigureAction consumes KB runtime key/value arguments"
      When call extract_persisted_helper_body
      The status should be success
      The output should include 'emit_action_parameters "$@"'
      The output should include '- reconfigure'
      The output should include 'Reconfigure action expects key/value arguments'
    End

    It "persisted reconfigureAction falls back to mounted config when kbagent drops runtime arguments"
      When call extract_persisted_helper_body
      The status should be success
      The output should include 'fill_config_parameters_or_defer "${parameter_file}" || exit 1'
      The output should include '/etc/mysql/conf.d/my.cnf'
      The output should include 'config_value_is_current "${param_name}" "${param_value}"'
      The output should include 'SELECT IF(@@GLOBAL.\`${param_name}\` <=> ${sql_value}, 1, 0);'
      The output should include 'reconfigure_diagnose_not_ready'
      The output should include 'phase: ${phase}'
      The output should include 'next-retry-safe: ${retry_safe}'
      The output should include 'projected-config-not-ready'
      The output should not include 'sleep 2'
      The output should include '{{- range (get $pd "dynamicParameters") }}'
      The output should include 'printf "%s=%s\n" "${param_name}" "${param_value}"'
    End
  End

  Describe "Rejected user-input SQL errors do not keep reconfigure on the failing path"
    It "base reconfigureAction skips classified engine rejects without exiting 1"
      When call extract_base_helper_body
      The status should be success
      The output should include 'skipped_count=$((skipped_count + 1))'
      The output should include 'parameter(s) were rejected by engine and skipped'
      The output should include 'if [ "${applied_count}" -eq 0 ] && [ "${skipped_count}" -eq 0 ]; then'
      The output should not include 'failing reconfigure to avoid accepting invalid rendered config'
    End

    It "persisted reconfigureAction skips classified engine rejects without writing overrides or exiting 1"
      When call extract_persisted_helper_body
      The status should be success
      The output should include 'skipped_count=$((skipped_count + 1))'
      The output should include 'continue'
      The output should include 'parameter(s) were rejected by engine and skipped'
      The output should include 'if [ "${applied_count}" -eq 0 ] && [ "${skipped_count}" -eq 0 ]; then'
      The output should not include 'failing reconfigure to avoid accepting invalid rendered config'
    End
  End

  Describe "Regression: KB-managed config has NO !includedir (alpha.84 v1 parser FAIL)"
    It "config/mariadb-semisync.tpl does NOT contain !includedir (mariadbd loads via --defaults-extra-file instead)"
      # alpha.84 v1 put !includedir into KB-managed my.cnf, which KB
      # ParametersDefinition's strict INI parser rejected. alpha.86
      # keeps !includedir OUT of this file (only in the PVC loader).
      When call grep -c '!includedir' "${SEMISYNC_CFG}"
      The status should be failure
      The output should equal "0"
    End

    It "config/mariadb-semisync.tpl content remains pure INI (no bang directives)"
      When call grep -c '^!' "${SEMISYNC_CFG}"
      The status should be failure
      The output should equal "0"
    End
  End

  Describe "Parameter effect-scope source still includes T6 target params"
    # Ensures the dynamic params list still includes the targets the
    # MariaDB T6 lane reconfigures; if these drop out, the persisted
    # helper's emit_action_parameters case statement would silently
    # skip them.
    It "slow_query_log is in dynamicParameters in the effect-scope file"
      When call grep -c '^[[:space:]]*-[[:space:]]*slow_query_log[[:space:]]*$' "${EFFECT_SCOPE}"
      The status should be success
      The output should equal "1"
    End

    It "long_query_time is in dynamicParameters in the effect-scope file"
      When call grep -c '^[[:space:]]*-[[:space:]]*long_query_time[[:space:]]*$' "${EFFECT_SCOPE}"
      The status should be success
      The output should equal "1"
    End
  End
End
