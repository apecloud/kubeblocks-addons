# VictoriaMetrics Select Configuration

# Basic settings
httpListenAddr: :${SERVICE_PORT}

# High availability settings
storageNode: ${STORAGE_NODE_ADDRESSES}
dedup.minScrapeInterval: ${MIN_SCRAPE_INTERVAL}

# Performance settings
memory.allowedPercent: ${MEMORY_ALLOWED_PERCENT}
search.maxQueryDuration: ${MAX_QUERY_DURATION}
search.maxQueryLen: ${MAX_QUERY_LEN}
search.maxConcurrentRequests: ${MAX_CONCURRENT_REQUESTS}

# Caching settings
cacheExpiry: ${CACHE_EXPIRY}

# Additional settings
{{ if index . "extra_select_flags" }}
{{ range $key, $value := .extra_select_flags }}
{{ $key }}: {{ $value }}
{{ end }}
{{ end }}