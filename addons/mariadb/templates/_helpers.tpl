{{/*
Expand the name of the chart.
*/}}
{{- define "mariadb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
alpha.89 v1 commit 13 v2 (Helen 2026-05-20, Jack B2 fix msg
`f9433634`) — Helm template-time fail-closed validation of
`.Values.replication.mode`. If the chart user sets the value to
anything other than the accepted set ("" / "async" / "semisync"),
`helm template` / `helm install` / `helm upgrade` aborts with a
clear error BEFORE the manifest is rendered. Without this gate, an
invalid value like `bogus` would render successfully and only fail
at container startup when the seeder runs (correctly fail-closed,
but the diagnosis loop is longer and the bad value is already
written into the rendered CmpD env).

Accepted values:
  ""        — default; mapper / seeder no-op; existing behavior.
  "async"   — install-time mode = async.
  "semisync" — install-time mode = semisync.

Called from `cmpd-replication.yaml` (the only place the value
is consumed). Other CmpDs do not declare the env entry and are not
affected.
*/}}
{{- define "mariadb.replication.mode.validate" -}}
{{- $mode := .Values.replication.mode | default "" -}}
{{- if and $mode (not (has $mode (list "async" "semisync"))) -}}
{{- fail (printf "invalid replication.mode=%q; expected one of \"\", \"async\", \"semisync\" (commit 13 v2 / Jack B2 install-time fail-closed)" $mode) -}}
{{- end -}}
{{- $mode -}}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "mariadb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mariadb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mariadb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mariadb.labels" -}}
helm.sh/chart: {{ include "mariadb.chart" . }}
{{ include "mariadb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Define image
*/}}
{{- define "mariadb.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}
{{- end }}

{{- define "mariadb.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}

{{- define "exporter.repository" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.prom.exporter.repository}}
{{- end }}

{{- define "exporter.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.prom.exporter.repository}}:{{.Values.image.prom.exporter.tag}}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "mariadb.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
{{ include "mariadb.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "mariadb.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Define mariadb component definition name
*/}}
{{- define "mariadb.cmpdName" -}}
mariadb-{{ .Chart.Version }}
{{- end -}}

{{/*
Define mariadb-replication component definition name
*/}}
{{- define "mariadb.replication.cmpdName" -}}
mariadb-replication-merged-{{ .Chart.Version }}
{{- end -}}

{{/*
Define mariadb-galera component definition name
*/}}
{{- define "mariadb.galera.cmpdName" -}}
mariadb-galera-{{ .Chart.Version }}
{{- end -}}

{{/*
Define mariadb component definition regular expression name prefix
*/}}
{{- define "mariadb.cmpdRegexpPattern" -}}
^mariadb-
{{- end -}}

{{/*
Define mariadb standalone component definition regular expression name prefix
(matches only standalone cmpd, not replication or galera)
*/}}
{{- define "mariadb.standalone.cmpdRegexpPattern" -}}
^mariadb-[0-9]
{{- end -}}

{{/*
Define mariadb-replication component definition regular expression name prefix
*/}}
{{- define "mariadb.replication.cmpdRegexpPattern" -}}
^mariadb-replication-merged-
{{- end -}}

{{/*
Define mariadb-galera component definition regular expression name prefix
*/}}
{{- define "mariadb.galera.cmpdRegexpPattern" -}}
^mariadb-galera-
{{- end -}}

{{/*
Define reloader script configmap name
*/}}
{{- define "mariadb.reloader.scriptConfigMapName" -}}
mariadb-reload-script
{{- end -}}

{{/*
Define versioned replication script configmap name.
*/}}
{{- define "mariadb.replication.scriptConfigMapName" -}}
{{- $version := .Chart.Version | replace "+" "-" | replace "." "-" | replace "_" "-" -}}
{{- printf "mariadb-replication-scripts-%s" $version | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Define galera script configmap name. Single source for the galera scripts CM
referenced from configmap-scripts-galera.yaml and cmpd-galera.yaml. Per
docs/addon-api/01-define-scope.md the resource name must come from one helper
so that multiple template files do not each stitch the same literal.
*/}}
{{- define "mariadb.galera.scriptConfigMapName" -}}
mariadb-galera-scripts
{{- end -}}

{{/*
Generate reloader scripts configmap data
*/}}
{{- define "mariadb.extend.reload.scripts" -}}
{{- range $path, $_ := $.Files.Glob "reloader/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
ComponentDefinition reconfigure action for MariaDB
*/}}
{{- define "mariadb.config.reconfigureAction" -}}
{{- $pd := .Files.Get "config/mariadb-config-effect-scope.yaml" | fromYaml }}
reconfigure:
  exec:
    container: mariadb
    image: {{ include "mariadb.image" . }}
    command:
      - /bin/sh
      - -c
      - |
        set -eu

        resolve_mariadb_cli() {
          if command -v mariadb >/dev/null 2>&1; then
            command -v mariadb
            return 0
          fi
          if [ -x /tools/mysql-client/bin/mariadb ]; then
            echo /tools/mysql-client/bin/mariadb
            return 0
          fi
          return 1
        }

        MARIADB_CLI="$(resolve_mariadb_cli || true)"
        if [ -z "${MARIADB_CLI}" ]; then
          echo "MariaDB client is unavailable in current reconfigure runtime" >&2
          exit 1
        fi

        # alpha.83 v1 (Helen): reconfigure action must use internal admin
        # account to call `SET GLOBAL`. User-facing root has SUPER stripped by
        # chart security hardening (alpha.64 "drop SUPER (admin bypass)"); the
        # internal admin account `kb_internal_root` carries ALL PRIVILEGES.
        # Without this, `SET GLOBAL slow_query_log=ON` and similar dynamic
        # variable writes fail with `ERROR 1227 (42000) ... SUPER privilege(s)`.
        # The MARIADB_ROOT_PASSWORD env shared with the internal admin (chart
        # provisions identical passwords); we keep the same env to avoid a new
        # secret indirection. Default fallback to kb_internal_root mirrors the
        # preStop hook convention in cmpd-replication.yaml.
        mariadb_exec() {
          query="$1"
          INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"
          "${MARIADB_CLI}" --user="${INTERNAL_ROOT_USER}" --password="${MARIADB_ROOT_PASSWORD}" --host=127.0.0.1 -P 3306 -NBe "${query}"
        }

        to_numeric_value() {
          value="$1"
          case "${value}" in
            ''|*[!0-9KkMmGgBb.]*|*.*.*)
              return 1
              ;;
            *[Kk][Bb])
              base="${value%[Kk][Bb]}"
              multiplier=1024
              ;;
            *[Kk])
              base="${value%[Kk]}"
              multiplier=1024
              ;;
            *[Mm][Bb])
              base="${value%[Mm][Bb]}"
              multiplier=1048576
              ;;
            *[Mm])
              base="${value%[Mm]}"
              multiplier=1048576
              ;;
            *[Gg][Bb])
              base="${value%[Gg][Bb]}"
              multiplier=1073741824
              ;;
            *[Gg])
              base="${value%[Gg]}"
              multiplier=1073741824
              ;;
            *)
              base="${value}"
              multiplier=1
              ;;
          esac

          case "${base}" in
            ''|*[!0-9.]*|*.*.*)
              return 1
              ;;
          esac

          if [ "${multiplier}" = "1" ]; then
            printf "%s\n" "${base}"
            return 0
          fi

          case "${base}" in
            *.*)
              return 1
              ;;
          esac

          expr "${base}" \* "${multiplier}"
        }

        emit_action_parameters() {
          if [ "$#" -gt 0 ]; then
            if [ "$#" -ne 2 ]; then
              echo "Reconfigure action expects key/value arguments, got $#: $*" >&2
              exit 1
            fi
            param_name="$1"
            param_value="$2"
            case "${param_name}" in
{{- range (get $pd "dynamicParameters") }}
            {{ . }})
              printf "%s=%s\n" "${param_name}" "${param_value}"
              ;;
{{- end }}
            *)
              echo "Ignoring non-dynamic reconfigure parameter ${param_name}" >&2
              ;;
            esac
            return 0
          fi

          env | while IFS='=' read -r param_name param_value; do
            case "${param_name}" in
{{- range (get $pd "dynamicParameters") }}
            {{ . }})
              printf "%s=%s\n" "${param_name}" "${param_value}"
              ;;
{{- end }}
            esac
          done | sort -u
        }

        emit_config_parameters() {
          for config_file in /etc/mysql/conf.d/my.cnf /etc/mysql/my.cnf /etc/mysql/mariadb.cnf; do
            [ -r "${config_file}" ] || continue
            while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
              case "${raw_line}" in
              ''|'#'*|';'*|'['*)
                continue
                ;;
              *=*)
                ;;
              *)
                continue
                ;;
              esac

              param_name="${raw_line%%=*}"
              param_value="${raw_line#*=}"
              param_name="$(printf "%s" "${param_name}" | tr '-' '_' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
              param_value="$(printf "%s" "${param_value}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
              case "${param_value}" in
              \"*\")
                param_value="${param_value#\"}"
                param_value="${param_value%\"}"
                ;;
              \'*\')
                param_value="${param_value#\'}"
                param_value="${param_value%\'}"
                ;;
              esac

              case "${param_name}" in
{{- range (get $pd "dynamicParameters") }}
              {{ . }})
                if ! config_value_is_current "${param_name}" "${param_value}"; then
                  printf "%s=%s\n" "${param_name}" "${param_value}"
                fi
                ;;
{{- end }}
              esac
            done < "${config_file}"
          done | sort -u
        }

        sql_value_literal() {
          value="$1"
          upper_value="$(printf "%s" "${value}" | tr '[:lower:]' '[:upper:]')"
          case "${upper_value}" in
          ON|TRUE)
            printf "1\n"
            return 0
            ;;
          OFF|FALSE)
            printf "0\n"
            return 0
            ;;
          esac

          if numeric_value="$(to_numeric_value "${value}" 2>/dev/null)"; then
            printf "%s\n" "${numeric_value}"
          else
            escaped_value="$(printf "%s" "${value}" | sed "s/'/''/g")"
            printf "'%s'\n" "${escaped_value}"
          fi
        }

        config_value_is_current() {
          param_name="$1"
          param_value="$2"
          sql_value="$(sql_value_literal "${param_value}")"
          result="$(mariadb_exec "SELECT IF(@@GLOBAL.\`${param_name}\` <=> ${sql_value}, 1, 0);" 2>/dev/null || true)"
          [ "${result}" = "1" ]
        }

        reconfigure_diagnose_not_ready() {
          phase="$1"
          ctx="$2"
          retry_safe="$3"
          {
            echo "reconfigure diagnosis:"
            echo "  action: reconfigure"
            echo "  phase: ${phase}"
            echo "${ctx}"
            echo "  next-retry-safe: ${retry_safe}"
          } >&2
        }

        fill_config_parameters_or_defer() {
          target_file="$1"
          emit_config_parameters > "${target_file}"
          if [ -s "${target_file}" ]; then
            return 0
          fi
          ctx="$(printf '  config-files: /etc/mysql/conf.d/my.cnf /etc/mysql/my.cnf /etc/mysql/mariadb.cnf\n  observed: no dynamic config delta between mounted config and current MariaDB runtime')"
          reconfigure_diagnose_not_ready \
            "projected-config-not-ready" \
            "${ctx}" \
            "yes"
          return 1
        }

        parameter_file="$(mktemp)"
        trap 'rm -f "${parameter_file}"' EXIT
        emit_action_parameters "$@" > "${parameter_file}"
        if [ ! -s "${parameter_file}" ]; then
          fill_config_parameters_or_defer "${parameter_file}" || exit 1
        fi
        if [ ! -s "${parameter_file}" ]; then
          exit 0
        fi

        applied_count=0
        skipped_count=0
        while IFS= read -r assignment; do
          [ -n "${assignment}" ] || continue
          case "${assignment}" in
          *=*)
            ;;
          *)
            continue
            ;;
          esac

          param_name="${assignment%%=*}"
          param_value="${assignment#*=}"
          param_name="$(printf "%s" "${param_name}" | tr '-' '_')"

          if numeric_value="$(to_numeric_value "${param_value}" 2>/dev/null)"; then
            query="SET GLOBAL \`${param_name}\` = ${numeric_value};"
          else
            escaped_value="$(printf "%s" "${param_value}" | sed "s/'/''/g")"
            query="SET GLOBAL \`${param_name}\` = '${escaped_value}';"
          fi

          if output="$(mariadb_exec "${query}" 2>&1)"; then
            echo "Set parameter ${param_name} to value ${param_value}"
            applied_count=$((applied_count + 1))
          else
            # Classify MariaDB SQL errors that are caused by bad user input.
            # These should not be retried indefinitely by the controller.
            error_code=$(printf '%s' "${output}" | grep -oE 'ERROR [0-9]+' | head -1 | awk '{print $2}')
            case "${error_code}" in
              1231|1232|1193|1064)
                echo "[REJECT] parameter ${param_name}=${param_value} rejected by engine (error ${error_code}): ${output}"
                echo "[REJECT] parameter ${param_name}=${param_value} rejected by engine (error ${error_code}): ${output}" >&2
                skipped_count=$((skipped_count + 1))
                ;;
              *)
                echo "Failed to set parameter ${param_name}=${param_value}: ${output}" >&2
                exit 1
                ;;
            esac
          fi
        done < "${parameter_file}"

        if [ "${skipped_count}" -gt 0 ]; then
          echo "${skipped_count} parameter(s) were rejected by engine and skipped"
          echo "${skipped_count} parameter(s) were rejected by engine and skipped" >&2
        fi
        if [ "${applied_count}" -eq 0 ] && [ "${skipped_count}" -eq 0 ]; then
          echo "No parameters were applied during reconfigure action" >&2
          exit 1
        fi
      - reconfigure
{{- end -}}

{{/*
ComponentDefinition reconfigure action for MariaDB — SEMISYNC variant with
persistent runtime-override files.

alpha.86 v1 (Helen 2026-05-19) — semisync topology adds a defense-in-depth
persistence layer on top of the base reconfigureAction body. The base helper
runs `SET GLOBAL` against the running mysqld; the assignment is runtime-only
and ANY mariadbd restart erases it. This variant additionally writes one
`/var/lib/mysql/runtime-overrides.d/<param_name>.cnf` file per parameter,
which mariadbd reads at startup via `--defaults-extra-file=
/var/lib/mysql/runtime-overrides.cnf` (the loader file is created by
init-syncer with the single line `!includedir /var/lib/mysql/
runtime-overrides.d/`).

Why a separate variant and not a flag in the base helper: standalone /
replication / galera cmpds neither have init-syncer create the loader
file nor pass `--defaults-extra-file` to mariadbd; adding persistence
writes there would produce dead files mariadbd never loads (the
non-empty-unenforced class). cmpd-replication.yaml is the single caller of
the persisted variant.

Jack 5-guard enforcement (peer review msg `a13b8850`); Guard 5
parse smoke REMOVED in alpha.88 after dry-run blocker (Jack msg
`e6afaa1a`):
  1. kbagent write permission to runtime-overrides.d: enforced by
     init-syncer chgrp 1000 + chmod 0770 on the dir (g+rwx) and
     chmod 0660 on loader file.
  2. --defaults-extra-file must be first mariadbd option: enforced in
     start_mariadbd_process function (position-checked by ShellSpec).
  3. param name/value injection defense: this helper rejects param
     names not matching `^[A-Za-z0-9_.-]+$` (mariadb option name spec)
     and rejects values containing newline / NUL / control chars or
     section header markers like `[mysqld]`.
  4. fail-closed on persistence failure: mkdir / write / mv any
     failure exits 1 after cleaning up the partial tmp file. Edge:
     when persist fails after SET GLOBAL succeeded, runtime is mutated
     but the action exits 1 (KB marks Ops Failed). Operator retries;
     retry is idempotent (SET GLOBAL is a no-op if value equal,
     persist overwrites). This is safer than false-success.
  5. ~~mariadbd parse smoke after each persist~~ REMOVED in alpha.88.
     The kbagent action runtime context does NOT include `mariadbd`
     on PATH (rc=127); combined with `set -e` + `var=$(...)` shell
     trap, the smoke command-substitution caused the action to exit
     immediately, bypassing both stderr-print and bad-file cleanup
     (alpha.86 + alpha.87 dry-runs left orphan `.cnf` files). Guards
     1-4 remain sufficient: injection defense covers the only inputs
     that could produce malformed `.cnf` content, and mariadbd's own
     error log on next restart is the authoritative validation
     surface for engine-side option-file parsing.
*/}}
{{- define "mariadb.config.reconfigureAction.persisted" -}}
{{- $pd := .Files.Get "config/mariadb-config-effect-scope.yaml" | fromYaml }}
reconfigure:
  exec:
    container: mariadb
    image: {{ include "mariadb.image" . }}
    command:
      - /bin/sh
      - -c
      - |
        set -eu

        resolve_mariadb_cli() {
          if command -v mariadb >/dev/null 2>&1; then
            command -v mariadb
            return 0
          fi
          if [ -x /tools/mysql-client/bin/mariadb ]; then
            echo /tools/mysql-client/bin/mariadb
            return 0
          fi
          return 1
        }

        MARIADB_CLI="$(resolve_mariadb_cli || true)"
        if [ -z "${MARIADB_CLI}" ]; then
          echo "MariaDB client is unavailable in current reconfigure runtime" >&2
          exit 1
        fi

        # alpha.83 v1: reconfigure action must use internal admin
        # account to call `SET GLOBAL`. User-facing root has SUPER
        # stripped by chart security hardening (alpha.64 "drop SUPER
        # admin bypass"); the internal admin account kb_internal_root
        # carries ALL PRIVILEGES.
        mariadb_exec() {
          query="$1"
          INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"
          "${MARIADB_CLI}" --user="${INTERNAL_ROOT_USER}" --password="${MARIADB_ROOT_PASSWORD}" --host=127.0.0.1 -P 3306 -NBe "${query}"
        }

        to_numeric_value() {
          value="$1"
          case "${value}" in
            ''|*[!0-9KkMmGgBb.]*|*.*.*)
              return 1
              ;;
            *[Kk][Bb])
              base="${value%[Kk][Bb]}"
              multiplier=1024
              ;;
            *[Kk])
              base="${value%[Kk]}"
              multiplier=1024
              ;;
            *[Mm][Bb])
              base="${value%[Mm][Bb]}"
              multiplier=1048576
              ;;
            *[Mm])
              base="${value%[Mm]}"
              multiplier=1048576
              ;;
            *[Gg][Bb])
              base="${value%[Gg][Bb]}"
              multiplier=1073741824
              ;;
            *[Gg])
              base="${value%[Gg]}"
              multiplier=1073741824
              ;;
            *)
              base="${value}"
              multiplier=1
              ;;
          esac

          case "${base}" in
            ''|*[!0-9.]*|*.*.*)
              return 1
              ;;
          esac

          if [ "${multiplier}" = "1" ]; then
            printf "%s\n" "${base}"
            return 0
          fi

          case "${base}" in
            *.*)
              return 1
              ;;
          esac

          expr "${base}" \* "${multiplier}"
        }

        emit_action_parameters() {
          if [ "$#" -gt 0 ]; then
            if [ "$#" -ne 2 ]; then
              echo "Reconfigure action expects key/value arguments, got $#: $*" >&2
              exit 1
            fi
            param_name="$1"
            param_value="$2"
            case "${param_name}" in
{{- range (get $pd "dynamicParameters") }}
            {{ . }})
              printf "%s=%s\n" "${param_name}" "${param_value}"
              ;;
{{- end }}
            *)
              echo "Ignoring non-dynamic reconfigure parameter ${param_name}" >&2
              ;;
            esac
            return 0
          fi

          env | while IFS='=' read -r param_name param_value; do
            case "${param_name}" in
{{- range (get $pd "dynamicParameters") }}
            {{ . }})
              printf "%s=%s\n" "${param_name}" "${param_value}"
              ;;
{{- end }}
            esac
          done | sort -u
        }

        emit_config_parameters() {
          for config_file in /etc/mysql/conf.d/my.cnf /etc/mysql/my.cnf /etc/mysql/mariadb.cnf; do
            [ -r "${config_file}" ] || continue
            while IFS= read -r raw_line || [ -n "${raw_line}" ]; do
              case "${raw_line}" in
              ''|'#'*|';'*|'['*)
                continue
                ;;
              *=*)
                ;;
              *)
                continue
                ;;
              esac

              param_name="${raw_line%%=*}"
              param_value="${raw_line#*=}"
              param_name="$(printf "%s" "${param_name}" | tr '-' '_' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
              param_value="$(printf "%s" "${param_value}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
              case "${param_value}" in
              \"*\")
                param_value="${param_value#\"}"
                param_value="${param_value%\"}"
                ;;
              \'*\')
                param_value="${param_value#\'}"
                param_value="${param_value%\'}"
                ;;
              esac

              case "${param_name}" in
{{- range (get $pd "dynamicParameters") }}
              {{ . }})
                if ! config_value_is_current "${param_name}" "${param_value}"; then
                  printf "%s=%s\n" "${param_name}" "${param_value}"
                fi
                ;;
{{- end }}
              esac
            done < "${config_file}"
          done | sort -u
        }

        sql_value_literal() {
          value="$1"
          upper_value="$(printf "%s" "${value}" | tr '[:lower:]' '[:upper:]')"
          case "${upper_value}" in
          ON|TRUE)
            printf "1\n"
            return 0
            ;;
          OFF|FALSE)
            printf "0\n"
            return 0
            ;;
          esac

          if numeric_value="$(to_numeric_value "${value}" 2>/dev/null)"; then
            printf "%s\n" "${numeric_value}"
          else
            escaped_value="$(printf "%s" "${value}" | sed "s/'/''/g")"
            printf "'%s'\n" "${escaped_value}"
          fi
        }

        config_value_is_current() {
          param_name="$1"
          param_value="$2"
          sql_value="$(sql_value_literal "${param_value}")"
          result="$(mariadb_exec "SELECT IF(@@GLOBAL.\`${param_name}\` <=> ${sql_value}, 1, 0);" 2>/dev/null || true)"
          [ "${result}" = "1" ]
        }

        reconfigure_diagnose_not_ready() {
          phase="$1"
          ctx="$2"
          retry_safe="$3"
          {
            echo "reconfigure diagnosis:"
            echo "  action: reconfigure"
            echo "  phase: ${phase}"
            echo "${ctx}"
            echo "  next-retry-safe: ${retry_safe}"
          } >&2
        }

        fill_config_parameters_or_defer() {
          target_file="$1"
          emit_config_parameters > "${target_file}"
          if [ -s "${target_file}" ]; then
            return 0
          fi
          ctx="$(printf '  config-files: /etc/mysql/conf.d/my.cnf /etc/mysql/my.cnf /etc/mysql/mariadb.cnf\n  observed: no dynamic config delta between mounted config and current MariaDB runtime')"
          reconfigure_diagnose_not_ready \
            "projected-config-not-ready" \
            "${ctx}" \
            "yes"
          return 1
        }

        # alpha.86 v1 — persistence paths and loader. init-syncer
        # creates the dir + loader file with correct group/mode; we
        # idempotently re-check existence in case the volume was
        # mounted after init-syncer (defense-in-depth).
        OVERRIDES_DIR="/var/lib/mysql/runtime-overrides.d"
        LOADER_FILE="/var/lib/mysql/runtime-overrides.cnf"
        if ! mkdir -p "${OVERRIDES_DIR}"; then
          echo "Failed to mkdir ${OVERRIDES_DIR}; reconfigure cannot persist runtime overrides" >&2
          exit 1
        fi
        if [ ! -f "${LOADER_FILE}" ]; then
          # init-syncer should have created this; recover idempotently.
          printf '!includedir %s/\n' "${OVERRIDES_DIR}" > "${LOADER_FILE}" 2>/dev/null || true
        fi

        parameter_file="$(mktemp)"
        trap 'rm -f "${parameter_file}"' EXIT
        emit_action_parameters "$@" > "${parameter_file}"
        if [ ! -s "${parameter_file}" ]; then
          fill_config_parameters_or_defer "${parameter_file}" || exit 1
        fi

        # alpha.89 v1 commit 12 (Helen 2026-05-20, C3 design mapper) —
        # translate the synthetic `replicationMode` ComponentSpec
        # parameter into the four real engine variables BEFORE the
        # main loop sees the parameter list. The mapper is the unique
        # consumer / writer of `replicationMode`; it strips any
        # synthetic `replicationmode` / `replicationMode` line, fails
        # closed on invalid mode or conflict with user-supplied real
        # vars, and is idempotent on both-consistent input. Contract
        # is locked in `scripts/replication-mode-mapper.sh`.
        #
        # The mapper is sourced (not executed) so it runs in the same
        # shell, preserves `set -eu`, and shares the trap'd parameter
        # file. The /scripts mount comes from the replication scripts
        # ConfigMap (configmap-scripts-replication.yaml commit 12).
        if [ -r /scripts/replication-mode-mapper.sh ]; then
          # shellcheck disable=SC1091
          __SOURCED__=1 . /scripts/replication-mode-mapper.sh
          # alpha.89 v1 commit 12 v2 (Helen 2026-05-20, Jack B1 fix
          # msg `008885e2`) — capture the mapper's original rc. The
          # earlier `if ! apply_replication_mode_mapping ...; then
          # mapper_rc=$?` form lost the rc because `!` inverts the
          # exit code, so `$?` inside the then-block was always 0.
          # The `|| mapper_rc=$?` form preserves the mapper's actual
          # return code (2/3/4/5) into the diagnostic sentinel, which
          # downstream first-blocker classification reads to decide
          # which contract layer (invalid mode vs conflict vs IO vs
          # bad arg) the failure came from.
          #
          # The `|| <cmd>` chain disables `set -e` for the mapper
          # invocation, so the action stays alive long enough to
          # print the rc-aware sentinel before exiting 1.
          mapper_rc=0
          apply_replication_mode_mapping "${parameter_file}" || mapper_rc=$?
          if [ "${mapper_rc}" -ne 0 ]; then
            echo "replicationMode mapper failed (rc=${mapper_rc}); reconfigure aborts before any SET GLOBAL or runtime-overrides.d write" >&2
            exit 1
          fi
        fi

        if [ ! -s "${parameter_file}" ]; then
          exit 0
        fi

        # alpha.86 v1 — injection defense per Jack guard 3.
        # Param name must match `^[A-Za-z0-9_.-]+$` (mariadb option
        # name spec). Param value rejects newline (\n, \r), NUL, and
        # other control chars (\x00-\x1f and \x7f); also rejects
        # bracketed strings like `[mysqld]` that would inject a new
        # section header into the option file.
        is_safe_param_name() {
          name="$1"
          case "${name}" in
            ''|*[!A-Za-z0-9_.-]*)
              return 1
              ;;
          esac
          return 0
        }
        is_safe_param_value() {
          val="$1"
          # Reject bracketed section headers anywhere in the value
          # (would inject a new section into the option file).
          case "${val}" in
            *'['*']'*)
              return 1
              ;;
          esac
          # Reject any control char (\x00-\x1f or \x7f) via tr -d.
          # \x0a (\n) / \x0d (\r) / \x00 (NUL) are all in this range,
          # so this single check covers newline / CR / NUL injection
          # as well as any other control byte. Earlier draft used a
          # case-pattern with `$(printf '\n')` for newline detection
          # but command substitution strips trailing newlines per POSIX,
          # so that pattern collapsed to `**` and rejected every value
          # including "ON" / "3" (Jack 07:02 peer review blocker B1).
          stripped=$(printf '%s' "${val}" | tr -d '\000-\037\177')
          [ "${stripped}" = "${val}" ]
        }

        applied_count=0
        skipped_count=0
        while IFS= read -r assignment; do
          [ -n "${assignment}" ] || continue
          case "${assignment}" in
          *=*)
            ;;
          *)
            continue
            ;;
          esac

          param_name="${assignment%%=*}"
          param_value="${assignment#*=}"
          param_name="$(printf "%s" "${param_name}" | tr '-' '_')"

          if ! is_safe_param_name "${param_name}"; then
            echo "Refusing to apply parameter with unsafe name: ${param_name}" >&2
            exit 1
          fi
          if ! is_safe_param_value "${param_value}"; then
            echo "Refusing to apply parameter ${param_name} with unsafe value (control char / newline / section marker)" >&2
            exit 1
          fi

          if numeric_value="$(to_numeric_value "${param_value}" 2>/dev/null)"; then
            query="SET GLOBAL \`${param_name}\` = ${numeric_value};"
            persist_quoted="${numeric_value}"
          else
            escaped_value="$(printf "%s" "${param_value}" | sed "s/'/''/g")"
            query="SET GLOBAL \`${param_name}\` = '${escaped_value}';"
            # my.cnf quoting: quote when value contains whitespace or
            # ini metacharacters; otherwise leave bare.
            case "${param_value}" in
              *[[:space:]\#\;]*)
                persist_escaped="$(printf "%s" "${param_value}" | sed 's/\\/\\\\/g; s/\"/\\\"/g')"
                persist_quoted="\"${persist_escaped}\""
                ;;
              *)
                persist_quoted="${param_value}"
                ;;
            esac
          fi

          if output="$(mariadb_exec "${query}" 2>&1)"; then
            echo "Set parameter ${param_name} to value ${param_value}"
            applied_count=$((applied_count + 1))
          else
            # Classify MariaDB SQL errors that are caused by bad user input.
            error_code=$(printf '%s' "${output}" | grep -oE 'ERROR [0-9]+' | head -1 | awk '{print $2}')
            case "${error_code}" in
              1231|1232|1193|1064)
                echo "[REJECT] parameter ${param_name}=${param_value} rejected by engine (error ${error_code}): ${output}"
                echo "[REJECT] parameter ${param_name}=${param_value} rejected by engine (error ${error_code}): ${output}" >&2
                skipped_count=$((skipped_count + 1))
                continue
                ;;
              *)
                echo "Failed to set parameter ${param_name}=${param_value}: ${output}" >&2
                exit 1
                ;;
            esac
          fi

          # alpha.86 v1 — persist the override AFTER SET GLOBAL succeeds.
          # Atomic rename protects against interrupted writes; parse
          # smoke catches mariadb-syntax-invalid input that would
          # crash mariadbd on next restart.
          override_file="${OVERRIDES_DIR}/${param_name}.cnf"
          override_tmp="${override_file}.tmp.$$"
          if ! {
            echo "[mysqld]"
            echo "${param_name} = ${persist_quoted}"
          } > "${override_tmp}"; then
            rm -f "${override_tmp}" 2>/dev/null || true
            echo "Failed to write tmp override file ${override_tmp}; reconfigure cannot guarantee persistence" >&2
            exit 1
          fi
          # alpha.89 v1 commit 12 (Helen 2026-05-20, Jack contract msg
          # `2e93eb72`) — byte-equal short-circuit. If the existing
          # override file already has identical content to the new
          # tmp file, skip the atomic mv so the on-disk file's mtime
          # is preserved across no-op reconfigures (idempotency
          # guarantee for both-consistent and repeated mode-only
          # reconfigure cases). The skip branch runs strictly after
          # safety validation (is_safe_param_name + is_safe_param_value
          # gated above) and after the mapper-driven conflict check
          # (apply_replication_mode_mapping runs before any reach into
          # this loop). Conflict cases never get here — the mapper
          # exits the action non-zero before any tmp file is written.
          # The alpha.86 timestamp comment was removed (commit 12)
          # because it forced every write to differ even when the
          # parameter value was unchanged.
          if [ -f "${override_file}" ] && cmp -s "${override_tmp}" "${override_file}"; then
            rm -f "${override_tmp}" 2>/dev/null || true
            echo "Override for ${param_name} already at target value; skipping rewrite to preserve mtime"
          elif ! mv "${override_tmp}" "${override_file}"; then
            rm -f "${override_tmp}" 2>/dev/null || true
            echo "Failed to rename tmp override into place at ${override_file}; reconfigure cannot guarantee persistence" >&2
            exit 1
          fi
          # alpha.88 v1 — parse smoke (formerly Jack guard 5) REMOVED
          # after alpha.86 + alpha.87 dry-runs (Jack msg `e6afaa1a`).
          # Root cause: kbagent action runtime context does not include
          # `mariadbd` on PATH (returns 127), and `set -e` combined with
          # the `var=$(...)` assignment pattern caused the shell to exit
          # immediately on the failing command-substitution — bypassing
          # the stderr-print + bad-file cleanup logic that should have
          # surfaced the diagnosis. The remaining defense layers are
          # sufficient:
          #   - is_safe_param_name regex `^[A-Za-z0-9_.-]+$` rejects
          #     option names that mariadbd's option-file parser would
          #     refuse.
          #   - is_safe_param_value rejects control chars / NUL /
          #     bracketed section markers, the only inputs that could
          #     escape the rendered `[mysqld]\nname = value` shape.
          #   - atomic temp + mv guarantees no half-written file.
          #   - mariadb option names that pass the regex but are not
          #     recognized by the engine produce a WARN on next restart
          #     (not a fatal error); the engine's own error log is the
          #     authoritative validation surface, and is more relevant
          #     than catching the same issue at write time.
        done < "${parameter_file}"

        if [ "${skipped_count}" -gt 0 ]; then
          echo "${skipped_count} parameter(s) were rejected by engine and skipped"
          echo "${skipped_count} parameter(s) were rejected by engine and skipped" >&2
        fi
        if [ "${applied_count}" -eq 0 ] && [ "${skipped_count}" -eq 0 ]; then
          echo "No parameters were applied during reconfigure action" >&2
          exit 1
        fi
      - reconfigure
{{- end -}}

{{/*
Syncer image (alpha.91, Helen 2026-05-24): use image.syncer.registry
with docker.io default, INDEPENDENT of image.registry. The syncer
image (apecloud/syncer:mariadb-isspromoted-fix-*) lives on docker.io
under apecloud/, while the engine image (mariadb:11.4.10) lives at
docker.io/mariadb. When users override image.registry to a mirror
like apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com for engine
images, syncer must still resolve to the registry where the
mariadb-aware syncer tag actually exists. Falls back to
image.registry (then docker.io) when image.syncer.registry not set,
preserving alpha.90 behavior for installations that don't override
registries.
*/}}
{{- define "mariadb.syncer.image" -}}
{{ .Values.image.syncer.registry | default (.Values.image.registry | default "docker.io") }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
{{- end -}}

{{/*
System accounts for standalone
*/}}
{{- define "mariadb.spec.systemAccounts" -}}
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 10
      numDigits: 3
      numSymbols: 4
      letterCase: MixedCases
{{- end -}}

{{/*
System accounts for replication (root only; replication uses root credentials)
*/}}
{{- define "mariadb.replication.spec.systemAccounts" -}}
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 10
      numDigits: 3
      numSymbols: 4
      letterCase: MixedCases
{{- end -}}

{{/*
System accounts for galera (root only; numSymbols=0 to avoid comment-char bug in wsrep_sst_auth option file)
*/}}
{{- define "mariadb.galera.spec.systemAccounts" -}}
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 10
      numDigits: 3
      numSymbols: 0
      letterCase: MixedCases
{{- end -}}

{{/*
System accounts for replication topology (Phase A account-model RFC; design review issue 3 from 2026-05-31 audit).

Phase A scope is DECLARATIVE ONLY. kb_internal_root and kb_replicator are declared as KubeBlocks-managed systemAccounts with `initAccount: true` so KB controller materializes a placeholder Secret per account and tracks the lifecycle hook, but does NOT execute `accountProvision.statement.create` SQL against the engine. Per `transformer_component_account_provision.go:161-167`, `initAccount: true` short-circuits the provision exec path.

DB-side runtime behavior is still owned by chart scripts: chart's `ensure_internal_local_admin` (cmpd-replication.yaml) and initdb (cmpd.yaml) continue to inline-create + maintain kb_internal_root and kb_replicator using `${MARIADB_ROOT_PASSWORD}`. The `kb_internal_root` @'%' allowlist is intentionally narrow: backup-required RELOAD/PROCESS, replication monitor/admin grants needed by syncer and mariabackup, narrow kubeblocks table grants, and SELECT mysql.user. `kb_replicator` remains REPLICATION SLAVE only.

Phase A's only behavior delta is that KB controller now materializes a Secret per declared account and tracks `Component.status.conditions[SystemAccountProvision]`. The KB-managed Secret password is random (per passwordGenerationPolicy below) and INTENTIONALLY DIFFERENT from the DB-side password (= MARIADB_ROOT_PASSWORD). No external consumer reads these two Secrets in Phase A; alpha.110 also did not expose them.

Phase B (separate future PR) will switch the chart to source the kb_internal_root / kb_replicator password from these Secrets via `credentialVarRef`, define `statement.create` + `statement.update` for real KB-driven provision, and sweep all 16+ script call sites in `ensure_internal_local_admin`, `replication-roleprobe.sh`, and `replication-switchover.sh` to use `${KB_INTERNAL_ROOT_PASSWORD}` / `${KB_REPLICATOR_PASSWORD}` atomically. Phase B's full grant contract design is captured in the addon-side RFC catalog.
*/}}
{{- define "mariadb.semisync.spec.systemAccounts" -}}
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 10
      numDigits: 3
      numSymbols: 4
      letterCase: MixedCases
  - name: kb_internal_root
    initAccount: true
    passwordGenerationPolicy:
      length: 32
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
  - name: kb_replicator
    initAccount: true
    passwordGenerationPolicy:
      length: 32
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
{{- end -}}

{{/*
System accounts for standalone topology (Phase A account-model RFC). Same declarative-only scope as the semisync helper above. Standalone declares only kb_internal_root because there is no replication (single-node).
*/}}
{{- define "mariadb.standalone.spec.systemAccounts" -}}
systemAccounts:
  - name: root
    initAccount: true
    passwordGenerationPolicy:
      length: 10
      numDigits: 3
      numSymbols: 4
      letterCase: MixedCases
  - name: kb_internal_root
    initAccount: true
    passwordGenerationPolicy:
      length: 32
      numDigits: 8
      numSymbols: 0
      letterCase: MixedCases
{{- end -}}

{{/*
Common vars for replication and galera
*/}}
{{- define "mariadb.spec.vars" -}}
vars:
  - name: MARIADB_ROOT_USER
    valueFrom:
      credentialVarRef:
        name: root
        optional: false
        username: Required
  - name: MARIADB_ROOT_PASSWORD
    valueFrom:
      credentialVarRef:
        name: root
        optional: false
        password: Required
  - name: CLUSTER_NAME
    valueFrom:
      clusterVarRef:
        clusterName: Required
  - name: CLUSTER_NAMESPACE
    valueFrom:
      clusterVarRef:
        namespace: Required
  - name: CLUSTER_UID
    valueFrom:
      clusterVarRef:
        clusterUID: Required
  - name: COMPONENT_NAME
    valueFrom:
      componentVarRef:
        optional: false
        shortName: Required
  - name: COMPONENT_POD_LIST
    valueFrom:
      componentVarRef:
        optional: false
        podNames: Required
  - name: COMPONENT_REPLICAS
    valueFrom:
      componentVarRef:
        optional: false
        replicas: Required
  - name: SERVICE_ETCD_ENDPOINT
    valueFrom:
      serviceRefVarRef:
        name: etcd
        endpoint: Required
        optional: true
  - name: LOCAL_ETCD_POD_FQDN
    valueFrom:
      componentVarRef:
        compDef: {{ .Values.etcd.etcdCmpdName }}
        optional: true
        podFQDNs: Required
  - name: LOCAL_ETCD_PORT
    valueFrom:
      serviceVarRef:
        compDef: {{ .Values.etcd.etcdCmpdName }}
        name: headless
        optional: true
        port:
          name: client
          option: Optional
  - name: SYNCER_HTTP_PORT
    value: "3601"
{{- end -}}

{{/*
Exporter container
*/}}
{{- define "mariadb.container.exporter" -}}
- name: exporter
  imagePullPolicy: {{ default "IfNotPresent" .Values.image.prom.pullPolicy }}
  ports:
    - name: metrics
      containerPort: 9104
      protocol: TCP
  env:
    - name: DATA_SOURCE_NAME
      value: "$(MARIADB_ROOT_USER):$(MARIADB_ROOT_PASSWORD)@(localhost:3306)/"
{{- end -}}
