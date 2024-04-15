set -e
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.rdb.zst" ${DATA_DIR}/kb-dp-dump.rdb
cat >> dts.ini <<EOF
[extractor]
db_type=redis
extract_type=snapshot_file
repl_port=10008
file_path=${DATA_DIR}/kb-dp-dump.rdb

[filter]
do_dbs=0
do_events=
ignore_dbs=
ignore_tbs=
do_tbs=

[sinker]
db_type=redis
sink_type=write
url=redis://default:${REDIS_DEFAULT_PASSWORD}@${DP_DB_HOST}:${DP_DB_PORT}
batch_size=200
is_cluster=true

[router]
db_map=
col_map=
tb_map=

[pipeline]
buffer_size=16000
checkpoint_interval_secs=10

[parallelizer]
parallel_type=redis
parallel_size=1

[runtime]
log_level=info
log4rs_file=./log4rs.yaml
log_dir=./logs
EOF
/ape-dts dts.ini
rm -rf ${DATA_DIR}/kb-dp-dump.rdb && sync
