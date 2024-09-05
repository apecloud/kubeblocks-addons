# kubeblocks-addons
KubeBlocks add-ons.

[![codecov](https://codecov.io/gh/apecloud/kubeblocks-addons/graph/badge.svg?token=NGTPFMY8NG)](https://codecov.io/gh/apecloud/kubeblocks-addons)

## Add-on Tutorial
> NOTE: This tutorial is applicable for KubeBlocks version 0.9.0.

* [Add-ons of KubeBlocks](https://kubeblocks.io/docs/preview/developer_docs/integration/add-ons-of-kubeblocks)
* [Add an add-on to KubeBlocks](https://kubeblocks.io/docs/preview/developer_docs/integration/how-to-add-an-add-on)
* [Backup and restore](https://kubeblocks.io/docs/preview/developer_docs/integration/backup-and-restore)
* [Parameter template](https://kubeblocks.io/docs/preview/developer_docs/integration/parameter-template)
* [Parameter configuration](https://kubeblocks.io/docs/preview/developer_docs/integration/parameter-configuration)
* [Configure monitoring](https://kubeblocks.io/docs/preview/developer_docs/integration/monitoring)
* [Multi-component configuration](https://kubeblocks.io/docs/preview/developer_docs/integration/multi-component)
* [Environment variables and placeholders](https://kubeblocks.io/docs/preview/developer_docs/integration/environment-variables-and-placeholders)

## Supported Add-ons

| NAME | DESCRIPTION | Maintainers |
| ---- | ----------- | ----------- |
| apecloud-mysql | ApeCloud MySQL is a database that is compatible with MySQL syntax and achieves high availability through the utilization of the RAFT consensus protocol. | xuriwuyun |
| apecloud-postgresql | ApeCloud PostgreSQL is a database that is compatible with PostgreSQL syntax and achieves high availability through the utilization of the RAFT consensus protocol. | ldming |
| camellia-redis-proxy | camellia-redis-proxy is a high-performance redis proxy developed using Netty4. | Y-Rookie |
| clickhouse | ClickHouse is an open-source column-oriented OLAP database management system. Use it to boost your database performance while providing linear scalability and hardware efficiency. | sophon-zt |
| dmdb | A Helm chart for Kubernetes |  |
| elasticsearch | Elasticsearch is a distributed, RESTful search engine optimized for speed and relevance on production-scale workloads. | iziang |
| etcd | Etcd is a strongly consistent, distributed key-value store that provides a reliable way to store data that needs to be accessed by a distributed system or cluster of machines. | free6om |
| flink | Apache Flink is a framework and distributed processing engine for stateful computations over unbounded and bounded data streams. | shanshanying |
| greatsql | GreatSQL is a high performance open source relational database management system  that can be used on common hardware for financial-grade application scenarios | ltaodream |
| greptimedb | An open-source, cloud-native, distributed time-series database with PromQL/SQL/Python supported. | GreptimeTeam sh2 |
| influxdb | InfluxDB(TM) is an open source time-series database. It is a core component of the TICK (Telegraf, InfluxDB(TM), Chronograf, Kapacitor) stack. |  |
| kafka | Apache Kafka is a distributed streaming platform designed to build real-time pipelines and can be used as a message broker or as a replacement for a log aggregation solution for big data applications. | caiq1nyu |
| llm | Large language models. | lynnleelhl |
| loki | Loki is a horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus. It is designed to be very cost effective and easy to operate. | Chen-speculation |
| mariadb | MariaDB is a high performance open source relational database management system that is widely used for web and application servers | yinmin |
| milvus | A cloud-native vector database, storage for next generation AI applications. | leon-inf |
| minio | High Performance, Kubernetes Native Object Storage | fengluodb |
| mogdb | A Helm chart for Kubernetes | yabinji shanshanying |
| mongodb | MongoDB is a document database designed for ease of application development and scaling. | xuriwuyun |
| mysql | MySQL is a widely used, open-source relational database management system (RDBMS) | xuriwuyun |
| nebula | NebulaGraph is a popular open-source graph database that can handle large volumes of data with milliseconds of latency, scale up quickly, and have the ability to perform fast graph analytics. | Shanshan Ying Xuntao Cheng |
| neon | Neon is a serverless open-source alternative to AWS Aurora Postgres. It separates storage and compute and substitutes the PostgreSQL storage layer by redistributing data across a cluster of nodes. | skyrise |
| oceanbase-ce | Unlimited scalable distributed database for data-intensive transactional and real-time operational analytics workloads, with ultra-fast performance that has once achieved world records in the TPC-C benchmark test. OceanBase has served over 400 customers across the globe and has been supporting all mission critical systems in Alipay. | Powerfool shanshanying |
| official-postgresql | A Official PostgreSQL cluster definition Helm chart for Kubernetes | kizuna-lek |
| opengauss | A Helm chart for Kubernetes | 1aal |
| openldap | The OpenLDAP Project is a collaborative effort to develop a robust, commercial-grade, fully featured, and open source LDAP suite of applications and development tools. This chart provides KubeBlocks' | kissycn |
| opensearch | Open source distributed and RESTful search engine. | iziang |
| opentenbase | OpenTenBase is an enterprise-level distributed HTAP open source database. | ldming |
| oracle | A Helm chart for Kubernetes | 1aal |
| orchestrator | Orchestrator is a MySQL high availability and replication management tool, runs as a service and provides command line access, HTTP API and Web interface. | kubeJocker |
| orioledb | OrioleDB is a new storage engine for PostgreSQL, bringing a modern approach to database capacity, capabilities and performance to the world's most-loved database platform. | 1aal |
| polardbx | PolarDB-X is a cloud native distributed SQL Database designed for high concurrency, massive storage, complex querying scenarios. | Vettal Wu |
| postgresql | A PostgreSQL (with Patroni HA) cluster definition Helm chart for Kubernetes | ldming |
| pulsar | Apache Pulsar is an open-source, distributed messaging and streaming platform built for the cloud. | caiq1nyu |
| qdrant | High-performance, massive-scale Vector Database for the next generation of AI. | iziang |
| rabbitmq | RabbitMQ is a reliable and mature messaging and streaming broker. | xuriwuyun |
| redis | Redis is an in-memory database that persists on disk. The data model is key-value, but many different kind of values are supported: Strings, Lists, Sets, Sorted Sets, Hashes, Streams, HyperLogLogs, Bitmaps. | Y-Rookie |
| risingwave | RisingWave is a distributed SQL streaming database that enables cost-efficient and reliable processing of streaming data. | RisingWave Labs |
| solr | Solr is the popular, blazing-fast, open source enterprise search platform built on Apache Lucene. | ApeCloud kissycn |
| starrocks-ce | A Linux Foundation project, is the next-generation data platform designed to make data-intensive real-time analytics fast and easy. | yandongxiao iziang |
| tdengine | TDengine is an open source, high-performance, cloud native time-series database optimized for Internet of Things (IoT), Connected Cars, Industrial IoT and DevOps. | leon-inf |
| tidb | TiDB is an open-source, cloud-native, distributed, MySQL-Compatible database for elastic scale and real-time analytics. | csuzhangxc cjc7373 |
| victoria-metrics | VictoriaMetrics is a fast, cost-effective and scalable monitoring solution and time series database. | sophon-zt ButterBright |
| weaviate | Weaviate is an open-source vector database. It allows you to store data objects and vector embeddings from your favorite ML-models, and scale seamlessly into billions of data objects. | iziang |
| xinference | Xorbits Inference(Xinference) is a powerful and versatile library designed to serve language, speech recognition, and multimodal models. | lynnleelhl |
| yashandb | YashanDB is a new database system completely independently designed and developed by SICS. Based on classical database theories, it incorporates original Bounded Evaluation theory, Approximation theory, Parallel Scalability theory and Cross-Modal Fusion Computation theory, supports multiple deployment methods such as stand-alone/primary-standby, shared cluster, and distributed ones, covers OLTP/HTAP/OLAP transactions and analyzes mixed load scenarios, and is fully compatible with privatization and cloud infrastructure, providing clients with one-stop enterprise-level converged data management solutions to meet the needs of key industries such as finance, government, telecommunications and energy for high performance, concurrency and security. | JesseAtSZ shanshanying |
| zookeeper | Apache ZooKeeper is a centralized service for maintaining configuration information, naming, providing distributed synchronization, and providing group services. | kubeJocker kissycn |