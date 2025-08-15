starlet_port = 9070

# The CN will report the following error if the storage_root_path is not exist when loading data using http port
# E0409 18:01:03.828197   281 update_manager.cpp:77] prepare_primary_index: load primary index failed: Internal error: lake_persistent_index_type of LOCAL will not take effect when as cn without any storage path
storage_root_path = /opt/starrocks/cn/storage
starlet_use_star_cache = true
starlet_star_cache_disk_size_percent = 100
starlet_star_cache_disk_size_bytes = {{ getComponentPVCSizeByName $.component "data" }}
datacache_disk_path = /opt/starrocks/cn/storage/datacache