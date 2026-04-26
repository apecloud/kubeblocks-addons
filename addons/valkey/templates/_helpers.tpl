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
KubeBlocks matches ComponentDefinition names against this regex, so new Chart
versions (e.g. valkey-9-0.2.0) are automatically picked up without editing
ClusterDefinition.
*/}}
{{- define "valkey.cmpdRegexpPattern" -}}
^valkey-\d+
{{- end -}}

{{/*
Sentinel component regexp pattern — matches valkey-sentinel-8-0.1.0 etc.
*/}}
{{- define "valkeySentinel.cmpdRegexpPattern" -}}
^valkey-sentinel-\d+
{{- end -}}

{{/*
Scripts ConfigMap name — versioned so upgrades create a new ConfigMap
and old clusters keep using the one they were provisioned with.
*/}}
{{- define "valkey.scriptsTemplate" -}}
valkey-scripts-template-{{ .Chart.Version }}
{{- end -}}

{{/*
Config ConfigMap name per major version.
Usage: {{ printf "valkey%s-config-template-%s" .major $.Chart.Version }}
(used inline in cmpd.yaml because it needs the loop variable .major)
*/}}

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
Iterates all environment variables whose names match a parameter key and
calls the reload script for each one.
This is defined as a helper so both the ComponentDefinition template and
any future versions can include it identically.
*/}}
{{- define "valkey.reconfigureAction" -}}
reconfigure:
  exec:
    container: valkey
    targetPodSelector: All
    command:
      - /bin/sh
      - -c
      - |
        set -eu
        env | cut -d= -f1 | grep -E '^[A-Za-z0-9_.-][A-Za-z0-9_.-]*$' | sort -u | while IFS= read -r param; do
          [ -n "${param}" ] || continue
          /scripts/reload-parameter.sh "${param}" "$(printenv "${param}")"
        done
{{- end -}}
