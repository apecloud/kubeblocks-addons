# VictoriaMetrics Insert Configuration

# Basic settings
httpListenAddr: :${SERVICE_PORT}

# High availability settings
storageNode: ${STORAGE_NODE_ADDRESSES}
replicationFactor: ${REPLICATION_FACTOR}

# Performance settings
memory.allowedPercent: ${MEMORY_ALLOWED_PERCENT}
maxLabelsPerTimeseries: ${MAX_LABELS_PER_TIMESERIES}
maxLabelValueLen: ${MAX_LABEL_VALUE_LEN}

# Routing settings
disableRerouting: ${DISABLE_REROUTING}
disableReroutingOnUnavailable: ${DISABLE_REROUTING_ON_UNAVAILABLE}

# Additional settings
{{ if index . "extra_insert_flags" }}
{{ range $key, $value := .extra_insert_flags }}
{{ $key }}: {{ $value }}
{{ end }}
{{ end }} 