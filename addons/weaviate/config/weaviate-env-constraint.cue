#WeaviateEnvs: {

	// Which modules to enable in the setup?
	ENABLE_MODULES?: string

	// The endpoint where to reach the transformers module if enabled
	TRANSFORMERS_INFERENCE_API?: string

	// The endpoint where to reach the clip module if enabled
	CLIP_INFERENCE_API?: string

	// The endpoint where to reach the img2vec-neural module if enabled
	IMAGE_INFERENCE_API?: string

	// The id of the AWS access key for the desired account.
	AWS_ACCESS_KEY_ID?: string

	// The secret AWS access key for the desired account.
	AWS_SECRET_ACCESS_KEY?: string

	// The path to the secret GCP service account or workload identity file.
	GOOGLE_APPLICATION_CREDENTIALS?: string

	// The name of your Azure Storage account.
	AZURE_STORAGE_ACCOUNT?: string

	// An access key for your Azure Storage account.
	AZURE_STORAGE_KEY?: string

	// A string that includes the authorization information required.
	AZURE_STORAGE_CONNECTION_STRING?: string

	QNA_INFERENCE_API?: string

	SPELLCHECK_INFERENCE_API?: string

	NER_INFERENCE_API?: string

	SUM_INFERENCE_API?: string

	OPENAI_APIKEY?: string

	HUGGINGFACE_APIKEY?: string

	COHERE_APIKEY?: string

	PALM_APIKEY?: string

	// Enables API key authentication.
	AUTHENTICATION_APIKEY_ENABLED?: string

	// List one or more keys, separated by commas. Each key corresponds to a specific user identity below.
	AUTHENTICATION_APIKEY_ALLOWED_KEYS?: string

	// List one or more user identities, separated by commas. Each identity corresponds to a specific key above.
	AUTHENTICATION_APIKEY_USERS?: string

	AUTHORIZATION_ADMINLIST_ENABLED?: string

	AUTHORIZATION_ADMINLIST_USERS?: string

	AUTHORIZATION_ADMINLIST_READONLY_USERS?: string
}
