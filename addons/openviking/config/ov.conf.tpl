{
  "storage": {
    "workspace": "{{ .Values.config.storage.workspace }}",
    "vectordb": {
      "name": "{{ .Values.config.storage.vectordb.name }}",
      "backend": "{{ .Values.config.storage.vectordb.backend }}",
      "project": "{{ .Values.config.storage.vectordb.project }}"
    },
    "agfs": {
      "backend": "{{ .Values.config.storage.agfs.backend }}",
      "timeout": {{ .Values.config.storage.agfs.timeout }}
    }
  },
  "log": {
    "level": "{{ .Values.config.log.level }}",
    "output": "{{ .Values.config.log.output }}"
  },
  "server": {
    "host": "{{ .Values.config.server.host }}",
    "port": {{ .Values.config.server.port }},
    "workers": {{ .Values.config.server.workers }},
    "root_api_key": "{{ .Values.config.server.root_api_key }}",
    "cors_origins": {{ .Values.config.server.cors_origins | toJson }}
  },
  "embedding": {
    "dense": {
      "api_base": "{{ .Values.config.embedding.dense.api_base }}",
      "api_key": "{{ .Values.config.embedding.dense.api_key }}",
      "provider": "{{ .Values.config.embedding.dense.provider }}",
      "dimension": {{ .Values.config.embedding.dense.dimension }},
      "model": "{{ .Values.config.embedding.dense.model }}",
      "input": "{{ .Values.config.embedding.dense.input }}"
    },
    "max_concurrent": {{ .Values.config.embedding.max_concurrent }}
  },
  "vlm": {
    "api_base": "{{ .Values.config.vlm.api_base }}",
    "api_key": "{{ .Values.config.vlm.api_key }}",
    "provider": "{{ .Values.config.vlm.provider }}",
    "model": "{{ .Values.config.vlm.model }}",
    "temperature": {{ .Values.config.vlm.temperature }},
    "max_retries": {{ .Values.config.vlm.max_retries }},
    "thinking": {{ .Values.config.vlm.thinking }},
    "max_concurrent": {{ .Values.config.vlm.max_concurrent }}
  }
}
