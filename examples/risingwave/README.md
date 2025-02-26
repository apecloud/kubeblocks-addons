# RisingWave

RisingWave is a distributed SQL streaming database that enables cost-efficient and reliable processing of streaming data. There are multiple components in the RisingWave system, each with a specific role.

- **Meta** node manages metadata and coordinates the system
- **Compute** nodes handle stream processing and query execution
- **Compactor** nodes manage data storage and compaction, and
- **Frontend** node serves as the entry point for user interactions.

RisingWave has multiple Connectors, enabling integration with external data sources and sinks, facilitating data ingestion and export.

Such architecture allows RisingWave to provide real-time analytics and high-concurrent access to Materialized Views, making it suitable for a wide range of applications in the modern data ecosystem.

## Features In KubeBlocks

### Lifecycle Management

| Horizontal<br/>scaling | Vertical <br/>scaling | Expand<br/>volume | Restart   | Stop/Start | Configure | Expose | Switchover |
|------------------------|-----------------------|-------------------|-----------|------------|-----------|--------|------------|
| Yes                    | Yes                   | Yes              | Yes       | Yes        | No       | Yes    | N/A      |

### Versions

| Major Versions |
|---------------|
| 1.0           |

## Prerequisites

- Kubernetes cluster >= v1.21
- `kubectl` installed, refer to [K8s Install Tools](https://kubernetes.io/docs/tasks/tools/)
- Helm, refer to [Installing Helm](https://helm.sh/docs/intro/install/)
- KubeBlocks installed and running, refer to [Install Kubeblocks](../docs/prerequisites.md)
- RisingWave Addon Enabled, refer to [Install Addons](../docs/install-addon.md)
- [Optional] ETCD Addon and MinIO Addon Enabled

## Examples

### [Create](cluster.yaml)

#### Pre-requisites

Before creating the RisingWave cluster, ETCD and Object Storage endpoints are required. Here in this example, we use MinIO as the object storage and ETCD as the metadata store.

```bash
kubectl apply -f examples/risingwave/etcd-cluster.yaml # create etcd cluster
kubectl apply -f examples/risingwave/minio-cluster.yaml # create minio cluster
```

What for all Cluster running and get ETCD and Minio Endpoint:

- ETCD endpoint:

```bash
# Get ETCD endpoint
ETCD_ENDPOINT="etcd-cluster-etcd-headless.default.svc.cluster.local:2379"
# Get Minio endpoint
MINIO_ENDPOINT="minio-cluster-minio.default.svc.cluster.local:9000"
# Get Minio user and password
MINIO_USER=$(kubectl get secret minio-cluster-minio-account-root -n default -o jsonpath="{.data.username}" | base64 --decode)
MINIO_PASSWORD=$(kubectl get secret minio-cluster-minio-account-root -n default -o jsonpath="{.data.password}" | base64 --decode)
# Create a Bucket `risingwave` in MinIO if not exists:
MINIO_BUCKER="<BUCKET_NAME>"
mc alias set minio http://$MINIO_ENDPOINT $MINIO_USER $MINIO_PASSWORD  # set minio alias
mc mb minio/${MINIO_BUCKER}  # create bucket
mc ls minio # list bucket
```

#### Create RisingWave Cluster

There are five components in the cluster, provisioned in the following order:

- connector
- meta
- compactor, compute
- frontend

> [!IMPORTANT]
> Before applying the yaml file, please replace envs `RW_STATE_STORE` and `RW_ETCD_ENDPOINTS` with the actual values.
>
> ```bash
> - name: RW_STATE_STORE
>   value: hummock+minio://${ENV:MINIO_USER}:${ENV:MINIO_PASSWORD}@${ENV:MINIO_ENDPOINT}/${ENV:MINIO_BUCKET}
> - name: RW_DATA_DIRECTORY
>   value: /path/to/prefix
> - name: RW_ETCD_ENDPOINTS
>   value: ${ENV:ETCD_ENDPOINT}
>  ```

```bash
kubectl apply -f examples/risingwave/cluster.yaml
```

#### Connect to RisingWave

Make sure RisingWave is up and running. To access RisingWave, you can expose the frontend service:

```bash
kubectl port-forward svc/risingwave-cluster-frontend -n default 4567:4567
```

Then, use the following command in the terminal to connect to RisingWave using `psql`:

```bash
psql -h localhost -p 4566 -d dev -U root
```

**Parameter Explanation:**

- `-h`: Specifies the hostname or IP address to connect to. The default is `localhost`.
- `-p`: Specifies the port number that RisingWave is listening on. The default is `4566`.
- `-d`: Specifies the database name. The default is `dev`.
- `-U`: Specifies the username. The default is `root`.

> [!Note]
> By default, the `root` user does not require a password to connect to the database.

#### Create a Table

Here is an example from the RisingWave [Quick Start](https://docs.risingwave.com/get-started/quickstart)

```sql
CREATE TABLE website_visits (
  timestamp timestamp with time zone,
  user_id varchar,
  page_id varchar,
  action varchar
);
```

This will create a table to store data related to website visits, where:

- `timestamp`: Records the visit time, with the data type as a timestamp with time zone.
- `user_id`: Records the user ID, with the data type as a variable-length string (`varchar`).
- `page_id`: Records the page ID, with the data type as a variable-length string.
- `action`: Records the user's action, such as viewing a page, with the data type as a variable-length string.

#### Insert Data

You can insert 5 rows of data into the `website_visits` table using the following SQL command:

```sql
INSERT INTO website_visits (timestamp, user_id, page_id, action) VALUES
  ('2023-06-13T10:00:00Z', 'user1', 'page1', 'view'),
  ('2023-06-13T10:01:00Z', 'user2', 'page2', 'view'),
  ('2023-06-13T10:02:00Z', 'user3', 'page3', 'view'),
  ('2023-06-13T10:03:00Z', 'user4', 'page1', 'view'),
  ('2023-06-13T10:04:00Z', 'user5', 'page2', 'view');
```

---

#### Verify the Inserted Data

After inserting the data, you can run the following query to verify the contents of the table:

```sql
SELECT * FROM website_visits;
```

The output should display:

| timestamp           | user_id | page_id | action |
|---------------------|---------|---------|--------|
| 2023-06-13 10:00:00+00 | user1   | page1   | view   |
| 2023-06-13 10:01:00+00 | user2   | page2   | view   |
| 2023-06-13 10:02:00+00 | user3   | page3   | view   |
| 2023-06-13 10:03:00+00 | user4   | page1   | view   |
| 2023-06-13 10:04:00+00 | user5   | page2   | view   |

### Horizontal scaling

#### [Scale-out](scale-out.yaml)

Horizontal scaling out risingwave compute component by adding ONE more replica:

```bash
kubectl apply -f examples/risingwave/scale-out.yaml
```

#### [Scale-in](scale-in.yaml)

Horizontal scaling in risingwave compute component by deleting ONE replica:

```bash
kubectl apply -f examples/risingwave/scale-in.yaml
```

### [Vertical scaling](verticalscale.yaml)

Vertical scaling up or down specified components requests and limits cpu or memory resource in the cluster

```bash
kubectl apply -f examples/risingwave/verticalscale.yaml
```

### [Restart](restart.yaml)

Restart the specified components in the cluster

```bash
kubectl apply -f examples/risingwave/restart.yaml
```

### [Stop](stop.yaml)

Stop the cluster and release all the pods of the cluster, but the storage will be reserved

```bash
kubectl apply -f examples/risingwave/stop.yaml
```

### [Start](start.yaml)

Start the stopped cluster

```bash
kubectl apply -f examples/risingwave/start.yaml
```

### Delete

If you want to delete the cluster and all its resource, you can modify the termination policy and then delete the cluster

```bash
kubectl patch cluster risingwave-cluster -p '{"spec":{"terminationPolicy":"WipeOut"}}' --type="merge"

kubectl delete cluster risingwave-cluster

kubectl delete cluster etcd-cluster #if you have created etcd cluster

kubectl delete cluster minio-cluster #if you have created minio cluster
```

## Appendix

### How to Set ENVs for different State Store

The hummock connection string differs based on the state store used. Here is a quick lookup for the connection string. Please refer to the [Hummock Documentation](https://legacy-docs.risingwave-labs.com/docs/current/risingwave-kubernetes/) for more details.

- s3: `hummock+s3://<S3_BUCKET_NAME>`
- minio: `hummock+minio://$(MINIO_USER):$(MINIO_PASSWORD)@$(MINIO_ENDPOINT)/$(MINIO_BUCKET)`
- oss: `hummock+oss://<OSS_BUCKET_NAME>`
- azblob: `hummock+azblob://<AZBLOB_CONTAINER_NAME>`
- gcs: `hummock+gcs://<GCS_BUCKET_NAME>`
- hdfs: `hummock+hdfs://<HDFS_NAME_NODE>`
- obs: `hummock+obs://<OBS_BUCKET_NAME>`
- localFs: `hummock+fs://<LOCAL_FS_PATH>`

And credentials are required and should be set as ENVs in the cluster. Here two examples are provided for S3 and MinIO:

- **Use S3 as State Store**

If you are working with S3, you need to set the following ENVs when creating the cluster:

```yaml
- name: RW_STATE_STORE
  value: hummock+s3://<S3_BUCKET_NAME>
- name: AWS_REGION
- name: AWS_ACCESS_KEY_ID
- name: AWS_SECRET_ACCESS_KEY
```

- **Use MinIO as State Store**

If you are working with MinIO, as in this example, you need to set the following ENVs when creating the cluster:

```yaml
- name: MINIO_USER
- name: MINIO_PASSWORD
- name: MINIO_BUCKET
- name: MINIO_ENDPOINT
- name: RW_STATE_STORE
  value: hummock+minio://$(MINIO_USER):$(MINIO_PASSWORD)@$(MINIO_ENDPOINT)/$(MINIO_BUCKET)
```
