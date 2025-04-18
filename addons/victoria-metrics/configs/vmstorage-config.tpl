# VictoriaMetrics Storage Configuration

# Basic settings
storageDataPath: /storage
httpListenAddr: :${SERVICE_PORT}
vminsertAddr: :${VMINSERT_PORT}
vmselectAddr: :${VMSELECT_PORT}

# High availability settings
dedup.minScrapeInterval: ${MIN_SCRAPE_INTERVAL}

# Storage retention settings
retentionPeriod: ${RETENTION_PERIOD}

# Performance settings
memory.allowedPercent: ${MEMORY_ALLOWED_PERCENT}
smallMergeThreshold: ${SMALL_MERGE_THRESHOLD}

# Limits
maxHourlySeries: ${MAX_HOURLY_SERIES}
maxDailySeries: ${MAX_DAILY_SERIES}
maxMonthlySeries: ${MAX_MONTHLY_SERIES}

# Additional settings
{{ if index . "extra_storage_flags" }}
{{ range $key, $value := .extra_storage_flags }}
{{ $key }}: {{ $value }}
{{ end }}
{{ end }} 