#LokiParameter: {
    "auth_enabled": bool

    "server.grpc_listen_port": string
    "server.http_listen_port": string
    "server.grpc_server_max_recv_msg_size": int

    "common.compactor_address": string
    "common.path_prefix": string
    "common.replication_factor": int
    "common.storage.filesystem.chunks_directory": string
    "common.storage.filesystem.rules_directory": string
    "common.storage.s3.endpoint": string
    "common.storage.s3.access_key_id": string
    "common.storage.s3.secret_access_key": string
    "common.storage.s3.bucketnames": string
    "common.storage.s3.s3forcepathstyle": string

    "storage_config.filesystem.directory": string
    "storage_config.aws.endpoint": string
    "storage_config.aws.access_key_id": string
    "storage_config.aws.secret_access_key": string
    "storage_config.aws.bucketnames": string
    "storage_config.aws.s3forcepathstyle": string

    "limits_config.ingestion_burst_size_mb": int
    "limits_config.max_cache_freshness_per_query": string
    "limits_config.reject_old_samples": bool
    "limits_config.reject_old_samples_max_age": string
    "limits_config.retention_period": string
    "limits_config.split_queries_by_interval": string

    "querier.max_concurrent": int


    "ruler.storage.local.directory": string
    "ruler.storage.s3.bucketnames": string
    "ruler.storage.type": string

    "compactor.apply_retention_interval": string
    "compactor.compaction_interval": string
    "compactor.retention_delete_worker_count": int
    "compactor.retention_enabled": bool
    "compactor.shared_store": string

    "index_gateway.mode": string

    "query_range.align_queries_with_step": bool

    "tracing.enabled": bool

    ...
}

loki: #LokiParameter & {

}
