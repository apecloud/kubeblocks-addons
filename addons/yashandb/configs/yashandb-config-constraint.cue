#YashanDBParameter: {
	// 2026-06-03 Reason: constrain only parameters already rendered by install.ini.tpl; Purpose: provide Stage 5A static configuration safety without claiming full YashanDB parameter coverage.
	REDO_FILE_SIZE?: =~"^[1-9][0-9]*[KMG]$"
	REDO_FILE_NUM?: int & >=1 & <=128
	INSTALL_SIMPLE_SCHEMA_SALES?: "Y" | "N" | "y" | "n"
	NLS_CHARACTERSET?: "UTF8" | "GBK"

	LISTEN_ADDR?: =~"^.+:[0-9]{1,5}$"
	DB_BLOCK_SIZE?: "2K" | "4K" | "8K" | "16K" | "32K"
	DATA_BUFFER_SIZE?: =~"^[1-9][0-9]*[KMG]$"
	SHARE_POOL_SIZE?: =~"^[1-9][0-9]*[KMG]$"
	WORK_AREA_POOL_SIZE?: =~"^[1-9][0-9]*[KMG]$"
	LARGE_POOL_SIZE?: =~"^[1-9][0-9]*[KMG]$"
	REDO_BUFFER_SIZE?: =~"^[1-9][0-9]*[KMG]$"
	UNDO_RETENTION?: int & >=0
	OPEN_CURSORS?: int & >=1
	MAX_SESSIONS?: int & >=1
	RUN_LOG_LEVEL?: "DEBUG" | "INFO" | "WARN" | "ERROR" | "FATAL"
	NODE_ID?: =~"^[0-9]+-[0-9]+:[0-9]+$"
}
