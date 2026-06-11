{{/*
Chart name.
*/}}
{{- define "valkey.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "valkey.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "valkey.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common annotations for all KubeBlocks resources.
  - helm.sh/resource-policy: keep  →  prevents CRDs from being deleted on `helm uninstall`
  - apps.kubeblocks.io/skip-immutable-check  →  allows re-installing without version conflict
  - kubeblocks.io/crd-api-version  →  declares which KubeBlocks API version this addon targets
*/}}
{{- define "valkey.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
apps.kubeblocks.io/skip-immutable-check: "true"
{{- end }}

{{/*
Regexp pattern used in ClusterDefinition.topologies[].components[].compDef.
ComponentDefinition names are major-scoped and intentionally do not include
Chart.Version; selection order must not depend on SemVer lexicographic sorting.
*/}}
{{- define "valkey.cmpdRegexpPattern" -}}
^valkey-[0-9]+$
{{- end -}}

{{/*
Scripts ConfigMap name — versioned so upgrades create a new ConfigMap
and old clusters keep using the one they were provisioned with.
*/}}
{{- define "valkey.scriptsTemplate" -}}
valkey-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Config ConfigMap name. The template is shared across supported Valkey majors
until an actual major-specific config delta appears.
*/}}
{{- define "valkey.configTemplate" -}}
valkey-config-template
{{- end -}}

{{/*
Inline helper to build the valkey-cli base command with optional TLS flags.
Produces a variable assignment: VALKEY_CLI_TLS_ARGS="--tls --insecure"
This is used inside shell scripts rather than as a Helm template.
*/}}

{{/*
Scripts data: bundle every file under scripts/ into a single ConfigMap.
*/}}
{{- define "valkey.extendScripts" -}}
{{- range $path, $_ := $.Files.Glob "scripts/**" }}
{{ $path | base }}: |-
{{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Default Valkey image (first version in the list).
Used as a fallback in ActionSet; BackupPolicyTemplate overrides per serviceVersion.
*/}}
{{- define "valkey.defaultImage" -}}
{{- $v := index .Values.valkeyVersions 0 -}}
{{ .Values.image.registry | default "docker.io" }}/{{ .Values.image.repository }}:{{ $v.defaultImageTag }}
{{- end }}

{{/*
Reconfigure action — called by KubeBlocks when config parameters change.
Reads the mounted ConfigMap config file and applies each parameter via
CONFIG SET through reload-parameter.sh.  Includes a freshness gate to
handle the Kubernetes ConfigMap projection race condition.
*/}}
{{- define "valkey.reconfigureAction" -}}
reconfigure:
  exec:
    container: valkey
    targetPodSelector: All
    command:
      - /scripts/reload-config.sh
{{- end -}}
