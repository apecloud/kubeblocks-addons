# kubeblocks-addons
KubeBlocks add-ons.

## Add-on Tutorial
> NOTE: This tutorial is applicable for KubeBlocks version 0.6.

* [Add-ons of KubeBlocks](https://kubeblocks.io/docs/release-0.6/developer_docs/integration/add-ons-of-kubeblocks)
* [Add an add-on to KubeBlocks](https://kubeblocks.io/docs/release-0.6/developer_docs/integration/how-to-add-an-add-on)
* [Backup and restore](https://kubeblocks.io/docs/release-0.6/developer_docs/integration/backup-and-restore)
* [Parameter template](https://kubeblocks.io/docs/release-0.6/developer_docs/integration/parameter-template)
* [Parameter configuration](https://kubeblocks.io/docs/release-0.6/developer_docs/integration/parameter-configuration)
* [Configure monitoring](https://kubeblocks.io/docs/release-0.6/developer_docs/integration/monitoring)
* [Multi-component configuration](https://kubeblocks.io/docs/release-0.6/developer_docs/integration/multi-component)
* [Environment variables and placeholders](https://kubeblocks.io/docs/release-0.6/developer_docs/integration/environment-variables-and-placeholders)

## Supported Add-ons
| NAME | VERSIOINS | DESCRIPTION | MAINTAINERS |
| ---- | ---- | ----------- | ----------- |
| apecloud-mysql | mysql-8.0.30 | ApeCloud MySQL is a database that is compatible with MySQL syntax and achieves high availability through the utilization of the RAFT consensus protocol. | ApeCloud |
| apecloud-postgresql | apecloud-postgres-14.11-0.7.3 | ApeCloud PostgreSQL is a database that is compatible with PostgreSQL syntax and achieves high availability through the utilization of the RAFT consensus protocol. | ApeCloud |
| camellia-redis-proxy | camellia-redis-proxy-1.2.26 | camellia-redis-proxy is a high-performance redis proxy developed using Netty4. | ApeCloud |
| clickhouse | clickhouse-24.3.10<br>clickhouse-keeper-24.3.10 | ClickHouse is an open-source column-oriented OLAP database management system. Use it to boost your database performance while providing linear scalability and hardware efficiency. | Nash Tsai |
| dmdb | dm8_single-0.1.0<br>dmdb_exporter-0.1.0 | A Helm chart for Kubernetes |  |
| elasticsearch | elasticsearch-7.10.1<br>elasticsearch-7.7.1<br>elasticsearch-7.8.1<br>elasticsearch-8.1.3<br>elasticsearch-8.8.2 | Elasticsearch is a distributed, RESTful search engine optimized for speed and relevance on production-scale workloads. |  |
| etcd | etcd-v3.5.6 | etcd is a strongly consistent, distributed key-value store that provides a reliable way to store data that needs to be accessed by a distributed system or cluster of machines. | free6om |
| flink | flink-1.16 | Apache Flink is a framework and distributed processing engine for stateful computations over unbounded and bounded data streams. | ApeCloud |
| foxlake | foxlake-main<br>mysql-8.0.30 | ApeCloud FoxLake is a fast & low-cost analytical MySQL. | Yusong Gao |
| greptimedb | etcd-v3.5.5<br>greptimedb-0.3.2 | An open-source, cloud-native, distributed time-series database with PromQL/SQL/Python supported. | GreptimeTeam |
| halo | halovector-14.10.231127-amd64 | Halo cluster definition Helm chart for Kubernetes |  |
| influxdb | influxdb-2.7.4-debian-11-r0 | InfluxDB(TM) is an open source time-series database. It is a core component of the TICK (Telegraf, InfluxDB(TM), Chronograf, Kapacitor) stack. |  |
| kafka | kafka-3.3.2<br>kafka-controller-3.3.2<br>kafka-exporter-1.6.0 | Apache Kafka is a distributed streaming platform designed to build real-time pipelines and can be used as a message broker or as a replacement for a log aggregation solution for big data applications. | Nash Tsai |
| llm | llama-cpp-python-latest<br>llama-cpp-python-latest-codeshell<br>llama-cpp-python-latest-new<br>llm-v0.2.7-amd64 | Large language models. |  |
| loki | loki-backend-1.0.0<br>loki-gateway-1.0.0<br>loki-read-1.0.0<br>loki-write-1.0.0 | Loki is a horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus. It is designed to be very cost effective and easy to operate. |  |
| mariadb | mariadb-10.6.15<br>mysqld-exporter-v0.14.0 | MariaDB is a high performance open source relational database management system that is widely used for web and application servers | yinmin |
| milvus | milvus-2.3.2<br>minio-8.0.17 | A cloud-native vector database, storage for next generation AI applications. | ApeCloud |
| minio | minio-0.9.0 | High Performance, Kubernetes Native Object Storage | ApeCloud |
| mogdb | mogdb-5.0.5 | A Helm chart for Kubernetes |  |
| mongodb | mongodb-5.0.14 | MongoDB is a document database designed for ease of application development and scaling. | xuriwuyun |
| mysql | mysql-5.7.44<br>mysql-8.0.33<br>mysql-8.4.2 | MySQL is a widely used, open-source relational database management system (RDBMS) | ApeCloud |
| nebula | nebula-console-v3.5.0<br>nebula-graphd-v3.5.0<br>nebula-metad-v3.5.0<br>nebula-storaged-v3.5.0 | NebulaGraph is a popular open-source graph database that can handle large volumes of data with milliseconds of latency, scale up quickly, and have the ability to perform fast graph analytics. | Shanshan Ying Xuntao Cheng |
| neon | neon-pg14-1.0.0 | Neon is a serverless open-source alternative to AWS Aurora Postgres. It separates storage and compute and substitutes the PostgreSQL storage layer by redistributing data across a cluster of nodes. | ApeCloud |
| oceanbase-ce | oceanbase-4.3.0 | Unlimited scalable distributed database for data-intensive transactional and real-time operational analytics workloads, with ultra-fast performance that has once achieved world records in the TPC-C benchmark test. OceanBase has served over 400 customers across the globe and has been supporting all mission critical systems in Alipay. |  |
| official-postgresql | postgres-12.15<br>postgres-14.7 | A Official PostgreSQL cluster definition Helm chart for Kubernetes | ApeCloud |
| opengauss | opengauss-3.0.0 | A Helm chart for Kubernetes |  |
| openldap | openldap-1.5.0 | The OpenLDAP Project is a collaborative effort to develop a robust, commercial-grade, fully featured, and open source LDAP suite of applications and development tools. This chart provides KubeBlocks' | kissycn |
| opensearch | opensearch-2.7.0<br>opensearch-dashboards-2.7.0 | Open source distributed and RESTful search engine. |  |
| oracle | oracle-19.3.0-ee<br>oracledb_exporter-0.5.2 | A Helm chart for Kubernetes |  |
| orchestrator | orchestrator-3.2.6 | Orchestrator is a MySQL high availability and replication management tool, runs as a service and provides command line access, HTTP API and Web interface. | ApeCloud |
| orioledb | orioledb-beta1<br>pgbouncer-1.19.0 | OrioleDB is a new storage engine for PostgreSQL, bringing a modern approach to database capacity, capabilities and performance to the world's most-loved database platform. |  |
| polardbx | mysqld-exporter-v0.14.0<br>polardbx-cdc-5.4.18-20231101115000<br>polardbx-engine-2.0-80-8.0.18-20231101115000<br>polardbx-exporter-v1.5.0<br>polardbx-sql-5.4.18-20231101115000 | PolarDB-X is a cloud native distributed SQL Database designed for high concurrency, massive storage, complex querying scenarios. | Vettal Wu |
| postgresql | postgresql-12.15.0<br>postgresql-14.8.0<br>postgresql-15.7.0<br>postgresql-16.4.0 | A PostgreSQL (with Patroni HA) cluster definition Helm chart for Kubernetes | ApeCloud |
| pulsar | pulsar-3.0.2 | Apache Pulsar is an open-source, distributed messaging and streaming platform built for the cloud. | ApeCloud |
| qdrant | qdrant-1.10.0<br>qdrant-1.5.0<br>qdrant-1.7.3<br>qdrant-1.8.1<br>qdrant-1.8.4 | High-performance, massive-scale Vector Database for the next generation of AI. | ApeCloud |
| rabbitmq | rabbitmq-3.13.2 | RabbitMQ is a reliable and mature messaging and streaming broker. | xuriwuyun |
| redis | redis-7.2.4<br>redis-cluster-7.2.4<br>redis-sentinel-7.2.4<br>redis-twemproxy-0.5.0 | Redis is an in-memory database that persists on disk. The data model is key-value, but many different kind of values are supported: Strings, Lists, Sets, Sorted Sets, Hashes, Streams, HyperLogLogs, Bitmaps. | ApeCloud |
| risingwave | risingwave-v1.0.0 | RisingWave is a distributed SQL streaming database that enables cost-efficient and reliable processing of streaming data. | RisingWave Labs |
| solr | solr-8.11.2 | Solr is the popular, blazing-fast, open source enterprise search platform built on Apache Lucene. | ApeCloud kissycn |
| starrocks-ce | starrocks-ce-be-3.2.2<br>starrocks-ce-be-3.3.0<br>starrocks-ce-fe-3.2.2<br>starrocks-ce-fe-3.3.0 | A Linux Foundation project, is the next-generation data platform designed to make data-intensive real-time analytics fast and easy. |  |
| tdengine | tdengine-3.0.5.0 | TDengine is an open source, high-performance, cloud native time-series database optimized for Internet of Things (IoT), Connected Cars, Industrial IoT and DevOps. | ApeCloud |
| tidb | busybox-1.35<br>pd-v7.1.2<br>tidb-v7.1.2<br>tikv-v7.1.2 | TiDB is an open-source, cloud-native, distributed, MySQL-Compatible database for elastic scale and real-time analytics. |  |
| victoria-metrics | minsert-1.0.0<br>mselect-1.0.0<br>mstorage-1.0.0 | VictoriaMetrics is a fast, cost-effective and scalable monitoring solution and time series database. |  |
| weaviate | weaviate-1.23.1 | Weaviate is an open-source vector database. It allows you to store data objects and vector embeddings from your favorite ML-models, and scale seamlessly into billions of data objects. | ApeCloud |
| xinference | xinference-0.11.0 | Xorbits Inference(Xinference) is a powerful and versatile library designed to serve language, speech recognition, and multimodal models. |  |
| yashandb | yashandb-personal-23.1.1.100 | YashanDB is a new database system completely independently designed and developed by SICS. Based on classical database theories, it incorporates original Bounded Evaluation theory, Approximation theory, Parallel Scalability theory and Cross-Modal Fusion Computation theory, supports multiple deployment methods such as stand-alone/primary-standby, shared cluster, and distributed ones, covers OLTP/HTAP/OLAP transactions and analyzes mixed load scenarios, and is fully compatible with privatization and cloud infrastructure, providing clients with one-stop enterprise-level converged data management solutions to meet the needs of key industries such as finance, government, telecommunications and energy for high performance, concurrency and security. |  |
| zookeeper | zookeeper-3.4.14<br>zookeeper-3.6.4<br>zookeeper-3.7.2<br>zookeeper-3.8.4<br>zookeeper-3.9.2 | Apache ZooKeeper is a centralized service for maintaining configuration information, naming, providing distributed synchronization, and providing group services. | ApeCloud kissycn |
