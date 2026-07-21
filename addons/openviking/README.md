# OpenViking Addon for KubeBlocks

This Helm chart packages [OpenViking](https://github.com/volcengine/OpenViking)
as a [KubeBlocks](https://kubeblocks.io/) addon.

OpenViking is an open-source RAG and semantic search engine that serves as a
Context Database MCP (Model Context Protocol) server.

## What this addon provides

- A `ComponentDefinition` (`openviking-0-<chartVersion>`) describing how to run
  the `openviking-server` process inside KubeBlocks.
- A `ComponentVersion` (`openviking`) mapping OpenViking service versions to
  container images.
- A configuration template (rendered into a `ConfigMap`) that produces
  `ov.conf` for the running pod, mounted at `/etc/openviking/ov.conf`.
  The file is rendered as JSON, which is the format `openviking-server` loads.
- A `ParametersDefinition` (`openviking-pd`) that exposes every field of
  `ov.conf` as a typed, validated KubeBlocks parameter, so configuration can
  be changed at day-2 with an `OpsRequest` of type `Reconfiguring`.
- A persistent data volume mounted at `/app/data` for the RocksDB-backed
  workspace.
- An HTTP service exposing the OpenViking API on port `1933`, with `/health`
  and `/ready` probes wired into the pod.

## Topology

OpenViking is a single-node service: the underlying RocksDB store does not
support multiple pods sharing the same PVC. The addon therefore uses
`updateStrategy: Serial` and the matching cluster chart pins `replicas: 1`.

## Install

```bash
# from the repo root
helm dependency update addons/openviking
helm upgrade --install kb-addon-openviking addons/openviking -n kb-system

# then create a cluster
helm upgrade --install ov-demo addons-cluster/openviking -n default \
  --set 'config.embedding.dense.api_key=YOUR_VOLCENGINE_KEY' \
  --set 'config.vlm.api_key=YOUR_VOLCENGINE_KEY'
```

## Versions

| Chart version | OpenViking appVersion |
|---------------|-----------------------|
| 0.1.0         | 0.3.12                |

## Reconfigure (day-2)

`ov.conf` is exposed as a KubeBlocks parameter set through the
`openviking-pd` `ParametersDefinition`. Parameters use **dot-paths** that mirror
the JSON layout of `ov.conf`. A change is applied with an `OpsRequest` of type
`Reconfiguring` against the configuration template `openviking-config`.

Example — change the embedding/VLM endpoints and the log level:

```yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ov-reconfigure
spec:
  clusterName: ov-demo
  type: Reconfiguring
  reconfigures:
    - componentName: openviking
      parameters:
        - key: embedding.dense.model
          value: doubao-embedding-large-text-240915
        - key: embedding.dense.api_key
          value: NEW_KEY
        - key: vlm.model
          value: doubao-1-5-vision-pro-250328
        - key: log.level
          value: DEBUG
      configItemDetails:
        - name: openviking-config
```

See `examples/openviking/configure.yaml` and
`examples/openviking/reconfigure-loglevel.yaml` for ready-to-apply manifests.

### Tunable parameters

All keys are declared as **static** in the `ParametersDefinition`: KubeBlocks
will rewrite the `ConfigMap` and trigger a pod restart for the change to take
effect (RocksDB workspace is preserved on the PVC).

| Section     | Keys (dot-path)                                                                                                  |
|-------------|------------------------------------------------------------------------------------------------------------------|
| `storage.*` | `storage.workspace`                                                                                              |
| `log.*`     | `log.level`, `log.output`                                                                                       |
| `server.*`  | `server.host`, `server.port`, `server.workers`, `server.root_api_key`, `server.cors_origins`                    |
| `embedding.*` | `embedding.dense.api_base`, `embedding.dense.api_key`, `embedding.dense.provider`, `embedding.dense.dimension`, `embedding.dense.model`, `embedding.dense.input`, `embedding.max_concurrent` |
| `vlm.*`     | `vlm.api_base`, `vlm.api_key`, `vlm.provider`, `vlm.model`, `vlm.temperature`, `vlm.max_retries`, `vlm.thinking`, `vlm.max_concurrent` |

Value constraints (enums, ranges) are enforced by the cue schema in
`config/ov-config-constraint.cue`; invalid `OpsRequest` payloads will be
rejected by the KubeBlocks parameter controller before any pod is restarted.
