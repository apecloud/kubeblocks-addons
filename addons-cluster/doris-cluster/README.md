<!--- app-name: doris-2.0.3 -->

# doris-2.0.3 By KubeBlocks

Apache Doris is an easy-to-use, high-performance and real-time analytical database based on MPP architecture, known for its extreme speed and ease of use. It only requires a sub-second response time to return query results under massive data and can support not only high-concurrent point query scenarios but also high-throughput complex analysis scenarios.

## TL;DR

```bash
$ helm repo add my-repo http://172.16.48.10:28081/chartrepo/helm-chart
$ helm install my-release my-repo/kb-doris-2.0.3
```

## Introduction

This chart bootstraps a Doris deployment on a Kubernetes cluster using the Helm package manager and KubeBlocks.

## Prerequisites
- Helm 3.2.0+
- Kubernetes 1.22.0
- PV provisioner support in the underlying infrastructure

## Installing the Chart

```bash
$ helm install my-release my-repo/kb-doris-2.0.3
```

## Uninstalling the Chart

```bash
$ helm delete my-release
```

