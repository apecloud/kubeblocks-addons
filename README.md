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
| NAME | VERSIOINS | DESCRIPTION | MAINTAINERS |
| ---- | ---- | ----------- | ----------- |
| apecloud-mysql | apecloud-mysql-8.0.30<br>wescale-0.2.7 | ApeCloud MySQL is a database that is compatible with MySQL syntax and achieves high availability through the utilization of the RAFT consensus protocol. | xuriwuyun |
| clickhouse | clickhouse-24.8.3 | ClickHouse is an open-source column-oriented OLAP database management system. Use it to boost your database performance while providing linear scalability and hardware efficiency. | sophon-zt |
| elasticsearch | elasticsearch-7.10.1<br>elasticsearch-7.7.1<br>elasticsearch-7.8.1<br>elasticsearch-8.1.3<br>elasticsearch-8.8.2 | Elasticsearch is a distributed, RESTful search engine optimized for speed and relevance on production-scale workloads. | iziang |
| etcd | etcd-v3.5.15<br>etcd-v3.5.6 | Etcd is a strongly consistent, distributed key-value store that provides a reliable way to store data that needs to be accessed by a distributed system or cluster of machines. | free6om |
| kafka | kafka-broker-3.3.2<br>kafka-combine-3.3.2<br>kafka-controller-3.3.2<br>kafka-exporter-1.6.0 | Apache Kafka is a distributed streaming platform designed to build real-time pipelines and can be used as a message broker or as a replacement for a log aggregation solution for big data applications. | caiq1nyu |
| loki | loki-1.0.0 | Loki is a horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus. It is designed to be very cost effective and easy to operate. | Chen-speculation |
| minio | minio-2024.6.29 | High Performance, Kubernetes Native Object Storage | fengluodb |
| mongodb | mongodb-4.0.28<br>mongodb-4.2.24<br>mongodb-4.4.29<br>mongodb-5.0.28<br>mongodb-6.0.16<br>mongodb-7.0.12 | MongoDB is a document database designed for ease of application development and scaling. | xuriwuyun |
| mysql | mysql-5.7.44<br>mysql-8.0.30<br>mysql-8.0.31<br>mysql-8.0.32<br>mysql-8.0.33<br>mysql-8.0.34<br>mysql-8.0.35<br>mysql-8.0.36<br>mysql-8.0.37<br>mysql-8.0.38<br>mysql-8.0.39<br>mysql-8.4.0<br>mysql-8.4.1<br>mysql-8.4.2<br>mysql-orc-5.7.44<br>mysql-orc-8.0.30<br>mysql-orc-8.0.31<br>mysql-orc-8.0.32<br>mysql-orc-8.0.33<br>mysql-orc-8.0.34<br>mysql-orc-8.0.35<br>mysql-orc-8.0.36<br>mysql-orc-8.0.37<br>mysql-orc-8.0.38<br>mysql-orc-8.0.39<br>mysql-proxysql-2.4.4 | MySQL is a widely used, open-source relational database management system (RDBMS) | xuriwuyun |
| orchestrator | orchestrator-3.2.6 | Orchestrator is a MySQL high availability and replication management tool, runs as a service and provides command line access, HTTP API and Web interface. | kubeJocker |
| postgresql | postgresql-12.14.0<br>postgresql-12.14.1<br>postgresql-12.15.0<br>postgresql-14.7.2<br>postgresql-14.8.0<br>postgresql-15.7.0<br>postgresql-16.4.0 | A PostgreSQL (with Patroni HA) cluster definition Helm chart for Kubernetes | ldming |
| pulsar | pulsar-bkrecovery-2.11.2<br>pulsar-bkrecovery-3.0.2<br>pulsar-bookkeeper-2.11.2<br>pulsar-bookkeeper-3.0.2<br>pulsar-broker-2.11.2<br>pulsar-broker-3.0.2<br>pulsar-proxy-2.11.2<br>pulsar-proxy-3.0.2<br>pulsar-zookeeper-2.11.2<br>pulsar-zookeeper-3.0.2 | Apache Pulsar is an open-source, distributed messaging and streaming platform built for the cloud. | caiq1nyu |
| qdrant | qdrant-1.10.0<br>qdrant-1.5.0<br>qdrant-1.7.3<br>qdrant-1.8.1<br>qdrant-1.8.4 | High-performance, massive-scale Vector Database for the next generation of AI. | iziang |
| rabbitmq | rabbitmq-3.10.25<br>rabbitmq-3.11.28<br>rabbitmq-3.12.14<br>rabbitmq-3.13.2<br>rabbitmq-3.8.14<br>rabbitmq-3.9.29 | RabbitMQ is a reliable and mature messaging and streaming broker. | xuriwuyun |
| redis | redis-7.0.6<br>redis-7.2.4<br>redis-cluster-7.0.6<br>redis-cluster-7.2.4<br>redis-sentinel-7.0.6<br>redis-sentinel-7.2.4<br>redis-twemproxy-0.5.0 | Redis is an in-memory database that persists on disk. The data model is key-value, but many different kind of values are supported: Strings, Lists, Sets, Sorted Sets, Hashes, Streams, HyperLogLogs, Bitmaps. | Y-Rookie |
| zookeeper | zookeeper-3.4.14<br>zookeeper-3.6.4<br>zookeeper-3.7.2<br>zookeeper-3.8.4<br>zookeeper-3.9.2 | Apache ZooKeeper is a centralized service for maintaining configuration information, naming, providing distributed synchronization, and providing group services. | kubeJocker kissycn |
