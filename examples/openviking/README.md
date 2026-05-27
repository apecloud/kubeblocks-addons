# OpenViking on KubeBlocks

[OpenViking](https://github.com/volcengine/OpenViking) is an open-source RAG
and semantic search engine that serves as a Context Database MCP (Model
Context Protocol) server.

This directory contains example manifests for running OpenViking via the
KubeBlocks `openviking` addon.

## Prerequisites

- A Kubernetes cluster with KubeBlocks `>= 1.0.0` installed.
- The `openviking` addon installed:
  ```bash
  helm dependency update ../../addons/openviking
  helm upgrade --install kb-addon-openviking ../../addons/openviking -n kb-system
  ```

## Create the cluster

```bash
kubectl create namespace demo
kubectl -n demo apply -f cluster.yaml
```

OpenViking is a single-node service: the underlying RocksDB store does not
support multiple pods sharing the same PVC. `replicas` must remain `1`.

## Day-2 operations

| Action          | Manifest                       |
|-----------------|--------------------------------|
| Stop cluster    | `stop.yaml`                    |
| Start cluster   | `start.yaml`                   |
| Restart cluster | `restart.yaml`                 |
| Vertical scale  | `verticalscale.yaml`           |
| Volume expand   | `volumeexpand.yaml`            |
| Reconfigure     | `configure.yaml`               |
| Reconfigure log | `reconfigure-loglevel.yaml`    |

Apply any of them with:

```bash
kubectl -n demo apply -f restart.yaml
```

## Access the API

```bash
kubectl -n demo port-forward svc/openviking-cluster-openviking-http 1933:1933
curl http://localhost:1933/health
```
