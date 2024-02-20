[install]
YASDB_HOME=$YASDB_MOUNT_HOME/yasdb_home
YASDB_DATA=$YASDB_MOUNT_HOME/yasdb_data
REDO_FILE_SIZE=100M
REDO_FILE_NUM=4
INSTALL_SIMPLE_SCHEMA_SALES=N
NLS_CHARACTERSET=UTF8
[instance]
LISTEN_ADDR=0.0.0.0:1688
DB_BLOCK_SIZE=8K
{{- $phy_memory := getContainerMemory ( index $.podSpec.containers 0 ) }}
{{- $phy_memory_mb := div $phy_memory ( mul 1024 1024 ) }}
{{- $buffer_pool_mb := mulf $phy_memory_mb 0.5 | int }}
DATA_BUFFER_SIZE={{- printf "%dM" $buffer_pool_mb}}
SHARE_POOL_SIZE=256M
WORK_AREA_POOL_SIZE=32M
LARGE_POOL_SIZE=32M
REDO_BUFFER_SIZE=8M
UNDO_RETENTION=300
OPEN_CURSORS=310
MAX_SESSIONS=1024
RUN_LOG_LEVEL=INFO
NODE_ID=1-1:1