{{/*
Expand the name of the chart.
*/}}
{{- define "mariadb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

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
mariadb-replication-{{ .Chart.Version }}
{{- end -}}

{{/*
Define mariadb-semisync component definition name
*/}}
{{- define "mariadb.semisync.cmpdName" -}}
mariadb-semisync-{{ .Chart.Version }}
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
^mariadb-replication-
{{- end -}}

{{/*
Define mariadb-semisync component definition regular expression name prefix
*/}}
{{- define "mariadb.semisync.cmpdRegexpPattern" -}}
^mariadb-semisync-
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

        mariadb_exec() {
          query="$1"
          "${MARIADB_CLI}" --user="${MARIADB_ROOT_USER}" --password="${MARIADB_ROOT_PASSWORD}" --host=127.0.0.1 -P 3306 -NBe "${query}"
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

        parameter_file="$(mktemp)"
        trap 'rm -f "${parameter_file}"' EXIT
        emit_action_parameters > "${parameter_file}"
        if [ ! -s "${parameter_file}" ]; then
          echo "No reconfigure parameters were injected into action environment" >&2
          exit 1
        fi

        applied_count=0
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
            echo "Failed to set parameter ${param_name}=${param_value}: ${output}" >&2
            exit 1
          fi
        done < "${parameter_file}"

        if [ "${applied_count}" -eq 0 ]; then
          echo "No parameters were applied during reconfigure action" >&2
          exit 1
        fi
{{- end -}}

{{/*
Syncer image
*/}}
{{- define "mariadb.syncer.image" -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.syncer.repository }}:{{ .Values.image.syncer.tag }}
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
