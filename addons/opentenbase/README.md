# OpenTenBase Add-on for KubeBlocks

There are two Helm charts for deploying the OpenTenBase KubeBlocks add-on on a Kubernetes cluster. Use this add-on, you can deploy and manage OpenTenBase clusters on Kubernetes. 

Now, already support OS architecture `amd64` and `arm64`. You can follow the steps below to deploy the OpenTenBase Cluster on you laptop(including Mac M1). This significantly lowers the barrier and difficulty for users to experience OpenTenBase.

## Prerequisites

Before you deploy the OpenTenBase KubeBlocks add-on, you need to have the following prerequisites:
* A Kubernetes cluster, you can use [minikube](https://minikube.sigs.k8s.io/docs/) to create a local cluster for testing
* The `kubectl` command-line tool installed on your local machine
* The `helm` command-line tool installed on your local machine
* The `kbcli` command-line tool to install the KubeBlocks control plane

## Install KubeBlocks

Refer to the [KubeBlocks installation guide](https://kubeblocks.io/docs/release-0.8/user_docs/installation/install-with-kbcli/install-kbcli) to install the `kbcli` and  KubeBlocks control plane on your Kubernetes cluster.

## Deploy OpenTenBase Add-on

To deploy the OpenTenBase add-on on your Kubernetes cluster, follow these steps:

```bash
$ helm install opentenbase ./opentenbase
```

Check the ClusterDefinition and ClusterVersion:

```bash
$ kubectl get cd opentenbase
NAME          MAIN-COMPONENT-NAME   STATUS      AGE
opentenbase   gtm                   Available   11m

$ kubectl get cv |grep opentenbase
opentenbase-2.5.0     opentenbase          Available   12m
```

## Create an OpenTenBase Cluster
Run the following command to create an OpenTenBase cluster:

```bash
$ helm install otb ../addons-cluster/opentenbase-cluster
```

This command will create an OpenTenBase cluster with one GTM, one Coordinator, and two Datanodes. Run the following command to check the status of the OpenTenBase cluster:

```bash
$ kubectl get cluster otb
NAME   CLUSTER-DEFINITION   VERSION              TERMINATION-POLICY   STATUS     AGE
otb    opentenbase          opentenbase-2.5.0   Delete               Creating   12s
```

Check the pods of the OpenTenBase cluster:

```bash
$ kubectl get pods -l app.kubernetes.io/instance=otb
NAME         READY   STATUS    RESTARTS   AGE
otb-cn-0-0   1/1     Running   0          2m39s
otb-dn-0-0   2/2     Running   0          2m39s
otb-dn-1-0   2/2     Running   0          2m39s
otb-gtm-0    1/1     Running   0          2m39s
```

Check all components status:

```bash
$ kbcli cluster describe otb
Name: otb        Created Time: Apr 07,2024 15:28 UTC+0800
NAMESPACE   CLUSTER-DEFINITION   VERSION              STATUS     TERMINATION-POLICY   
default     opentenbase          opentenbase-2.5.0   Updating   Delete               

Endpoints:
COMPONENT   MODE        INTERNAL                                  EXTERNAL   
gtm         ReadWrite   otb-gtm.default.svc.cluster.local:50001   <none>     
dn-0        ReadWrite   otb-dn-0.default.svc.cluster.local:5432   <none>     
dn-1        ReadWrite   otb-dn-1.default.svc.cluster.local:5432   <none>     
cn-0        ReadWrite   otb-cn-0.default.svc.cluster.local:5432   <none>     

Topology:
COMPONENT   INSTANCE     ROLE     STATUS    AZ       NODE                            CREATED-TIME                 
cn-0        otb-cn-0-0   <none>   Running   <none>   kind-control-plane/172.18.0.2   Apr 07,2024 15:28 UTC+0800   
dn-0        otb-dn-0-0   <none>   Running   <none>   kind-control-plane/172.18.0.2   Apr 07,2024 15:28 UTC+0800   
dn-1        otb-dn-1-0   <none>   Running   <none>   kind-control-plane/172.18.0.2   Apr 07,2024 15:28 UTC+0800   
gtm         otb-gtm-0    <none>   Running   <none>   kind-control-plane/172.18.0.2   Apr 07,2024 15:28 UTC+0800   

Resources Allocation:
COMPONENT   DEDICATED   CPU(REQUEST/LIMIT)   MEMORY(REQUEST/LIMIT)   STORAGE-SIZE   STORAGE-CLASS   
gtm         false       1 / 1                1Gi / 1Gi               data:20Gi      standard        
dn-0        false       1 / 1                1Gi / 1Gi               data:20Gi      standard        
dn-1        false       1 / 1                1Gi / 1Gi               data:20Gi      standard        
cn-0        false       1 / 1                1Gi / 1Gi               data:20Gi      standard        

Images:
COMPONENT   TYPE   IMAGE                                    
gtm         gtm    docker.io/domainlau/opentenbase:v2.5.0   
dn-0        dn     docker.io/domainlau/opentenbase:v2.5.0   
dn-1        dn     docker.io/domainlau/opentenbase:v2.5.0   
cn-0        cn     docker.io/domainlau/opentenbase:v2.5.0   

Show cluster events: kbcli cluster list-events -n default otb
```

## Connect to the OpenTenBase Cluster
Run the following command to connect to the OpenTenBase cluster:

```bash
$ kubectl exec -it otb-cn-0-0 -- bash

opentenbase@otb-cn-0-0:~$ psql postgres
psql (PostgreSQL 10.0 OpenTenBase V2)
Type "help" for help.

postgres=# select * from pgxc_node;
 node_name | node_type | node_port |     node_host     | nodeis_primary | nodeis_preferred |   node_id   |  node_cluster_name  
-----------+-----------+-----------+-------------------+----------------+------------------+-------------+---------------------
 a_one     | G         |     50001 | otb-gtm           | t              | f                | -1343982441 | opentenbase_cluster
 dn_0      | D         |      5432 | otb-dn-0          | f              | f                |  1485981022 | opentenbase_cluster
 dn_1      | D         |      5432 | otb-dn-1          | f              | f                | -1300059100 | opentenbase_cluster
 cn_0      | C         |      5432 | otb-cn-0          | f              | f                | -1541982360 | opentenbase_cluster
(4 rows)

postgres=# create default node group default_group with(dn_0, dn_1);
CREATE NODE GROUP
postgres=# create sharding group to group default_group;
CREATE SHARDING GROUP
postgres=# clean sharding;
CLEAN SHARDING
postgres=# select * from pgxc_group;
  group_name   | default_group | group_members 
---------------+---------------+---------------
 default_group |             1 | 16384 16385
(1 row)
postgres=# create table public.t1_pt(
f1 int not null,
f2 timestamp not null,
f3 varchar(20),
primary key(f1)) 
partition by range (f2) 
begin (timestamp without time zone '2019-01-01 0:0:0') 
step (interval '1 month') partitions (3) 
distribute by shard(f1) 
to group default_group;
CREATE TABLE
postgres=# \d+ public.t1_pt
                                             Table "public.t1_pt"
 Column |            Type             | Collation | Nullable | Default | Storage  | Stats target | Description 
--------+-----------------------------+-----------+----------+---------+----------+--------------+-------------
 f1     | integer                     |           | not null |         | plain    |              | 
 f2     | timestamp without time zone |           | not null |         | plain    |              | 
 f3     | character varying(20)       |           |          |         | extended |              | 
Indexes:
    "t1_pt_pkey" PRIMARY KEY, btree (f1)
Distribute By: SHARD(f1)
Location Nodes: ALL DATANODES
Partition By: RANGE(f2)
     Partitions number: 3
     Start With: 2019-01-01
     Interval Of Partition: 1 MONTH
```

Or, you can use `kubectl port-forward` and connect to the OpenTenBase cluster from your local machine:

```bash
$ kubectl port-forward svc/otb-cn-0 5432:5432
```

Then, you can connect to the OpenTenBase cluster using the `psql` command:

```bash
$ psql -h 127.0.0.1 -p 5432 -U opentenbase postgres
```

## Delete the OpenTenBase Cluster
Run the following command to delete the OpenTenBase cluster:

```bash
$ helm uninstall otb
```
