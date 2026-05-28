{
  "storage": {
    "workspace": {{ index . "storage.workspace" | default (.Values.config.storage.workspace | quote) | quote }},
    "vectordb": {
      "name": {{ index . "storage.vectordb.name" | default (.Values.config.storage.vectordb.name | quote) | quote }},
      "backend": {{ index . "storage.vectordb.backend" | default (.Values.config.storage.vectordb.backend | quote) | quote }},
      "project": {{ index . "storage.vectordb.project" | default (.Values.config.storage.vectordb.project | quote) | quote }}
    },
    "agfs": {
      "backend": {{ index . "storage.agfs.backend" | default (.Values.config.storage.agfs.backend | quote) | quote }},
      "timeout": {{ index . "storage.agfs.timeout" | default .Values.config.storage.agfs.timeout }}
    }
  },
  "log": {
    "level": {{ index . "log.level" | default (.Values.config.log.level | quote) | quote }},
    "output": {{ index . "log.output" | default (.Values.config.log.output | quote) | quote }}
  },
  "server": {
    "host": {{ index . "server.host" | default (.Values.config.server.host | quote) | quote }},
    "port": {{ index . "server.port" | default .Values.config.server.port }},
    "workers": {{ index . "server.workers" | default .Values.config.server.workers }},
    "root_api_key": {{ index . "server.root_api_key" | default (.Values.config.server.root_api_key | quote) | quote }},
    "cors_origins": {{ index . "server.cors_origins" | default (.Values.config.server.cors_origins | toJson) | toJson }}
  },
  "embedding": {
    "dense": {
      "api_base": {{ index . "embedding.dense.api_base" | default (.Values.config.embedding.dense.api_base | quote) | quote }},
      "api_key": {{ index . "embedding.dense.api_key" | default (.Values.config.embedding.dense.api_key | quote) | quote }},
      "provider": {{ index . "embedding.dense.provider" | default (.Values.config.embedding.dense.provider | quote) | quote }},
      "dimension": {{ index . "embedding.dense.dimension" | default .Values.config.embedding.dense.dimension }},
      "model": {{ index . "embedding.dense.model" | default (.Values.config.embedding.dense.model | quote) | quote }},
      "input": {{ index . "embedding.dense.input" | default (.Values.config.embedding.dense.input | quote) | quote }}
    },
    "max_concurrent": {{ index . "embedding.max_concurrent" | default .Values.config.embedding.max_concurrent }}
  },
  "vlm": {
    "api_base": {{ index . "vlm.api_base" | default (.Values.config.vlm.api_base | quote) | quote }},
    "api_key": {{ index . "vlm.api_key" | default (.Values.config.vlm.api_key | quote) | quote }},
    "provider": {{ index . "vlm.provider" | default (.Values.config.vlm.provider | quote) | quote }},
    "model": {{ index . "vlm.model" | default (.Values.config.vlm.model | quote) | quote }},
    "temperature": {{ index . "vlm.temperature" | default .Values.config.vlm.temperature }},
    "max_retries": {{ index . "vlm.max_retries" | default .Values.config.vlm.max_retries }},
    "thinking": {{ index . "vlm.thinking" | default .Values.config.vlm.thinking }},
    "max_concurrent": {{ index . "vlm.max_concurrent" | default .Values.config.vlm.max_concurrent }}
  }
}
