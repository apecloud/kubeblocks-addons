# KubeBlocks for Kblib

A Library Helm chart used for building the foundation of common utilities for KubeBlocks Addons, including various common script tools, configuration template definitions, etc.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+
- KubeBlocks installed and running
- Valid KubeBlocks Enterprise License Agreement

## Installation

```bash
helm install kblib kblib-<version>.tgz \
  --namespace kb-system \
  --create-namespace
```

## Uninstallation

```bash
helm uninstall kblib --namespace kb-system
```

## License

This chart is part of **KubeBlocks Enterprise Addons**, proprietary software
owned by ApeCloud Co., Ltd. A valid license is required to install and use
this software.

Full terms: [LICENSE](./LICENSE)
Licensing inquiries: support@apecloud.com
