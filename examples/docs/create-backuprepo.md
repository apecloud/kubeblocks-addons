# Backup Repository

A backup repository is a storage location where backup files are stored. You can create a backup repository to store backup files in a location that is different from the default backup repository. You can create a backup repository on a local disk, a network share, or a cloud storage.

## Creating a Backup Repository

1. Create a secret with your S3 credentials.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <S3_SECRET_NAME>
  # Namespace depends on the configuration
  namespace: kb-system
stringData:
  accessKeyID: <S3_ACCESS_KEY_ID>
  secretAccessKey: <S3_SECRET_ACCESS_KEY>
```

1. Create a `BackupRepository` CR with the following configuration.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupRepo
metadata:
  name: <YOUR_BACKUP_REPO_NAME>
  annotations:
    # Optional, using this annotation to mark this backuprepo as default
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
  # Valida options are [s3, oss, cos, gcs, obs, minio]
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
    bucket: <YOUR_BUCKET_NAME>
    # Note: set the region name to you own needs
    region: <YOUR_S3_REGION>
  # References to the secret that holds the credentials for the `StorageProvider`.
  # kubectl create secret generic demo-credential-for-backuprepo --from-literal=accessKeyId=* --from-literal=secretAccessKey=* --namespace=kb-system
  credential:
    # name is unique within a namespace to reference a secret resource.
    # Note: set the secret name to you own needs
    name: <S3_SECRET_NAME>
    # Namespace depends on the configuration
    namespace: kb-system
  # Specifies reclaim policy of the PV created by this backup repository
  # Delete: means the volume will be deleted from Kubernetes on release from its claim.
  # Retain: means the volume will be left in its current phase (Released) for manual reclamation by the administrator.
  # Valid Options are [Retain, Delete]
  pvReclaimPolicy: Retain
```

1. Verify the creation of the backup repository.

```bash
kubectl get backuprepo
```

If the backup repository is created successfully, you will see the following output. Make sure the status is `Ready`.

```bash
NAME           STATUS   STORAGEPROVIDER   ACCESSMETHOD   DEFAULT   AGE
kb-oss         Ready    oss               Tool           true      1m
```

### Create a Backup Repository with Access Method Set to `Mount`

> [!NOTE]
> If the `accessMethod` is set to `Mount`, it will mount the PVC through the CSI driver, make sure it is installed and configured properly.

Here is an example of install csi-s3 driver and create a backup repository with the access method set to `Mount`.

1. Install csi-s3 driver[^1]

csi-s3 driver can dynamically allocate buckets and mount them via a fuse mount into any container.

```bash
helm repo add yandex-s3 https://yandex-cloud.github.io/k8s-csi-s3/charts

helm install csi-s3 yandex-s3/csi-s3 -n kb-system
```

1. Create a `BackupRepository` CR with the following configuration.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupRepo
metadata:
  name: <YOUR_BACKUP_REPO_NAME>
  annotations:
    # Optional, using this annotation to mark this backuprepo as default
    dataprotection.kubeblocks.io/is-default-repo: 'true'
spec:
  storageProviderRef: oss
  accessMethod: Mount # set the access method to Mount
  config:
    bucket: <YOUR_BUCKET_NAME>
    region: <YOUR_S3_REGION>
  credential:
    name: <S3_SECRET_NAME>
    namespace: kb-system
  pvReclaimPolicy: Retain
```

### Create a Backup Repository with storageProviderRef Set to `nfs`

> [!NOTE]
> To create a backup repository with storageProviderRef set to `nfs`, make sure CSI Driver `nfs.csi.k8s.io` is installed and configured properly.

Here is an example of installing the `nfs.csi.k8s.io` driver and creating a backup repository with the `storageProviderRef` set to `nfs`.

1. Install the csi-driver-nfs driver.

```bash
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kb-system --version v4.9.0
```

1. Create a `BackupRepository` CR with the following configuration.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupRepo
metadata:
  name: <YOUR_BACKUP_REPO_NAME>
  annotations:
    # Optional, using this annotation to mark this backuprepo as default
    dataprotection.kubeblocks.io/is-default-repo: 'true'
spec:
  storageProviderRef: nfs
  accessMethod: Tool
  config:
    # extra mount options
    nfsMountOptions: ""
    # REQUIRED: NFS Server address
    nfsServer: <YOUR_NFS_SERVER_ADDRESS>
    # NFS share
    nfsShare: "/"
    # sub directory under nfs share
    nfsSubDir: ""
  pvReclaimPolicy: Retain
```

### Create a Backup Repository with storageProviderRef Set to `pvc`

1. Create a `BackupRepository` CR with the following configuration.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: BackupRepo
metadata:
  name: <YOUR_BACKUP_REPO_NAME>
  annotations:
    # Optional, using this annotation to mark this backuprepo as default
    dataprotection.kubeblocks.io/is-default-repo: 'true'
spec:
  storageProviderRef: pvc # set to PVC
  accessMethod: Mount
  config:
    accessMode: ReadWriteOnce # ReadWriteOnce, ReadOnlyMany, ReadWriteMany
    storageClassName: <YOUR_STORAGE_CLASS_NAME>
    volumeMode: Filesystem
  pvReclaimPolicy: Retain # Retain or Delete
  volumeCapacity: 100Gi # Size of the volume
 ```

## How to Add a Storage Provider

There are a handful of storage providers that are supported by KubeBlocks.

```yaml
kubectl get storageprovider
```

You can add a new storage provider by creating a new CR of kind `StorageProvider`.
You may refer to the above examples to add a new storage provider.

Here is an example for azure blob.

```yaml
apiVersion: dataprotection.kubeblocks.io/v1alpha1
kind: StorageProvider
metadata:
  name: azure-blob
spec:
  csiDriverName: blob.csi.azure.com # Specifies the name of the CSI driver used to access remote storage.
  # A Go template utilized to render and generate
  # `kubernetes.storage.k8s.io.v1.StorageClass`
  # resources. The `StorageClass' created by this template is aimed at using the
  # CSI driver.
  storageClassTemplate: |
    provisioner: blob.csi.azure.com
    allowVolumeExpansion: true
    parameters:
      resourceGroup: "{{ .Parameters.resourceGroup }}"
      storageAccount: "{{ .Parameters.storageAccount }}"
      protocol: nfs
      containerName: "{{ .Parameters.containerName }}"
    mountOptions:
      - nconnect=4
  # Describes the parameters required for storage.
  parametersSchema:
    # Defines the parameters in OpenAPI V3.
    openAPIV3Schema:
      type: "object"
      properties:
        resourceGroup:
          type: string
          description: "Azure resource group"
        storageAccount:
          type: string
          description: "Azure storage account"
        containerName:
          type: string
          description: "Name of the Azure Blob Storage container"
```

Make sure required CSI Drivers are installed and configured properly.

## References

[^1]: CSI S3 Driver: https://github.com/yandex-cloud/k8s-csi-s3?tab=readme-ov-file
[^2]: CSI NFS Driver: https://github.com/kubernetes-csi/csi-driver-nfs/tree/master/charts