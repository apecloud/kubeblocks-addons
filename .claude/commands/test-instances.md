Create database cluster instances to validate the deployed KubeBlocks addon, testing every topology.

**Target:** $ARGUMENTS
(Engine name, optional version, optional cluster env — e.g., `redis`, `redis 7.2.4`, or `redis 7.2.4 AWS_CN_NORTH_1`. Version omitted → tests all available versions. Cluster env omitted → use `KUBECONFIG` default.)

---

## Step 0: Load Environment

```bash
SCRIPT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"

# Parse arguments: ENGINE [VERSION] [ENV]
# ENV is identified by being all-uppercase with underscores (e.g. AWS_CN_NORTH_1)
# VERSION contains dots (e.g. 7.2.4)
ARGS=($ARGUMENTS)
ENGINE="${ARGS[0]:-}"
VERSION=""
ENV_NAME=""
for arg in "${ARGS[@]:1}"; do
  if [[ "$arg" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    ENV_NAME="$arg"
  else
    VERSION="$arg"
  fi
done

# Resolve KUBECONFIG
if [[ -n "$ENV_NAME" ]]; then
  KV="KUBECONFIG_${ENV_NAME}"
  RESOLVED=$(eval echo "\$$KV")
  [[ -z "$RESOLVED" ]] && { echo "ERROR: KUBECONFIG_${ENV_NAME} not defined in .env"; exit 1; }
  export KUBECONFIG="$RESOLVED"
else
  [ -n "$KUBECONFIG" ] && export KUBECONFIG
fi

kubectl cluster-info --request-timeout=5s \
  || { echo "ERROR: kubectl cannot reach the cluster. Check KUBECONFIG in .env"; exit 1; }
echo "Cluster: ${ENV_NAME:-default}  KUBECONFIG=${KUBECONFIG:-~/.kube/config}"
```

---

## OPS Test Matrix

For each engine, tests are organized by Feature → Operation, matching the official KubeBlocks v1.0 regression report format:

| Feature | Operations |
|---|---|
| **Lifecycle** | Create, Start, Stop, Restart (cluster + per-component), Update (Monitor enable, TerminationPolicy WipeOut) |
| **Scale** | VerticalScaling, VolumeExpansion, HorizontalScaling In/Out, HscaleOfflineInstances, HscaleOnlineInstances, RebuildInstance |
| **Upgrade** | Service version upgrade (forward + backward) |
| **SwitchOver** | Promote, SwitchOver (per component) |
| **Failover** | ChaosMesh fault injection with expected HA recovery: Full CPU, Network Corrupt, OOM, Pod Kill, Kill 1, Network Loss, Network Delay, Pod Failure, Network Bandwidth, Network Partition, Delete Pod All |
| **NoFailover** | ChaosMesh fault injection without failover expected: DNS Error, Network Duplicate, DNS Random, Connection Stress, Time Offset |
| **Backup Restore** | Backup (xtrabackup / xtrabackup-inc / pbm-physical / wal-g / pg-basebackup / datafile / dump / full / volume-snapshot / topics), Schedule Backup/Restore, Restore, Restore Increment, Delete Restore Cluster |
| **Parameter** | Reconfiguring (set specific parameters per component) |
| **Accessibility** | Expose Enable/Disable (internet/intranet), Connect |
| **Stress** | Bench (service + LB service), Tpch |

> **ChaosMesh** is the chaos engineering tool used for Failover and NoFailover tests. It must be installed in the cluster.
> Check both common namespaces: `kubectl get pods -n chaos-mesh` or `kubectl get pods -n chaos-testing`.
> Use whichever namespace is present as `CHAOS_NS`.

> **Single-node topology limitations:** Some operations are architecturally incompatible with single-node topologies and must be marked `N/A` without attempting:
> - **HorizontalScaling Out/In, HscaleOfflineInstances, HscaleOnlineInstances** — single-node uses `discovery.type: single-node`; additional nodes cannot join.
> - **SwitchOver** — no secondary exists to promote.
> - **Failover (all 11 cases)** — single-node has no HA election. Recovery is Kubernetes pod restart (restartPolicy), not application-level failover. Results should be labeled as "K8s pod restart recovery" rather than "HA failover". Test in multi-node topology for true failover validation.

---

## Step 1: Prerequisites

```bash
ENGINE=<engine>

# 1. ChaosMesh availability
kubectl get pods -n chaos-testing --no-headers 2>/dev/null | head -3 \
  || echo "ChaosMesh not found — chaos tests will be SKIPPED"

# 2. ClusterDefinition must be Available
PHASE=$(kubectl get clusterdefinition $ENGINE -o jsonpath='{.status.phase}' 2>/dev/null)
echo "ClusterDefinition phase: $PHASE"
# If not Available → run /deploy-addon first

# 3. addons-cluster chart must exist
ls addons-cluster/$ENGINE/Chart.yaml 2>/dev/null || echo "addons-cluster not found — cannot test"
```

## Step 1b: Load Known Issues

Query GitHub for open issues labelled **`skip-in-test`** in `apecloud/kubeblocks-addons`.
Each matching issue represents a known failing test case — skip it this run; re-run automatically when the issue is closed.

**Convention for issue titles:** `[<engine>] <Operation>: <short description>`
Example: `[elasticsearch] full-backup: JavaClassNotFoundException in es-agent 0.1.0`

```bash
ENGINE=<engine>

# Fetch all open issues with skip-in-test label for this engine
echo "=== Known Issues (skip-in-test) ==="
gh issue list \
  --repo apecloud/kubeblocks-addons \
  --label "skip-in-test" \
  --state open \
  --json number,title \
  --jq ".[] | select(.title | test(\"\\\\[${ENGINE}\"; \"i\")) | \"  SKIP  #\\(.number)  \\(.title)\""

# Save skip list for reference during the run
SKIP_ISSUES=$(gh issue list \
  --repo apecloud/kubeblocks-addons \
  --label "skip-in-test" \
  --state open \
  --json number,title \
  --jq "[.[] | select(.title | test(\"\\\\[${ENGINE}\"; \"i\")) | {number: .number, title: .title}]")
echo "$SKIP_ISSUES"
```

Before each test case, check whether its operation appears in `$SKIP_ISSUES`:

```bash
# Helper: returns issue number if this operation is a known skip, empty otherwise
function known_skip() {
  local operation="$1"
  echo "$SKIP_ISSUES" | python3 -c "
import sys, json
issues = json.load(sys.stdin)
op = '''$operation'''.lower()
for i in issues:
    if op in i['title'].lower():
        print(i['number'])
        break
"
}

# Usage before any test case:
ISSUE=$(known_skip "full-backup")
if [[ -n "$ISSUE" ]]; then
  echo "SKIPPED — known issue #${ISSUE} (skip-in-test)"
else
  # run the test
fi
```

> **Rule:**
> - Issue **OPEN** + label `skip-in-test` → mark `SKIPPED (known #XXXX)`, do not attempt.
> - Issue **CLOSED** → label is gone → test runs automatically next time.
> - To file a new known issue: `gh issue create --label "skip-in-test,bug" --title "[<engine>] <Operation>: ..."`.
> - No extra files needed anywhere — GitHub Issues is the single source of truth.

## Step 2: Enumerate Topologies and Component Names

```bash
ENGINE=<engine>

helm template test-addon addons/$ENGINE | python3 -c "
import sys, yaml
for doc in yaml.safe_load_all(sys.stdin):
    if doc and doc.get('kind') == 'ClusterDefinition':
        for t in doc.get('spec', {}).get('topologies', []):
            marker = ' [default]' if t.get('default') else ''
            print(f'Topology: {t[\"name\"]}{marker}  replicas suggestion: {t.get(\"replicas\", \"?\")}')
            for c in t.get('components', []):
                print(f'  component: {c[\"name\"]}  compDef: {c[\"compDef\"]}')
            for s in t.get('shardings', []):
                print(f'  sharding: {s[\"name\"]}')
"
```

## Step 2b: Query Component Replicas Limits

Before generating cluster YAMLs, read the `replicasLimit` from every deployed ComponentDefinition for this engine. Use `minReplicas` as the lower bound when setting `replicas` for each component.

```bash
ENGINE=<engine>

kubectl get componentdefinition -o json | python3 -c "
import sys, json
data = json.load(sys.stdin)
engine = sys.argv[1]
for item in data.get('items', []):
    name = item['metadata']['name']
    if not name.startswith(engine):
        continue
    rl = item.get('spec', {}).get('replicasLimit') or {}
    min_r = rl.get('minReplicas', 1)
    max_r = rl.get('maxReplicas', 16384)
    print(f'{name}  minReplicas={min_r}  maxReplicas={max_r}')
" "$ENGINE"
```

Record the per-component minimums. For each component in every cluster YAML: set `replicas = max(1, minReplicas)`. If `minReplicas > 1`, a topology using fewer replicas will hit `PreCheckFailed` before any pod is created.

---

## Step 3: Enumerate Available Service Versions

```bash
ENGINE=<engine>

kubectl get componentversion $ENGINE -o json | python3 -c "
import sys, json
cv = json.load(sys.stdin)
releases = cv.get('spec', {}).get('releases', [])
for r in sorted(releases, key=lambda r: r['serviceVersion']):
    print(r['serviceVersion'])
" 2>/dev/null || echo "ComponentVersion $ENGINE not found"
```

If a specific version was requested in arguments, test only that version.

## Step 4: Probe Image Existence

Before deploying test clusters, check whether the container images actually exist.

**China cloud note:** Clusters on Volcengine/Aliyun cannot reach docker.io (returns HTTP 000). In that case, fall back to the Aliyun mirror. If pods are already Running in the cluster, the image clearly exists — skip the check entirely and record as EXISTS.

```bash
ENGINE=<engine>
ALIYUN_MIRROR="apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud"

check_image() {
  local IMAGE="$1"
  if command -v skopeo &>/dev/null; then
    skopeo inspect "docker://${IMAGE}" --no-creds 2>/dev/null && return 0 || return 1
  else
    # curl-based fallback (docker.io only)
    local REPO="${IMAGE#docker.io/}"
    local NAME="${REPO%%:*}"
    local TAG="${REPO##*:}"
    TOKEN=$(curl -s \
      "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${NAME}:pull" \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null)
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
      "https://registry.hub.docker.com/v2/${NAME}/manifests/${TAG}" 2>/dev/null)
    [[ "$STATUS" == "200" ]]
  fi
}

for VERSION in <versions-to-test>; do
  echo -n "docker.io/apecloud/$ENGINE:$VERSION ... "
  if check_image "docker.io/apecloud/${ENGINE}:${VERSION}"; then
    echo "EXISTS"
  else
    # docker.io unreachable (HTTP 000) from China cloud? Try Aliyun mirror.
    echo -n "MISSING on docker.io — trying Aliyun mirror ... "
    if check_image "${ALIYUN_MIRROR}/${ENGINE}:${VERSION}"; then
      echo "EXISTS (Aliyun mirror)"
    else
      echo "MISSING on both registries"
    fi
  fi
done
```

**For MISSING images (both registries):** Record as "Image not in registry — test skipped". Do NOT change version tags. Proceed with remaining versions.

**If docker.io returns HTTP 000 but Aliyun mirror returns EXISTS:** The cluster is in a China region. Images are available. Proceed with testing normally.

---

## Engine-Specific Resource Minimums

Some engines require more memory than the generic template defaults (`memory: 512Mi`). Apply these per-component minimums when generating cluster YAMLs:

| Engine | Component | Minimum memory limit | Reason |
|---|---|---|---|
| Elasticsearch / Kibana | kibana (v8+) | 1Gi | Node.js JS heap exhausts 512Mi before startup probe fires → CrashLoopBackOff |

---

## Feature Tests

Run the following for each (topology, version) combination where the image exists. Track every result as PASSED / FAILED / SKIPPED / Not implemented.

### Timeouts and Early Failure Detection

Set these variables once at the start of each test session:

```bash
KB_POD=$(kubectl get pods -n kb-system --no-headers 2>/dev/null \
  | grep "^kubeblocks-[^d]" | awk '{print $1}' | head -1)
echo "KB operator pod: $KB_POD"
```

**Timeout reference by operation type:**

| Operation | Expected | Timeout | Check KB logs if stuck > |
|---|---|---|---|
| Create cluster (multi-node) | 120-180s | 240s | 90s |
| Stop | 30-60s | 90s | 60s |
| Start | 60-120s | 180s | 90s |
| Restart (OpsRequest) | 60-90s | 120s | 60s |
| VerticalScaling | 60-120s | 180s | 90s |
| VolumeExpansion | 10-30s | 60s | 30s |
| HScaling Out/In | 60-120s | 180s | 60s |
| Upgrade | 120-240s | 300s | 120s |
| SwitchOver | 30-60s | 90s | 45s |
| Failover chaos (60s fault) | 60+60s | 180s | 150s |
| NoFailover chaos (60s fault) | 60+30s | 120s | 100s |
| Backup | 30-60s | 120s | 60s |
| Restore cluster | 60-120s | 180s | 90s |

**OpsRequest wait helper** — use this instead of bare `kubectl wait` or blind loops:

```bash
# wait_ops <opsrequest-name> <timeout-seconds>
function wait_ops() {
  local NAME=$1 TIMEOUT=${2:-120}
  for ((i=0; i<TIMEOUT; i+=10)); do
    PHASE=$(kubectl get opsrequest $NAME -o jsonpath='{.status.phase}' 2>/dev/null)
    [[ "$PHASE" == "Succeed" ]] && echo "✓ $NAME Succeed in ${i}s" && return 0
    [[ "$PHASE" == "Failed"  ]] && echo "✗ $NAME Failed:" \
      && kubectl get opsrequest $NAME -o jsonpath='{.status.conditions[-1].message}' 2>/dev/null && echo "" && return 1
    # Check KB logs at halfway point if still Running
    if (( i == TIMEOUT/2 )); then
      echo "  [${i}s] ops=$PHASE — checking KB logs:"
      kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null \
        | grep -E "ERROR|build error|$CLUSTER_NAME" | tail -8
    else
      (( i % 30 == 0 && i > 0 )) && echo "  [${i}s] ops=$PHASE"
    fi
    sleep 10
  done
  echo "✗ $NAME timeout after ${TIMEOUT}s — KB logs:"
  kubectl logs $KB_POD -n kb-system --tail=30 2>/dev/null \
    | grep -E "ERROR|build error|$CLUSTER_NAME" | tail -10
  return 1
}
```

### Feature: Lifecycle

#### Create

```bash
mkdir -p workspace/tests
ENGINE=<engine>  TOPOLOGY=<topology>  VERSION=<version>
CLUSTER_NAME="${ENGINE:0:10}-${TOPOLOGY:0:8}"
cat > workspace/tests/${ENGINE}-${TOPOLOGY}-test.yaml << EOF
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: default
spec:
  terminationPolicy: Delete
  clusterDef: ${ENGINE}
  topology: ${TOPOLOGY}
  componentSpecs:
    # One entry per component in this topology (names from Step 2).
    # Set replicas = max(1, minReplicas) from Step 2b — using fewer than minReplicas
    # causes PreCheckFailed before any pod is created.
    - name: <component-name>
      serviceVersion: "${VERSION}"
      replicas: <replicas>  # from Step 2b: max(1, minReplicas for this component)
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
EOF

kubectl apply -f workspace/tests/${ENGINE}-${TOPOLOGY}-test.yaml
```

Wait for Running (timeout 240s — check KB operator logs if not Running by 90s):

```bash
CLUSTER_NAME=<cluster-name>
KB_POD=$(kubectl get pods -n kb-system --no-headers 2>/dev/null | grep "^kubeblocks-[^d]" | awk '{print $1}' | head -1)
TIMEOUT=240; INTERVAL=10; PHASE=""

for ((i=0; i<TIMEOUT; i+=INTERVAL)); do
  PHASE=$(kubectl get cluster "$CLUSTER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "  [${i}s] phase=${PHASE:-unknown}"
  [[ "$PHASE" == "Running" ]] && echo "✓ Running" && break

  POD_TABLE=$(kubectl get pods -l "app.kubernetes.io/instance=$CLUSTER_NAME" --no-headers 2>/dev/null)
  if echo "$POD_TABLE" | grep -qE 'CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError'; then
    echo "✗ Unrecoverable pod failure:"; echo "$POD_TABLE"; PHASE="PodFailed"; break
  fi
  if (( i == 90 )); then
    echo "⚠ Still Creating at 90s — checking KB operator logs:"
    kubectl logs $KB_POD -n kb-system --tail=30 2>/dev/null \
      | grep -E "ERROR|build error|$CLUSTER_NAME" | tail -10
    echo "$POD_TABLE"
  fi
  sleep $INTERVAL
done

[[ "$PHASE" != "Running" ]] && echo "✗ Did not reach Running (last: $PHASE)"
```

**Note:** KubeBlocks v1 clusters have NO "Failed" or "Error" phase. Detect failures at the pod level.

#### Stop / Start

```bash
# Stop — MUST use --type=json to patch only the stop field.
# --type=merge replaces the entire componentSpecs array, wiping serviceVersion/replicas/resources.
# Find the array index for each component first (0-based).
kubectl patch cluster $CLUSTER_NAME --type=json \
  -p='[{"op":"add","path":"/spec/componentSpecs/0/stop","value":true}]'
# For multiple components add one op per index:
# -p='[{"op":"add","path":"/spec/componentSpecs/0/stop","value":true},{"op":"add","path":"/spec/componentSpecs/1/stop","value":true}]'

# Wait for Stopped — typical: 30-60s, timeout 90s
for i in {1..18}; do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Stopped" ]] && echo "✓ Stopped in $((i*5))s" && break
  (( i == 12 )) && echo "⚠ Still not Stopped at 60s — check KB logs:" \
    && kubectl logs $KB_POD -n kb-system --tail=10 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  sleep 5
done

# Start (reverse)
kubectl patch cluster $CLUSTER_NAME --type=json \
  -p='[{"op":"replace","path":"/spec/componentSpecs/0/stop","value":false}]'
# Wait for Running — typical: 60-120s, timeout 180s
for i in {1..36}; do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Running in $((i*5))s" && break
  (( i == 18 )) && echo "⚠ Still not Running at 90s — check KB logs:" \
    && kubectl logs $KB_POD -n kb-system --tail=10 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  sleep 5
done
```

#### Restart

```bash
# Restart entire cluster
kubectl annotate cluster $CLUSTER_NAME \
  kubeblocks.io/restart="$(date +%s)" --overwrite
kubectl wait cluster $CLUSTER_NAME --for=jsonpath='{.status.phase}'=Running --timeout=120s \
  || { echo "⚠ Restart timeout — KB logs:"; kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -10; }

# Restart specific component
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: restart-<component>-$(date +%s)
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: Restart
  restart:
    - componentName: <component>
EOF
```

#### Update Monitor / TerminationPolicy

```bash
# Enable monitor — MUST use --type=json to patch a single field inside componentSpecs.
# --type=merge replaces the entire componentSpecs array, wiping replicas/resources/volumeClaimTemplates
# for every component not listed in the patch body. This corrupts the cluster spec.
# Find the array index for the target component first (0-based).
kubectl patch cluster $CLUSTER_NAME --type=json \
  -p='[{"op":"add","path":"/spec/componentSpecs/0/monitor","value":true}]'

# Update TerminationPolicy — scalar field at spec level, --type=merge is safe here
kubectl patch cluster $CLUSTER_NAME --type=merge \
  -p '{"spec":{"terminationPolicy":"WipeOut"}}'

# Revert TerminationPolicy
kubectl patch cluster $CLUSTER_NAME --type=merge \
  -p '{"spec":{"terminationPolicy":"Delete"}}'
```

---

### Feature: Scale

#### VerticalScaling

```bash
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: vscale-$(date +%s)
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: VerticalScaling
  verticalScaling:
    - componentName: <component>
      requests: { cpu: "0.2", memory: "256Mi" }
      limits:   { cpu: "1",   memory: "1Gi"  }
EOF
wait_ops vscale-${TS} 180
```

#### VolumeExpansion

```bash
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: volexp-$(date +%s)
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: VolumeExpansion
  volumeExpansion:
    - componentName: <component>
      volumeClaimTemplates:
        - name: data
          storage: "21Gi"
EOF
wait_ops volexp-${TS} 60
```

#### HorizontalScaling In / Out

> **Note:** The `replicas` field does NOT exist in `horizontalScaling` (KB v1 API).
> Use `scaleOut.replicaChanges` to add replicas and `scaleIn.replicaChanges` to remove replicas.
> **Single-node topologies** (e.g. `discovery.type: single-node` in Elasticsearch): mark as N/A — adding nodes is architecturally unsupported.

```bash
# Scale Out (increase replicas by N)
TS=$(date +%s)
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: hscale-out-${TS}
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: HorizontalScaling
  horizontalScaling:
    - componentName: <component>
      scaleOut:
        replicaChanges: <N>
EOF
wait_ops hscale-out-${TS} 180

# Scale In (decrease replicas by N)
TS=$(date +%s)
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: hscale-in-${TS}
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: HorizontalScaling
  horizontalScaling:
    - componentName: <component>
      scaleIn:
        replicaChanges: <N>
EOF
wait_ops hscale-in-${TS} 180
```

#### HscaleOfflineInstances / HscaleOnlineInstances

```bash
# Take specific instance offline (by pod name suffix)
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: hscale-offline-$(date +%s)
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: HorizontalScaling
  horizontalScaling:
    - componentName: <component>
      offlineInstancesToOnline: []
      onlineInstancesToOffline: ["<cluster-name>-<component>-N"]
EOF

# Bring it back online
# Swap offlineInstancesToOnline / onlineInstancesToOffline values
```

#### RebuildInstance

```bash
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: rebuild-$(date +%s)
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: RebuildInstance
  rebuildFrom:
    - componentName: <component>
      instances:
        - name: <cluster-name>-<component>-N
EOF
wait_ops rebuild-${TS} 300
```

---

### Feature: Upgrade

```bash
# Service version upgrade (forward)
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: upgrade-$(date +%s)
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: Upgrade
  upgrade:
    components:
      - componentName: <component>
        serviceVersion: "<target-version>"
EOF
wait_ops upgrade-${TS} 300

# Downgrade (same OpsRequest type, earlier version)
```

Test both upgrade paths (forward to latest, backward to original) per the report pattern.

> **Engine constraint (not a bug):** Some engines (e.g. Elasticsearch) prohibit in-place downgrades at the data layer — the node will refuse to start if on-disk data is from a newer version. Mark such downgrades as `N/A (Engine Constraint)`, not FAILED.

---

### Feature: SwitchOver

```bash
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: switchover-$(date +%s)
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: Switchover
  switchover:
    - componentName: <component>
      instanceName: "*"   # promote any secondary to primary
EOF
wait_ops switchover-${TS} 90
```

---

### Feature: Failover (ChaosMesh)

Chaos faults that **trigger a failover** — the HA mechanism must re-elect a new primary and the cluster should return to Running with data intact.

> **Single-node topology:** These tests verify Kubernetes pod restart recovery only — there is no application-level HA election. Mark results as "K8s pod restart recovery (not HA failover)" and note the topology. For true failover validation, use multi-node topology with 3+ replicas.

Requires ChaosMesh. Check namespace: `kubectl get pods -n chaos-mesh` or `kubectl get pods -n chaos-testing`. If not available, mark all as SKIPPED.

```bash
CLUSTER_NAME=<cluster-name>
COMPONENT=<component>
NAMESPACE=default

# Identify the current primary pod
PRIMARY_POD=$(kubectl get pods -l "app.kubernetes.io/instance=$CLUSTER_NAME" \
  -o jsonpath='{.items[0].metadata.name}')  # adjust selector for primary role if applicable

# Set CHAOS_NS to whichever namespace ChaosMesh is installed in
CHAOS_NS=chaos-mesh   # or chaos-testing
```

#### Pod Kill

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: chaos-pod-kill-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
      app.kubernetes.io/component: "$COMPONENT"
  gracePeriod: 0
EOF
# Wait for cluster to recover to Running
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Kill 1 (kill process PID 1)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: chaos-kill1-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: container-kill
  mode: one
  containerNames: ["<main-container-name>"]
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Pod Failure (pod unavailable for a period)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: chaos-pod-failure-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: pod-failure
  mode: one
  duration: "60s"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### OOM (memory stress → OOM kill)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: chaos-oom-$(date +%s)
  namespace: $CHAOS_NS
spec:
  mode: one
  duration: "30s"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
  stressors:
    memory:
      workers: 1
      size: "512MB"
EOF
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Full CPU

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: chaos-cpu-$(date +%s)
  namespace: $CHAOS_NS
spec:
  mode: one
  duration: "60s"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
  stressors:
    cpu:
      workers: 2
      load: 100
EOF
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Network Loss

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: chaos-netloss-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: loss
  mode: one
  duration: "60s"
  loss:
    loss: "100"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Network Corrupt

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: chaos-netcorrupt-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: corrupt
  mode: one
  duration: "60s"
  corrupt:
    corrupt: "60"
    correlation: "25"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Network Bandwidth

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: chaos-netbw-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: bandwidth
  mode: one
  duration: "60s"
  bandwidth:
    rate: "1mbps"
    limit: 100
    buffer: 10000
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Network Delay

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: chaos-netdelay-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: delay
  mode: one
  duration: "60s"
  delay:
    latency: "500ms"
    correlation: "25"
    jitter: "50ms"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Network Partition

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: chaos-partition-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: partition
  mode: one
  duration: "60s"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=120; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 60 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 120 )) && echo "✗ No recovery after 120s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Delete Pod All

```bash
kubectl delete pods -l "app.kubernetes.io/instance=$CLUSTER_NAME" --force --grace-period=0
for ((i=0; i<=150; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 75 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 150 )) && echo "✗ No recovery after 150s — last phase: ${PHASE}" && break
  sleep 10
done
```

---

### Feature: NoFailover (ChaosMesh — no HA election expected)

These faults should **not** trigger failover. The cluster may be temporarily degraded but should recover without leader election.

#### Network Duplicate

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: chaos-netdup-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: duplicate
  mode: one
  duration: "60s"
  duplicate:
    duplicate: "60"
    correlation: "25"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=90; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 40 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 90 )) && echo "✗ No recovery after 90s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### DNS Error

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: DNSChaos
metadata:
  name: chaos-dnserr-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: error
  mode: one
  duration: "60s"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=90; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 40 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 90 )) && echo "✗ No recovery after 90s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### DNS Random

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: DNSChaos
metadata:
  name: chaos-dnsrandom-$(date +%s)
  namespace: $CHAOS_NS
spec:
  action: random
  mode: one
  duration: "60s"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=90; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 40 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 90 )) && echo "✗ No recovery after 90s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Time Offset

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: TimeChaos
metadata:
  name: chaos-timeoffset-$(date +%s)
  namespace: $CHAOS_NS
spec:
  mode: one
  duration: "60s"
  timeOffset: "-1h"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
EOF
for ((i=0; i<=90; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 40 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 90 )) && echo "✗ No recovery after 90s — last phase: ${PHASE}" && break
  sleep 10
done
```

#### Connection Stress

```bash
cat <<EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: chaos-connstress-$(date +%s)
  namespace: $CHAOS_NS
spec:
  mode: one
  duration: "60s"
  selector:
    namespaces: [$NAMESPACE]
    labelSelectors:
      app.kubernetes.io/instance: "$CLUSTER_NAME"
  stressors:
    cpu:
      workers: 1
      load: 50
EOF
for ((i=0; i<=90; i+=10)); do
  PHASE=$(kubectl get cluster $CLUSTER_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Running" ]] && echo "✓ Recovered in ${i}s" && break
  if (( i == 40 )); then
    echo "  [${i}s] still ${PHASE} — KB logs:"
    kubectl logs $KB_POD -n kb-system --tail=20 2>/dev/null | grep -E "ERROR|$CLUSTER_NAME" | tail -5
  fi
  (( i == 90 )) && echo "✗ No recovery after 90s — last phase: ${PHASE}" && break
  sleep 10
done
```

**Cleanup chaos objects after each test:**
```bash
kubectl delete networkchaos,podchaos,stresschaos,dnschaos,timechaos \
  -n $CHAOS_NS -l "app.kubernetes.io/instance=$CLUSTER_NAME" 2>/dev/null || true
```

---

### Feature: Backup Restore

The backup method depends on the engine. Common methods from the regression report:

| Engine | Backup Methods |
|---|---|
| MySQL (8.0 / 5.7) | xtrabackup, xtrabackup-inc (incremental), volume-snapshot, Schedule xtrabackup |
| PostgreSQL | wal-g, pg-basebackup, volume-snapshot, Schedule pg-basebackup |
| MongoDB | pbm-physical, dump, datafile, volume-snapshot, Schedule pbm-physical |
| Redis | datafile, volume-snapshot, Schedule datafile, aof |
| Redis Cluster | datafile, Schedule datafile |
| Kafka | topics |
| Qdrant | datafile, Schedule datafile |
| Etcd | datafile |
| Elasticsearch | es-dump, full-backup (⚠ full-backup fails with JavaClassNotFoundException in ES 7.x — use es-dump) |
| Milvus | full, volume-snapshot |
| Clickhouse | full |
| TDengine | dump |
| Kingbase | full |
| GaussDB | gaussdb-roach |
| Oracle | oracle-rman |
| OceanBase Ent | full, full-for-rebuild |
| MSSQL | full |
| Doris | full |

```bash
# Create backup
cat <<EOF | kubectl apply -f -
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: backup-test-$(date +%s)
  namespace: default
spec:
  backupMethod: <method>          # e.g. xtrabackup, wal-g, datafile
  backupPolicyName: <cluster-name>-<component>-backup-policy
EOF

# Wait for backup Completed
kubectl wait backup backup-test-<ts> --for=jsonpath='{.status.phase}'=Completed --timeout=300s

# Restore from backup
cat <<EOF | kubectl apply -f -
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: <cluster-name>-restore
  namespace: default
  annotations:
    kubeblocks.io/restore-from-backup: '{"<component>":{"name":"backup-test-<ts>","namespace":"default","volumeRestorePolicy":"Parallel"}}'
spec:
  terminationPolicy: Delete
  clusterDef: <engine>
  topology: <topology>
  componentSpecs:
    - name: <component>
      serviceVersion: "<version>"
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
EOF

kubectl wait cluster <cluster-name>-restore --for=jsonpath='{.status.phase}'=Running --timeout=300s

# Cleanup restore cluster
kubectl delete cluster <cluster-name>-restore
```

#### Schedule Backup

```bash
cat <<EOF | kubectl apply -f -
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupSchedule
metadata:
  name: sched-backup-$(date +%s)
  namespace: default
spec:
  backupPolicyName: <cluster-name>-<component>-backup-policy
  schedules:
    - backupMethod: <method>
      cronExpression: "*/5 * * * *"   # every 5 min for testing
      enabled: true
      retentionPeriod: 1h
EOF
# Wait for at least one backup to complete, then delete schedule
```

#### Restore Increment (xtrabackup-inc)

```bash
# First ensure a full xtrabackup exists, then apply incremental backup,
# then restore incrementally. Only applicable to engines with xtrabackup-inc method.
```

---

### Feature: Parameter (Reconfiguring)

> **Pre-check — ParametersDef is optional.** Not every addon implements live reconfiguration.
> Check before attempting the test:
> ```bash
> kubectl get parametersdef --no-headers 2>/dev/null | grep <engine>
> ```
>
> | Result | Action | Report state |
> |---|---|---|
> | ParametersDef found | Run the test | `PASSED` / `FAILED` |
> | ParametersDef missing, team plans to add it | Skip, file a **Feature** issue | `N/A (ParametersDef not yet implemented)` |
> | ParametersDef missing, intentionally not supported | Skip, no issue needed | `N/A (not applicable for this engine)` |
>
> **Never mark `FAILED` just because ParametersDef is absent** — that is a feature gap, not a broken feature.
> Only mark `FAILED` if ParametersDef exists but the OpsRequest errors out or times out.

Common parameter examples from the regression report:

| Engine | Parameter | Example Value |
|---|---|---|
| MySQL 8.0 | binlog_expire_logs_seconds | 691200 |
| MySQL 5.7 | expire_logs_days | 8 |
| PostgreSQL | max_connections | 200 |
| PostgreSQL | shared_buffers | 512MB |
| Redis | maxclients | 10001 |
| Redis | aof-timestamp-enabled | yes |
| Kingbase | shared_buffers | 1GB |
| OceanBase | system_memory | 2G |
| OceanBase Ent | net_thread_count | 4 |
| GaussDB | alarm_report_interval | 20 |
| Oracle | open_cursors | 400 |
| DamengDB | BUFFER | 900 |
| TDengine | numOfRpcSessions | 40000 |
| ApeCloud MySQL | log_error_verbosity, max_connections, general_log, innodb_sort_buffer_size | various |
| Vastbase | audit_buffer_fflush_interval | 150 |

```bash
# NOTE: the field is "reconfigures" (plural array), NOT "reconfigure".
TS=$(date +%s)
cat <<EOF | kubectl apply -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: reconfig-${TS}
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: Reconfiguring
  reconfigures:
    - componentName: <component>
      parameters:
        - key: <param-name>
          value: "<param-value>"
EOF
for i in {1..36}; do
  PHASE=$(kubectl get opsrequest reconfig-${TS} -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Succeed" ]] && echo "✓ Reconfiguring Succeed" && break
  [[ "$PHASE" == "Failed" ]]  && echo "✗ Reconfiguring Failed" && break
  (( i % 6 == 0 )) && echo "  [${i}] ops=$PHASE"
  sleep 5
done
```

> If `ParametersDef` is absent and you attempt the OpsRequest anyway, it will stay in `Running` indefinitely — cancel it with `kubectl delete opsrequest reconfig-<ts>` and mark the result `N/A`.

---

### Feature: Accessibility

#### Expose (internet/intranet LoadBalancer service)

> **Expose strategy by component type:**
> - Components **with roles** (e.g. MySQL primary/secondary): use the OpsRequest approach with `roleSelector` to expose only the primary.
> - Components **without roles** (e.g. Elasticsearch master/data): use the direct Service approach with `apps.kubeblocks.io/component-name` label selector. The OpsRequest approach will hang if the component has no roles and a `roleSelector` is injected.
>
> Check whether a component has roles before choosing the approach:
> ```bash
> kubectl get componentdefinition <compdef-name> -o jsonpath='{.spec.roles[*].name}'
> # Empty output → use direct Service approach
> ```

**Approach A — OpsRequest (for components WITH roles):**

```bash
# NOTE: the "switch" field is required but missing from the CRD schema validation.
# Use --validate=false to bypass client-side validation.
# Do NOT include roleSelector for components that have no roles defined.
TS=$(date +%s)
cat <<EOF | kubectl apply --validate=false -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: expose-enable-${TS}
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: Expose
  expose:
    - componentName: <component>
      switch: Enable
      services:
        - name: internet
          serviceType: LoadBalancer
          annotations: {}
EOF
for i in {1..24}; do
  PHASE=$(kubectl get opsrequest expose-enable-${TS} -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Succeed" ]] && echo "✓ Expose Enable Succeed" && break
  [[ "$PHASE" == "Failed" ]]  && echo "✗ Expose Enable Failed" && break
  sleep 5
done

# Disable
TS=$(date +%s)
cat <<EOF | kubectl apply --validate=false -f -
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: expose-disable-${TS}
  namespace: default
spec:
  clusterName: $CLUSTER_NAME
  type: Expose
  expose:
    - componentName: <component>
      switch: Disable
      services:
        - name: internet
          serviceType: LoadBalancer
EOF
for i in {1..24}; do
  PHASE=$(kubectl get opsrequest expose-disable-${TS} -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$PHASE" == "Succeed" ]] && echo "✓ Expose Disable Succeed" && break
  sleep 5
done
```

**Approach B — Direct Service (for components WITHOUT roles, e.g. Elasticsearch):**

```bash
# Enable: create LB service using apps.kubeblocks.io/component-name label
COMPONENT=<component>   # e.g. master, data, mdit
SVC_NAME="${CLUSTER_NAME}-${COMPONENT}-internet"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${SVC_NAME}
  namespace: default
  labels:
    app.kubernetes.io/instance: ${CLUSTER_NAME}
    apps.kubeblocks.io/component-name: ${COMPONENT}
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/instance: ${CLUSTER_NAME}
    apps.kubeblocks.io/component-name: ${COMPONENT}
  ports:
    - name: <port-name>   # e.g. http
      port: <port>        # e.g. 9200
      targetPort: <port-name>
      protocol: TCP
EOF

# Wait for external IP
for ((i=0; i<120; i+=5)); do
  IP=$(kubectl get svc ${SVC_NAME} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [[ -n "$IP" ]] && echo "✓ LB ready: $IP" && break
  sleep 5
done

# Disable: delete the service
kubectl delete svc ${SVC_NAME}
echo "✓ LB removed"
```

#### Connect

```bash
# Get connection credential secret
kubectl get secret -l app.kubernetes.io/instance=$CLUSTER_NAME -o name
kubectl get secret <cluster-name>-<component>-account-root -o jsonpath='{.data.password}' \
  | base64 -d

# Engine-specific connection test (adapt per engine)
# MySQL example:
kubectl exec -it <pod-name> -- mysql -u root -p<password> -e "SELECT 1"
# PostgreSQL:
kubectl exec -it <pod-name> -- psql -U postgres -c "SELECT 1"
# Redis:
kubectl exec -it <pod-name> -- redis-cli PING
```

---

### Feature: Stress (Bench)

```bash
# Use kbcli bench or engine-specific tool
# MySQL / PostgreSQL example with sysbench via kbcli:
kbcli bench sysbench $CLUSTER_NAME --component <component> \
  --driver mysql --database mydb --tables 5 --table-size 10000 \
  --duration 30 --threads 8

# Test against LB service (if Expose was enabled):
kbcli bench sysbench $CLUSTER_NAME --component <component> \
  --driver mysql --host <lb-ip> --port 3306 \
  --duration 30 --threads 8
```

---

### Cleanup

```bash
kubectl delete cluster $CLUSTER_NAME
# terminationPolicy=Delete cleans up PVCs automatically
```

---

## Troubleshooting: OpsRequest Stuck or Cluster Abnormal

When an OpsRequest stays in `Running` indefinitely, or the cluster enters `Abnormal` phase with no obvious pod-level error, check the **KubeBlocks operator logs** — they surface controller-level errors that are invisible in pod events:

```bash
# Find the KB operator pod
kubectl get pods -n kb-system --no-headers | grep kubeblocks

# Search for errors related to your cluster
kubectl logs <kubeblocks-pod> -n kb-system --tail=500 \
  | grep -E "ERROR|build error|$CLUSTER_NAME" \
  | grep -v "replicas.*out-of-limit" \
  | tail -30

# Common patterns and their meanings:
# "replicas 0 out-of-limit [1, 16384]"  → a component's replicas was zeroed out
#   → likely caused by --type=merge patch on componentSpecs array
#   → fix: kubectl patch --type=json to restore correct replicas
#
# "not all component sub-resources deleted" → component is stuck deleting
#   → check for finalizers: kubectl get component <name> -o jsonpath='{.metadata.finalizers}'
#
# "OpsRequest is forbidden when Cluster.status.phase=Updating"
#   → wait for cluster to return to Running before submitting next OpsRequest
```

> **Rule: never use `--type=merge` on `spec.componentSpecs`.**
> It replaces the entire array, zeroing out replicas/resources/volumeClaimTemplates for every
> component not included in the patch body. Always use `--type=json` for any field inside `componentSpecs`.

---

## Final Report

Generate a report matching the official KubeBlocks regression report format:

```
## Instance Test Results

Engine: <engine> ( Topology = <topology> ; Replicas = <N> )
Component Definition: <cmpd-name>
Component Version: <cv-name>
Service Version: <version>

| Feature       | Operation               | State   | Description |
|---------------|-------------------------|---------|-------------|
| Lifecycle     | Create                  | PASSED  | Create a cluster with the specified topology <topology> with the specified component definition <cmpd-name> and service version <version> |
| Lifecycle     | Start                   | PASSED  | Start the cluster |
| Lifecycle     | Stop                    | PASSED  | Stop the cluster |
| Lifecycle     | Restart                 | PASSED  | Restart the cluster |
| Lifecycle     | Update                  | PASSED  | Update the cluster Monitor enable |
| Lifecycle     | Update                  | PASSED  | Update the cluster TerminationPolicy WipeOut |
| Scale         | VerticalScaling         | PASSED  | VerticalScaling the cluster specify component <component> |
| Scale         | VolumeExpansion         | PASSED  | VolumeExpansion the cluster specify component <component> |
| Scale         | HorizontalScaling In    | PASSED  | HorizontalScaling In the cluster specify component <component> |
| Scale         | HorizontalScaling Out   | PASSED  | HorizontalScaling Out the cluster specify component <component> |
| Scale         | RebuildInstance         | -       | Not implemented or unsupported |
| Upgrade       | Upgrade                 | PASSED  | Upgrade the cluster specify component <component> service version from <v1> to <v2> |
| SwitchOver    | SwitchOver              | PASSED  | SwitchOver the cluster specify component <component> |
| Failover      | Kill 1                  | PASSED  | Simulates conditions where process 1 killed ... |
| Failover      | Pod Kill                | PASSED  | Simulates conditions where pods experience kill ... |
| NoFailover    | Connection Stress       | PASSED  | Simulates conditions where pods experience connection stress ... |
| Backup Restore| Backup                  | PASSED  | The cluster <method> Backup |
| Backup Restore| Restore                 | PASSED  | The cluster <method> Restore |
| Backup Restore| Delete Restore Cluster  | PASSED  | Delete the <method> restore cluster |
| Parameter     | Reconfiguring           | PASSED  | Reconfiguring the cluster specify component <component> set <param>=<value> |
| Accessibility | Expose                  | PASSED  | Expose Enable the internet service with <component> component |
| Accessibility | Connect                 | PASSED  | Connect to the cluster |
| Stress        | Bench                   | PASSED  | Bench the cluster service with <component> component |

### Conclusion
All implemented operations: PASSED
Not implemented or unsupported: <list operations marked "-">
Images not yet in registry: <list any skipped versions>
```

State values:
- `PASSED` — operation completed successfully
- `FAILED` — operation attempted but did not succeed
- `SKIPPED` — precondition not met (e.g., image missing, ChaosMesh not installed)
- `-` — Not implemented or unsupported (engine/topology does not support this operation)

---

## Filing Issues

When a test case FAILs due to a bug in the addon or its dependencies, file a GitHub issue at `https://github.com/apecloud/kubeblocks-addons/issues`.

### Labels

Apply exactly one primary label:

| Label | When to use |
|---|---|
| `Bug` | Something is broken — wrong behavior, crash, error |
| `Feature` | New capability that does not exist yet |
| `Improvement` | Existing feature works but could be better (performance, UX, coverage) |
| `Chore` | Maintenance, dependency update, CI, cleanup |
| `Document` | Documentation missing or incorrect |

```bash
# Example: file a Bug and assign to a maintainer
gh issue create \
  --repo apecloud/kubeblocks-addons \
  --title "bug: <engine> <operation> fails with <error>" \
  --label "Bug" \
  --assignee <github-username> \
  --body "$(cat <<'EOF'
## Summary
<one-line description>

## Trigger Path
<exact call chain that reproduces the error>

## Root Cause
<what is actually wrong>

## Fix
<suggested fix>

## Workaround
<how to avoid the issue until it is fixed, if any>
EOF
)"
```
