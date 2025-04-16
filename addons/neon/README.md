# Neon

Neon is a serverless open-source alternative to AWS Aurora Postgres. It separates storage and compute and substitutes the PostgreSQL storage layer by redistributing data across a cluster of nodes.

## Prerequisites

Neon Auto-scaling requires virtualization technology, requiring the host to have virtualization turned on.

NeonVM and Autoscaling are not expected to work outside Linux x86.

NeonVM deployment relies on cert-manager.

This example assumes that you have a Kubernetes cluster installed and running, and that you have installed the kubectl command line tool and helm somewhere in your path. Please see the [getting started](https://kubernetes.io/docs/setup/)  and [Installing Helm](https://helm.sh/docs/intro/install/) for installation instructions for your platform.

Also, this example requires kubeblocks installed and running. Here is the steps to install kubeblocks, please replace "`$kb_version`" with the version you want to use.
```bash
# Add Helm repo
helm repo add kubeblocks https://apecloud.github.io/helm-charts
# If github is not accessible or very slow for you, please use following repo instead
helm repo add kubeblocks https://jihulab.com/api/v4/projects/85949/packages/helm/stable

# Update helm repo
helm repo update

# Get the versions of KubeBlocks and select the one you want to use
helm search repo kubeblocks/kubeblocks --versions
# If you want to obtain the development versions of KubeBlocks, Please add the '--devel' parameter as the following command
helm search repo kubeblocks/kubeblocks --versions --devel

# Create dependent CRDs
kubectl create -f https://github.com/apecloud/kubeblocks/releases/download/v$kb_version/kubeblocks_crds.yaml
# If github is not accessible or very slow for you, please use following command instead
kubectl create -f https://jihulab.com/api/v4/projects/98723/packages/generic/kubeblocks/v$kb_version/kubeblocks_crds.yaml

# Install KubeBlocks
helm install kubeblocks kubeblocks/kubeblocks --namespace kb-system --create-namespace --version="$kb_version"
```

Enable neon

```bash
# Add Helm repo
helm repo add kubeblocks-addons https://apecloud.github.io/helm-charts
# If github is not accessible or very slow for you, please use following repo instead
helm repo add kubeblocks-addons https://jihulab.com/api/v4/projects/150246/packages/helm/stable
# Update helm repo
helm repo update

# Enable neon
helm upgrade -i kb-addon-neon kubeblocks-addons/neon --version $kb_version -n kb-system

# Add Helm repo
helm repo add kubeblocks-applications https://apecloud.github.io/helm-charts
# If github is not accessible or very slow for you, please use following repo instead
helm repo add kubeblocks-applications https://jihulab.com/api/v4/projects/152630/packages/helm/stable
# Update helm repo
helm repo update

# Install cert-manager
helm upgrade -i cert-manager kubeblocks-applications/cert-manager --version v1.14.2 -n cert-manager
```
- Create K8s Namespace `demo`, to keep resources created in this tutorial isolated:

  ```bash
  kubectl create ns demo
  ```

## Examples

### Create
Create a neon cluster with specified cluster definition.
```yaml
# cat examples/neon/cluster.yaml
apiVersion: apps.kubeblocks.io/v1
kind: Cluster
metadata:
  name: neon-cluster
  namespace: demo
spec:
  # Specifies the name of the ClusterDefinition to use when creating a Cluster.
  clusterDefinitionRef: neon
  # Specifies the name of the Topology defined in ClusterDefinition to use when creating a Cluster.
  topology: default
  # Specifies the behavior when a Cluster is deleted.
  # - `DoNotTerminate`: Prevents deletion of the Cluster. This policy ensures that all resources remain intact.
  # - `Halt`: Deletes Cluster resources like Pods and Services but retains Persistent Volume Claims (PVCs), allowing for data preservation while stopping other operations.
  # - `Delete`: Extends the `Halt` policy by also removing PVCs, leading to a thorough cleanup while removing all persistent data.
  # - `WipeOut`: An aggressive policy that deletes all Cluster resources, including volume snapshots and backups in external storage. This results in complete data removal and should be used cautiously, primarily in non-production environments to avoid irreversible data loss.
  terminationPolicy: Delete
  # Specifies a list of ClusterComponentSpec objects used to define the individual components that make up a Cluster. This field allows for detailed configuration of each component within the Cluster.
  # Note: `shardingSpecs` and `componentSpecs` cannot both be empty; at least one must be defined to configure a cluster.
  # ClusterComponentSpec defines the specifications for a Component in a Cluster.
  componentSpecs:
    - name: neon-broker
      replicas: 1
      resources:
        limits:
          cpu: "1"
          memory: "2Gi"
        requests:
          cpu: '0.5'
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
    - name: neon-safekeeper
      replicas: 3
      resources:
        limits:
          cpu: "1"
          memory: "2Gi"
        requests:
          cpu: '0.5'
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: neon-safekeeper
          spec:
            storageClassName:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
    - name: neon-pageserver
      replicas: 1
      resources:
        limits:
          cpu: "1"
          memory: "2Gi"
        requests:
          cpu: '0.5'
          memory: 0.5Gi
      volumeClaimTemplates:
        - name: neon-pageserver
          spec:
            storageClassName:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 20Gi
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: compute-node-config
  namespace: demo
data:
  compute.sh: |-
    #!/bin/bash
    set -ex
    export PAGESERVER=neon-cluster-neon-pageserver-headless.default.svc.cluster.local
    export SAFEKEEPERS=neon-cluster-neon-safekeeper-headless.default.svc.cluster.local:5454
    SPEC_FILE_ORG=/spec_prep_docker.json
    SPEC_FILE=/spec.json
    PG_VERSION=14
    echo "Waiting pageserver become ready."
    while ! nc -z $PAGESERVER 6400; do
    sleep 1;
    done
    echo "Page server is ready."

    echo "Create a tenant and timeline"
    if [ -z "$TENANT" ]; then
    PARAMS=(
    -sb
    -X POST
    -H "Content-Type: application/json"
    -d "{}"
    "http://${PAGESERVER}:9898/v1/tenant/"
    )
    tenant_id=$(curl "${PARAMS[@]}" | sed 's/"//g')
    else
    tenant_id=$TENANT
    fi

    if [ -z "$TIMELINE" ]; then
    PARAMS=(
    -sb
    -X POST
    -H "Content-Type: application/json"
    -d "{\"tenant_id\":\"${tenant_id}\", \"pg_version\": ${PG_VERSION}}"
    "http://${PAGESERVER}:9898/v1/tenant/${tenant_id}/timeline/"
    )
    result=$(curl "${PARAMS[@]}")
    echo $result | jq .

    echo "Overwrite tenant id and timeline id in spec file"
    tenant_id=$(echo ${result} | jq -r .tenant_id)
    timeline_id=$(echo ${result} | jq -r .timeline_id)

    else

    #If not empty CREATE_BRANCH
    #we create branch with given ancestor_timeline_id as TIMELINE

    if [ ! -z "$CREATE_BRANCH" ]; then

    PARAMS=(
    -sb
    -X POST
    -H "Content-Type: application/json"
    -d "{\"tenant_id\":\"${tenant_id}\", \"pg_version\": ${PG_VERSION}, \"ancestor_timeline_id\":\"${TIMELINE}\"}"
    "http://${PAGESERVER}:9898/v1/tenant/${tenant_id}/timeline/"
    )

    result=$(curl "${PARAMS[@]}")
    echo $result | jq .

    echo "Overwrite tenant id and timeline id in spec file"
    tenant_id=$(echo ${result} | jq -r .tenant_id)
    timeline_id=$(echo ${result} | jq -r .timeline_id)

    else
    timeline_id=$TIMELINE
    fi #end if CREATE_BRANCH

    fi

    sed "s/TENANT_ID/${tenant_id}/" ${SPEC_FILE_ORG} > ${SPEC_FILE}
    sed -i "s/TIMELINE_ID/${timeline_id}/" ${SPEC_FILE}
    sed -i "s/PAGESERVER_SPEC/${PAGESERVER}/" ${SPEC_FILE}
    sed -i "s/SAFEKEEPERS_SPEC/${SAFEKEEPERS}/" ${SPEC_FILE}

    cat ${SPEC_FILE}

    echo "Start compute node"
    whoami
    echo $PWD
    if [ ! -d "data" ]; then
    mkdir data
    fi
    ls -lah /data

    if [ ! -d "/data/pgdata" ]; then
    mkdir -p /data/pgdata
    fi
    chown -R postgres:postgres /data
    nohup su - postgres -c "/usr/local/bin/compute_ctl --pgdata /data/pgdata -C 'postgresql://cloud_admin@localhost:55432/postgres' -b /usr/local/bin/postgres -S ${SPEC_FILE}" &

  entrypoint.sh: |-
    #!/bin/sh
    cd /opt/neondatabase-neon
    ./target/release/neon_local start
    ./target/release/neon_local pg start main
    while true; do
    sleep 1000
    done

  spec.json: |-
    {
        "format_version": 1.0,

        "timestamp": "2022-10-12T18:00:00.000Z",
        "operation_uuid": "0f657b36-4b0f-4a2d-9c2e-1dcd615e7d8c",

        "cluster": {
          "cluster_id": "cluster1",
          "name": "Trolladyngja",
          "state": "restarted",
          "roles": [
            {
              "name": "cloud_admin",
              "encrypted_password": "b093c0d3b281ba6da1eacc608620abd8",
              "options": null
            }
          ],
          "databases": [
          ],
          "settings": [
            {
              "name": "fsync",
              "value": "off",
              "vartype": "bool"
            },
            {
              "name": "wal_level",
              "value": "replica",
              "vartype": "enum"
            },
            {
              "name": "hot_standby",
              "value": "on",
              "vartype": "bool"
            },
            {
              "name": "wal_log_hints",
              "value": "on",
              "vartype": "bool"
            },
            {
              "name": "log_connections",
              "value": "on",
              "vartype": "bool"
            },
            {
              "name": "port",
              "value": "55432",
              "vartype": "integer"
            },
            {
              "name": "shared_buffers",
              "value": "1MB",
              "vartype": "string"
            },
            {
              "name": "max_connections",
              "value": "100",
              "vartype": "integer"
            },
            {
              "name": "listen_addresses",
              "value": "0.0.0.0",
              "vartype": "string"
            },
            {
              "name": "max_wal_senders",
              "value": "10",
              "vartype": "integer"
            },
            {
              "name": "max_replication_slots",
              "value": "10",
              "vartype": "integer"
            },
            {
              "name": "wal_sender_timeout",
              "value": "5s",
              "vartype": "string"
            },
            {
              "name": "wal_keep_size",
              "value": "0",
              "vartype": "integer"
            },
            {
              "name": "password_encryption",
              "value": "md5",
              "vartype": "enum"
            },
            {
              "name": "restart_after_crash",
              "value": "off",
              "vartype": "bool"
            },
            {
              "name": "synchronous_standby_names",
              "value": "walproposer",
              "vartype": "string"
            },
            {
              "name": "shared_preload_libraries",
              "value": "neon",
              "vartype": "string"
            },
            {
              "name": "neon.safekeepers",
              "value": "neon-cluster-neon-safekeeper-0.neon-cluster-neon-safekeeper-headless.default.svc.cluster.local,neon-cluster-neon-safekeeper-1.neon-cluster-neon-safekeeper-headless.default.svc.cluster.local,neon-cluster-neon-safekeeper-2.neon-cluster-neon-safekeeper-headless.default.svc.cluster.local:5454",
              "vartype": "string"
            },
            {
              "name": "neon.timeline_id",
              "value": "b93d7329d4488763dfd47b0faa75e33d",
              "vartype": "string"
            },
            {
              "name": "neon.tenant_id",
              "value": "eb7a5b7ef4070cdc870dbf514c4f7c67",
              "vartype": "string"
            },
            {
              "name": "neon.pageserver_connstring",
              "value": "host=neon-cluster-neon-pageserver-0.neon-cluster-neon-pageserver-headless.default.svc.cluster.local port=6400",
              "vartype": "string"
            },
            {
              "name": "max_replication_write_lag",
              "value": "500MB",
              "vartype": "string"
            },
            {
              "name": "max_replication_flush_lag",
              "value": "10GB",
              "vartype": "string"
            }
          ]
        },

        "delta_operations": [
        ]
    }
  spec_prep_docker.json: |-
    {
        "format_version": 1.0,

        "timestamp": "2022-10-12T18:00:00.000Z",
        "operation_uuid": "0f657b36-4b0f-4a2d-9c2e-1dcd615e7d8c",

        "cluster": {
          "cluster_id": "cluster1",
          "name": "Trolladyngja",
          "state": "restarted",
          "roles": [
            {
              "name": "cloud_admin",
              "encrypted_password": "b093c0d3b281ba6da1eacc608620abd8",
              "options": null
            }
          ],
          "databases": [
          ],
          "settings": [
            {
              "name": "fsync",
              "value": "off",
              "vartype": "bool"
            },
            {
              "name": "wal_level",
              "value": "replica",
              "vartype": "enum"
            },
            {
              "name": "hot_standby",
              "value": "on",
              "vartype": "bool"
            },
            {
              "name": "wal_log_hints",
              "value": "on",
              "vartype": "bool"
            },
            {
              "name": "log_connections",
              "value": "on",
              "vartype": "bool"
            },
            {
              "name": "port",
              "value": "55432",
              "vartype": "integer"
            },
            {
              "name": "shared_buffers",
              "value": "1MB",
              "vartype": "string"
            },
            {
              "name": "max_connections",
              "value": "100",
              "vartype": "integer"
            },
            {
              "name": "listen_addresses",
              "value": "0.0.0.0",
              "vartype": "string"
            },
            {
              "name": "max_wal_senders",
              "value": "10",
              "vartype": "integer"
            },
            {
              "name": "max_replication_slots",
              "value": "10",
              "vartype": "integer"
            },
            {
              "name": "wal_sender_timeout",
              "value": "5s",
              "vartype": "string"
            },
            {
              "name": "wal_keep_size",
              "value": "0",
              "vartype": "integer"
            },
            {
              "name": "password_encryption",
              "value": "md5",
              "vartype": "enum"
            },
            {
              "name": "restart_after_crash",
              "value": "off",
              "vartype": "bool"
            },
            {
              "name": "synchronous_standby_names",
              "value": "walproposer",
              "vartype": "string"
            },
            {
              "name": "shared_preload_libraries",
              "value": "neon",
              "vartype": "string"
            },
            {
              "name": "neon.safekeepers",
              "value": "SAFEKEEPERS_SPEC",
              "vartype": "string"
            },
            {
              "name": "neon.timeline_id",
              "value": "TIMELINE_ID",
              "vartype": "string"
            },
            {
              "name": "neon.tenant_id",
              "value": "TENANT_ID",
              "vartype": "string"
            },
            {
              "name": "neon.pageserver_connstring",
              "value": "host=PAGESERVER_SPEC port=6400",
              "vartype": "string"
            },
            {
              "name": "max_replication_write_lag",
              "value": "500MB",
              "vartype": "string"
            },
            {
              "name": "max_replication_flush_lag",
              "value": "10GB",
              "vartype": "string"
            }
          ]
        },

        "delta_operations": [
        ]
    }
---
apiVersion: vm.neon.tech/v1
kind: VirtualMachine
metadata:
  name: vm-compute-node
  namespace: demo
  annotations:
    # In this example, these bounds aren't necessary. So... here's what they look like :)
    autoscaling.neon.tech/bounds: '{ "min": { "cpu": 0.25, "mem": "1Gi" }, "max": { "cpu": 1.25, "mem": "5Gi" } }'
  labels:
    autoscaling.neon.tech/enabled: "true"
    # Set to "true" to continuously migrate the VM (TESTING ONLY)
    autoscaling.neon.tech/testing-only-always-migrate: "false"
spec:
  schedulerName: autoscale-scheduler
  guest:
    cpus: { min: 1, use: 1, max: 2 }
    memorySlotSize: 1Gi
    memorySlots: { min: 1, use: 1, max: 5 }
    rootDisk:
      image: apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/pg14-disk-test:test
      size: 12Gi
      imagePullPolicy: IfNotPresent
    command:
      - /bin/bash
      - -c
      - |
        if [ ! -f "/tmp/script_executed" ]; then
            set -ex
            trap : TERM INT
            whoami
            export PAGESERVER=neon-cluster-neon-pageserver-headless.default.svc.cluster.local
            export SAFEKEEPERS=neon-cluster-neon-safekeeper-headless.default.svc.cluster.local:5454
            cp scripts/* ./
            chmod +x compute.sh entrypoint.sh spec.json spec_prep_docker.json
            ./compute.sh

            touch /tmp/script_executed
        else
            echo "Scripts already executed."
        fi
    ports:
      - port: 22   # ssh
      - port: 55432 # postgres
      - port: 9100 # metrics
      - port: 10301 # informant
  disks:
    - name: compute-node-config
      mountPath: /scripts
      readOnly: false
      configMap:
        name: compute-node-config

```

```bash
kubectl apply -f examples/neon/cluster.yaml
```


### Vertical scaling NeonVM
Vertical scaling up or down NeonVM specified cpu or memory.

View NeonVM CPU/MEMORY information.
```bash
kubectl get neonvm -n demo
NAME              CPUS   MEMORY   POD                     EXTRAIP   STATUS    AGE
vm-compute-node   1      1Gi      vm-compute-node-g8wsb             Running   5m22s
```

Vertical scaling NeonVM CPU
```bash

kubectl patch neonvm -n demo vm-compute-node --type='json' -p='[{"op": "replace", "path": "/spec/guest/cpus/use", "value":2}]'
```
View NeonVM CPU information after Vertical scaling.
```bash
kubectl get neonvm -n demo
NAME              CPUS   MEMORY   POD                     EXTRAIP   STATUS    AGE
vm-compute-node   2      1Gi      vm-compute-node-g8wsb             Running   5m45s
```

Vertical scaling NeonVM MEMORY
```bash
kubectl patch neonvm vm-compute-node --type='json' -p='[{"op": "replace", "path": "/spec/guest/memorySlots/use", "value":4}]'
```

View NeonVM MEMORY information after Vertical scaling.
```bash
kubectl get neonvm -n demo
NAME              CPUS   MEMORY   POD                     EXTRAIP   STATUS    AGE
vm-compute-node   2      4Gi      vm-compute-node-g8wsb             Running   10m
```


### Delete
If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster
```bash
kubectl patch cluster -n demo neon-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

 kubectl delete cluster -n demoneon-cluster
```
