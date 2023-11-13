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
| NAME | APP-VERSION | DESCRIPTION |
| ---- | --------- | ----------- |
| apecloud-mysql | 8.0.30 | ApeCloud MySQL is a database that is compatible with MySQL syntax and achieves high availability through the utilization of the RAFT consensus protocol.
| apecloud-postgresql | latest | ApeCloud PostgreSQL is a database that is compatible with PostgreSQL syntax and achieves high availability through the utilization of the RAFT consensus protocol.
| clickhouse | 22.9.4 | ClickHouse is an open-source column-oriented OLAP database management system. Use it to boost your database performance while providing linear scalability and hardware efficiency.
| elasticsearch | 8.8.2 | Elasticsearch is a distributed, RESTful search engine optimized for speed and relevance on production-scale workloads.
| etcd | 3.5.6 | etcd is a strongly consistent, distributed key-value store that provides a reliable way to store data that needs to be accessed by a distributed system or cluster of machines.
| foxlake | 0.2.0 | ApeCloud FoxLake is an open-source cloud-native data warehouse.
| greptimedb | 0.3.2 | An open-source, cloud-native, distributed time-series database with PromQL/SQL/Python supported.
| kafka | 3.3.2 | Apache Kafka is a distributed streaming platform designed to build real-time pipelines and can be used as a message broker or as a replacement for a log aggregation solution for big data applications.
| llm | baichuan-7b-q4<br>baichuan2-13b-q4<br>baichuan2-7b-4q<br>codeshell-7b-chat-q4<br>latest<br>replit-code-3b-f16<br>zephyr-beta-7b-q4 | Large language models.
| mariadb | 10.6.15 | MariaDB is a high performance open source relational database management system that is widely used for web and application servers
| milvus | 2.2.4 | A cloud-native vector database, storage for next generation AI applications.
| mongodb | 4.0<br>4.2<br>4.4<br>5.0<br>5.0.20<br>6.0<br>sharding-5.0 | MongoDB is a document database designed for ease of application development and scaling.
| mysql | 5.7.42<br>8.0.33 | MySQL is a widely used, open-source relational database management system (RDBMS)
| nebula | 3.5.0 | NebulaGraph is a popular open-source graph database that can handle large volumes of data with milliseconds of latency, scale up quickly, and have the ability to perform fast graph analytics.
| neon | latest | Neon is a serverless open-source alternative to AWS Aurora Postgres. It separates storage and compute and substitutes the PostgreSQL storage layer by redistributing data across a cluster of nodes.
| oceanbase | 4.2.0.0-100010032023083021 | Unlimited scalable distributed database for data-intensive transactional and real-time operational analytics workloads, with ultra-fast performance that has once achieved world records in the TPC-C benchmark test. OceanBase has served over 400 customers across the globe and has been supporting all mission critical systems in Alipay.
| official-postgresql | 12.15<br>14.7<br>14.7-zhparser | A Official PostgreSQL cluster definition Helm chart for Kubernetes
| openldap | 2.4.57 | The OpenLDAP Project is a collaborative effort to develop a robust, commercial-grade, fully featured, and open source LDAP suite of applications and development tools. This chart provides KubeBlocks'
| opensearch | 2.7.0 | Open source distributed and RESTful search engine.
| oracle-mysql | 8.0.32<br>8.0.32-perf | MySQL is a widely used, open-source relational database management system (RDBMS)
| orioledb | beta1 | OrioleDB is a new storage engine for PostgreSQL, bringing a modern approach to database capacity, capabilities and performance to the world's most-loved database platform.
| polardbx | 2.3 | PolarDB-X is a cloud native distributed SQL Database designed for high concurrency, massive storage, complex querying scenarios.
| postgresql | 12.14.0<br>12.14.1<br>12.15.0<br>14.7.2<br>14.8.0 | A PostgreSQL (with Patroni HA) cluster definition Helm chart for Kubernetes
| pulsar | 2.11.2 | Apache Pulsar is an open-source, distributed messaging and streaming platform built for the cloud.
| qdrant | 1.5.0 | High-performance, massive-scale Vector Database for the next generation of AI.
| redis | 7.0.6 | Redis is an in-memory database that persists on disk. The data model is key-value, but many different kind of values are supported: Strings, Lists, Sets, Sorted Sets, Hashes, Streams, HyperLogLogs, Bitmaps.
| risingwave | v1.0.0 | RisingWave is a distributed SQL streaming database that enables cost-efficient and reliable processing of streaming data.
| starrocks | 3.1.1 | A Linux Foundation project, is the next-generation data platform designed to make data-intensive real-time analytics fast and easy.
| tdengine | 3.0.5.0 | A Specific Implementation of TDengine Chart for Kubernetes, and provides by KubeBlocks' ClusterDefinition API manifests.
| weaviate | 1.18.0 | Weaviate is an open-source vector database. It allows you to store data objects and vector embeddings from your favorite ML-models, and scale seamlessly into billions of data objects.
| xinference | 1.16.0<br>cpu-latest | Xorbits Inference(Xinference) is a powerful and versatile library designed to serve language, speech recognition, and multimodal models.
| zookeeper | 3.7.1 | Apache ZooKeeper is a centralized service for maintaining configuration information, naming, providing distributed synchronization, and providing group services.
