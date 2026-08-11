# KubeBlocks for Microsoft SQL Server

Microsoft SQL Server is a relational database management system developed by Microsoft. It is a powerful, scalable, and secure relational database management system (RDBMS) designed for enterprise grid computing and data warehousing.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+
- KubeBlocks installed and running
- Valid KubeBlocks Enterprise License Agreement

## Installation

```bash
helm install mssql mssql-<version>.tgz \
  --namespace kb-system \
  --create-namespace
```

## Uninstallation

```bash
helm uninstall mssql --namespace kb-system
```

## License

This chart is part of **KubeBlocks Enterprise Addons**, proprietary software
owned by ApeCloud Co., Ltd. A valid license is required to install and use
this software.

Full terms: [LICENSE](./LICENSE)
Licensing inquiries: support@apecloud.com
