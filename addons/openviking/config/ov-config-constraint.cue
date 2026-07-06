// OpenViking ov.conf parameter schema.
//
// All keys are optional so that Reconfiguring OpsRequests can patch any
// subset of parameters without re-supplying the whole document.
#OpenVikingParameter: {
	storage?: {
		// Local workspace directory for the RocksDB-backed store.
		workspace?: string

		vectordb?: {
			// Logical vector database name.
			name?: string
			// Backend implementation. Currently only "local" is supported by the addon.
			backend?: string | *"local"
			// Project identifier used to scope vectors inside the backend.
			project?: string
		}

		agfs?: {
			// AGFS backend implementation. "local" runs in-process.
			backend?: string | *"local"
			// AGFS request timeout in seconds.
			timeout?: int & >=1 & <=600
		}
	}

	log?: {
		// Log level. Valid values: DEBUG, INFO, WARN, ERROR.
		level?: "DEBUG" | "INFO" | "WARN" | "ERROR" | *"INFO"
		// Log output destination: "stdout" or a file path.
		output?: string | *"stdout"
	}

	server?: {
		// Bind address.
		host?: string | *"0.0.0.0"
		// HTTP port. Must match servicePort in the addon values.
		port?: int & >=1 & <=65535 | *1933
		// Number of worker processes. OpenViking uses RocksDB and currently
		// only supports a single worker per pod.
		workers?: int & >=1 & <=1 | *1
		// API key required by clients. Empty disables authentication.
		root_api_key?: string
		// CORS allowed origins.
		cors_origins?: [...string]
	}

	embedding?: {
		dense?: {
			// Embedding service base URL.
			api_base?: string
			// API key for the embedding provider.
			api_key?: string
			// Provider implementation. e.g. "volcengine", "openai".
			provider?: string
			// Embedding vector dimension. Must match the model.
			dimension?: int & >=1 & <=8192
			// Model identifier understood by the provider.
			model?: string
			// Input modality: "text" or "multimodal".
			input?: "text" | "multimodal" | *"text"
		}
		// Maximum concurrent embedding requests.
		max_concurrent?: int & >=1 & <=1024
	}

	vlm?: {
		// VLM service base URL.
		api_base?: string
		// API key for the VLM provider.
		api_key?: string
		// Provider implementation.
		provider?: string
		// Model identifier.
		model?: string
		// Sampling temperature.
		temperature?: float & >=0.0 & <=2.0
		// Maximum number of retries on transient errors.
		max_retries?: int & >=0 & <=10
		// Whether to enable model "thinking" / chain-of-thought mode.
		thinking?: bool
		// Maximum concurrent VLM requests.
		max_concurrent?: int & >=1 & <=1024
	}
}
