# KubeBlocks Addon Development — Claude Code Context

This directory is a **Claude Code-driven** template for developing, validating, and deploying KubeBlocks Addons.
Copy `CLAUDE.md` and `.claude/` to the root of your KubeBlocks community addons repository.

## Project Layout

```
<addon-repo>/
├── addons/
│   └── <engine>/               ← addon Helm chart
│       ├── Chart.yaml          ← declares kblib dependency, KB version annotation
│       ├── values.yaml         ← versions array, image repos
│       ├── config/             ← ConfigMaps for config file templates
│       ├── scripts/            ← shell scripts (loaded into ConfigMaps)
│       └── templates/
│           ├── _helpers.tpl    ← naming helpers, regex patterns, annotations
│           ├── clusterdefinition.yaml
│           ├── cmpd-<component>.yaml   ← one file per component type
│           ├── cmpv-<component>.yaml   ← one file per component type
│           └── paramsdef-*.yaml        ← optional: live reconfiguration
├── addons-cluster/
│   └── <engine>/               ← cluster instantiation Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           └── cluster.yaml
├── addons/kblib/               ← shared Helm library chart (always present)
└── workspace/                  ← auto-created; test YAMLs
    └── tests/
```

## Available Commands

| Command | Purpose |
|---|---|
| `/generate-addon` | Full workflow: code → review → deploy → test instances |
| `/review-addon` | Code-only review against KubeBlocks standards |
| `/deploy-addon` | Deploy addon Helm chart to K8s and verify CRD status |
| `/test-instances` | Create database instances for every topology and wait for Running |
| `/diagnose` | Collect fresh diagnostics from existing failed cluster instances |
| `/sync-image` | Pull a Docker image and push it to the apecloud Docker Hub org |

---

## KubeBlocks v1.0 API — Core Rules

> Full Go struct reference: `claude-docs/kb-api-reference.md`

### Resources (all use `apps.kubeblocks.io/v1`)

| Resource | Purpose |
|---|---|
| `ComponentDefinition` | Reusable blueprint: PodSpec, configs, scripts, lifecycle hooks, roles |
| `ClusterDefinition` | Topologies — maps component names to ComponentDefinitions via regex |
| `ComponentVersion` | Maps service versions to container images per component |
| `Addon` | Helm-based packaging for the KubeBlocks addon manager |

**NEVER use `ClusterVersion`** — removed in KubeBlocks 1.0.

### Required Annotations on All CRD Resources

```yaml
annotations:
  kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
  apps.kubeblocks.io/skip-immutable-check: "true"   # CRITICAL: enables helm upgrade
```

Without `skip-immutable-check`, every `helm upgrade` will fail because ComponentDefinition fields are immutable at the CRD level. All production addons set this annotation.

In `_helpers.tpl`:
```
{{- define "<engine>.annotations" -}}
{{ include "kblib.helm.resourcePolicy" . }}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
apps.kubeblocks.io/skip-immutable-check: "true"
{{- end }}
```

### ComponentDefinition Naming

```
name: {{ printf "%s-%s" .componentDef $.Chart.Version }}
# e.g. "redis-7-1.1.0"
```

The `compDef` field in ClusterDefinition uses a **regex helper**, not a plain string:

```yaml
# In _helpers.tpl:
{{- define "redis.cmpdRegexpPattern" -}}
^redis-\d+
{{- end -}}

# In clusterdefinition.yaml:
compDef: {{ include "redis.cmpdRegexpPattern" . }}
# → matches redis-7-1.0.0, redis-7-1.1.0, redis-8-1.0.0, etc.
```

### ComponentDefinition Key Fields

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentDefinition
metadata:
  name: {{ printf "%s-%s" .componentDef $.Chart.Version }}
  annotations:
    kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
    apps.kubeblocks.io/skip-immutable-check: "true"
spec:
  provider: kubeblocks
  serviceKind: <protocol>       # e.g. redis, postgresql, elasticsearch
  serviceVersion: <semver>      # the version this ComponentDefinition targets
  podManagementPolicy: OrderedReady
  podUpgradePolicy: ReCreate    # typically ReCreate for major version upgrades
  minReadySeconds: 10
  volumes:
    - name: data
      needSnapshot: true
  roles:
    - name: primary
      updatePriority: 2
      participatesInQuorum: false
      isExclusive: true         # only one pod can be primary at a time
    - name: secondary
      updatePriority: 1
      participatesInQuorum: false
  configs:
    - name: <engine>-config
      template: <configmap-name>     # NOTE: field is "template", not "templateRef"
      namespace: {{ .Release.Namespace }}
      volumeName: <engine>-config
      externalManaged: true
  exporter:
    containerName: metrics
  lifecycleActions:
    roleProbe:
      periodSeconds: 1
      timeoutSeconds: 1
      exec:
        container: <engine>
        command: [...]
  runtime:                           # corev1.PodSpec — required
    containers: [...]
```

### ClusterDefinition Topologies

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ClusterDefinition
metadata:
  name: <engine>
  annotations:
    kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
    apps.kubeblocks.io/skip-immutable-check: "true"
spec:
  topologies:
    - name: standalone
      default: true
      components:
        - name: <comp>               # IANA service name, max 16 chars
          compDef: {{ include "<engine>.cmpdRegexpPattern" . }}
    - name: replication
      components:
        - name: <comp>
          compDef: {{ include "<engine>.cmpdRegexpPattern" . }}
      orders:
        provision: ["<comp>"]
        terminate: ["<comp>"]
        update: ["<comp>"]
```

### ComponentVersion — Image Mapping

```yaml
apiVersion: apps.kubeblocks.io/v1
kind: ComponentVersion
metadata:
  name: <engine>
spec:
  compatibilityRules:
    - compDefs: ["<engine>-7-"]     # prefix of ComponentDefinition names
      releases: ["7.2.4", "7.2.11"]
    - compDefs: ["<engine>-8-"]
      releases: ["8.2.2"]
  releases:
    - name: "7.2.4"
      serviceVersion: "7.2.4"
      images:
        <container>: docker.io/apecloud/<engine>:7.2.4
        metrics: docker.io/apecloud/<engine>-exporter:v1.80.1
        switchover: docker.io/apecloud/<engine>:7.2.4   # action containers as separate keys
```

### values.yaml — Version Array Pattern

```yaml
# Real pattern used in production addons:
<engine>Versions:
  - major: "7"
    componentDef: "<engine>-7"
    serviceVersion: "7.2.11"
    defaultImageTag: "7.2.0-v19"
    mirrorVersions:
      - { version: "7.2.4",  imageTag: "7.2.0-v10" }
      - { version: "7.2.11", imageTag: "7.2.0-v19" }
  - major: "8"
    componentDef: "<engine>-8"
    serviceVersion: "8.2.2"
    defaultImageTag: "8.2.2"
    mirrorVersions:
      - { version: "8.2.2", imageTag: "8.2.2" }
```

Templates iterate with `{{- range .Values.<engine>Versions }}` to generate one ComponentDefinition and one set of ComponentVersion releases per major version.

---

## Helm Chart Coding Rules

> Full details: `claude-docs/coding-rules.md`

### File Naming
- Multiple component types → multiple files: `cmpd-redis.yaml`, `cmpd-redis-sentinel.yaml`
- NOT a single `componentdefinition.yaml` (that is only for trivial single-component addons)

### configs[] Field Names
- Use `template:` (not `templateRef:`) for the ConfigMap reference
- `volumeName` must exist in both `runtime.volumes` and `runtime.containers[*].volumeMounts`

### _helpers.tpl
- Never remove existing `{{- define "..." -}}` blocks
- Always add new helpers; never modify existing ones in breaking ways

### Self-Validation
```bash
helm template test-addon addons/<engine>
```
Must pass before any `kubectl apply`.

---

## QA and Testing Rules

> Full procedures: `claude-docs/qa-and-testing.md`

### Cluster Phase Values (KB v1)
`Creating` → `Running` / `Updating` → `Stopping` → `Stopped` → `Deleting`

**There is no `Failed` or `Error` cluster phase in KubeBlocks v1.**
Failures are visible in component status and pod events/logs, not in cluster phase.

### Cluster YAML — Always Include terminationPolicy

```yaml
spec:
  terminationPolicy: Delete   # REQUIRED field. Delete cleans up PVCs on delete.
  clusterDef: <engine>
  topology: standalone
  componentSpecs:
    - name: <comp>
      serviceVersion: "7.2.4"
      replicas: 1
      resources:
        limits:   { cpu: "0.5", memory: "512Mi" }
        requests: { cpu: "0.1", memory: "256Mi" }
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes: [ReadWriteOnce]
            storageClassName: ""
            resources:
              requests:
                storage: 20Gi
```

### Image Existence Check
Before deploying test clusters, verify images exist:
```bash
skopeo inspect docker://docker.io/apecloud/<engine>:<version> --no-creds 2>/dev/null \
  && echo EXISTS || echo MISSING
```
If missing: skip that version's tests, do NOT change the YAML version tag.

---

## Decision Logic

> Full rules: `claude-docs/workflow-rules.md`

- Goal is purely "test/deploy/validate" → skip code generation, go directly to deploy or test
- After `test_instance` fails with live clusters → run `diagnose` first, then `code`
- After `diagnose` → run `code` then `deploy` (never diagnose again after code runs)
- Same error 3+ consecutive cycles → stop and report as unrecoverable
- `ErrImagePull` on a valid version tag → YAML is correct, image not yet published → skip test, proceed to finish
