# ClickHouse

ClickHouse is an open-source column-oriented OLAP database management system. Use it to boost your database performance while providing linear scalability and hardware efficiency.

There are two key components in the ClickHouse cluster:

- ClickHouse Server: The ClickHouse server is responsible for processing queries and managing data storage.
- ClickHouse Keeper: The ClickHouse Keeper is responsible for monitoring the health of the ClickHouse server and performing failover operations when necessary, alternative to the Zookeeper.

## Features In KubeBlocks

### Lifecycle Management

#### ClickHouse Server

| Topology           | Horizontal scaling | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose | Switchover |
| ------------------ | ------------------ | ---------------- | ------------- | ------- | ---------- | --------- | ------ | ---------- |
| standalone/cluster | Yes                | Yes              | Yes           | Yes     | Yes        | Yes       | Yes    | N/A        |

#### ClickHouse Keeper

| Topology | Horizontal scaling | Vertical scaling | Expand volume | Restart | Stop/Start | Configure | Expose | Switchover |
| -------- | ------------------ | ---------------- | ------------- | ------- | ---------- | --------- | ------ | ---------- |
| cluster  | Yes                | Yes              | Yes           | Yes     | Yes        | Yes       | N/A    | Yes        |

### Backup and Restore

| Feature     | Method | Description |
|-------------|--------|------------|
| Full Backup | clickhouse-backup | uses `clickhouse-backup` tool to perform full backups of ClickHouse data |
| Incremental Backup | clickhouse-backup | uses `clickhouse-backup` tool to perform incremental backups based on previous backup |


### Versions

| Major Versions | Description     |
| -------------- | --------------- |
| 22             | 22.3.18, 22.3.20, 22.8.21 |
| 24             | 24.8.3          |
| 25             | 25.4.4          |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- ClickHouse Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create

#### Standalone Mode

Create a ClickHouse cluster with only ClickHouse server:

```yaml
# cat examples/clickhouse/cluster-standalone.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: clickhouse-standalone
  namespace: demo
spec:
  # Specifies the name of the ClusterDef to use when creating a Cluster.
  clusterDef: clickhouse
  # Specifies the clickhouse cluster topology defined in ClusterDefinition.Spec.topologies, support standalone, cluster
  # - `standalone`: single clickhouse instance
  # - `cluster`: clickhouse with ClickHouse Keeper as coordinator
  topology: standalone
  # Specifies the behavior when a Cluster is deleted.
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the individual components that make up a Cluster. This field allows for detailed configuration of each component within the Cluster.
  # Note: `shardingSpecs` and `componentSpecs` cannot both be empty; at least one must be defined to configure a cluster.
  # ClusterComponentSpec defines the specifications for a Component in a Cluster.
  componentSpecs:
    - name: clickhouse
      replicas: 1
      systemAccounts:
        - name: admin
          secretRef:
            name: udf-account-info
            namespace: demo
      resources:
        limits:
          cpu: '0.5'
          memory: 1Gi
        requests:
          cpu: '0.5'
          memory: 1Gi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: udf-account-info
  namespace: demo
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=  # 'password123' in base64

```

```bash
kubectl apply -f examples/clickhouse/cluster-standalone.yaml
```

It will create only one ClickHouse server pod with the default configuration. This example includes a predefined secret `udf-account-info` with password `password123`.

To connect to the ClickHouse server, you can use the following command:

```bash
clickhouse-client --host <clickhouse-endpoint> --port 9000 --user admin --password
```

> [!NOTE]
> The password is defined in the secret `udf-account-info` or you can find it in `<clusterName>-clickhouse-account-admin`.

e.g. you can get the password by the following command:

```bash
# For the standalone cluster
kubectl get secrets clickhouse-standalone-clickhouse-account-admin -n demo -oyaml  | yq .data.password -r | base64 -d

# Or from the predefined secret
kubectl get secrets udf-account-info -n demo -oyaml  | yq .data.password -r | base64 -d
```

where the secret name follows the pattern `<clusterName>-<componentName>-account-<accountName>`.

#### Cluster Mode

Create a ClickHouse cluster with ClickHouse servers and ch-keeper. The default cluster configuration includes sharding with 2 shards, each shard having 2 replicas:

```yaml
# cat examples/clickhouse/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: clickhouse-cluster
  namespace: demo
spec:
  # Specifies the name of the ClusterDef to use when creating a Cluster.
  clusterDef: clickhouse
  # Specifies the clickhouse cluster topology defined in ClusterDefinition.Spec.topologies.
  # - `standalone`: single clickhouse instance
  # - `cluster`: clickhouse with ClickHouse Keeper as coordinator
  topology: cluster
  # Specifies the behavior when a Cluster is deleted.
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the individual components that make up a Cluster. This field allows for detailed configuration of each component within the Cluster.
  # Note: `shardingSpecs` and `componentSpecs` cannot both be empty; at least one must be defined to configure a cluster.
  # ClusterComponentSpec defines the specifications for a Component in a Cluster.
  componentSpecs:
    - name: ch-keeper
      componentDef: clickhouse-keeper-1
      replicas: 1
      resources:
        limits:
          cpu: '0.5'
          memory: 1Gi
        requests:
          cpu: '0.5'
          memory: 1Gi
      systemAccounts:
        - name: admin
          secretRef:
            name: udf-account-info
            namespace: demo
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 10Gi
  shardings:
    - name: clickhouse
      shards: 2 # with 2 shard
      template:
        name: clickhouse  # each shard is a clickhouse component, with 2 replicas
        componentDef: clickhouse-1
        replicas: 2
        systemAccounts:
          - name: admin # name of the system account
            secretRef:
              name: udf-account-info
              namespace: demo
        resources:
          limits:
            cpu: "1"
            memory: 2Gi
          requests:
            cpu: "1"
            memory: 2Gi
        volumeClaimTemplates:
          - name: data
            spec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 20Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: udf-account-info
  namespace: demo  # optional
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=  # 'password123' in base64
```

```bash
kubectl apply -f examples/clickhouse/cluster.yaml
```

This example creates a cluster with:
- 1 ClickHouse Keeper instance for coordination (`ch-keeper` component using `clickhouse-keeper-1` ComponentDef)
- 2 shards with 2 replicas each (total 4 ClickHouse server instances using `clickhouse-1` ComponentDef)
- Shows how to override the default accounts' password using a predefined secret

Option 1. override the rule `passwordConfig` to generate password

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: ch-keeper
      replicas: 1
      # Overrides system accounts defined in referenced ComponentDefinition.
      systemAccounts:
        - name: admin # name of the system account
          passwordConfig: # config rule to generate  password
            length: 10
            numDigits: 5
            numSymbols: 0
            letterCase: MixedCases
            seed: clickhouse-cluster
```

Option 2. specify the secret for the account

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: ch-keeper
      replicas: 1
      # Overrides system accounts defined in referenced ComponentDefinition.
      systemAccounts:
        - name: admin # name of the system account
          secretRef:
            name: udf-account-info
            namespace: demo
  shardings:
    - name: clickhouse
      shards: 2
      template:
        name: clickhouse
        replicas: 2
        systemAccounts:
          - name: admin
            secretRef:
              name: udf-account-info
              namespace: demo
```

The secret `udf-account-info` is automatically created with the cluster and contains:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: udf-account-info
  namespace: demo
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=  # 'password123' in base64
```

#### Cluster Mode with TLS Enabled

To create one ClickHouse server pod with the default configuration and TLS enabled.

```yaml
# cat examples/clickhouse/cluster-tls.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: clickhouse-tls
  namespace: demo
spec:
  # Specifies the name of the ClusterDef to use when creating a Cluster.
  clusterDef: clickhouse
  # Specifies the clickhouse cluster topology defined in ClusterDefinition.Spec.topologies.
  # - `standalone`: single clickhouse instance
  # - `cluster`: clickhouse with ClickHouse Keeper as coordinator
  topology: cluster
  # Specifies the behavior when a Cluster is deleted.
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the individual components that make up a Cluster. This field allows for detailed configuration of each component within the Cluster.
  # Note: `shardingSpecs` and `componentSpecs` cannot both be empty; at least one must be defined to configure a cluster.
  # ClusterComponentSpec defines the specifications for a Component in a Cluster.
  componentSpecs:
    - name: ch-keeper
      componentDef: clickhouse-keeper-1
      replicas: 1
      resources:
        limits:
          cpu: '0.5'
          memory: 1Gi
        requests:
          cpu: '0.5'
          memory: 1Gi
      systemAccounts:
        - name: admin
          secretRef:
            name: udf-account-info
            namespace: demo
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 10Gi
      tls: true   # set TLS to true for keeper
      issuer:     # if TLS is True, this filed is required.
        name: UserProvided  # set Issuer to UserProvided, P.S. KubeBlocks Issuer is unable for sharding typology.
        secretRef:
          name: clickhouse-cluster-tls
          namespace: demo
          ca: ca.crt
          cert: tls.crt
          key: tls.key
  shardings:
    - name: clickhouse
      shards: 1
      template:
        name: clickhouse
        componentDef: clickhouse-1
        replicas: 2
        systemAccounts:
          - name: admin
            secretRef:
              name: udf-account-info
              namespace: demo
        resources:
          limits:
            cpu: '1'
            memory: 2Gi
          requests:
            cpu: '1'
            memory: 2Gi
        volumeClaimTemplates:
          - name: data
            spec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 20Gi
        tls: true # set TLS to true
        issuer: # if TLS is True, this filed is required.
          name: UserProvided  # set Issuer to UserProvided, P.S. KubeBlocks Issuer is unable for sharding typology.
          secretRef:
            name: clickhouse-cluster-tls
            namespace: demo
            ca: ca.crt
            cert: tls.crt
            key: tls.key
---
apiVersion: v1
kind: Secret
metadata:
  name: udf-account-info
  namespace: demo
type: Opaque
data:
  password: cGFzc3dvcmQxMjM= # 'password123' in base64
---
# pre generated tls secret
apiVersion: v1
kind: Secret
metadata:
  name: clickhouse-cluster-tls
  namespace: demo
type: Opaque
stringData:
  ca.crt: |
    -----BEGIN CERTIFICATE-----
    MIIDDTCCAfWgAwIBAgIUO9i4NfSWZ6WsJV0iRUgnd6TdEBwwDQYJKoZIhvcNAQEL
    BQAwFTETMBEGA1UEAwwKS3ViZUJsb2NrczAgFw0yNTA4MTkwODM1NTRaGA8yMTI1
    MDcyNjA4MzU1NFowFTETMBEGA1UEAwwKS3ViZUJsb2NrczCCASIwDQYJKoZIhvcN
    AQEBBQADggEPADCCAQoCggEBANATB/zvCOxh7uMmAs7ZvaKdVnoDaWieEe8dmBdi
    i+RXGbBqK0vlXY1VNTBAXblVZAdJJIKqnVXOy9N0A5puRUYSv5vAx8YRLf/wc0n3
    nx23Uhsf5ltg31BviyEAXdeF0HPqiZ5CEmF4FZreuC6L9+qsJLj3eJEeX3/dLIY/
    vndTV9xmLJKlLihoIhPv0pTNuAhCQ6IEXLrTDi9yX7qhp68wdZUwWhaVVOrgZDh+
    wFMG8CGdnAhRlvJywHs04D6nSz18yEBOe3bs0wojhZ5/6oyMHZfQaLYIT2de9Pkq
    UWZ6MtPWHmUGFDJtbshO112OUdex7qj6cUQbOnDYDmJCIXcCAwEAAaNTMFEwHQYD
    VR0OBBYEFBIsXVPpBuEpCSZGsi+0dDfum33bMB8GA1UdIwQYMBaAFBIsXVPpBuEp
    CSZGsi+0dDfum33bMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEB
    AMmzmkpsUPQqE/aBCXKUN+6Pa+201XM9KmsUPxRdZEHVVZOXIzYFq/m1TPRvjL2T
    Fk2Foazu3mcnJkWYWZuVkBymCRvF1oWct0mP0SBOljrI37m2GQoZ4KviqhFaCiX6
    a3/IBBY6jLnt2ITBxRKetyZlGZvAkpuuKvwX0r363wVH0lkfg7ckhXuUGFl1UUL+
    EzJLG+7BAN8SHs1slopTNZmoBROq0KNHzSrHzchBZwB4XjhHxjbmde0WKf8i9foC
    mPgPyAQw7GjRYEDwbiVp3sXrl0SCWCeOhsZROYh7FxAqT5hAn11b4YpBeOa0fhLB
    L674jxJcLVvhS87M6MCnTuY=
    -----END CERTIFICATE-----
  tls.crt: |
    -----BEGIN CERTIFICATE-----
    MIIDjTCCAnWgAwIBAgIUON/zD6nQWQkXu38Wk/GRxxPDswMwDQYJKoZIhvcNAQEL
    BQAwFTETMBEGA1UEAwwKS3ViZUJsb2NrczAgFw0yNTA4MTkwODM1NTRaGA8yMTI1
    MDcyNjA4MzU1NFowFTETMBEGA1UEAwwKY2xpY2tob3VzZTCCASIwDQYJKoZIhvcN
    AQEBBQADggEPADCCAQoCggEBALNRYLXK15aBYZ52ORhd5YT//q0EZ2cG72sRI8T+
    KC2Kn0yLDxJhpXw3q8rpC0sBQUfNJBbEuilobjZoEqd31LqaMSMzBV5svzhScDor
    lkKsIdm1nCavCYyisJTE0va+rS+7Ti+rdDdQBkvoZ02xSM6leNrdyEnDvojAmsqu
    Y2gI9UEzP/ESSiGi1Jn6VG1xZ3jLxGS0F6OeShZYPGYZ95hHQyG6SP8wmS3ERF5h
    2OV3bgmKdDTmYP7VKC3pqzB8Q6E310hPB1mXPfev9VNzEsE0hkGF7DGfT+IFfEur
    VTRiaz/DC0jM2wOzWbJEQqYGzXaYH4smQHvhwetpwGNhymcCAwEAAaOB0jCBzzCB
    jAYDVR0RBIGEMIGBgglsb2NhbGhvc3SCDyouY2x1c3Rlci5sb2NhbIIfKi5jbGlj
    a2hvdXNlLWNsdXN0ZXItY2xpY2tob3VzZYIeKi5jbGlja2hvdXNlLWNsdXN0ZXIt
    Y2gta2VlcGVyggpjbGlja2hvdXNlhwR/AAABhxAAAAAAAAAAAAAAAAAAAAABMB0G
    A1UdDgQWBBTfVj9MCyWaGYqWgNoEH0oty8EyEzAfBgNVHSMEGDAWgBQSLF1T6Qbh
    KQkmRrIvtHQ37pt92zANBgkqhkiG9w0BAQsFAAOCAQEAc8gJJWOIm6IXvFcKFCny
    EbQhDRVaqW44o3DmQBlvK3oqYyeRRoVIaxYkxKM6VPNaapEd46Pa+qcZ0widXQjI
    VfsgtAtJOW3vmdu375o9gfqy94YAWRR8i5u887OWs9LRWVMZQ7js7J98KVBxMFZ/
    xd9Fa87pB9VcljS56/KjQ3fnQYp2qZvV3GaeEwPTZfqOzfUxRQqLtO6SUiwAZkgg
    awEgkRUVlrr6IOQs9rJzC1yPdmvS8n90gPi2cfNVEBznzOyLVPVxgZtXwuGxaPkH
    ptmkFBDDNwELkuJ6csEcoeae3Wcm/MwXMjIwvNF3JyKOHeIJ43fWKEc1YRNeYOB5
    NQ==
    -----END CERTIFICATE-----
  tls.key: |
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCzUWC1yteWgWGe
    djkYXeWE//6tBGdnBu9rESPE/igtip9Miw8SYaV8N6vK6QtLAUFHzSQWxLopaG42
    aBKnd9S6mjEjMwVebL84UnA6K5ZCrCHZtZwmrwmMorCUxNL2vq0vu04vq3Q3UAZL
    6GdNsUjOpXja3chJw76IwJrKrmNoCPVBMz/xEkohotSZ+lRtcWd4y8RktBejnkoW
    WDxmGfeYR0Mhukj/MJktxEReYdjld24JinQ05mD+1Sgt6aswfEOhN9dITwdZlz33
    r/VTcxLBNIZBhewxn0/iBXxLq1U0Yms/wwtIzNsDs1myREKmBs12mB+LJkB74cHr
    acBjYcpnAgMBAAECggEANWvukGpMXRHRh9h3vQsoOD3d3SS9O4Pk6vRRwDvps1uj
    hrW8+UBvATlCrHJOQ3utu5rhgAj+3xw2DW5m9E5uaWNLdU2bcVybgUeKGMJogxdu
    BEKnMR0fjq7fRYr3wLvgs6ItMmV1e48TOSUVNZ+17Z59iVLeex9eUbZzxyM6CUF1
    3/zWQD+s4clbDgWgAZCJdEB095nPNnXhkdr/jwcHv8SbpVKUpHlEvfuZjI3gK2MJ
    tJx4xGUyaHU+CVBEp4LYWSs8z6Z6E+M7hEPpfFBZKm/52oYEbdMJjANAGXhB30LL
    HjYRQcqqAiv+3RCklwEH/+Kt0sjKHLn+oEd/V66SzQKBgQDoOacnXI9+977sK6uX
    ynbHUWTo3GFvooWItAVVFxnUYH00+lN0ddXzjHPQqwkHBPoi9bePEfQJjK9FpOtz
    OaX5DtY2McU39ZuU0g96bs4AHHQq/98HTFa6BqN9IP5qGaCeoTtPhafsZkwa1h87
    iCR8vpRmrE+amj7pgwuCEFLdLQKBgQDFrRYt2KJF7eT42S98FBtA/5AeByR4/sSk
    rD80TONtAcBLc8E/yi+ro3kkz9OdZM3CPc/Sa9d/dfsvxo4geIt9n0ThzW4aH2Xo
    BjmnkYMWZXWOiVQy9Vo3PfdMbmZBON2u16swH8r0mJClN0O4Z7OVxdhW2P7nACb7
    Ek7DcgyKYwKBgQDj90y24C9hlbUPxKLzJGbLrYRg746a9zEdDJO7fyz1Bi+DZUWt
    qst4BWXf7zaydFlVHl+ujBJDmZ6pwIb+GxZqUv1IQD15fJrZUgityL5i74u+dmYr
    lO4COegeOthlsXiyoFZH7030TEvjgFUyrKgc6T1nOTn/6/FcbC9M49dklQKBgQCw
    l68vp89X721VThjYnNG4IFbsLG9N1DNx9RrFq0ak1CKohTGHviUWDYUk+LDQdARI
    2ZV2IrcyfAC5LoU7xtS+lfEgU7hfh9svC5in9RuJf3wkqNRabct5fFcXpayd6aJJ
    Fwwsgsp59m2J2zQZYjMRwtxAwbv+O6mXNES+330KhwKBgCqZ6RFkyf/pjueoRGCP
    qb2WDHvRhkFlHsh/o0scxXiGToiTgi/Yc41Dg6xJMRuPtt+L/sezXmq6H2evX+qg
    Lv4A0A0slfWLy5WFUqa3JNIzmDEeugaHGGyeJoKXZz5Hrjeq+JEL1FsiMhCYwrl8
    jE0KUAC77WR5lWODcvXAmD58
    -----END PRIVATE KEY-----
```

```bash
kubectl apply -f examples/clickhouse/cluster-tls.yaml
```

Compared to the default configuration, the only difference is the `tls` and `issuer` fields in the `cluster-tls.yaml` file.

```yaml
tls: true  # enable tls
issuer:    # set issuer information
  name: KubeBlocks
```

To connect to the ClickHouse server, you can use the following command:

```bash
clickhouse-client --host <clickhouse-endpoint>  --port 9440 --secure  --user admin --password
```


### Horizontal scaling

#### Scale-out

Horizontal scaling out Clickhouse by adding ONE more replica:

```yaml
# cat examples/clickhouse/scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ch-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: clickhouse
    # Specifies the replica changes for scaling out components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/clickhouse/scale-out.yaml
```

#### Scale-out Sharding

Horizontal scaling out ClickHouse by adding ONE more shard (from 2 shards to 3 shards):

```yaml
# cat examples/clickhouse/scale-out-sharding.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ch-scale-out-sharding
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component,
  # including desired replica changes, configurations for new instances,
  # modifications for existing instances, and take offline/online the specified instances.
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: clickhouse
    # Specifies the desired number of shards for the component.
    # This parameter is mutually exclusive with other parameters.
    # This will scale out from 2 shards to 3 shards (as defined in cluster.yaml)
    shards: 3
```

```bash
kubectl apply -f examples/clickhouse/scale-out-sharding.yaml
```

This operation increases the number of shards in the ClickHouse cluster, which provides better data distribution and query performance for large datasets.

> [!IMPORTANT]
> **Post Scale-out Processing Required**: After scaling out shards, you need to copy database and table schemas to new shards using the post-processing operation:
>
> ```bash
> kubectl apply -f examples/clickhouse/post-scale-out-shard.yaml
> ```
>
> This operation copies all existing database schemas and table structures from old shards to the new shards.

#### Scale-in

Horizontal scaling in Clickhouse by deleting ONE replica:

```yaml
# cat examples/clickhouse/scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ch-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: clickhouse
    # Specifies the replica changes for scaling out components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 1
```

```bash
kubectl apply -f examples/clickhouse/scale-in.yaml
```

#### Scale-in Sharding

Horizontal scaling in ClickHouse by removing ONE shard (from 3 shards back to 2 shards):

```yaml
# cat examples/clickhouse/scale-in-sharding.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ch-scale-in-sharding
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component,
  # including desired replica changes, configurations for new instances,
  # modifications for existing instances, and take offline/online the specified instances.
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: clickhouse
    # Specifies the desired number of shards for the component.
    # This parameter is mutually exclusive with other parameters.
    # This will scale in from 3 shards back to 2 shards (original configuration)
    shards: 2
```

```bash
kubectl apply -f examples/clickhouse/scale-in-sharding.yaml
```

> [!WARNING]
> Scaling in shards will permanently remove data from the removed shards. Make sure to backup or redistribute data before scaling in.

#### Post Scale-out Shard Processing

Copy database and table schemas to new shards after shard scale-out:

```yaml
# cat examples/clickhouse/post-scale-out-shard.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ch-post-scale-out-shard
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Custom
  # Custom operation to trigger post-processing after shard scale-out
  custom:
    opsDefinitionName: post-scale-out-shard-for-clickhouse
    components:
    - componentName: clickhouse
```

```bash
kubectl apply -f examples/clickhouse/post-scale-out-shard.yaml
```

This operation should be run after scaling out shards to ensure new shards have the same database schemas and table structures as existing shards.

#### Keeper-Scale-out

Horizontal scaling out Clickhouse Keeper by adding TWO more replica:

```yaml
# cat examples/clickhouse/keeper-scale-out.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ch-scale-out
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the name of the Component.
  - componentName: ch-keeper
    # Specifies the replica changes for scaling out components
    scaleOut:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 2 
```

```bash
kubectl apply -f examples/clickhouse/keeper-scale-out.yaml
```

#### Keeper-Scale-in

Horizontal scaling in Clickhouse Keeper by deleting TWO replica:

```yaml
# cat examples/clickhouse/keeper-scale-in.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ch-scale-in
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: HorizontalScaling
  # Lists HorizontalScaling objects, each specifying scaling requirements for a Component, including desired total replica counts, configurations for new instances, modifications for existing instances, and instance downscaling options
  horizontalScaling:
    # Specifies the ame of the Component.
  - componentName: ch-keeper
    # Specifies the replica changes for scaling out components
    scaleIn:
      # Specifies the replica changes for the component.
      # add one more replica to current component
      replicaChanges: 2 
```

```bash
kubectl apply -f examples/clickhouse/keeper-scale-in.yaml
```

#### Scale-in/out using Cluster API

Alternatively, you can update the `replicas` field in the `spec.componentSpecs.replicas` section to your desired non-zero number.

```yaml
# snippet of cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
spec:
  componentSpecs:
    - name: clickhouse
      replicas: 2 # Update `replicas` to 1 for scaling in, and to 3 for scaling out
```

### Vertical scaling

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```yaml
# cat examples/clickhouse/verticalscale.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: clickhouse-verticalscaling
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: VerticalScaling
  # Lists VerticalScaling objects, each specifying a component and its desired compute resources for vertical scaling.
  verticalScaling:
    # Specifies the name of the Component.
    # - clickhouse
    # - ch-keeper
  - componentName: clickhouse
    # VerticalScaling refers to the process of adjusting the compute resources (e.g., CPU, memory) allocated to a Component. It defines the parameters required for the operation.
    requests:
      cpu: '1'
      memory: '2Gi'
    limits:
      cpu: '1'
      memory: '2Gi'

```

```bash
kubectl apply -f examples/clickhouse/verticalscale.yaml
```

### Switchover for Clickhouse Keeper

#### Switchover without preferred candidates

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/clickhouse/keeper-switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: keeper-switchover
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: ch-keeper
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: "clickhouse-cluster-ch-keeper-0"

```

```yaml
# cat examples/clickhouse/keeper-switchover.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: keeper-switchover
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: ch-keeper
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: "clickhouse-cluster-ch-keeper-0"
```

```bash
kubectl apply -f examples/clickhouse/keeper-switchover.yaml
```

#### Switchover-specified-instance

Switchover a specified instance as the new primary or leader of the cluster

```yaml
# cat examples/clickhouse/keeper-switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: keeper-switchover
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: ch-keeper
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: "clickhouse-cluster-ch-keeper-0"
    # Specifies the instance that will become the new leader, if not specify, the first non leader instance will become candidate.
    # Need to ensure the candidate instance is catch up logs of the quorum, otherwise the switchover will transfer the leader to other instance.
    candidateName: "clickhouse-cluster-ch-keeper-1"

```

```yaml
# cat examples/clickhouse/keeper-switchover-specified-instance.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: keeper-switchover
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Switchover
  # Lists Switchover objects, each specifying a Component to perform the switchover operation.
  switchover:
    # Specifies the name of the Component.
  - componentName: ch-keeper
    # Specifies the instance whose role will be transferred.
    # A typical usage is to transfer the leader role in a consensus system.
    instanceName: "clickhouse-cluster-ch-keeper-0"
    # Specifies the instance that will become the new leader, if not specify, the first non leader instance will become candidate.
    # Need to ensure the candidate instance is catch up logs of the quorum, otherwise the switchover will transfer the leader to other instance.
    candidateName: "clickhouse-cluster-ch-keeper-1"
```

```bash
kubectl apply -f examples/clickhouse/keeper-switchover-specified-instance.yaml
```

You may need to update the `opsrequest.spec.switchover.instanceName` field to your desired instance name.

### Expand volume

> [!NOTE]
> Make sure the storage class you use supports volume expansion.

Check the storage class with following command:

```bash
kubectl get storageclass
```

If the `ALLOWVOLUMEEXPANSION` column is `true`, the storage class supports volume expansion.

Increase size of volume storage with the specified components in the cluster

```yaml
# cat examples/clickhouse/volumeexpand.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: clickhouse-volumeexpansion
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: VolumeExpansion
  # Lists VolumeExpansion objects, each specifying a component and its corresponding volumeClaimTemplates that requires storage expansion.
  volumeExpansion:
    # Specifies the name of the Component.
    # - clickhouse
    # - ch-keeper
  - componentName: clickhouse
    # volumeClaimTemplates specifies the storage size and volumeClaimTemplate name.
    volumeClaimTemplates:
      # A reference to the volumeClaimTemplate name from the cluster components.
    - name: data
      storage: 30Gi

```

```bash
kubectl apply -f examples/clickhouse/volumeexpand.yaml
```

### Reconfigure

> [!NOTE]
> This reconfigure section is applicable for ClickHouse Addons v1.0.1.
> Those who are using ClickHouse Addons v1.0.2 and above, please refer to [Using Config Templates](../addons/clickhouse/README.md#using-config-templates) for more details.


Reconfigure parameters with the specified components in the cluster

```yaml
# cat examples/clickhouse/configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: ch-reconfiguring
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  # Instructs the system to bypass pre-checks (including cluster state checks and customized pre-conditions hooks) and immediately execute the opsRequest, except for the opsRequest of 'Start' type, which will still undergo pre-checks even if `force` is true.  Note: Once set, the `force` field is immutable and cannot be updated.
  force: false
  # Specifies a component and its configuration updates. This field is deprecated and replaced by `reconfigures`.
  reconfigures:
    # Specifies the name of the Component.
  - componentName: clickhouse
    parameters:
      # Represents the name of the parameter that is to be updated.
    - key: clickhouse.profiles.web.max_bytes_to_read
      # Represents the parameter values that are to be updated.
      # If set to nil, the parameter defined by the Key field will be removed from the configuration file.
      value: '200000000000'
  # Specifies the maximum number of seconds the OpsRequest will wait for its start conditions to be met before aborting. If set to 0 (default), the start conditions must be met immediately for the OpsRequest to proceed.
  preConditionDeadlineSeconds: 0
  type: Reconfiguring
```

```bash
kubectl apply -f examples/clickhouse/configure.yaml
```

This example will change the `max_bytes_to_read` to `200000000000`.
To verify the configuration, you can connect to the ClickHouse server and run the following command:

```bash
# connect to the clickhouse pod
kubectl exec -it clickhouse-cluster-clickhouse-0 -- /bin/bash
```

and check the configuration:

```bash
# connect to the clickhouse server
clickhouse-client --user $CLICKHOUSE_ADMIN_USER --password $CLICKHOUSE_ADMIN_PASSWORD
> set profile='web';
> select name,value from system.settings where name like 'max_bytes%';
```

<details>
<summary>Explanation of the configuration</summary>
The `user.xml` file is an xml file that contains the configuration of the ClickHouse server.

```xml
<clickhouse>
  <profiles>
    <default>
      <!-- The maximum number of threads when running a single query. -->
      <max_threads>8</max_threads>
    </default>
    <web>
      <max_rows_to_read>1000000000</max_rows_to_read>
      <max_bytes_to_read>100000000000</max_bytes_to_read>
    </web>
  </profiles>
</clickhouse>
```

When updating the configuration, the key we set in the `configure.yaml` file should be the same as the key in the `user.xml` file, for example:

```yaml
# snippet of configure.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
spec:
  reconfigures:
  - componentName: clickhouse
    parameters:
    - key: clickhouse.profiles.web.max_bytes_to_read
      value: '200000000000'
```

To update parameter `max_bytes_to_read`, we use the full path `clickhouse.profiles.web.max_bytes_to_read` w.r.t the `user.xml` file.

</details>


### Using Config Templates

> [!NOTE]
> This section is applicable for ClickHouse Addons v1.0.2 and above.

Create a ClickHouse cluster with config templates:

```yaml
# cat examples/clickhouse/cluster-with-config-templates.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: clickhouse-cluster-with-tpl
  namespace: demo
spec:
  clusterDef: clickhouse
  topology: cluster
  terminationPolicy: Delete
  componentSpecs:
    - name: ch-keeper
      componentDef: clickhouse-keeper-1
      replicas: 1
      resources:
        limits:
          cpu: '0.5'
          memory: 1Gi
        requests:
          cpu: '0.5'
          memory: 1Gi
      systemAccounts:
        - name: admin
          secretRef:
            name: udf-account-info
            namespace: demo
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 10Gi
  shardings:
    - name: clickhouse
      shards: 2 # with 2 shard
      template:
        name: clickhouse  # each shard is a clickhouse component, with 2 replicas
        componentDef: clickhouse-1
        replicas: 2
        configs:
        - name: clickhouse-user-tpl # refers to the name defined in `componentDefinition.spec.configs[].name'
          configMap:
            name: custom-user-configuration-tpl # refers to the configmap with your customized configuration info.
          variables:
            max_threads: "16"
        systemAccounts:
          - name: admin
            secretRef:
              name: udf-account-info
              namespace: demo
        resources:
          limits:
            cpu: "1"
            memory: 2Gi
          requests:
            cpu: "1"
            memory: 2Gi
        volumeClaimTemplates:
          - name: data
            spec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 20Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: udf-account-info
  namespace: demo  # optional
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=  # 'password123' in base64
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-user-configuration-tpl
  namespace: demo
data:
  user.xml: |
    {{- $var_max_threads := "8" }}
    {{- if index . "udf_max_threads" }}
    {{- $var_max_threads = $.udf_max_threads }}
    {{- end }}

    <clickhouse>
      <!-- Settings profiles -->
      <profiles>
        <!-- Admin user settings -->
        <default>
          <!-- The maximum number of threads when running a single query, which is used for admin user -->
          <max_threads>{{ $var_max_threads }}</max_threads>
          <log_queries>1</log_queries>
          <log_queries_min_query_duration_ms>2000</log_queries_min_query_duration_ms>
        </default>
      </profiles>

      <!-- Users and roles -->
      <users>
        <!-- Admin user with full access -->
        <admin replace="replace">
          <password from_env="CLICKHOUSE_ADMIN_PASSWORD"/>
          <access_management>1</access_management>
          <named_collection_control>1</named_collection_control>
          <show_named_collections>1</show_named_collections>
          <show_named_collections_secrets>1</show_named_collections_secrets>

          <networks replace="replace">
            <ip>::/0</ip>
          </networks>

          <profile>default</profile>
          <quota>default</quota>
        </admin>
      </users>
    </clickhouse>

```

```bash
kubectl apply -f examples/clickhouse/cluster-with-config-templates.yaml
```

This example will create a ClickHouse cluster with user customized config templates, which is defined in the ConfigMap named `custom-user-configuration-tpl` in the namespace `demo`, through the `configs` API showing below:

```yaml
configs:
  - name: clickhouse-user-tpl # refers to the config name defined in `componentDefinition.spec.configs[].name'
    configMap:
      name: custom-user-configuration-tpl # refers to your configmap with customized configuration.
```

To verify the configuration, you can connect to the ClickHouse server and run the following command:

```bash
clickhouse-client --user $CLICKHOUSE_ADMIN_USER --password $CLICKHOUSE_ADMIN_PASSWORD
```

and check the configuration:

```bash
> set profile='default'; # set the profile to `default`
> select name,value from system.settings where name like 'max_threads%'; # check the `max_threads` configuration, which is `8` by default.
```

There are two ways to update the configuration:

#### Option 1. Update through Variables

- Step 1. Define a variable in the Config Template:

    For example, in the ConfigMap `custom-user-configuration-tpl`, we defined a variable `udf_max_threads`  and how it will be used in the `user.xml` file:

    ```yaml
    data:
      user.xml: |
        {{- $var_max_threads := "8" }}      # default value is `8`
        {{- if index . "udf_max_threads" }} # if the variable is defined, use the value of the variable
        {{- $var_max_threads = $.udf_max_threads }} # use the value of the variable
        {{- end }}

        <clickhouse>
          <profiles>
            <default>
              <max_threads>{{ $var_max_threads }}</max_threads>
        # ... other configurations omitted for brevity ...
    ```

- Step 2. Specify the variable and its value in the `cluster-with-config-templates.yaml` CR:

    ```yaml
    configs:
    - name: clickhouse-user-tpl
      configMap:
        name: custom-user-configuration-tpl
      variables:
        udf_max_threads: "16" # set variable `udf_max_threads` to 16.
    ```

    Login to the ClickHouse server and check the configuration:
    ```bash
    clickhouse-client --user $CLICKHOUSE_ADMIN_USER --password $CLICKHOUSE_ADMIN_PASSWORD
    > set profile='default';
    > select name,value from system.settings where name like 'max_threads%';
    ```

    You will see the `max_threads` configuration is `16`.

#### Option 2. Update through config template

- Step 1. Update Config Template

    For example, in the ConfigMap `custom-user-configuration-tpl`, you can update the `user.xml` file directly:

    ```yaml
    data:
      user.xml: |
        <clickhouse>
          <profiles>
            <default>
              <max_threads>16</max_threads>  # change from 8 to 16.
        # ... other configurations omitted for brevity ...
    ```

- Step 2. Annotate Component to trigger a reconcile

    Updates in ConfigMap will not trigger a reconcile of the cluster, you need to annotate the component to trigger a reconcile.

    For example, if the component name is `clickhouse-cluster-clickhouse`, you can run the following command:
    ```bash
    kubectl annotate component clickhouse-cluster-clickhouse kubeblocks.io/config=max_threads -n demo
    ```

#### Comparison between Option 1 and Option 2

| Aspect | Option 1 (Variables) | Option 2 (Config Template) |
|--------|---------------------|----------------------------|
| **Configuration Method** | Through variables in cluster CR | Direct modification of config template |
| **Reconcile Trigger** | Automatic when CR is updated | Manual annotation required |
| **Complexity** | Lower - declarative approach | Higher - requires understanding of template structure |
| **Use Case** | When only a couple of configurations need to be updated | Best for batch updates of configurations |

You can choose the appropriate method based on your needs and operational preferences.

### Backup and Restore

#### Prerequisites for Backup

Before creating backups, you need to set up a backup repository. First, create a BackupRepo:

```yaml
# cat examples/clickhouse/backuprepo.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupRepo
metadata:
  name: <test-backuprepo>
  annotations:
    # optional, mark this backuprepo as default
    dataprotection.kubeblocks.io/is-default-repo: 'true'
spec:
  # Specifies the name of the `StorageProvider` used by this backup repository.
  # Currently, KubeBlocks supports configuring various object storage services as backup repositories
  # - s3 (Amazon Simple Storage Service)
  # - oss (Alibaba Cloud Object Storage Service)
  # - cos (Tencent Cloud Object Storage)
  # - gcs (Google Cloud Storage)
  # - obs (Huawei Cloud Object Storage)
  # - minio, and other S3-compatible services.
  # Note: set the provider name to you own needs
  storageProviderRef: oss
  # Specifies the access method of the backup repository.
  # - Tool
  # - Mount
  # If the access mode is Mount, it will mount the PVC through the CSI driver (make sure it is installed and configured properly)
  # In Tool mode, it will directly stream to the object storage without mounting the PVC.
  accessMethod: Tool
  # Stores the non-secret configuration parameters for the `StorageProvider`.
  config:
    # Note: set the bucket name to you own needs
    bucket: <kubeblocks-test>
    # Note: set the region name to you own needs
    region: <cn-zhangjiakou>
  # References to the secret that holds the credentials for the `StorageProvider`.
  # kubectl create secret generic demo-credential-for-backuprepo --from-literal=accessKeyId=* --from-literal=secretAccessKey=* --namespace=kb-system
  credential:
    # name is unique within a namespace to reference a secret resource.
    # Note: set the secret name to you own needs
    name: <credential-for-backuprepo>
    # namespace defines the space within which the secret name must be unique.
    namespace: kb-system
  # Specifies reclaim policy of the PV created by this backup repository
  # Valid Options are [Retain, Delete]
  # Delete means the volume will be deleted from Kubernetes on release from its claim.
  # Retain means the volume will be left in its current phase (Released) for manual reclamation by the administrator.
  pvReclaimPolicy: Retain

```

```bash
# Edit the backuprepo.yaml file with your storage provider details
kubectl apply -f examples/clickhouse/backuprepo.yaml
```

Make sure to update the following fields in `backuprepo.yaml`:
- `storageProviderRef`: Set to your storage provider (s3, oss, cos, gcs, obs, minio, etc.)
- `config.bucket`: Your storage bucket name
- `config.region`: Your storage region
- `credential.name`: Reference to your storage credentials secret

Create the credentials secret:

```bash
kubectl create secret generic credential-for-backuprepo \
  --from-literal=accessKeyId=<your-access-key> \
  --from-literal=secretAccessKey=<your-secret-key> \
  --namespace=kb-system
```

#### Create Backup

Create a backup of your ClickHouse cluster:

```yaml
# cat examples/clickhouse/backup.yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: Backup
metadata:
  name: clickhouse-cluster-backup
  namespace: demo
spec:
  # Specifies the backup method name that is defined in the backup policy.
  # - full
  # - incremental
  backupMethod: full
  # Specifies the backup policy to be applied for this backup.
  backupPolicyName: clickhouse-cluster-clickhouse-backup-policy
  # Determines whether the backup contents stored in the backup repository should be deleted when the backup custom resource(CR) is deleted. Supported values are `Retain` and `Delete`.
  # - `Retain` means that the backup content and its physical snapshot on backup repository are kept.
  # - `Delete` means that the backup content and its physical snapshot on backup repository are deleted.
  deletionPolicy: Delete

```

```bash
kubectl apply -f examples/clickhouse/backup.yaml
```

This will create a full backup using the `clickhouse-backup` tool. The backup supports both:
- **Full Backup**: Complete backup of all ClickHouse data
- **Incremental Backup**: Backup only changes since the last backup

To create an incremental backup, modify the `backupMethod` field in `backup.yaml`:

```yaml
spec:
  backupMethod: incremental  # Change from 'full' to 'incremental'
```

### Restart

Restart the specified components in the cluster

```yaml
# cat examples/clickhouse/restart.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: clickhouse-restart
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Restart
  # Lists Components to be restarted. ComponentOps specifies the Component to be operated on.
  restart:
    # Specifies the name of the Component.
    # - clickhouse
    # - ch-keeper
  - componentName: clickhouse

```

```bash
kubectl apply -f examples/clickhouse/restart.yaml
```


### Stop

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```yaml
# cat examples/clickhouse/stop.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: clickhouse-stop
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Stop

```

```bash
kubectl apply -f examples/clickhouse/stop.yaml
```

### Start

Start the stopped cluster

```yaml
# cat examples/clickhouse/start.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: clickhouse-start
  namespace: demo
spec:
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  type: Start

```

```bash
kubectl apply -f examples/clickhouse/start.yaml
```

### Expose

Expose ClickHouse services to external access. Note that ClickHouse Keeper does not need to be exposed as it's an internal coordination service.

#### Expose with LoadBalancer

Expose ClickHouse using LoadBalancer service type:

```yaml
# cat examples/clickhouse/expose-enable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: clickhouse-expose-enable
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: clickhouse
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are `ClusterIP`, `NodePort`, and `LoadBalancer`.
      serviceType: LoadBalancer
      # Contains cloud provider related parameters if ServiceType is LoadBalancer.
      # Following is an example for Aliyun ACK, please adjust the following annotations as needed.
      annotations:
        service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
        service.beta.kubernetes.io/alibaba-cloud-loadbalancer-charge-type: ""
        service.beta.kubernetes.io/alibaba-cloud-loadbalancer-spec: slb.s1.small
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Enable
```

```bash
kubectl apply -f examples/clickhouse/expose-enable.yaml
```

This will create a LoadBalancer service for the ClickHouse component. You can then connect using:

```bash
clickhouse-client --host <loadbalancer-ip> --port 9000 --user admin --password
```

#### Disable Expose

Remove the exposed service:

```yaml
# cat examples/clickhouse/expose-disable.yaml
apiVersion: operations.kubeblocks.io/v1alpha1
kind: OpsRequest
metadata:
  name: clickhouse-expose-disable
  namespace: demo
spec:
  # Specifies the type of this operation.
  type: Expose
  # Specifies the name of the Cluster resource that this operation is targeting.
  clusterName: clickhouse-cluster
  # Lists Expose objects, each specifying a Component and its services to be exposed.
  expose:
    # Specifies the name of the Component.
  - componentName: clickhouse
    # Specifies a list of OpsService. When an OpsService is exposed, a corresponding ClusterService will be added to `cluster.spec.services`.
    services:
    - name: internet
      # Determines how the Service is exposed. Defaults to 'ClusterIP'.
      # Valid options are `ClusterIP`, `NodePort`, and `LoadBalancer`.
      serviceType: LoadBalancer
    # Indicates whether the services will be exposed. 'Enable' exposes the services. while 'Disable' removes the exposed Service.
    switch: Disable
```

```bash
kubectl apply -f examples/clickhouse/expose-disable.yaml
```

#### Cluster with NodePort

Create a ClickHouse cluster with NodePort services:

```yaml
# cat examples/clickhouse/cluster-with-nodeport.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: clickhouse-cluster-nodeport
  namespace: demo
spec:
  terminationPolicy: Delete
  # Specifies the services to be exposed at the cluster level, allowing the cluster to be accessed from outside.
  services:
    # Exposes ClickHouse service using NodePort
    - name: clickhouse-nodeport
      # Type of the exposed service. Valid options are 'ClusterIP', 'NodePort', and 'LoadBalancer'.
      serviceType: NodePort
      # Sharding associated with this service
      shardingSelector: clickhouse
      # Role selector for the component service.
      # In a ClickHouse cluster, we only expose nodes without specifying roles
      # since all nodes can handle read/write requests
  # Components that make up the cluster
  componentSpecs:
    # ch-keeper component for distributed mode
    - name: ch-keeper
      componentDef: clickhouse-keeper-1
      replicas: 1
      resources:
        limits:
          cpu: "0.5"
          memory: 1Gi
        requests:
          cpu: "0.5"
          memory: 1Gi
      systemAccounts:
        - name: admin
          secretRef:
            name: udf-account-info
            namespace: demo
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
  # ClickHouse sharding configuration
  shardings:
    - name: clickhouse
      shards: 1  # single shard for compatibility
      template:
        name: clickhouse
        componentDef: clickhouse-1
        replicas: 2
        # Component-level services override services defined in referenced ComponentDefinition
        # This example creates a per-pod NodePort service for each ClickHouse instance
        services:
          - name: clickhouse-per-pod
            serviceType: NodePort
            podService: true
        resources:
          limits:
            cpu: "0.5"
            memory: 0.5Gi
          requests:
            cpu: "0.5"
            memory: 0.5Gi
        volumeClaimTemplates:
          - name: data
            spec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 20Gi
        systemAccounts:
          - name: admin
            secretRef:
              name: udf-account-info
              namespace: demo
---
apiVersion: v1
kind: Secret
metadata:
  name: udf-account-info
  namespace: demo
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=  # 'password123' in base64
```

```bash
kubectl apply -f examples/clickhouse/cluster-with-nodeport.yaml
```

This example demonstrates two approaches:
1. Cluster-level NodePort service that load balances across all ClickHouse instances
2. Per-pod NodePort services for direct access to individual ClickHouse instances

To connect via NodePort:

```bash
# Get the NodePort
kubectl get svc -n demo | grep clickhouse

# Connect using node IP and NodePort
clickhouse-client --host <node-ip> --port <node-port> --user admin --password
```

### Observability

There are various ways to monitor the cluster. Here we use Prometheus and Grafana to demonstrate how to monitor the cluster.

#### Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator.
Or you can follow the steps in [How to install the Prometheus Operator](../docs/install-prometheus.md) to install the Prometheus Operator.

#### Create PodMonitor

Apply the `PodMonitor` file to monitor the cluster:

```yaml
# cat examples/clickhouse/pod-monitor.yaml

apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: clickhouse-pod-monitor
  namespace: demo
  labels:               # this is labels set in `prometheus.spec.podMonitorSelector`
    release: prometheus
spec:
  jobLabel: app.kubernetes.io/managed-by
  # defines the labels which are transferred from the
  # associated Kubernetes `Pod` object onto the ingested metrics
  # set the lables w.r.t you own needs
  podTargetLabels:
  - app.kubernetes.io/instance
  - app.kubernetes.io/managed-by
  - apps.kubeblocks.io/component-name
  - apps.kubeblocks.io/pod-name
  podMetricsEndpoints:
    - path: /metrics
      port: http-metrics
      scheme: http
  namespaceSelector:
    matchNames:
      - demo
  selector:
    matchLabels:
      app.kubernetes.io/instance: clickhouse-cluster # set cluster name
```

```bash
kubectl apply -f examples/clickhouse/pod-monitor.yaml
```

It sets endpoints as follows:

```yaml
  podMetricsEndpoints:
    - path: /metrics
      port: http-metrics
      scheme: http
```

> [!NOTE]
> Make sure the labels are set correctly in the `PodMonitor` file to match the dashboard.

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
# Delete clusters and resources
kubectl delete -f examples/clickhouse/cluster.yaml
kubectl delete -f examples/clickhouse/cluster-standalone.yaml
...
```
