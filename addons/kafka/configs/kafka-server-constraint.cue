package kafka

// Generated from Kafka ConfigDef metadata, using tools/gen-cue.
// Dotted Kafka property names are intentionally kept as flat quoted fields.

#Shared: {
	// Listeners to publish to ZooKeeper for clients to use, if different than the listeners config property. In IaaS environments, this may need to be different from the interface to which the broker binds. If this is not set, the value for listeners will be used. Unlike listeners, it is not valid to advertise the 0.0.0.0 meta-address. Also unlike listeners, there can be duplicated ports in this property, so that one listener can be configured to advertise another listener's address. This can be useful in some cases where external load balancers are used.
	// "advertised.listeners"?: *null | string | null

	// Deprecated. Whether to automatically include JmxReporter even if it's not listed in metric.reporters. This configuration will be removed in Kafka 4.0, users should instead include org.apache.kafka.common.metrics.JmxReporter in metric.reporters in order to enable the JmxReporter.
	"auto.include.jmx.reporter"?: *true | bool

	// Connection close delay on failed authentication: this is the time (in milliseconds) by which connection close will be delayed on authentication failure. This must be configured to be less than connections.max.idle.ms to prevent connection timeout.
	"connection.failed.authentication.delay.ms"?: *100 | int & >=0 & <=2147483647

	// Idle connections timeout: the server socket processor threads close the connections that idle more than this
	"connections.max.idle.ms"?: *600000 | int & >=-9223372036854775808 & <=9223372036854775807

	// When explicitly set to a positive number (the default is 0, not a positive number), a session lifetime that will not exceed the configured value will be communicated to v2.2.0 or later clients when they authenticate. The broker will disconnect any such connection that is not re-authenticated within the session lifetime and that is then subsequently used for any purpose other than re-authentication. Configuration names can optionally be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.oauthbearer.connections.max.reauth.ms=3600000
	"connections.max.reauth.ms"?: *0 | int & >=-9223372036854775808 & <=9223372036854775807

	// Name of listener used for communication between controller and brokers. A broker will use the control.plane.listener.name to locate the endpoint in listeners list, to listen for connections from the controller. For example, if a broker's config is: listeners = INTERNAL://192.1.1.8:9092, EXTERNAL://10.1.1.5:9093, CONTROLLER://192.1.1.8:9094listener.security.protocol.map = INTERNAL:PLAINTEXT, EXTERNAL:SSL, CONTROLLER:SSLcontrol.plane.listener.name = CONTROLLER On startup, the broker will start listening on "192.1.1.8:9094" with security protocol "SSL". On the controller side, when it discovers a broker's published endpoints through ZooKeeper, it will use the control.plane.listener.name to find the endpoint, which it will use to establish connection to the broker. For example, if the broker's published endpoints on ZooKeeper are: "endpoints" : ["INTERNAL://broker1.example.com:9092","EXTERNAL://broker1.example.com:9093","CONTROLLER://broker1.example.com:9094"] and the controller's config is: listener.security.protocol.map = INTERNAL:PLAINTEXT, EXTERNAL:SSL, CONTROLLER:SSLcontrol.plane.listener.name = CONTROLLER then the controller will use "broker1.example.com:9094" with security protocol "SSL" to connect to the broker. If not explicitly configured, the default value will be null and there will be no dedicated endpoints for controller connections. If explicitly configured, the value cannot be the same as the value of inter.broker.listener.name.
	"control.plane.listener.name"?: *null | string | null

	// A comma-separated list of the names of the listeners used by the controller. This is required if running in KRaft mode. When communicating with the controller quorum, the broker will always use the first listener in this list. Note: The ZooKeeper-based controller should not set this configuration.
	// "controller.listener.names"?: *null | string | null

	// The metrics polling interval (in seconds) which can be used in kafka.metrics.reporters implementations.
	"kafka.metrics.polling.interval.secs"?: *10 | int & >=1 & <=2147483647

	// A list of classes to use as Yammer metrics custom reporters. The reporters should implement kafka.metrics.KafkaMetricsReporter trait. If a client wants to expose JMX operations on a custom reporter, the custom reporter needs to additionally implement an MBean trait that extends kafka.metrics.KafkaMetricsReporterMBean trait so that the registered MBean is compliant with the standard MBean convention.
	"kafka.metrics.reporters"?: *[] | [...string]

	// Map between listener names and security protocols. This must be defined for the same security protocol to be usable in more than one port or IP. For example, internal and external traffic can be separated even if SSL is required for both. Concretely, the user could define listeners with names INTERNAL and EXTERNAL and this property as: INTERNAL:SSL,EXTERNAL:SSL. As shown, key and value are separated by a colon and map entries are separated by commas. Each listener name should only appear once in the map. Different security (SSL and SASL) settings can be configured for each listener by adding a normalised prefix (the listener name is lowercased) to the config name. For example, to set a different keystore for the INTERNAL listener, a config with name listener.name.internal.ssl.keystore.location would be set. If the config for the listener name is not set, the config will fallback to the generic config (i.e. ssl.keystore.location). Note that in KRaft a default mapping from the listener names defined by controller.listener.names to PLAINTEXT is assumed if no explicit mapping is provided and no other security protocol is in use.
	// "listener.security.protocol.map"?: *"SASL_SSL:SASL_SSL,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT" | string

	// Listener List - Comma-separated list of URIs we will listen on and the listener names. If the listener name is not a security protocol, listener.security.protocol.map must also be set. Listener names and port numbers must be unique unless %n one listener is an IPv4 address and the other listener is %n an IPv6 address (for the same port).%n Specify hostname as 0.0.0.0 to bind to all interfaces.%n Leave hostname empty to bind to default interface.%n Examples of legal listener lists:%n PLAINTEXT://myhost:9092,SSL://:9091%n CLIENT://0.0.0.0:9092,REPLICATION://localhost:9093%n PLAINTEXT://127.0.0.1:9092,SSL://[::1]:9092%n
	// "listeners"?: *"PLAINTEXT://:9092" | string

	// The maximum connection creation rate we allow in the broker at any time. Listener-level limits may also be configured by prefixing the config name with the listener prefix, for example, listener.name.internal.max.connection.creation.rate.Broker-wide connection rate limit should be configured based on broker capacity while listener limits should be configured based on application requirements. New connections will be throttled if either the listener or the broker limit is reached, with the exception of inter-broker listener. Connections on the inter-broker listener will be throttled only when the listener-level rate limit is reached.
	"max.connection.creation.rate"?: *2147483647 | int & >=0 & <=2147483647

	// The maximum number of connections we allow in the broker at any time. This limit is applied in addition to any per-ip limits configured using max.connections.per.ip. Listener-level limits may also be configured by prefixing the config name with the listener prefix, for example, listener.name.internal.max.connections.per.ip. Broker-wide limit should be configured based on broker capacity while listener limits should be configured based on application requirements. New connections are blocked if either the listener or broker limit is reached. Connections on the inter-broker listener are permitted even if broker-wide limit is reached. The least recently used connection on another listener will be closed in this case.
	"max.connections"?: *2147483647 | int & >=0 & <=2147483647

	// The maximum number of connections we allow from each ip address. This can be set to 0 if there are overrides configured using max.connections.per.ip.overrides property. New connections from the ip address are dropped if the limit is reached.
	"max.connections.per.ip"?: *2147483647 | int & >=0 & <=2147483647

	// A comma-separated list of per-ip or hostname overrides to the default maximum number of connections. An example value is "hostName:100,127.0.0.1:200"
	"max.connections.per.ip.overrides"?: *"" | string

	// A list of classes to use as metrics reporters. Implementing the org.apache.kafka.common.metrics.MetricsReporter interface allows plugging in classes that will be notified of new metric creation. The JmxReporter is always included to register JMX statistics.
	"metric.reporters"?: *[] | [...string]

	// The number of samples maintained to compute metrics.
	"metrics.num.samples"?: *2 | int & >=1 & <=2147483647

	// The highest recording level for metrics.
	"metrics.recording.level"?: *"INFO" | string

	// The window of time a metrics sample is computed over.
	"metrics.sample.window.ms"?: *30000 | int & >=1 & <=9223372036854775807

	// The node ID associated with the roles this process is playing when process.roles is non-empty. This is required configuration when running in KRaft mode.
	// "node.id"?: *-1 | int & >=-2147483648 & <=2147483647

	// The number of threads that the server uses for receiving requests from the network and sending responses to the network. Noted: each listener (except for controller listener) creates its own thread pool.
	"num.network.threads"?: *3 | int & >=1 & <=2147483647

	// The fully qualified name of a class that implements the KafkaPrincipalBuilder interface, which is used to build the KafkaPrincipal object used during authorization. If no principal builder is defined, the default behavior depends on the security protocol in use. For SSL authentication, the principal will be derived using the rules defined by ssl.principal.mapping.rules applied on the distinguished name from the client certificate if one is provided; otherwise, if client authentication is not required, the principal name will be ANONYMOUS. For SASL authentication, the principal will be derived using the rules defined by sasl.kerberos.principal.to.local.rules if GSSAPI is in use, and the SASL authentication ID for other mechanisms. For PLAINTEXT, the principal will be ANONYMOUS.
	"principal.builder.class"?: *"class org.apache.kafka.common.security.authenticator.DefaultKafkaPrincipalBuilder" | string

	// The roles that this process plays: 'broker', 'controller', or 'broker,controller' if it is both. This configuration is only applicable for clusters in KRaft (Kafka Raft) mode (instead of ZooKeeper). Leave this config undefined or empty for ZooKeeper clusters.
	// "process.roles"?: *[] | [...("broker" | "controller")]

	// The number of queued bytes allowed before no more requests are read
	"queued.max.request.bytes"?: *-1 | int & >=-9223372036854775808 & <=9223372036854775807

	// The number of queued requests allowed for data-plane, before blocking the network threads
	"queued.max.requests"?: *500 | int & >=1 & <=2147483647

	// The fully qualified name of a SASL client callback handler class that implements the AuthenticateCallbackHandler interface.
	"sasl.client.callback.handler.class"?: *null | string | null

	// The list of SASL mechanisms enabled in the Kafka server. The list may contain any mechanism for which a security provider is available. Only GSSAPI is enabled by default.
	"sasl.enabled.mechanisms"?: *["GSSAPI"] | [...string]

	// JAAS login context parameters for SASL connections in the format used by JAAS configuration files. JAAS configuration file format is described here. The format for the value is: loginModuleClass controlFlag (optionName=optionValue)*;. For brokers, the config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.jaas.config=com.example.ScramLoginModule required;
	"sasl.jaas.config"?: *null | string | null

	// Kerberos kinit command path.
	"sasl.kerberos.kinit.cmd"?: *"/usr/bin/kinit" | string

	// Login thread sleep time between refresh attempts.
	"sasl.kerberos.min.time.before.relogin"?: *60000 | int & >=-9223372036854775808 & <=9223372036854775807

	// A list of rules for mapping from principal names to short names (typically operating system usernames). The rules are evaluated in order and the first rule that matches a principal name is used to map it to a short name. Any later rules in the list are ignored. By default, principal names of the form {username}/{hostname}@{REALM} are mapped to {username}. For more details on the format please see security authorization and acls. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the principal.builder.class configuration.
	"sasl.kerberos.principal.to.local.rules"?: *["DEFAULT"] | [...string]

	// The Kerberos principal name that Kafka runs as. This can be defined either in Kafka's JAAS config or in Kafka's config.
	"sasl.kerberos.service.name"?: *null | string | null

	// Percentage of random jitter added to the renewal time.
	"sasl.kerberos.ticket.renew.jitter"?: *0.05 | number

	// Login thread will sleep until the specified window factor of time from last refresh to ticket's expiry has been reached, at which time it will try to renew the ticket.
	"sasl.kerberos.ticket.renew.window.factor"?: *0.8 | number

	// The fully qualified name of a SASL login callback handler class that implements the AuthenticateCallbackHandler interface. For brokers, login callback handler config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.login.callback.handler.class=com.example.CustomScramLoginCallbackHandler
	"sasl.login.callback.handler.class"?: *null | string | null

	// The fully qualified name of a class that implements the Login interface. For brokers, login config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.login.class=com.example.CustomScramLogin
	"sasl.login.class"?: *null | string | null

	// The (optional) value in milliseconds for the external authentication provider connection timeout. Currently applies only to OAUTHBEARER.
	"sasl.login.connect.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The (optional) value in milliseconds for the external authentication provider read timeout. Currently applies only to OAUTHBEARER.
	"sasl.login.read.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The amount of buffer time before credential expiration to maintain when refreshing a credential, in seconds. If a refresh would otherwise occur closer to expiration than the number of buffer seconds then the refresh will be moved up to maintain as much of the buffer time as possible. Legal values are between 0 and 3600 (1 hour); a default value of 300 (5 minutes) is used if no value is specified. This value and sasl.login.refresh.min.period.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.buffer.seconds"?: *300 | int & >=-32768 & <=32767

	// The desired minimum time for the login refresh thread to wait before refreshing a credential, in seconds. Legal values are between 0 and 900 (15 minutes); a default value of 60 (1 minute) is used if no value is specified. This value and sasl.login.refresh.buffer.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.min.period.seconds"?: *60 | int & >=-32768 & <=32767

	// Login refresh thread will sleep until the specified window factor relative to the credential's lifetime has been reached, at which time it will try to refresh the credential. Legal values are between 0.5 (50%) and 1.0 (100%) inclusive; a default value of 0.8 (80%) is used if no value is specified. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.window.factor"?: *0.8 | number

	// The maximum amount of random jitter relative to the credential's lifetime that is added to the login refresh thread's sleep time. Legal values are between 0 and 0.25 (25%) inclusive; a default value of 0.05 (5%) is used if no value is specified. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.window.jitter"?: *0.05 | number

	// The (optional) value in milliseconds for the maximum wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to OAUTHBEARER.
	"sasl.login.retry.backoff.max.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the initial wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to OAUTHBEARER.
	"sasl.login.retry.backoff.ms"?: *100 | int & >=-9223372036854775808 & <=9223372036854775807

	// SASL mechanism used for communication with controllers. Default is GSSAPI.
	"sasl.mechanism.controller.protocol"?: *"GSSAPI" | string

	// SASL mechanism used for inter-broker communication. Default is GSSAPI.
	"sasl.mechanism.inter.broker.protocol"?: *"GSSAPI" | string

	// The (optional) value in seconds to allow for differences between the time of the OAuth/OIDC identity provider and the broker.
	"sasl.oauthbearer.clock.skew.seconds"?: *30 | int & >=-2147483648 & <=2147483647

	// The (optional) comma-delimited setting for the broker to use to verify that the JWT was issued for one of the expected audiences. The JWT will be inspected for the standard OAuth "aud" claim and if this value is set, the broker will match the value from JWT's "aud" claim to see if there is an exact match. If there is no match, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.expected.audience"?: *null | [...string] | null

	// The (optional) setting for the broker to use to verify that the JWT was created by the expected issuer. The JWT will be inspected for the standard OAuth "iss" claim and if this value is set, the broker will match it exactly against what is in the JWT's "iss" claim. If there is no match, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.expected.issuer"?: *null | string | null

	// The (optional) value in milliseconds for the broker to wait between refreshing its JWKS (JSON Web Key Set) cache that contains the keys to verify the signature of the JWT.
	"sasl.oauthbearer.jwks.endpoint.refresh.ms"?: *3600000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the maximum wait between attempts to retrieve the JWKS (JSON Web Key Set) from the external authentication provider. JWKS retrieval uses an exponential backoff algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
	"sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the initial wait between JWKS (JSON Web Key Set) retrieval attempts from the external authentication provider. JWKS retrieval uses an exponential backoff algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
	"sasl.oauthbearer.jwks.endpoint.retry.backoff.ms"?: *100 | int & >=-9223372036854775808 & <=9223372036854775807

	// The OAuth/OIDC provider URL from which the provider's JWKS (JSON Web Key Set) can be retrieved. The URL can be HTTP(S)-based or file-based. If the URL is HTTP(S)-based, the JWKS data will be retrieved from the OAuth/OIDC provider via the configured URL on broker startup. All then-current keys will be cached on the broker for incoming requests. If an authentication request is received for a JWT that includes a "kid" header claim value that isn't yet in the cache, the JWKS endpoint will be queried again on demand. However, the broker polls the URL every sasl.oauthbearer.jwks.endpoint.refresh.ms milliseconds to refresh the cache with any forthcoming keys before any JWT requests that include them are received. If the URL is file-based, the broker will load the JWKS file from a configured location on startup. In the event that the JWT includes a "kid" header value that isn't in the JWKS file, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.jwks.endpoint.url"?: *null | string | null

	// The OAuth claim for the scope is often named "scope", but this (optional) setting can provide a different name to use for the scope included in the JWT payload's claims if the OAuth/OIDC provider uses a different name for that claim.
	"sasl.oauthbearer.scope.claim.name"?: *"scope" | string

	// The OAuth claim for the subject is often named "sub", but this (optional) setting can provide a different name to use for the subject included in the JWT payload's claims if the OAuth/OIDC provider uses a different name for that claim.
	"sasl.oauthbearer.sub.claim.name"?: *"sub" | string

	// The URL for the OAuth/OIDC identity provider. If the URL is HTTP(S)-based, it is the issuer's token endpoint URL to which requests will be made to login based on the configuration in sasl.jaas.config. If the URL is file-based, it specifies a file containing an access token (in JWT serialized form) issued by the OAuth/OIDC identity provider to use for authorization.
	"sasl.oauthbearer.token.endpoint.url"?: *null | string | null

	// The fully qualified name of a SASL server callback handler class that implements the AuthenticateCallbackHandler interface. Server callback handlers must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.plain.sasl.server.callback.handler.class=com.example.CustomPlainCallbackHandler.
	"sasl.server.callback.handler.class"?: *null | string | null

	// The maximum receive size allowed before and during initial SASL authentication. Default receive size is 512KB. GSSAPI limits requests to 64K, but we allow upto 512KB by default for custom SASL mechanisms. In practice, PLAIN, SCRAM and OAUTH mechanisms can use much smaller limits.
	"sasl.server.max.receive.size"?: *524288 | int & >=-2147483648 & <=2147483647

	// A list of configurable creator classes each returning a provider implementing security algorithms. These classes should implement the org.apache.kafka.common.security.auth.SecurityProviderCreator interface.
	"security.providers"?: *null | string | null

	// The maximum number of pending connections on the socket. In Linux, you may also need to configure somaxconn and tcp_max_syn_backlog kernel parameters accordingly to make the configuration takes effect.
	"socket.listen.backlog.size"?: *50 | int & >=1 & <=2147483647

	// The SO_RCVBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
	"socket.receive.buffer.bytes"?: *102400 | int & >=-2147483648 & <=2147483647

	// The maximum number of bytes in a socket request
	"socket.request.max.bytes"?: *104857600 | int & >=1 & <=2147483647

	// The SO_SNDBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
	"socket.send.buffer.bytes"?: *102400 | int & >=-2147483648 & <=2147483647

	// Indicates whether changes to the certificate distinguished name should be allowed during a dynamic reconfiguration of certificates or not.
	"ssl.allow.dn.changes"?: *false | bool

	// Indicates whether changes to the certificate subject alternative names should be allowed during a dynamic reconfiguration of certificates or not.
	"ssl.allow.san.changes"?: *false | bool

	// A list of cipher suites. This is a named combination of authentication, encryption, MAC and key exchange algorithm used to negotiate the security settings for a network connection using TLS or SSL network protocol. By default all the available cipher suites are supported.
	"ssl.cipher.suites"?: *[] | [...string]

	// Configures kafka broker to request client authentication. The following settings are common: ssl.client.auth=required If set to required client authentication is required. ssl.client.auth=requested This means client authentication is optional. unlike required, if this option is set client can choose not to provide authentication information about itself ssl.client.auth=none This means client authentication is not needed.
	"ssl.client.auth"?: *"none" | string & ("required" | "requested" | "none")

	// The list of protocols enabled for SSL connections. The default is 'TLSv1.2,TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. With the default value for Java 11, clients and servers will prefer TLSv1.3 if both support it and fallback to TLSv1.2 otherwise (assuming both support at least TLSv1.2). This default should be fine for most cases. Also see the config documentation for `ssl.protocol`.
	"ssl.enabled.protocols"?: *["TLSv1.2", "TLSv1.3"] | [...string]

	// The endpoint identification algorithm to validate server hostname using server certificate.
	"ssl.endpoint.identification.algorithm"?: *"https" | string

	// The class of type org.apache.kafka.common.security.auth.SslEngineFactory to provide SSLEngine objects. Default value is org.apache.kafka.common.security.ssl.DefaultSslEngineFactory. Alternatively, setting this to org.apache.kafka.common.security.ssl.CommonNameLoggingSslEngineFactory will log the common name of expired SSL certificates used by clients to authenticate at any of the brokers with log level INFO. Note that this will cause a tiny delay during establishment of new connections from mTLS clients to brokers due to the extra code for examining the certificate chain provided by the client. Note further that the implementation uses a custom truststore based on the standard Java truststore and thus might be considered a security risk due to not being as mature as the standard one.
	"ssl.engine.factory.class"?: *null | string | null

	// The password of the private key in the key store file or the PEM key specified in 'ssl.keystore.key'.
	"ssl.key.password"?: *null | string | null

	// The algorithm used by key manager factory for SSL connections. Default value is the key manager factory algorithm configured for the Java Virtual Machine.
	"ssl.keymanager.algorithm"?: *"SunX509" | string

	// Certificate chain in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with a list of X.509 certificates
	"ssl.keystore.certificate.chain"?: *null | string | null

	// Private key in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with PKCS#8 keys. If the key is encrypted, key password must be specified using 'ssl.key.password'
	"ssl.keystore.key"?: *null | string | null

	// The location of the key store file. This is optional for client and can be used for two-way authentication for client.
	"ssl.keystore.location"?: *null | string | null

	// The store password for the key store file. This is optional for client and only needed if 'ssl.keystore.location' is configured. Key store password is not supported for PEM format.
	"ssl.keystore.password"?: *null | string | null

	// The file format of the key store file. This is optional for client. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
	// "ssl.keystore.type"?: *"JKS" | string

	// A list of rules for mapping from distinguished name from the client certificate to short name. The rules are evaluated in order and the first rule that matches a principal name is used to map it to a short name. Any later rules in the list are ignored. By default, distinguished name of the X.500 certificate will be the principal. For more details on the format please see security authorization and acls. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the principal.builder.class configuration.
	"ssl.principal.mapping.rules"?: *"DEFAULT" | string

	// The SSL protocol used to generate the SSLContext. The default is 'TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. This value should be fine for most use cases. Allowed values in recent JVMs are 'TLSv1.2' and 'TLSv1.3'. 'TLS', 'TLSv1.1', 'SSL', 'SSLv2' and 'SSLv3' may be supported in older JVMs, but their usage is discouraged due to known security vulnerabilities. With the default value for this config and 'ssl.enabled.protocols', clients will downgrade to 'TLSv1.2' if the server does not support 'TLSv1.3'. If this config is set to 'TLSv1.2', clients will not use 'TLSv1.3' even if it is one of the values in ssl.enabled.protocols and the server only supports 'TLSv1.3'.
	"ssl.protocol"?: *"TLSv1.3" | string

	// The name of the security provider used for SSL connections. Default value is the default security provider of the JVM.
	"ssl.provider"?: *null | string | null

	// The SecureRandom PRNG implementation to use for SSL cryptography operations.
	"ssl.secure.random.implementation"?: *null | string | null

	// The algorithm used by trust manager factory for SSL connections. Default value is the trust manager factory algorithm configured for the Java Virtual Machine.
	"ssl.trustmanager.algorithm"?: *"PKIX" | string

	// Trusted certificates in the format specified by 'ssl.truststore.type'. Default SSL engine factory supports only PEM format with X.509 certificates.
	"ssl.truststore.certificates"?: *null | string | null

	// The location of the trust store file.
	"ssl.truststore.location"?: *null | string | null

	// The password for the trust store file. If a password is not set, trust store file configured will still be used, but integrity checking is disabled. Trust store password is not supported for PEM format.
	"ssl.truststore.password"?: *null | string | null

	// The file format of the trust store file. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
	"ssl.truststore.type"?: *"JKS" | string

	// The maximum size (after compression if compression is used) of telemetry metrics pushed from a client to the broker. The default value is 1048576 (1 MB).
	"telemetry.max.bytes"?: *1048576 | int & >=1 & <=2147483647

}

#Controller: {
	// Listeners to publish to ZooKeeper for clients to use, if different than the listeners config property. In IaaS environments, this may need to be different from the interface to which the broker binds. If this is not set, the value for listeners will be used. Unlike listeners, it is not valid to advertise the 0.0.0.0 meta-address. Also unlike listeners, there can be duplicated ports in this property, so that one listener can be configured to advertise another listener's address. This can be useful in some cases where external load balancers are used.
	// "advertised.listeners"?: *null | string | null

	// Deprecated. Whether to automatically include JmxReporter even if it's not listed in metric.reporters. This configuration will be removed in Kafka 4.0, users should instead include org.apache.kafka.common.metrics.JmxReporter in metric.reporters in order to enable the JmxReporter.
	"auto.include.jmx.reporter"?: *true | bool

	// Connection close delay on failed authentication: this is the time (in milliseconds) by which connection close will be delayed on authentication failure. This must be configured to be less than connections.max.idle.ms to prevent connection timeout.
	"connection.failed.authentication.delay.ms"?: *100 | int & >=0 & <=2147483647

	// Idle connections timeout: the server socket processor threads close the connections that idle more than this
	"connections.max.idle.ms"?: *600000 | int & >=-9223372036854775808 & <=9223372036854775807

	// When explicitly set to a positive number (the default is 0, not a positive number), a session lifetime that will not exceed the configured value will be communicated to v2.2.0 or later clients when they authenticate. The broker will disconnect any such connection that is not re-authenticated within the session lifetime and that is then subsequently used for any purpose other than re-authentication. Configuration names can optionally be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.oauthbearer.connections.max.reauth.ms=3600000
	"connections.max.reauth.ms"?: *0 | int & >=-9223372036854775808 & <=9223372036854775807

	// Name of listener used for communication between controller and brokers. A broker will use the control.plane.listener.name to locate the endpoint in listeners list, to listen for connections from the controller. For example, if a broker's config is: listeners = INTERNAL://192.1.1.8:9092, EXTERNAL://10.1.1.5:9093, CONTROLLER://192.1.1.8:9094listener.security.protocol.map = INTERNAL:PLAINTEXT, EXTERNAL:SSL, CONTROLLER:SSLcontrol.plane.listener.name = CONTROLLER On startup, the broker will start listening on "192.1.1.8:9094" with security protocol "SSL". On the controller side, when it discovers a broker's published endpoints through ZooKeeper, it will use the control.plane.listener.name to find the endpoint, which it will use to establish connection to the broker. For example, if the broker's published endpoints on ZooKeeper are: "endpoints" : ["INTERNAL://broker1.example.com:9092","EXTERNAL://broker1.example.com:9093","CONTROLLER://broker1.example.com:9094"] and the controller's config is: listener.security.protocol.map = INTERNAL:PLAINTEXT, EXTERNAL:SSL, CONTROLLER:SSLcontrol.plane.listener.name = CONTROLLER then the controller will use "broker1.example.com:9094" with security protocol "SSL" to connect to the broker. If not explicitly configured, the default value will be null and there will be no dedicated endpoints for controller connections. If explicitly configured, the value cannot be the same as the value of inter.broker.listener.name.
	"control.plane.listener.name"?: *null | string | null

	// A comma-separated list of the names of the listeners used by the controller. This is required if running in KRaft mode. When communicating with the controller quorum, the broker will always use the first listener in this list. Note: The ZooKeeper-based controller should not set this configuration.
	// "controller.listener.names"?: *null | string | null

	// The duration in milliseconds that the leader will wait for writes to accumulate before flushing them to disk.
	"controller.quorum.append.linger.ms"?: *25 | int & >=-2147483648 & <=2147483647

	// validator: non-empty list
	// List of endpoints to use for bootstrapping the cluster metadata. The endpoints are specified in comma-separated list of {host}:{port} entries. For example: localhost:9092,localhost:9093,localhost:9094.
	// "controller.quorum.bootstrap.servers"?: *[] | [...string]

	// Maximum time in milliseconds before starting new elections. This is used in the binary exponential backoff mechanism that helps prevent gridlocked elections
	"controller.quorum.election.backoff.max.ms"?: *1000 | int & >=-2147483648 & <=2147483647

	// Maximum time in milliseconds to wait without being able to fetch from the leader before triggering a new election
	"controller.quorum.election.timeout.ms"?: *1000 | int & >=-2147483648 & <=2147483647

	// Maximum time without a successful fetch from the current leader before becoming a candidate and triggering an election for voters; Maximum time a leader can go without receiving valid fetch or fetchSnapshot request from a majority of the quorum before resigning.
	"controller.quorum.fetch.timeout.ms"?: *2000 | int & >=-2147483648 & <=2147483647

	// The configuration controls the maximum amount of time the client will wait for the response of a request. If the response is not received before the timeout elapses the client will resend the request if necessary or fail the request if retries are exhausted.
	"controller.quorum.request.timeout.ms"?: *2000 | int & >=-2147483648 & <=2147483647

	// The amount of time to wait before attempting to retry a failed request to a given topic partition. This avoids repeatedly sending requests in a tight loop under some failure scenarios. This value is the initial backoff value and will increase exponentially for each failed request, up to the retry.backoff.max.ms value.
	"controller.quorum.retry.backoff.ms"?: *20 | int & >=-2147483648 & <=2147483647

	// validator: non-empty list
	// Map of id/endpoint information for the set of voters in a comma-separated list of {id}@{host}:{port} entries. For example: 1@localhost:9092,2@localhost:9093,3@localhost:9094
	// "controller.quorum.voters"?: *[] | [...string]

	// Enables delete topic. Delete topic through the admin tool will have no effect if this config is turned off
	"delete.topic.enable"?: *true | bool

	// Enable the Eligible leader replicas
	"eligible.leader.replicas.enable"?: *false | bool

	// The metrics polling interval (in seconds) which can be used in kafka.metrics.reporters implementations.
	"kafka.metrics.polling.interval.secs"?: *10 | int & >=1 & <=2147483647

	// A list of classes to use as Yammer metrics custom reporters. The reporters should implement kafka.metrics.KafkaMetricsReporter trait. If a client wants to expose JMX operations on a custom reporter, the custom reporter needs to additionally implement an MBean trait that extends kafka.metrics.KafkaMetricsReporterMBean trait so that the registered MBean is compliant with the standard MBean convention.
	"kafka.metrics.reporters"?: *[] | [...string]

	// Map between listener names and security protocols. This must be defined for the same security protocol to be usable in more than one port or IP. For example, internal and external traffic can be separated even if SSL is required for both. Concretely, the user could define listeners with names INTERNAL and EXTERNAL and this property as: INTERNAL:SSL,EXTERNAL:SSL. As shown, key and value are separated by a colon and map entries are separated by commas. Each listener name should only appear once in the map. Different security (SSL and SASL) settings can be configured for each listener by adding a normalised prefix (the listener name is lowercased) to the config name. For example, to set a different keystore for the INTERNAL listener, a config with name listener.name.internal.ssl.keystore.location would be set. If the config for the listener name is not set, the config will fallback to the generic config (i.e. ssl.keystore.location). Note that in KRaft a default mapping from the listener names defined by controller.listener.names to PLAINTEXT is assumed if no explicit mapping is provided and no other security protocol is in use.
	// "listener.security.protocol.map"?: *"SASL_SSL:SASL_SSL,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT" | string

	// Listener List - Comma-separated list of URIs we will listen on and the listener names. If the listener name is not a security protocol, listener.security.protocol.map must also be set. Listener names and port numbers must be unique unless %n one listener is an IPv4 address and the other listener is %n an IPv6 address (for the same port).%n Specify hostname as 0.0.0.0 to bind to all interfaces.%n Leave hostname empty to bind to default interface.%n Examples of legal listener lists:%n PLAINTEXT://myhost:9092,SSL://:9091%n CLIENT://0.0.0.0:9092,REPLICATION://localhost:9093%n PLAINTEXT://127.0.0.1:9092,SSL://[::1]:9092%n
	// "listeners"?: *"PLAINTEXT://:9092" | string

	// The maximum connection creation rate we allow in the broker at any time. Listener-level limits may also be configured by prefixing the config name with the listener prefix, for example, listener.name.internal.max.connection.creation.rate.Broker-wide connection rate limit should be configured based on broker capacity while listener limits should be configured based on application requirements. New connections will be throttled if either the listener or the broker limit is reached, with the exception of inter-broker listener. Connections on the inter-broker listener will be throttled only when the listener-level rate limit is reached.
	"max.connection.creation.rate"?: *2147483647 | int & >=0 & <=2147483647

	// The maximum number of connections we allow in the broker at any time. This limit is applied in addition to any per-ip limits configured using max.connections.per.ip. Listener-level limits may also be configured by prefixing the config name with the listener prefix, for example, listener.name.internal.max.connections.per.ip. Broker-wide limit should be configured based on broker capacity while listener limits should be configured based on application requirements. New connections are blocked if either the listener or broker limit is reached. Connections on the inter-broker listener are permitted even if broker-wide limit is reached. The least recently used connection on another listener will be closed in this case.
	"max.connections"?: *2147483647 | int & >=0 & <=2147483647

	// The maximum number of connections we allow from each ip address. This can be set to 0 if there are overrides configured using max.connections.per.ip.overrides property. New connections from the ip address are dropped if the limit is reached.
	"max.connections.per.ip"?: *2147483647 | int & >=0 & <=2147483647

	// A comma-separated list of per-ip or hostname overrides to the default maximum number of connections. An example value is "hostName:100,127.0.0.1:200"
	"max.connections.per.ip.overrides"?: *"" | string

	// This configuration determines where we put the metadata log for clusters in KRaft mode. If it is not set, the metadata log is placed in the first log directory from log.dirs.
	"metadata.log.dir"?: *null | string | null

	// This is the maximum number of bytes in the log between the latest snapshot and the high-watermark needed before generating a new snapshot. The default value is 20971520. To generate snapshots based on the time elapsed, see the metadata.log.max.snapshot.interval.ms configuration. The Kafka node will generate a snapshot when either the maximum time interval is reached or the maximum bytes limit is reached.
	"metadata.log.max.record.bytes.between.snapshots"?: *20971520 | int & >=1 & <=9223372036854775807

	// This is the maximum number of milliseconds to wait to generate a snapshot if there are committed records in the log that are not included in the latest snapshot. A value of zero disables time based snapshot generation. The default value is 3600000. To generate snapshots based on the number of metadata bytes, see the metadata.log.max.record.bytes.between.snapshots configuration. The Kafka node will generate a snapshot when either the maximum time interval is reached or the maximum bytes limit is reached.
	"metadata.log.max.snapshot.interval.ms"?: *3600000 | int & >=0 & <=9223372036854775807

	// The maximum size of a single metadata log file.
	"metadata.log.segment.bytes"?: *1073741824 | int & >=12 & <=2147483647

	// The maximum time before a new metadata log file is rolled out (in milliseconds).
	"metadata.log.segment.ms"?: *604800000 | int & >=-9223372036854775808 & <=9223372036854775807

	// This configuration controls how often the active controller should write no-op records to the metadata partition. If the value is 0, no-op records are not appended to the metadata partition. The default value is 500
	"metadata.max.idle.interval.ms"?: *500 | int & >=0 & <=2147483647

	// The maximum combined size of the metadata log and snapshots before deleting old snapshots and log files. Since at least one snapshot must exist before any logs can be deleted, this is a soft limit.
	"metadata.max.retention.bytes"?: *104857600 | int & >=-9223372036854775808 & <=9223372036854775807

	// The number of milliseconds to keep a metadata log file or snapshot before deleting it. Since at least one snapshot must exist before any logs can be deleted, this is a soft limit.
	"metadata.max.retention.ms"?: *604800000 | int & >=-9223372036854775808 & <=9223372036854775807

	// A list of classes to use as metrics reporters. Implementing the org.apache.kafka.common.metrics.MetricsReporter interface allows plugging in classes that will be notified of new metric creation. The JmxReporter is always included to register JMX statistics.
	"metric.reporters"?: *[] | [...string]

	// The number of samples maintained to compute metrics.
	"metrics.num.samples"?: *2 | int & >=1 & <=2147483647

	// The highest recording level for metrics.
	"metrics.recording.level"?: *"INFO" | string

	// The window of time a metrics sample is computed over.
	"metrics.sample.window.ms"?: *30000 | int & >=1 & <=9223372036854775807

	// The node ID associated with the roles this process is playing when process.roles is non-empty. This is required configuration when running in KRaft mode.
	// "node.id"?: *-1 | int & >=-2147483648 & <=2147483647

	// The number of threads that the server uses for receiving requests from the network and sending responses to the network. Noted: each listener (except for controller listener) creates its own thread pool.
	"num.network.threads"?: *3 | int & >=1 & <=2147483647

	// The fully qualified name of a class that implements the KafkaPrincipalBuilder interface, which is used to build the KafkaPrincipal object used during authorization. If no principal builder is defined, the default behavior depends on the security protocol in use. For SSL authentication, the principal will be derived using the rules defined by ssl.principal.mapping.rules applied on the distinguished name from the client certificate if one is provided; otherwise, if client authentication is not required, the principal name will be ANONYMOUS. For SASL authentication, the principal will be derived using the rules defined by sasl.kerberos.principal.to.local.rules if GSSAPI is in use, and the SASL authentication ID for other mechanisms. For PLAINTEXT, the principal will be ANONYMOUS.
	"principal.builder.class"?: *"class org.apache.kafka.common.security.authenticator.DefaultKafkaPrincipalBuilder" | string

	// The roles that this process plays: 'broker', 'controller', or 'broker,controller' if it is both. This configuration is only applicable for clusters in KRaft (Kafka Raft) mode (instead of ZooKeeper). Leave this config undefined or empty for ZooKeeper clusters.
	// "process.roles"?: *[] | [...("broker" | "controller")]

	// The number of queued bytes allowed before no more requests are read
	"queued.max.request.bytes"?: *-1 | int & >=-9223372036854775808 & <=9223372036854775807

	// The number of queued requests allowed for data-plane, before blocking the network threads
	"queued.max.requests"?: *500 | int & >=1 & <=2147483647

	// The fully qualified name of a SASL client callback handler class that implements the AuthenticateCallbackHandler interface.
	"sasl.client.callback.handler.class"?: *null | string | null

	// The list of SASL mechanisms enabled in the Kafka server. The list may contain any mechanism for which a security provider is available. Only GSSAPI is enabled by default.
	"sasl.enabled.mechanisms"?: *["GSSAPI"] | [...string]

	// JAAS login context parameters for SASL connections in the format used by JAAS configuration files. JAAS configuration file format is described here. The format for the value is: loginModuleClass controlFlag (optionName=optionValue)*;. For brokers, the config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.jaas.config=com.example.ScramLoginModule required;
	"sasl.jaas.config"?: *null | string | null

	// Kerberos kinit command path.
	"sasl.kerberos.kinit.cmd"?: *"/usr/bin/kinit" | string

	// Login thread sleep time between refresh attempts.
	"sasl.kerberos.min.time.before.relogin"?: *60000 | int & >=-9223372036854775808 & <=9223372036854775807

	// A list of rules for mapping from principal names to short names (typically operating system usernames). The rules are evaluated in order and the first rule that matches a principal name is used to map it to a short name. Any later rules in the list are ignored. By default, principal names of the form {username}/{hostname}@{REALM} are mapped to {username}. For more details on the format please see security authorization and acls. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the principal.builder.class configuration.
	"sasl.kerberos.principal.to.local.rules"?: *["DEFAULT"] | [...string]

	// The Kerberos principal name that Kafka runs as. This can be defined either in Kafka's JAAS config or in Kafka's config.
	"sasl.kerberos.service.name"?: *null | string | null

	// Percentage of random jitter added to the renewal time.
	"sasl.kerberos.ticket.renew.jitter"?: *0.05 | number

	// Login thread will sleep until the specified window factor of time from last refresh to ticket's expiry has been reached, at which time it will try to renew the ticket.
	"sasl.kerberos.ticket.renew.window.factor"?: *0.8 | number

	// The fully qualified name of a SASL login callback handler class that implements the AuthenticateCallbackHandler interface. For brokers, login callback handler config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.login.callback.handler.class=com.example.CustomScramLoginCallbackHandler
	"sasl.login.callback.handler.class"?: *null | string | null

	// The fully qualified name of a class that implements the Login interface. For brokers, login config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.login.class=com.example.CustomScramLogin
	"sasl.login.class"?: *null | string | null

	// The (optional) value in milliseconds for the external authentication provider connection timeout. Currently applies only to OAUTHBEARER.
	"sasl.login.connect.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The (optional) value in milliseconds for the external authentication provider read timeout. Currently applies only to OAUTHBEARER.
	"sasl.login.read.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The amount of buffer time before credential expiration to maintain when refreshing a credential, in seconds. If a refresh would otherwise occur closer to expiration than the number of buffer seconds then the refresh will be moved up to maintain as much of the buffer time as possible. Legal values are between 0 and 3600 (1 hour); a default value of 300 (5 minutes) is used if no value is specified. This value and sasl.login.refresh.min.period.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.buffer.seconds"?: *300 | int & >=-32768 & <=32767

	// The desired minimum time for the login refresh thread to wait before refreshing a credential, in seconds. Legal values are between 0 and 900 (15 minutes); a default value of 60 (1 minute) is used if no value is specified. This value and sasl.login.refresh.buffer.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.min.period.seconds"?: *60 | int & >=-32768 & <=32767

	// Login refresh thread will sleep until the specified window factor relative to the credential's lifetime has been reached, at which time it will try to refresh the credential. Legal values are between 0.5 (50%) and 1.0 (100%) inclusive; a default value of 0.8 (80%) is used if no value is specified. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.window.factor"?: *0.8 | number

	// The maximum amount of random jitter relative to the credential's lifetime that is added to the login refresh thread's sleep time. Legal values are between 0 and 0.25 (25%) inclusive; a default value of 0.05 (5%) is used if no value is specified. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.window.jitter"?: *0.05 | number

	// The (optional) value in milliseconds for the maximum wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to OAUTHBEARER.
	"sasl.login.retry.backoff.max.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the initial wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to OAUTHBEARER.
	"sasl.login.retry.backoff.ms"?: *100 | int & >=-9223372036854775808 & <=9223372036854775807

	// SASL mechanism used for communication with controllers. Default is GSSAPI.
	"sasl.mechanism.controller.protocol"?: *"GSSAPI" | string

	// SASL mechanism used for inter-broker communication. Default is GSSAPI.
	"sasl.mechanism.inter.broker.protocol"?: *"GSSAPI" | string

	// The (optional) value in seconds to allow for differences between the time of the OAuth/OIDC identity provider and the broker.
	"sasl.oauthbearer.clock.skew.seconds"?: *30 | int & >=-2147483648 & <=2147483647

	// The (optional) comma-delimited setting for the broker to use to verify that the JWT was issued for one of the expected audiences. The JWT will be inspected for the standard OAuth "aud" claim and if this value is set, the broker will match the value from JWT's "aud" claim to see if there is an exact match. If there is no match, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.expected.audience"?: *null | [...string] | null

	// The (optional) setting for the broker to use to verify that the JWT was created by the expected issuer. The JWT will be inspected for the standard OAuth "iss" claim and if this value is set, the broker will match it exactly against what is in the JWT's "iss" claim. If there is no match, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.expected.issuer"?: *null | string | null

	// The (optional) value in milliseconds for the broker to wait between refreshing its JWKS (JSON Web Key Set) cache that contains the keys to verify the signature of the JWT.
	"sasl.oauthbearer.jwks.endpoint.refresh.ms"?: *3600000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the maximum wait between attempts to retrieve the JWKS (JSON Web Key Set) from the external authentication provider. JWKS retrieval uses an exponential backoff algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
	"sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the initial wait between JWKS (JSON Web Key Set) retrieval attempts from the external authentication provider. JWKS retrieval uses an exponential backoff algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
	"sasl.oauthbearer.jwks.endpoint.retry.backoff.ms"?: *100 | int & >=-9223372036854775808 & <=9223372036854775807

	// The OAuth/OIDC provider URL from which the provider's JWKS (JSON Web Key Set) can be retrieved. The URL can be HTTP(S)-based or file-based. If the URL is HTTP(S)-based, the JWKS data will be retrieved from the OAuth/OIDC provider via the configured URL on broker startup. All then-current keys will be cached on the broker for incoming requests. If an authentication request is received for a JWT that includes a "kid" header claim value that isn't yet in the cache, the JWKS endpoint will be queried again on demand. However, the broker polls the URL every sasl.oauthbearer.jwks.endpoint.refresh.ms milliseconds to refresh the cache with any forthcoming keys before any JWT requests that include them are received. If the URL is file-based, the broker will load the JWKS file from a configured location on startup. In the event that the JWT includes a "kid" header value that isn't in the JWKS file, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.jwks.endpoint.url"?: *null | string | null

	// The OAuth claim for the scope is often named "scope", but this (optional) setting can provide a different name to use for the scope included in the JWT payload's claims if the OAuth/OIDC provider uses a different name for that claim.
	"sasl.oauthbearer.scope.claim.name"?: *"scope" | string

	// The OAuth claim for the subject is often named "sub", but this (optional) setting can provide a different name to use for the subject included in the JWT payload's claims if the OAuth/OIDC provider uses a different name for that claim.
	"sasl.oauthbearer.sub.claim.name"?: *"sub" | string

	// The URL for the OAuth/OIDC identity provider. If the URL is HTTP(S)-based, it is the issuer's token endpoint URL to which requests will be made to login based on the configuration in sasl.jaas.config. If the URL is file-based, it specifies a file containing an access token (in JWT serialized form) issued by the OAuth/OIDC identity provider to use for authorization.
	"sasl.oauthbearer.token.endpoint.url"?: *null | string | null

	// The fully qualified name of a SASL server callback handler class that implements the AuthenticateCallbackHandler interface. Server callback handlers must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.plain.sasl.server.callback.handler.class=com.example.CustomPlainCallbackHandler.
	"sasl.server.callback.handler.class"?: *null | string | null

	// The maximum receive size allowed before and during initial SASL authentication. Default receive size is 512KB. GSSAPI limits requests to 64K, but we allow upto 512KB by default for custom SASL mechanisms. In practice, PLAIN, SCRAM and OAUTH mechanisms can use much smaller limits.
	"sasl.server.max.receive.size"?: *524288 | int & >=-2147483648 & <=2147483647

	// A list of configurable creator classes each returning a provider implementing security algorithms. These classes should implement the org.apache.kafka.common.security.auth.SecurityProviderCreator interface.
	"security.providers"?: *null | string | null

	// The maximum number of pending connections on the socket. In Linux, you may also need to configure somaxconn and tcp_max_syn_backlog kernel parameters accordingly to make the configuration takes effect.
	"socket.listen.backlog.size"?: *50 | int & >=1 & <=2147483647

	// The SO_RCVBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
	"socket.receive.buffer.bytes"?: *102400 | int & >=-2147483648 & <=2147483647

	// The maximum number of bytes in a socket request
	"socket.request.max.bytes"?: *104857600 | int & >=1 & <=2147483647

	// The SO_SNDBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
	"socket.send.buffer.bytes"?: *102400 | int & >=-2147483648 & <=2147483647

	// Indicates whether changes to the certificate distinguished name should be allowed during a dynamic reconfiguration of certificates or not.
	"ssl.allow.dn.changes"?: *false | bool

	// Indicates whether changes to the certificate subject alternative names should be allowed during a dynamic reconfiguration of certificates or not.
	"ssl.allow.san.changes"?: *false | bool

	// A list of cipher suites. This is a named combination of authentication, encryption, MAC and key exchange algorithm used to negotiate the security settings for a network connection using TLS or SSL network protocol. By default all the available cipher suites are supported.
	"ssl.cipher.suites"?: *[] | [...string]

	// Configures kafka broker to request client authentication. The following settings are common: ssl.client.auth=required If set to required client authentication is required. ssl.client.auth=requested This means client authentication is optional. unlike required, if this option is set client can choose not to provide authentication information about itself ssl.client.auth=none This means client authentication is not needed.
	"ssl.client.auth"?: *"none" | string & ("required" | "requested" | "none")

	// The list of protocols enabled for SSL connections. The default is 'TLSv1.2,TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. With the default value for Java 11, clients and servers will prefer TLSv1.3 if both support it and fallback to TLSv1.2 otherwise (assuming both support at least TLSv1.2). This default should be fine for most cases. Also see the config documentation for `ssl.protocol`.
	"ssl.enabled.protocols"?: *["TLSv1.2", "TLSv1.3"] | [...string]

	// The endpoint identification algorithm to validate server hostname using server certificate.
	"ssl.endpoint.identification.algorithm"?: *"https" | string

	// The class of type org.apache.kafka.common.security.auth.SslEngineFactory to provide SSLEngine objects. Default value is org.apache.kafka.common.security.ssl.DefaultSslEngineFactory. Alternatively, setting this to org.apache.kafka.common.security.ssl.CommonNameLoggingSslEngineFactory will log the common name of expired SSL certificates used by clients to authenticate at any of the brokers with log level INFO. Note that this will cause a tiny delay during establishment of new connections from mTLS clients to brokers due to the extra code for examining the certificate chain provided by the client. Note further that the implementation uses a custom truststore based on the standard Java truststore and thus might be considered a security risk due to not being as mature as the standard one.
	"ssl.engine.factory.class"?: *null | string | null

	// The password of the private key in the key store file or the PEM key specified in 'ssl.keystore.key'.
	"ssl.key.password"?: *null | string | null

	// The algorithm used by key manager factory for SSL connections. Default value is the key manager factory algorithm configured for the Java Virtual Machine.
	"ssl.keymanager.algorithm"?: *"SunX509" | string

	// Certificate chain in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with a list of X.509 certificates
	"ssl.keystore.certificate.chain"?: *null | string | null

	// Private key in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with PKCS#8 keys. If the key is encrypted, key password must be specified using 'ssl.key.password'
	"ssl.keystore.key"?: *null | string | null

	// The location of the key store file. This is optional for client and can be used for two-way authentication for client.
	"ssl.keystore.location"?: *null | string | null

	// The store password for the key store file. This is optional for client and only needed if 'ssl.keystore.location' is configured. Key store password is not supported for PEM format.
	"ssl.keystore.password"?: *null | string | null

	// The file format of the key store file. This is optional for client. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
	// "ssl.keystore.type"?: *"JKS" | string

	// A list of rules for mapping from distinguished name from the client certificate to short name. The rules are evaluated in order and the first rule that matches a principal name is used to map it to a short name. Any later rules in the list are ignored. By default, distinguished name of the X.500 certificate will be the principal. For more details on the format please see security authorization and acls. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the principal.builder.class configuration.
	"ssl.principal.mapping.rules"?: *"DEFAULT" | string

	// The SSL protocol used to generate the SSLContext. The default is 'TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. This value should be fine for most use cases. Allowed values in recent JVMs are 'TLSv1.2' and 'TLSv1.3'. 'TLS', 'TLSv1.1', 'SSL', 'SSLv2' and 'SSLv3' may be supported in older JVMs, but their usage is discouraged due to known security vulnerabilities. With the default value for this config and 'ssl.enabled.protocols', clients will downgrade to 'TLSv1.2' if the server does not support 'TLSv1.3'. If this config is set to 'TLSv1.2', clients will not use 'TLSv1.3' even if it is one of the values in ssl.enabled.protocols and the server only supports 'TLSv1.3'.
	"ssl.protocol"?: *"TLSv1.3" | string

	// The name of the security provider used for SSL connections. Default value is the default security provider of the JVM.
	"ssl.provider"?: *null | string | null

	// The SecureRandom PRNG implementation to use for SSL cryptography operations.
	"ssl.secure.random.implementation"?: *null | string | null

	// The algorithm used by trust manager factory for SSL connections. Default value is the trust manager factory algorithm configured for the Java Virtual Machine.
	"ssl.trustmanager.algorithm"?: *"PKIX" | string

	// Trusted certificates in the format specified by 'ssl.truststore.type'. Default SSL engine factory supports only PEM format with X.509 certificates.
	"ssl.truststore.certificates"?: *null | string | null

	// The location of the trust store file.
	"ssl.truststore.location"?: *null | string | null

	// The password for the trust store file. If a password is not set, trust store file configured will still be used, but integrity checking is disabled. Trust store password is not supported for PEM format.
	"ssl.truststore.password"?: *null | string | null

	// The file format of the trust store file. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
	"ssl.truststore.type"?: *"JKS" | string

	// The maximum size (after compression if compression is used) of telemetry metrics pushed from a client to the broker. The default value is 1048576 (1 MB).
	"telemetry.max.bytes"?: *1048576 | int & >=1 & <=2147483647

	// Enable ZK to KRaft migration
	"zookeeper.metadata.migration.enable"?: *false | bool

	...
}

#Broker: {
	// Listeners to publish to ZooKeeper for clients to use, if different than the listeners config property. In IaaS environments, this may need to be different from the interface to which the broker binds. If this is not set, the value for listeners will be used. Unlike listeners, it is not valid to advertise the 0.0.0.0 meta-address. Also unlike listeners, there can be duplicated ports in this property, so that one listener can be configured to advertise another listener's address. This can be useful in some cases where external load balancers are used.
	// "advertised.listeners"?: *null | string | null

	// The alter configs policy class that should be used for validation. The class should implement the org.apache.kafka.server.policy.AlterConfigPolicy interface.
	"alter.config.policy.class.name"?: *null | string | null

	// The number of samples to retain in memory for alter log dirs replication quotas
	"alter.log.dirs.replication.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for alter log dirs replication quotas
	"alter.log.dirs.replication.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// validator: non-null string
	// The fully qualified name of a class that implements org.apache.kafka.server.authorizer.Authorizer interface, which is used by the broker for authorization.
	"authorizer.class.name"?: *"" | string

	// Enable auto creation of topic on the server.
	"auto.create.topics.enable"?: *true | bool

	// Deprecated. Whether to automatically include JmxReporter even if it's not listed in metric.reporters. This configuration will be removed in Kafka 4.0, users should instead include org.apache.kafka.common.metrics.JmxReporter in metric.reporters in order to enable the JmxReporter.
	"auto.include.jmx.reporter"?: *true | bool

	// Enables auto leader balancing. A background thread checks the distribution of partition leaders at regular intervals, configurable by leader.imbalance.check.interval.seconds. If the leader imbalance exceeds leader.imbalance.per.broker.percentage, leader rebalance to the preferred leader for partitions is triggered.
	"auto.leader.rebalance.enable"?: *true | bool

	// The number of threads to use for various background processing tasks
	"background.threads"?: *10 | int & >=1 & <=2147483647

	// The length of time in milliseconds between broker heartbeats. Used when running in KRaft mode.
	"broker.heartbeat.interval.ms"?: *2000 | int & >=-2147483648 & <=2147483647

	// The broker id for this server. If unset, a unique broker id will be generated.To avoid conflicts between ZooKeeper generated broker id's and user configured broker id's, generated broker ids start from reserved.broker.max.id + 1.
	"broker.id"?: *-1 | int & >=-2147483648 & <=2147483647

	// Enable automatic broker id generation on the server. When enabled the value configured for reserved.broker.max.id should be reviewed.
	"broker.id.generation.enable"?: *true | bool

	// Rack of the broker. This will be used in rack aware replication assignment for fault tolerance. Examples: RACK1, us-east-1d
	"broker.rack"?: *null | string | null

	// The length of time in milliseconds that a broker lease lasts if no heartbeats are made. Used when running in KRaft mode.
	"broker.session.timeout.ms"?: *9000 | int & >=-2147483648 & <=2147483647

	// The fully qualified name of a class that implements the ClientQuotaCallback interface, which is used to determine quota limits applied to client requests. By default, the &lt;user&gt; and &lt;client-id&gt; quotas that are stored in ZooKeeper are applied. For any given request, the most specific quota that matches the user principal of the session and the client-id of the request is applied.
	"client.quota.callback.class"?: *null | string | null

	// validator: [1,...,9] or -1
	// The compression level to use if compression.type is set to 'gzip'.
	"compression.gzip.level"?: *-1 | int & >=-2147483648 & <=2147483647

	// The compression level to use if compression.type is set to 'lz4'.
	"compression.lz4.level"?: *9 | int & >=1 & <=17

	// Specify the final compression type for a given topic. This configuration accepts the standard compression codecs ('gzip', 'snappy', 'lz4', 'zstd'). It additionally accepts 'uncompressed' which is equivalent to no compression; and 'producer' which means retain the original compression codec set by the producer.
	"compression.type"?: *"producer" | string & ("uncompressed" | "zstd" | "lz4" | "snappy" | "gzip" | "producer")

	// The compression level to use if compression.type is set to 'zstd'.
	"compression.zstd.level"?: *3 | int & >=-131072 & <=22

	// Connection close delay on failed authentication: this is the time (in milliseconds) by which connection close will be delayed on authentication failure. This must be configured to be less than connections.max.idle.ms to prevent connection timeout.
	"connection.failed.authentication.delay.ms"?: *100 | int & >=0 & <=2147483647

	// Idle connections timeout: the server socket processor threads close the connections that idle more than this
	"connections.max.idle.ms"?: *600000 | int & >=-9223372036854775808 & <=9223372036854775807

	// When explicitly set to a positive number (the default is 0, not a positive number), a session lifetime that will not exceed the configured value will be communicated to v2.2.0 or later clients when they authenticate. The broker will disconnect any such connection that is not re-authenticated within the session lifetime and that is then subsequently used for any purpose other than re-authentication. Configuration names can optionally be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.oauthbearer.connections.max.reauth.ms=3600000
	"connections.max.reauth.ms"?: *0 | int & >=-9223372036854775808 & <=9223372036854775807

	// Name of listener used for communication between controller and brokers. A broker will use the control.plane.listener.name to locate the endpoint in listeners list, to listen for connections from the controller. For example, if a broker's config is: listeners = INTERNAL://192.1.1.8:9092, EXTERNAL://10.1.1.5:9093, CONTROLLER://192.1.1.8:9094listener.security.protocol.map = INTERNAL:PLAINTEXT, EXTERNAL:SSL, CONTROLLER:SSLcontrol.plane.listener.name = CONTROLLER On startup, the broker will start listening on "192.1.1.8:9094" with security protocol "SSL". On the controller side, when it discovers a broker's published endpoints through ZooKeeper, it will use the control.plane.listener.name to find the endpoint, which it will use to establish connection to the broker. For example, if the broker's published endpoints on ZooKeeper are: "endpoints" : ["INTERNAL://broker1.example.com:9092","EXTERNAL://broker1.example.com:9093","CONTROLLER://broker1.example.com:9094"] and the controller's config is: listener.security.protocol.map = INTERNAL:PLAINTEXT, EXTERNAL:SSL, CONTROLLER:SSLcontrol.plane.listener.name = CONTROLLER then the controller will use "broker1.example.com:9094" with security protocol "SSL" to connect to the broker. If not explicitly configured, the default value will be null and there will be no dedicated endpoints for controller connections. If explicitly configured, the value cannot be the same as the value of inter.broker.listener.name.
	"control.plane.listener.name"?: *null | string | null

	// Enable controlled shutdown of the server.
	"controlled.shutdown.enable"?: *true | bool

	// Controlled shutdown can fail for multiple reasons. This determines the number of retries when such failure happens
	"controlled.shutdown.max.retries"?: *3 | int & >=-2147483648 & <=2147483647

	// Before each retry, the system needs time to recover from the state that caused the previous failure (Controller fail over, replica lag etc). This config determines the amount of time to wait before retrying.
	"controlled.shutdown.retry.backoff.ms"?: *5000 | int & >=-9223372036854775808 & <=9223372036854775807

	// A comma-separated list of the names of the listeners used by the controller. This is required if running in KRaft mode. When communicating with the controller quorum, the broker will always use the first listener in this list. Note: The ZooKeeper-based controller should not set this configuration.
	// "controller.listener.names"?: *null | string | null

	// The number of samples to retain in memory for controller mutation quotas
	"controller.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for controller mutations quotas
	"controller.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// The socket timeout for controller-to-broker channels.
	"controller.socket.timeout.ms"?: *30000 | int & >=-2147483648 & <=2147483647

	// The create topic policy class that should be used for validation. The class should implement the org.apache.kafka.server.policy.CreateTopicPolicy interface.
	"create.topic.policy.class.name"?: *null | string | null

	// The replication factor for automatically created topics, and for topics created with -1 as the replication factor
	"default.replication.factor"?: *1 | int & >=-2147483648 & <=2147483647

	// Scan interval to remove expired delegation tokens.
	"delegation.token.expiry.check.interval.ms"?: *3600000 | int & >=1 & <=9223372036854775807

	// The token validity time in milliseconds before the token needs to be renewed. Default value 1 day.
	"delegation.token.expiry.time.ms"?: *86400000 | int & >=1 & <=9223372036854775807

	// DEPRECATED: An alias for delegation.token.secret.key, which should be used instead of this config.
	"delegation.token.master.key"?: *null | string | null

	// The token has a maximum lifetime beyond which it cannot be renewed anymore. Default value 7 days.
	"delegation.token.max.lifetime.ms"?: *604800000 | int & >=1 & <=9223372036854775807

	// Secret key to generate and verify delegation tokens. The same key must be configured across all the brokers. If using Kafka with KRaft, the key must also be set across all controllers. If the key is not set or set to empty string, brokers will disable the delegation token support.
	"delegation.token.secret.key"?: *null | string | null

	// The purge interval (in number of requests) of the delete records request purgatory
	"delete.records.purgatory.purge.interval.requests"?: *1 | int & >=-2147483648 & <=2147483647

	// A comma-separated list of listener names which may be started before the authorizer has finished initialization. This is useful when the authorizer is dependent on the cluster itself for bootstrapping, as is the case for the StandardAuthorizer (which stores ACLs in the metadata log.) By default, all listeners included in controller.listener.names will also be early start listeners. A listener should not appear in this list if it accepts external traffic.
	"early.start.listeners"?: *null | string | null

	// The maximum number of bytes we will return for a fetch request. Must be at least 1024.
	"fetch.max.bytes"?: *57671680 | int & >=1024 & <=2147483647

	// The purge interval (in number of requests) of the fetch request purgatory
	"fetch.purgatory.purge.interval.requests"?: *1000 | int & >=-2147483648 & <=2147483647

	// The server side assignors as a list of full class names. The first one in the list is considered as the default assignor to be used in the case where the consumer does not specify an assignor.
	"group.consumer.assignors"?: *["org.apache.kafka.coordinator.group.assignor.UniformAssignor", "org.apache.kafka.coordinator.group.assignor.RangeAssignor"] | [...string]

	// The heartbeat interval given to the members of a consumer group.
	"group.consumer.heartbeat.interval.ms"?: *5000 | int & >=1 & <=2147483647

	// The maximum heartbeat interval for registered consumers.
	"group.consumer.max.heartbeat.interval.ms"?: *15000 | int & >=1 & <=2147483647

	// The maximum allowed session timeout for registered consumers.
	"group.consumer.max.session.timeout.ms"?: *60000 | int & >=1 & <=2147483647

	// The maximum number of consumers that a single consumer group can accommodate. This value will only impact the new consumer coordinator. To configure the classic consumer coordinator check group.max.size instead.
	"group.consumer.max.size"?: *2147483647 | int & >=1 & <=2147483647

	// The minimum heartbeat interval for registered consumers.
	"group.consumer.min.heartbeat.interval.ms"?: *5000 | int & >=1 & <=2147483647

	// The minimum allowed session timeout for registered consumers.
	"group.consumer.min.session.timeout.ms"?: *45000 | int & >=1 & <=2147483647

	// The timeout to detect client failures when using the consumer group protocol.
	"group.consumer.session.timeout.ms"?: *45000 | int & >=1 & <=2147483647

	// The duration in milliseconds that the coordinator will wait for writes to accumulate before flushing them to disk. Transactional writes are not accumulated.
	"group.coordinator.append.linger.ms"?: *10 | int & >=0 & <=2147483647

	// The list of enabled rebalance protocols. Supported protocols: consumer,classic,share,unknown. The consumer rebalance protocol is in early access and therefore must not be used in production.
	"group.coordinator.rebalance.protocols"?: *["classic"] | [...("consumer" | "classic" | "share" | "unknown")]

	// The number of threads used by the group coordinator.
	"group.coordinator.threads"?: *1 | int & >=1 & <=2147483647

	// The amount of time the group coordinator will wait for more consumers to join a new group before performing the first rebalance. A longer delay means potentially fewer rebalances, but increases the time until processing begins.
	"group.initial.rebalance.delay.ms"?: *3000 | int & >=-2147483648 & <=2147483647

	// The maximum allowed session timeout for registered consumers. Longer timeouts give consumers more time to process messages in between heartbeats at the cost of a longer time to detect failures.
	"group.max.session.timeout.ms"?: *1800000 | int & >=-2147483648 & <=2147483647

	// The maximum number of consumers that a single consumer group can accommodate.
	"group.max.size"?: *2147483647 | int & >=1 & <=2147483647

	// The minimum allowed session timeout for registered consumers. Shorter timeouts result in quicker failure detection at the cost of more frequent consumer heartbeating, which can overwhelm broker resources.
	"group.min.session.timeout.ms"?: *6000 | int & >=-2147483648 & <=2147483647

	// The maximum number of delivery attempts for a record delivered to a share group.
	"group.share.delivery.count.limit"?: *5 | int & >=2 & <=10

	// The heartbeat interval given to the members of a share group.
	"group.share.heartbeat.interval.ms"?: *5000 | int & >=1 & <=2147483647

	// The maximum number of share groups.
	"group.share.max.groups"?: *10 | int & >=1 & <=100

	// The maximum heartbeat interval for share group members.
	"group.share.max.heartbeat.interval.ms"?: *15000 | int & >=1 & <=2147483647

	// The record acquisition lock maximum duration in milliseconds for share groups.
	"group.share.max.record.lock.duration.ms"?: *60000 | int & >=30000 & <=3600000

	// The maximum allowed session timeout for share group members.
	"group.share.max.session.timeout.ms"?: *60000 | int & >=1 & <=2147483647

	// The maximum number of members that a single share group can accommodate.
	"group.share.max.size"?: *200 | int & >=10 & <=1000

	// The minimum heartbeat interval for share group members.
	"group.share.min.heartbeat.interval.ms"?: *5000 | int & >=1 & <=2147483647

	// The record acquisition lock minimum duration in milliseconds for share groups.
	"group.share.min.record.lock.duration.ms"?: *15000 | int & >=1000 & <=30000

	// The minimum allowed session timeout for share group members.
	"group.share.min.session.timeout.ms"?: *45000 | int & >=1 & <=2147483647

	// Share-group record lock limit per share-partition.
	"group.share.partition.max.record.locks"?: *200 | int & >=100 & <=10000

	// The record acquisition lock duration in milliseconds for share groups.
	"group.share.record.lock.duration.ms"?: *30000 | int & >=1000 & <=60000

	// The timeout to detect client failures when using the share group protocol.
	"group.share.session.timeout.ms"?: *45000 | int & >=1 & <=2147483647

	// When initially registering with the controller quorum, the number of milliseconds to wait before declaring failure and exiting the broker process.
	"initial.broker.registration.timeout.ms"?: *60000 | int & >=-2147483648 & <=2147483647

	// Name of listener used for communication between brokers. If this is unset, the listener name is defined by security.inter.broker.protocolIt is an error to set this and security.inter.broker.protocol properties at the same time.
	// "inter.broker.listener.name"?: *null | string | null

	// validator: [0.8.0, 0.8.1, 0.8.2, 0.9.0, 0.10.0-IV0, 0.10.0-IV1, 0.10.1-IV0, 0.10.1-IV1, 0.10.1-IV2, 0.10.2-IV0, 0.11.0-IV0, 0.11.0-IV1, 0.11.0-IV2, 1.0-IV0, 1.1-IV0, 2.0-IV0, 2.0-IV1, 2.1-IV0, 2.1-IV1, 2.1-IV2, 2.2-IV0, 2.2-IV1, 2.3-IV0, 2.3-IV1, 2.4-IV0, 2.4-IV1, 2.5-IV0, 2.6-IV0, 2.7-IV0, 2.7-IV1, 2.7-IV2, 2.8-IV0, 2.8-IV1, 3.0-IV0, 3.0-IV1, 3.1-IV0, 3.2-IV0, 3.3-IV0, 3.3-IV1, 3.3-IV2, 3.3-IV3, 3.4-IV0, 3.5-IV0, 3.5-IV1, 3.5-IV2, 3.6-IV0, 3.6-IV1, 3.6-IV2, 3.7-IV0, 3.7-IV1, 3.7-IV2, 3.7-IV3, 3.7-IV4, 3.8-IV0, 3.9-IV0, 4.0-IV0, 4.0-IV1]
	// Specify which version of the inter-broker protocol will be used. . This is typically bumped after all brokers were upgraded to a new version. Example of some valid values are: 0.8.0, 0.8.1, 0.8.1.1, 0.8.2, 0.8.2.0, 0.8.2.1, 0.9.0.0, 0.9.0.1 Check MetadataVersion for the full list.
	"inter.broker.protocol.version"?: *"3.9-IV0" | string

	// The metrics polling interval (in seconds) which can be used in kafka.metrics.reporters implementations.
	"kafka.metrics.polling.interval.secs"?: *10 | int & >=1 & <=2147483647

	// A list of classes to use as Yammer metrics custom reporters. The reporters should implement kafka.metrics.KafkaMetricsReporter trait. If a client wants to expose JMX operations on a custom reporter, the custom reporter needs to additionally implement an MBean trait that extends kafka.metrics.KafkaMetricsReporterMBean trait so that the registered MBean is compliant with the standard MBean convention.
	"kafka.metrics.reporters"?: *[] | [...string]

	// The frequency with which the partition rebalance check is triggered by the controller
	"leader.imbalance.check.interval.seconds"?: *300 | int & >=1 & <=9223372036854775807

	// The ratio of leader imbalance allowed per broker. The controller would trigger a leader balance if it goes above this value per broker. The value is specified in percentage.
	"leader.imbalance.per.broker.percentage"?: *10 | int & >=-2147483648 & <=2147483647

	// Map between listener names and security protocols. This must be defined for the same security protocol to be usable in more than one port or IP. For example, internal and external traffic can be separated even if SSL is required for both. Concretely, the user could define listeners with names INTERNAL and EXTERNAL and this property as: INTERNAL:SSL,EXTERNAL:SSL. As shown, key and value are separated by a colon and map entries are separated by commas. Each listener name should only appear once in the map. Different security (SSL and SASL) settings can be configured for each listener by adding a normalised prefix (the listener name is lowercased) to the config name. For example, to set a different keystore for the INTERNAL listener, a config with name listener.name.internal.ssl.keystore.location would be set. If the config for the listener name is not set, the config will fallback to the generic config (i.e. ssl.keystore.location). Note that in KRaft a default mapping from the listener names defined by controller.listener.names to PLAINTEXT is assumed if no explicit mapping is provided and no other security protocol is in use.
	// "listener.security.protocol.map"?: *"SASL_SSL:SASL_SSL,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT" | string

	// Listener List - Comma-separated list of URIs we will listen on and the listener names. If the listener name is not a security protocol, listener.security.protocol.map must also be set. Listener names and port numbers must be unique unless %n one listener is an IPv4 address and the other listener is %n an IPv6 address (for the same port).%n Specify hostname as 0.0.0.0 to bind to all interfaces.%n Leave hostname empty to bind to default interface.%n Examples of legal listener lists:%n PLAINTEXT://myhost:9092,SSL://:9091%n CLIENT://0.0.0.0:9092,REPLICATION://localhost:9093%n PLAINTEXT://127.0.0.1:9092,SSL://[::1]:9092%n
	// "listeners"?: *"PLAINTEXT://:9092" | string

	// The amount of time to sleep when there are no logs to clean
	"log.cleaner.backoff.ms"?: *15000 | int & >=0 & <=9223372036854775807

	// The total memory used for log deduplication across all cleaner threads
	"log.cleaner.dedupe.buffer.size"?: *134217728 | int & >=-9223372036854775808 & <=9223372036854775807

	// The amount of time to retain tombstone message markers for log compacted topics. This setting also gives a bound on the time in which a consumer must complete a read if they begin from offset 0 to ensure that they get a valid snapshot of the final stage (otherwise tombstones messages may be collected before a consumer completes their scan).
	"log.cleaner.delete.retention.ms"?: *86400000 | int & >=0 & <=9223372036854775807

	// Enable the log cleaner process to run on the server. Should be enabled if using any topics with a cleanup.policy=compact including the internal offsets topic. If disabled those topics will not be compacted and continually grow in size.
	"log.cleaner.enable"?: *true | bool

	// Log cleaner dedupe buffer load factor. The percentage full the dedupe buffer can become. A higher value will allow more log to be cleaned at once but will lead to more hash collisions
	"log.cleaner.io.buffer.load.factor"?: *0.9 | number

	// The total memory used for log cleaner I/O buffers across all cleaner threads
	"log.cleaner.io.buffer.size"?: *524288 | int & >=0 & <=2147483647

	// The log cleaner will be throttled so that the sum of its read and write i/o will be less than this value on average
	"log.cleaner.io.max.bytes.per.second"?: *1.7976931348623157E308 | number

	// The maximum time a message will remain ineligible for compaction in the log. Only applicable for logs that are being compacted.
	"log.cleaner.max.compaction.lag.ms"?: *9223372036854775807 | int & >=1 & <=9223372036854775807

	// The minimum ratio of dirty log to total log for a log to eligible for cleaning. If the log.cleaner.max.compaction.lag.ms or the log.cleaner.min.compaction.lag.ms configurations are also specified, then the log compactor considers the log eligible for compaction as soon as either: (i) the dirty ratio threshold has been met and the log has had dirty (uncompacted) records for at least the log.cleaner.min.compaction.lag.ms duration, or (ii) if the log has had dirty (uncompacted) records for at most the log.cleaner.max.compaction.lag.ms period.
	"log.cleaner.min.cleanable.ratio"?: *0.5 | number & >=0 & <=1

	// The minimum time a message will remain uncompacted in the log. Only applicable for logs that are being compacted.
	"log.cleaner.min.compaction.lag.ms"?: *0 | int & >=0 & <=9223372036854775807

	// The number of background threads to use for log cleaning
	"log.cleaner.threads"?: *1 | int & >=0 & <=2147483647

	// The default cleanup policy for segments beyond the retention window. A comma separated list of valid policies. Valid policies are: "delete" and "compact"
	"log.cleanup.policy"?: *["delete"] | [...("compact" | "delete")]

	// The directory in which the log data is kept (supplemental for log.dirs property)
	"log.dir"?: *"/tmp/kafka-logs" | string

	// If the broker is unable to successfully communicate to the controller that some log directory has failed for longer than this time, the broker will fail and shut down.
	"log.dir.failure.timeout.ms"?: *30000 | int & >=1 & <=9223372036854775807

	// A comma-separated list of the directories where the log data is stored. If not set, the value in log.dir is used.
	"log.dirs"?: *null | string | null

	// The number of messages accumulated on a log partition before messages are flushed to disk.
	"log.flush.interval.messages"?: *9223372036854775807 | int & >=1 & <=9223372036854775807

	// The maximum time in ms that a message in any topic is kept in memory before flushed to disk. If not set, the value in log.flush.scheduler.interval.ms is used
	"log.flush.interval.ms"?: *null | int & >=-9223372036854775808 & <=9223372036854775807 | null

	// The frequency with which we update the persistent record of the last flush which acts as the log recovery point.
	"log.flush.offset.checkpoint.interval.ms"?: *60000 | int & >=0 & <=2147483647

	// The frequency in ms that the log flusher checks whether any log needs to be flushed to disk
	"log.flush.scheduler.interval.ms"?: *9223372036854775807 | int & >=-9223372036854775808 & <=9223372036854775807

	// The frequency with which we update the persistent record of log start offset
	"log.flush.start.offset.checkpoint.interval.ms"?: *60000 | int & >=0 & <=2147483647

	// The interval with which we add an entry to the offset index.
	"log.index.interval.bytes"?: *4096 | int & >=0 & <=2147483647

	// The maximum size in bytes of the offset index
	"log.index.size.max.bytes"?: *10485760 | int & >=4 & <=2147483647

	// The maximum size of local log segments that can grow for a partition before it gets eligible for deletion. Default value is -2, it represents `log.retention.bytes` value to be used. The effective value should always be less than or equal to `log.retention.bytes` value.
	"log.local.retention.bytes"?: *-2 | int & >=-2 & <=9223372036854775807

	// The number of milliseconds to keep the local log segments before it gets eligible for deletion. Default value is -2, it represents `log.retention.ms` value is to be used. The effective value should always be less than or equal to `log.retention.ms` value.
	"log.local.retention.ms"?: *-2 | int & >=-2 & <=9223372036854775807

	// This configuration controls whether down-conversion of message formats is enabled to satisfy consume requests. When set to false, broker will not perform down-conversion for consumers expecting an older message format. The broker responds with UNSUPPORTED_VERSION error for consume requests from such older clients. This configurationdoes not apply to any message format conversion that might be required for replication to followers.
	"log.message.downconversion.enable"?: *true | bool

	// validator: [0.8.0, 0.8.1, 0.8.2, 0.9.0, 0.10.0-IV0, 0.10.0-IV1, 0.10.1-IV0, 0.10.1-IV1, 0.10.1-IV2, 0.10.2-IV0, 0.11.0-IV0, 0.11.0-IV1, 0.11.0-IV2, 1.0-IV0, 1.1-IV0, 2.0-IV0, 2.0-IV1, 2.1-IV0, 2.1-IV1, 2.1-IV2, 2.2-IV0, 2.2-IV1, 2.3-IV0, 2.3-IV1, 2.4-IV0, 2.4-IV1, 2.5-IV0, 2.6-IV0, 2.7-IV0, 2.7-IV1, 2.7-IV2, 2.8-IV0, 2.8-IV1, 3.0-IV0, 3.0-IV1, 3.1-IV0, 3.2-IV0, 3.3-IV0, 3.3-IV1, 3.3-IV2, 3.3-IV3, 3.4-IV0, 3.5-IV0, 3.5-IV1, 3.5-IV2, 3.6-IV0, 3.6-IV1, 3.6-IV2, 3.7-IV0, 3.7-IV1, 3.7-IV2, 3.7-IV3, 3.7-IV4, 3.8-IV0, 3.9-IV0, 4.0-IV0, 4.0-IV1]
	// Specify the message format version the broker will use to append messages to the logs. The value should be a valid MetadataVersion. Some examples are: 0.8.2, 0.9.0.0, 0.10.0, check MetadataVersion for more details. By setting a particular message format version, the user is certifying that all the existing messages on disk are smaller or equal than the specified version. Setting this value incorrectly will cause consumers with older versions to break as they will receive messages with a format that they don't understand.
	"log.message.format.version"?: *"3.0-IV1" | string

	// This configuration sets the allowable timestamp difference between the message timestamp and the broker's timestamp. The message timestamp can be later than or equal to the broker's timestamp, with the maximum allowable difference determined by the value set in this configuration. If log.message.timestamp.type=CreateTime, the message will be rejected if the difference in timestamps exceeds this specified threshold. This configuration is ignored if log.message.timestamp.type=LogAppendTime.
	"log.message.timestamp.after.max.ms"?: *9223372036854775807 | int & >=0 & <=9223372036854775807

	// This configuration sets the allowable timestamp difference between the broker's timestamp and the message timestamp. The message timestamp can be earlier than or equal to the broker's timestamp, with the maximum allowable difference determined by the value set in this configuration. If log.message.timestamp.type=CreateTime, the message will be rejected if the difference in timestamps exceeds this specified threshold. This configuration is ignored if log.message.timestamp.type=LogAppendTime.
	"log.message.timestamp.before.max.ms"?: *9223372036854775807 | int & >=0 & <=9223372036854775807

	// [DEPRECATED] The maximum difference allowed between the timestamp when a broker receives a message and the timestamp specified in the message. If log.message.timestamp.type=CreateTime, a message will be rejected if the difference in timestamp exceeds this threshold. This configuration is ignored if log.message.timestamp.type=LogAppendTime.The maximum timestamp difference allowed should be no greater than log.retention.ms to avoid unnecessarily frequent log rolling.
	"log.message.timestamp.difference.max.ms"?: *9223372036854775807 | int & >=0 & <=9223372036854775807

	// Define whether the timestamp in the message is message create time or log append time. The value should be either CreateTime or LogAppendTime.
	"log.message.timestamp.type"?: *"CreateTime" | string & ("CreateTime" | "LogAppendTime")

	// Should pre allocate file when create new segment? If you are using Kafka on Windows, you probably need to set it to true.
	"log.preallocate"?: *false | bool

	// The maximum size of the log before deleting it
	"log.retention.bytes"?: *-1 | int & >=-9223372036854775808 & <=9223372036854775807

	// The frequency in milliseconds that the log cleaner checks whether any log is eligible for deletion
	"log.retention.check.interval.ms"?: *300000 | int & >=1 & <=9223372036854775807

	// The number of hours to keep a log file before deleting it (in hours), tertiary to log.retention.ms property
	"log.retention.hours"?: *168 | int & >=-2147483648 & <=2147483647

	// The number of minutes to keep a log file before deleting it (in minutes), secondary to log.retention.ms property. If not set, the value in log.retention.hours is used
	"log.retention.minutes"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The number of milliseconds to keep a log file before deleting it (in milliseconds), If not set, the value in log.retention.minutes is used. If set to -1, no time limit is applied.
	"log.retention.ms"?: *null | int & >=-9223372036854775808 & <=9223372036854775807 | null

	// The maximum time before a new log segment is rolled out (in hours), secondary to log.roll.ms property
	"log.roll.hours"?: *168 | int & >=1 & <=2147483647

	// The maximum jitter to subtract from logRollTimeMillis (in hours), secondary to log.roll.jitter.ms property
	"log.roll.jitter.hours"?: *0 | int & >=0 & <=2147483647

	// The maximum jitter to subtract from logRollTimeMillis (in milliseconds). If not set, the value in log.roll.jitter.hours is used
	"log.roll.jitter.ms"?: *null | int & >=-9223372036854775808 & <=9223372036854775807 | null

	// The maximum time before a new log segment is rolled out (in milliseconds). If not set, the value in log.roll.hours is used
	"log.roll.ms"?: *null | int & >=-9223372036854775808 & <=9223372036854775807 | null

	// The maximum size of a single log file
	"log.segment.bytes"?: *1073741824 | int & >=14 & <=2147483647

	// The amount of time to wait before deleting a file from the filesystem. If the value is 0 and there is no file to delete, the system will wait 1 millisecond. Low value will cause busy waiting
	"log.segment.delete.delay.ms"?: *60000 | int & >=0 & <=9223372036854775807

	// The maximum connection creation rate we allow in the broker at any time. Listener-level limits may also be configured by prefixing the config name with the listener prefix, for example, listener.name.internal.max.connection.creation.rate.Broker-wide connection rate limit should be configured based on broker capacity while listener limits should be configured based on application requirements. New connections will be throttled if either the listener or the broker limit is reached, with the exception of inter-broker listener. Connections on the inter-broker listener will be throttled only when the listener-level rate limit is reached.
	"max.connection.creation.rate"?: *2147483647 | int & >=0 & <=2147483647

	// The maximum number of connections we allow in the broker at any time. This limit is applied in addition to any per-ip limits configured using max.connections.per.ip. Listener-level limits may also be configured by prefixing the config name with the listener prefix, for example, listener.name.internal.max.connections.per.ip. Broker-wide limit should be configured based on broker capacity while listener limits should be configured based on application requirements. New connections are blocked if either the listener or broker limit is reached. Connections on the inter-broker listener are permitted even if broker-wide limit is reached. The least recently used connection on another listener will be closed in this case.
	"max.connections"?: *2147483647 | int & >=0 & <=2147483647

	// The maximum number of connections we allow from each ip address. This can be set to 0 if there are overrides configured using max.connections.per.ip.overrides property. New connections from the ip address are dropped if the limit is reached.
	"max.connections.per.ip"?: *2147483647 | int & >=0 & <=2147483647

	// A comma-separated list of per-ip or hostname overrides to the default maximum number of connections. An example value is "hostName:100,127.0.0.1:200"
	"max.connections.per.ip.overrides"?: *"" | string

	// The maximum number of total incremental fetch sessions that we will maintain. FetchSessionCache is sharded into 8 shards and the limit is equally divided among all shards. Sessions are allocated to each shard in round-robin. Only entries within a shard are considered eligible for eviction.
	"max.incremental.fetch.session.cache.slots"?: *1000 | int & >=0 & <=2147483647

	// The maximum number of partitions can be served in one request.
	"max.request.partition.size.limit"?: *2000 | int & >=1 & <=2147483647

	// The largest record batch size allowed by Kafka (after compression if compression is enabled). If this is increased and there are consumers older than 0.10.2, the consumers' fetch size must also be increased so that they can fetch record batches this large. In the latest message format version, records are always grouped into batches for efficiency. In previous message format versions, uncompressed records are not grouped into batches and this limit only applies to a single record in that case.This can be set per topic with the topic level max.message.bytes config.
	"message.max.bytes"?: *1048588 | int & >=0 & <=2147483647

	// A list of classes to use as metrics reporters. Implementing the org.apache.kafka.common.metrics.MetricsReporter interface allows plugging in classes that will be notified of new metric creation. The JmxReporter is always included to register JMX statistics.
	"metric.reporters"?: *[] | [...string]

	// The number of samples maintained to compute metrics.
	"metrics.num.samples"?: *2 | int & >=1 & <=2147483647

	// The highest recording level for metrics.
	"metrics.recording.level"?: *"INFO" | string

	// The window of time a metrics sample is computed over.
	"metrics.sample.window.ms"?: *30000 | int & >=1 & <=9223372036854775807

	// When a producer sets acks to "all" (or "-1"), min.insync.replicas specifies the minimum number of replicas that must acknowledge a write for the write to be considered successful. If this minimum cannot be met, then the producer will raise an exception (either NotEnoughReplicas or NotEnoughReplicasAfterAppend).When used together, min.insync.replicas and acks allow you to enforce greater durability guarantees. A typical scenario would be to create a topic with a replication factor of 3, set min.insync.replicas to 2, and produce with acks of "all". This will ensure that the producer raises an exception if a majority of replicas do not receive a write.
	"min.insync.replicas"?: *1 | int & >=1 & <=2147483647

	// The node ID associated with the roles this process is playing when process.roles is non-empty. This is required configuration when running in KRaft mode.
	// "node.id"?: *-1 | int & >=-2147483648 & <=2147483647

	// The number of threads that the server uses for processing requests, which may include disk I/O
	"num.io.threads"?: *8 | int & >=1 & <=2147483647

	// The number of threads that the server uses for receiving requests from the network and sending responses to the network. Noted: each listener (except for controller listener) creates its own thread pool.
	"num.network.threads"?: *3 | int & >=1 & <=2147483647

	// The default number of log partitions per topic
	"num.partitions"?: *1 | int & >=1 & <=2147483647

	// The number of threads per data directory to be used for log recovery at startup and flushing at shutdown
	"num.recovery.threads.per.data.dir"?: *1 | int & >=1 & <=2147483647

	// The number of threads that can move replicas between log directories, which may include disk I/O
	"num.replica.alter.log.dirs.threads"?: *null | int & >=-2147483648 & <=2147483647 | null

	// Number of fetcher threads used to replicate records from each source broker. The total number of fetchers on each broker is bound by num.replica.fetchers multiplied by the number of brokers in the cluster.Increasing this value can increase the degree of I/O parallelism in the follower and leader broker at the cost of higher CPU and memory utilization.
	"num.replica.fetchers"?: *1 | int & >=-2147483648 & <=2147483647

	// The maximum size for a metadata entry associated with an offset commit.
	"offset.metadata.max.bytes"?: *4096 | int & >=-2147483648 & <=2147483647

	// DEPRECATED: The required acks before the commit can be accepted. In general, the default (-1) should not be overridden.
	"offsets.commit.required.acks"?: *-1 | int & >=-32768 & <=32767

	// Offset commit will be delayed until all replicas for the offsets topic receive the commit or this timeout is reached. This is similar to the producer request timeout.
	"offsets.commit.timeout.ms"?: *5000 | int & >=1 & <=2147483647

	// Batch size for reading from the offsets segments when loading offsets into the cache (soft-limit, overridden if records are too large).
	"offsets.load.buffer.size"?: *5242880 | int & >=1 & <=2147483647

	// Frequency at which to check for stale offsets
	"offsets.retention.check.interval.ms"?: *600000 | int & >=1 & <=9223372036854775807

	// For subscribed consumers, committed offset of a specific partition will be expired and discarded when 1) this retention period has elapsed after the consumer group loses all its consumers (i.e. becomes empty); 2) this retention period has elapsed since the last time an offset is committed for the partition and the group is no longer subscribed to the corresponding topic. For standalone consumers (using manual assignment), offsets will be expired after this retention period has elapsed since the time of last commit. Note that when a group is deleted via the delete-group request, its committed offsets will also be deleted without extra retention period; also when a topic is deleted via the delete-topic request, upon propagated metadata update any group's committed offsets for that topic will also be deleted without extra retention period.
	"offsets.retention.minutes"?: *10080 | int & >=1 & <=2147483647

	// Compression codec for the offsets topic - compression may be used to achieve "atomic" commits.
	"offsets.topic.compression.codec"?: *0 | int & >=-2147483648 & <=2147483647

	// The number of partitions for the offset commit topic (should not change after deployment).
	"offsets.topic.num.partitions"?: *50 | int & >=1 & <=2147483647

	// The replication factor for the offsets topic (set higher to ensure availability). Internal topic creation will fail until the cluster size meets this replication factor requirement.
	"offsets.topic.replication.factor"?: *3 | int & >=1 & <=32767

	// The offsets topic segment bytes should be kept relatively small in order to facilitate faster log compaction and cache loads.
	"offsets.topic.segment.bytes"?: *104857600 | int & >=1 & <=2147483647

	// The Cipher algorithm used for encoding dynamically configured passwords.
	"password.encoder.cipher.algorithm"?: *"AES/CBC/PKCS5Padding" | string

	// The iteration count used for encoding dynamically configured passwords.
	"password.encoder.iterations"?: *4096 | int & >=1024 & <=2147483647

	// The key length used for encoding dynamically configured passwords.
	"password.encoder.key.length"?: *128 | int & >=8 & <=2147483647

	// The SecretKeyFactory algorithm used for encoding dynamically configured passwords. Default is PBKDF2WithHmacSHA512 if available and PBKDF2WithHmacSHA1 otherwise.
	"password.encoder.keyfactory.algorithm"?: *null | string | null

	// The old secret that was used for encoding dynamically configured passwords. This is required only when the secret is updated. If specified, all dynamically encoded passwords are decoded using this old secret and re-encoded using password.encoder.secret when broker starts up.
	"password.encoder.old.secret"?: *null | string | null

	// The secret used for encoding dynamically configured passwords for this broker.
	"password.encoder.secret"?: *null | string | null

	// The fully qualified name of a class that implements the KafkaPrincipalBuilder interface, which is used to build the KafkaPrincipal object used during authorization. If no principal builder is defined, the default behavior depends on the security protocol in use. For SSL authentication, the principal will be derived using the rules defined by ssl.principal.mapping.rules applied on the distinguished name from the client certificate if one is provided; otherwise, if client authentication is not required, the principal name will be ANONYMOUS. For SASL authentication, the principal will be derived using the rules defined by sasl.kerberos.principal.to.local.rules if GSSAPI is in use, and the SASL authentication ID for other mechanisms. For PLAINTEXT, the principal will be ANONYMOUS.
	"principal.builder.class"?: *"class org.apache.kafka.common.security.authenticator.DefaultKafkaPrincipalBuilder" | string

	// The roles that this process plays: 'broker', 'controller', or 'broker,controller' if it is both. This configuration is only applicable for clusters in KRaft (Kafka Raft) mode (instead of ZooKeeper). Leave this config undefined or empty for ZooKeeper clusters.
	// "process.roles"?: *[] | [...("broker" | "controller")]

	// The time in ms that a topic partition leader will wait before expiring producer IDs. Producer IDs will not expire while a transaction associated to them is still ongoing. Note that producer IDs may expire sooner if the last write from the producer ID is deleted due to the topic's retention settings. Setting this value the same or higher than delivery.timeout.ms can help prevent expiration during retries and protect against message duplication, but the default should be reasonable for most use cases.
	"producer.id.expiration.ms"?: *86400000 | int & >=1 & <=2147483647

	// The purge interval (in number of requests) of the producer request purgatory
	"producer.purgatory.purge.interval.requests"?: *1000 | int & >=-2147483648 & <=2147483647

	// The number of queued bytes allowed before no more requests are read
	"queued.max.request.bytes"?: *-1 | int & >=-9223372036854775808 & <=9223372036854775807

	// The number of queued requests allowed for data-plane, before blocking the network threads
	"queued.max.requests"?: *500 | int & >=1 & <=2147483647

	// The number of samples to retain in memory for client quotas
	"quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for client quotas
	"quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// The maximum amount of time the server will wait before answering the remote fetch request
	"remote.fetch.max.wait.ms"?: *500 | int & >=1 & <=2147483647

	// The total size of the space allocated to store index files fetched from remote storage in the local storage.
	"remote.log.index.file.cache.total.size.bytes"?: *1073741824 | int & >=1 & <=9223372036854775807

	// validator: The default value of -1 means that this will be set to the configured value of remote.log.manager.thread.pool.size, if available; otherwise, it defaults to 10.
	// Size of the thread pool used in scheduling tasks to copy segments. The default value of -1 means that this will be set to the configured value of remote.log.manager.thread.pool.size, if available; otherwise, it defaults to 10.
	"remote.log.manager.copier.thread.pool.size"?: *-1 | int & >=-2147483648 & <=2147483647

	// The maximum number of bytes that can be copied from local storage to remote storage per second. This is a global limit for all the partitions that are being copied from local storage to remote storage. The default value is Long.MAX_VALUE, which means there is no limit on the number of bytes that can be copied per second.
	"remote.log.manager.copy.max.bytes.per.second"?: *9223372036854775807 | int & >=1 & <=9223372036854775807

	// The number of samples to retain in memory for remote copy quota management. The default value is 11, which means there are 10 whole windows + 1 current window.
	"remote.log.manager.copy.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for remote copy quota management. The default value is 1 second.
	"remote.log.manager.copy.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// validator: The default value of -1 means that this will be set to the configured value of remote.log.manager.thread.pool.size, if available; otherwise, it defaults to 10.
	// Size of the thread pool used in scheduling tasks to clean up remote log segments. The default value of -1 means that this will be set to the configured value of remote.log.manager.thread.pool.size, if available; otherwise, it defaults to 10.
	"remote.log.manager.expiration.thread.pool.size"?: *-1 | int & >=-2147483648 & <=2147483647

	// The maximum number of bytes that can be fetched from remote storage to local storage per second. This is a global limit for all the partitions that are being fetched from remote storage to local storage. The default value is Long.MAX_VALUE, which means there is no limit on the number of bytes that can be fetched per second.
	"remote.log.manager.fetch.max.bytes.per.second"?: *9223372036854775807 | int & >=1 & <=9223372036854775807

	// The number of samples to retain in memory for remote fetch quota management. The default value is 11, which means there are 10 whole windows + 1 current window.
	"remote.log.manager.fetch.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for remote fetch quota management. The default value is 1 second.
	"remote.log.manager.fetch.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// Interval at which remote log manager runs the scheduled tasks like copy segments, and clean up remote log segments.
	"remote.log.manager.task.interval.ms"?: *30000 | int & >=1 & <=9223372036854775807

	// Deprecated. Size of the thread pool used in scheduling tasks to copy segments, fetch remote log indexes and clean up remote log segments.
	"remote.log.manager.thread.pool.size"?: *10 | int & >=1 & <=2147483647

	// The maximum size of custom metadata in bytes that the broker should accept from a remote storage plugin. If custom metadata exceeds this limit, the updated segment metadata will not be stored, the copied data will be attempted to delete, and the remote copying task for this topic-partition will stop with an error.
	"remote.log.metadata.custom.metadata.max.bytes"?: *128 | int & >=0 & <=2147483647

	// validator: non-empty string
	// Fully qualified class name of `RemoteLogMetadataManager` implementation.
	"remote.log.metadata.manager.class.name"?: *"org.apache.kafka.server.log.remote.metadata.storage.TopicBasedRemoteLogMetadataManager" | string

	// Class path of the `RemoteLogMetadataManager` implementation. If specified, the RemoteLogMetadataManager implementation and its dependent libraries will be loaded by a dedicated classloader which searches this class path before the Kafka broker class path. The syntax of this parameter is same as the standard Java class path string.
	"remote.log.metadata.manager.class.path"?: *null | string | null

	// validator: non-empty string
	// Prefix used for properties to be passed to RemoteLogMetadataManager implementation. For example this value can be `rlmm.config.`.
	"remote.log.metadata.manager.impl.prefix"?: *"rlmm.config." | string

	// validator: non-empty string
	// Listener name of the local broker to which it should get connected if needed by RemoteLogMetadataManager implementation.
	"remote.log.metadata.manager.listener.name"?: *null | string | null

	// Maximum remote log reader thread pool task queue size. If the task queue is full, fetch requests are served with an error.
	"remote.log.reader.max.pending.tasks"?: *100 | int & >=1 & <=2147483647

	// Size of the thread pool that is allocated for handling remote log reads.
	"remote.log.reader.threads"?: *10 | int & >=1 & <=2147483647

	// validator: non-empty string
	// Fully qualified class name of `RemoteStorageManager` implementation.
	"remote.log.storage.manager.class.name"?: *null | string | null

	// Class path of the `RemoteStorageManager` implementation. If specified, the RemoteStorageManager implementation and its dependent libraries will be loaded by a dedicated classloader which searches this class path before the Kafka broker class path. The syntax of this parameter is same as the standard Java class path string.
	"remote.log.storage.manager.class.path"?: *null | string | null

	// validator: non-empty string
	// Prefix used for properties to be passed to RemoteStorageManager implementation. For example this value can be `rsm.config.`.
	"remote.log.storage.manager.impl.prefix"?: *"rsm.config." | string

	// Whether to enable tiered storage functionality in a broker or not. Valid values are `true` or `false` and the default value is false. When it is true broker starts all the services required for the tiered storage functionality.
	"remote.log.storage.system.enable"?: *false | bool

	// The amount of time to sleep when fetch partition error occurs.
	"replica.fetch.backoff.ms"?: *1000 | int & >=0 & <=2147483647

	// The number of bytes of messages to attempt to fetch for each partition. This is not an absolute maximum, if the first record batch in the first non-empty partition of the fetch is larger than this value, the record batch will still be returned to ensure that progress can be made. The maximum record batch size accepted by the broker is defined via message.max.bytes (broker config) or max.message.bytes (topic config).
	"replica.fetch.max.bytes"?: *1048576 | int & >=0 & <=2147483647

	// Minimum bytes expected for each fetch response. If not enough bytes, wait up to replica.fetch.wait.max.ms (broker config).
	"replica.fetch.min.bytes"?: *1 | int & >=-2147483648 & <=2147483647

	// Maximum bytes expected for the entire fetch response. Records are fetched in batches, and if the first record batch in the first non-empty partition of the fetch is larger than this value, the record batch will still be returned to ensure that progress can be made. As such, this is not an absolute maximum. The maximum record batch size accepted by the broker is defined via message.max.bytes (broker config) or max.message.bytes (topic config).
	"replica.fetch.response.max.bytes"?: *10485760 | int & >=0 & <=2147483647

	// The maximum wait time for each fetcher request issued by follower replicas. This value should always be less than the replica.lag.time.max.ms at all times to prevent frequent shrinking of ISR for low throughput topics
	"replica.fetch.wait.max.ms"?: *500 | int & >=-2147483648 & <=2147483647

	// The frequency with which the high watermark is saved out to disk
	"replica.high.watermark.checkpoint.interval.ms"?: *5000 | int & >=-9223372036854775808 & <=9223372036854775807

	// If a follower hasn't sent any fetch requests or hasn't consumed up to the leaders log end offset for at least this time, the leader will remove the follower from isr
	"replica.lag.time.max.ms"?: *30000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The fully qualified class name that implements ReplicaSelector. This is used by the broker to find the preferred read replica. By default, we use an implementation that returns the leader.
	"replica.selector.class"?: *null | string | null

	// The socket receive buffer for network requests to the leader for replicating data
	"replica.socket.receive.buffer.bytes"?: *65536 | int & >=-2147483648 & <=2147483647

	// The socket timeout for network requests. Its value should be at least replica.fetch.wait.max.ms
	"replica.socket.timeout.ms"?: *30000 | int & >=-2147483648 & <=2147483647

	// The number of samples to retain in memory for replication quotas
	"replication.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for replication quotas
	"replication.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// The configuration controls the maximum amount of time the client will wait for the response of a request. If the response is not received before the timeout elapses the client will resend the request if necessary or fail the request if retries are exhausted.
	"request.timeout.ms"?: *30000 | int & >=-2147483648 & <=2147483647

	// Max number that can be used for a broker.id
	"reserved.broker.max.id"?: *1000 | int & >=0 & <=2147483647

	// The fully qualified name of a SASL client callback handler class that implements the AuthenticateCallbackHandler interface.
	"sasl.client.callback.handler.class"?: *null | string | null

	// The list of SASL mechanisms enabled in the Kafka server. The list may contain any mechanism for which a security provider is available. Only GSSAPI is enabled by default.
	"sasl.enabled.mechanisms"?: *["GSSAPI"] | [...string]

	// JAAS login context parameters for SASL connections in the format used by JAAS configuration files. JAAS configuration file format is described here. The format for the value is: loginModuleClass controlFlag (optionName=optionValue)*;. For brokers, the config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.jaas.config=com.example.ScramLoginModule required;
	"sasl.jaas.config"?: *null | string | null

	// Kerberos kinit command path.
	"sasl.kerberos.kinit.cmd"?: *"/usr/bin/kinit" | string

	// Login thread sleep time between refresh attempts.
	"sasl.kerberos.min.time.before.relogin"?: *60000 | int & >=-9223372036854775808 & <=9223372036854775807

	// A list of rules for mapping from principal names to short names (typically operating system usernames). The rules are evaluated in order and the first rule that matches a principal name is used to map it to a short name. Any later rules in the list are ignored. By default, principal names of the form {username}/{hostname}@{REALM} are mapped to {username}. For more details on the format please see security authorization and acls. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the principal.builder.class configuration.
	"sasl.kerberos.principal.to.local.rules"?: *["DEFAULT"] | [...string]

	// The Kerberos principal name that Kafka runs as. This can be defined either in Kafka's JAAS config or in Kafka's config.
	"sasl.kerberos.service.name"?: *null | string | null

	// Percentage of random jitter added to the renewal time.
	"sasl.kerberos.ticket.renew.jitter"?: *0.05 | number

	// Login thread will sleep until the specified window factor of time from last refresh to ticket's expiry has been reached, at which time it will try to renew the ticket.
	"sasl.kerberos.ticket.renew.window.factor"?: *0.8 | number

	// The fully qualified name of a SASL login callback handler class that implements the AuthenticateCallbackHandler interface. For brokers, login callback handler config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.login.callback.handler.class=com.example.CustomScramLoginCallbackHandler
	"sasl.login.callback.handler.class"?: *null | string | null

	// The fully qualified name of a class that implements the Login interface. For brokers, login config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.login.class=com.example.CustomScramLogin
	"sasl.login.class"?: *null | string | null

	// The (optional) value in milliseconds for the external authentication provider connection timeout. Currently applies only to OAUTHBEARER.
	"sasl.login.connect.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The (optional) value in milliseconds for the external authentication provider read timeout. Currently applies only to OAUTHBEARER.
	"sasl.login.read.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The amount of buffer time before credential expiration to maintain when refreshing a credential, in seconds. If a refresh would otherwise occur closer to expiration than the number of buffer seconds then the refresh will be moved up to maintain as much of the buffer time as possible. Legal values are between 0 and 3600 (1 hour); a default value of 300 (5 minutes) is used if no value is specified. This value and sasl.login.refresh.min.period.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.buffer.seconds"?: *300 | int & >=-32768 & <=32767

	// The desired minimum time for the login refresh thread to wait before refreshing a credential, in seconds. Legal values are between 0 and 900 (15 minutes); a default value of 60 (1 minute) is used if no value is specified. This value and sasl.login.refresh.buffer.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.min.period.seconds"?: *60 | int & >=-32768 & <=32767

	// Login refresh thread will sleep until the specified window factor relative to the credential's lifetime has been reached, at which time it will try to refresh the credential. Legal values are between 0.5 (50%) and 1.0 (100%) inclusive; a default value of 0.8 (80%) is used if no value is specified. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.window.factor"?: *0.8 | number

	// The maximum amount of random jitter relative to the credential's lifetime that is added to the login refresh thread's sleep time. Legal values are between 0 and 0.25 (25%) inclusive; a default value of 0.05 (5%) is used if no value is specified. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.window.jitter"?: *0.05 | number

	// The (optional) value in milliseconds for the maximum wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to OAUTHBEARER.
	"sasl.login.retry.backoff.max.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the initial wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to OAUTHBEARER.
	"sasl.login.retry.backoff.ms"?: *100 | int & >=-9223372036854775808 & <=9223372036854775807

	// SASL mechanism used for communication with controllers. Default is GSSAPI.
	"sasl.mechanism.controller.protocol"?: *"GSSAPI" | string

	// SASL mechanism used for inter-broker communication. Default is GSSAPI.
	"sasl.mechanism.inter.broker.protocol"?: *"GSSAPI" | string

	// The (optional) value in seconds to allow for differences between the time of the OAuth/OIDC identity provider and the broker.
	"sasl.oauthbearer.clock.skew.seconds"?: *30 | int & >=-2147483648 & <=2147483647

	// The (optional) comma-delimited setting for the broker to use to verify that the JWT was issued for one of the expected audiences. The JWT will be inspected for the standard OAuth "aud" claim and if this value is set, the broker will match the value from JWT's "aud" claim to see if there is an exact match. If there is no match, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.expected.audience"?: *null | [...string] | null

	// The (optional) setting for the broker to use to verify that the JWT was created by the expected issuer. The JWT will be inspected for the standard OAuth "iss" claim and if this value is set, the broker will match it exactly against what is in the JWT's "iss" claim. If there is no match, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.expected.issuer"?: *null | string | null

	// The (optional) value in milliseconds for the broker to wait between refreshing its JWKS (JSON Web Key Set) cache that contains the keys to verify the signature of the JWT.
	"sasl.oauthbearer.jwks.endpoint.refresh.ms"?: *3600000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the maximum wait between attempts to retrieve the JWKS (JSON Web Key Set) from the external authentication provider. JWKS retrieval uses an exponential backoff algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
	"sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the initial wait between JWKS (JSON Web Key Set) retrieval attempts from the external authentication provider. JWKS retrieval uses an exponential backoff algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
	"sasl.oauthbearer.jwks.endpoint.retry.backoff.ms"?: *100 | int & >=-9223372036854775808 & <=9223372036854775807

	// The OAuth/OIDC provider URL from which the provider's JWKS (JSON Web Key Set) can be retrieved. The URL can be HTTP(S)-based or file-based. If the URL is HTTP(S)-based, the JWKS data will be retrieved from the OAuth/OIDC provider via the configured URL on broker startup. All then-current keys will be cached on the broker for incoming requests. If an authentication request is received for a JWT that includes a "kid" header claim value that isn't yet in the cache, the JWKS endpoint will be queried again on demand. However, the broker polls the URL every sasl.oauthbearer.jwks.endpoint.refresh.ms milliseconds to refresh the cache with any forthcoming keys before any JWT requests that include them are received. If the URL is file-based, the broker will load the JWKS file from a configured location on startup. In the event that the JWT includes a "kid" header value that isn't in the JWKS file, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.jwks.endpoint.url"?: *null | string | null

	// The OAuth claim for the scope is often named "scope", but this (optional) setting can provide a different name to use for the scope included in the JWT payload's claims if the OAuth/OIDC provider uses a different name for that claim.
	"sasl.oauthbearer.scope.claim.name"?: *"scope" | string

	// The OAuth claim for the subject is often named "sub", but this (optional) setting can provide a different name to use for the subject included in the JWT payload's claims if the OAuth/OIDC provider uses a different name for that claim.
	"sasl.oauthbearer.sub.claim.name"?: *"sub" | string

	// The URL for the OAuth/OIDC identity provider. If the URL is HTTP(S)-based, it is the issuer's token endpoint URL to which requests will be made to login based on the configuration in sasl.jaas.config. If the URL is file-based, it specifies a file containing an access token (in JWT serialized form) issued by the OAuth/OIDC identity provider to use for authorization.
	"sasl.oauthbearer.token.endpoint.url"?: *null | string | null

	// The fully qualified name of a SASL server callback handler class that implements the AuthenticateCallbackHandler interface. Server callback handlers must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.plain.sasl.server.callback.handler.class=com.example.CustomPlainCallbackHandler.
	"sasl.server.callback.handler.class"?: *null | string | null

	// The maximum receive size allowed before and during initial SASL authentication. Default receive size is 512KB. GSSAPI limits requests to 64K, but we allow upto 512KB by default for custom SASL mechanisms. In practice, PLAIN, SCRAM and OAUTH mechanisms can use much smaller limits.
	"sasl.server.max.receive.size"?: *524288 | int & >=-2147483648 & <=2147483647

	// Security protocol used to communicate between brokers. Valid values are: PLAINTEXT, SSL, SASL_PLAINTEXT, SASL_SSL. It is an error to set this and inter.broker.listener.name properties at the same time.
	"security.inter.broker.protocol"?: *"PLAINTEXT" | string & ("PLAINTEXT" | "SSL" | "SASL_PLAINTEXT" | "SASL_SSL")

	// A list of configurable creator classes each returning a provider implementing security algorithms. These classes should implement the org.apache.kafka.common.security.auth.SecurityProviderCreator interface.
	"security.providers"?: *null | string | null

	// The maximum amount of time the client will wait for the socket connection to be established. The connection setup timeout will increase exponentially for each consecutive connection failure up to this maximum. To avoid connection storms, a randomization factor of 0.2 will be applied to the timeout resulting in a random range between 20% below and 20% above the computed value.
	"socket.connection.setup.timeout.max.ms"?: *30000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The amount of time the client will wait for the socket connection to be established. If the connection is not built before the timeout elapses, clients will close the socket channel. This value is the initial backoff value and will increase exponentially for each consecutive connection failure, up to the socket.connection.setup.timeout.max.ms value.
	"socket.connection.setup.timeout.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The maximum number of pending connections on the socket. In Linux, you may also need to configure somaxconn and tcp_max_syn_backlog kernel parameters accordingly to make the configuration takes effect.
	"socket.listen.backlog.size"?: *50 | int & >=1 & <=2147483647

	// The SO_RCVBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
	"socket.receive.buffer.bytes"?: *102400 | int & >=-2147483648 & <=2147483647

	// The maximum number of bytes in a socket request
	"socket.request.max.bytes"?: *104857600 | int & >=1 & <=2147483647

	// The SO_SNDBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
	"socket.send.buffer.bytes"?: *102400 | int & >=-2147483648 & <=2147483647

	// Indicates whether changes to the certificate distinguished name should be allowed during a dynamic reconfiguration of certificates or not.
	"ssl.allow.dn.changes"?: *false | bool

	// Indicates whether changes to the certificate subject alternative names should be allowed during a dynamic reconfiguration of certificates or not.
	"ssl.allow.san.changes"?: *false | bool

	// A list of cipher suites. This is a named combination of authentication, encryption, MAC and key exchange algorithm used to negotiate the security settings for a network connection using TLS or SSL network protocol. By default all the available cipher suites are supported.
	"ssl.cipher.suites"?: *[] | [...string]

	// Configures kafka broker to request client authentication. The following settings are common: ssl.client.auth=required If set to required client authentication is required. ssl.client.auth=requested This means client authentication is optional. unlike required, if this option is set client can choose not to provide authentication information about itself ssl.client.auth=none This means client authentication is not needed.
	"ssl.client.auth"?: *"none" | string & ("required" | "requested" | "none")

	// The list of protocols enabled for SSL connections. The default is 'TLSv1.2,TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. With the default value for Java 11, clients and servers will prefer TLSv1.3 if both support it and fallback to TLSv1.2 otherwise (assuming both support at least TLSv1.2). This default should be fine for most cases. Also see the config documentation for `ssl.protocol`.
	"ssl.enabled.protocols"?: *["TLSv1.2", "TLSv1.3"] | [...string]

	// The endpoint identification algorithm to validate server hostname using server certificate.
	"ssl.endpoint.identification.algorithm"?: *"https" | string

	// The class of type org.apache.kafka.common.security.auth.SslEngineFactory to provide SSLEngine objects. Default value is org.apache.kafka.common.security.ssl.DefaultSslEngineFactory. Alternatively, setting this to org.apache.kafka.common.security.ssl.CommonNameLoggingSslEngineFactory will log the common name of expired SSL certificates used by clients to authenticate at any of the brokers with log level INFO. Note that this will cause a tiny delay during establishment of new connections from mTLS clients to brokers due to the extra code for examining the certificate chain provided by the client. Note further that the implementation uses a custom truststore based on the standard Java truststore and thus might be considered a security risk due to not being as mature as the standard one.
	"ssl.engine.factory.class"?: *null | string | null

	// The password of the private key in the key store file or the PEM key specified in 'ssl.keystore.key'.
	"ssl.key.password"?: *null | string | null

	// The algorithm used by key manager factory for SSL connections. Default value is the key manager factory algorithm configured for the Java Virtual Machine.
	"ssl.keymanager.algorithm"?: *"SunX509" | string

	// Certificate chain in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with a list of X.509 certificates
	"ssl.keystore.certificate.chain"?: *null | string | null

	// Private key in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with PKCS#8 keys. If the key is encrypted, key password must be specified using 'ssl.key.password'
	"ssl.keystore.key"?: *null | string | null

	// The location of the key store file. This is optional for client and can be used for two-way authentication for client.
	"ssl.keystore.location"?: *null | string | null

	// The store password for the key store file. This is optional for client and only needed if 'ssl.keystore.location' is configured. Key store password is not supported for PEM format.
	"ssl.keystore.password"?: *null | string | null

	// The file format of the key store file. This is optional for client. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
	// "ssl.keystore.type"?: *"JKS" | string

	// A list of rules for mapping from distinguished name from the client certificate to short name. The rules are evaluated in order and the first rule that matches a principal name is used to map it to a short name. Any later rules in the list are ignored. By default, distinguished name of the X.500 certificate will be the principal. For more details on the format please see security authorization and acls. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the principal.builder.class configuration.
	"ssl.principal.mapping.rules"?: *"DEFAULT" | string

	// The SSL protocol used to generate the SSLContext. The default is 'TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. This value should be fine for most use cases. Allowed values in recent JVMs are 'TLSv1.2' and 'TLSv1.3'. 'TLS', 'TLSv1.1', 'SSL', 'SSLv2' and 'SSLv3' may be supported in older JVMs, but their usage is discouraged due to known security vulnerabilities. With the default value for this config and 'ssl.enabled.protocols', clients will downgrade to 'TLSv1.2' if the server does not support 'TLSv1.3'. If this config is set to 'TLSv1.2', clients will not use 'TLSv1.3' even if it is one of the values in ssl.enabled.protocols and the server only supports 'TLSv1.3'.
	"ssl.protocol"?: *"TLSv1.3" | string

	// The name of the security provider used for SSL connections. Default value is the default security provider of the JVM.
	"ssl.provider"?: *null | string | null

	// The SecureRandom PRNG implementation to use for SSL cryptography operations.
	"ssl.secure.random.implementation"?: *null | string | null

	// The algorithm used by trust manager factory for SSL connections. Default value is the trust manager factory algorithm configured for the Java Virtual Machine.
	"ssl.trustmanager.algorithm"?: *"PKIX" | string

	// Trusted certificates in the format specified by 'ssl.truststore.type'. Default SSL engine factory supports only PEM format with X.509 certificates.
	"ssl.truststore.certificates"?: *null | string | null

	// The location of the trust store file.
	"ssl.truststore.location"?: *null | string | null

	// The password for the trust store file. If a password is not set, trust store file configured will still be used, but integrity checking is disabled. Trust store password is not supported for PEM format.
	"ssl.truststore.password"?: *null | string | null

	// The file format of the trust store file. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
	"ssl.truststore.type"?: *"JKS" | string

	// The maximum size (after compression if compression is used) of telemetry metrics pushed from a client to the broker. The default value is 1048576 (1 MB).
	"telemetry.max.bytes"?: *1048576 | int & >=1 & <=2147483647

	// The interval at which to rollback transactions that have timed out
	"transaction.abort.timed.out.transaction.cleanup.interval.ms"?: *10000 | int & >=1 & <=2147483647

	// The maximum allowed timeout for transactions. If a client’s requested transaction time exceed this, then the broker will return an error in InitProducerIdRequest. This prevents a client from too large of a timeout, which can stall consumers reading from topics included in the transaction.
	"transaction.max.timeout.ms"?: *900000 | int & >=1 & <=2147483647

	// Enable verification that checks that the partition has been added to the transaction before writing transactional records to the partition
	"transaction.partition.verification.enable"?: *true | bool

	// The interval at which to remove transactions that have expired due to transactional.id.expiration.ms passing
	"transaction.remove.expired.transaction.cleanup.interval.ms"?: *3600000 | int & >=1 & <=2147483647

	// Batch size for reading from the transaction log segments when loading producer ids and transactions into the cache (soft-limit, overridden if records are too large).
	"transaction.state.log.load.buffer.size"?: *5242880 | int & >=1 & <=2147483647

	// The minimum number of replicas that must acknowledge a write to transaction topic in order to be considered successful.
	"transaction.state.log.min.isr"?: *2 | int & >=1 & <=2147483647

	// The number of partitions for the transaction topic (should not change after deployment).
	"transaction.state.log.num.partitions"?: *50 | int & >=1 & <=2147483647

	// The replication factor for the transaction topic (set higher to ensure availability). Internal topic creation will fail until the cluster size meets this replication factor requirement.
	"transaction.state.log.replication.factor"?: *3 | int & >=1 & <=32767

	// The transaction topic segment bytes should be kept relatively small in order to facilitate faster log compaction and cache loads
	"transaction.state.log.segment.bytes"?: *104857600 | int & >=1 & <=2147483647

	// The time in ms that the transaction coordinator will wait without receiving any transaction status updates for the current transaction before expiring its transactional id. Transactional IDs will not expire while a the transaction is still ongoing.
	"transactional.id.expiration.ms"?: *604800000 | int & >=1 & <=2147483647

	// Indicates whether to enable replicas not in the ISR set to be elected as leader as a last resort, even though doing so may result in data lossNote: In KRaft mode, when enabling this config dynamically, it needs to wait for the unclean leader election thread to trigger election periodically (default is 5 minutes). Please run `kafka-leader-election.sh` with `unclean` option to trigger the unclean leader election immediately if needed.
	"unclean.leader.election.enable"?: *false | bool

	// Typically set to org.apache.zookeeper.ClientCnxnSocketNetty when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the same-named zookeeper.clientCnxnSocket system property.
	"zookeeper.clientCnxnSocket"?: *null | string | null

	// Specifies the ZooKeeper connection string in the form hostname:port where host and port are the host and port of a ZooKeeper server. To allow connecting through other ZooKeeper nodes when that ZooKeeper machine is down you can also specify multiple hosts in the form hostname1:port1,hostname2:port2,hostname3:port3. The server can also have a ZooKeeper chroot path as part of its ZooKeeper connection string which puts its data under some path in the global ZooKeeper namespace. For example to give a chroot path of /chroot/path you would give the connection string as hostname1:port1,hostname2:port2,hostname3:port3/chroot/path.
	"zookeeper.connect"?: *null | string | null

	// The max time that the client waits to establish a connection to ZooKeeper. If not set, the value in zookeeper.session.timeout.ms is used
	"zookeeper.connection.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The maximum number of unacknowledged requests the client will send to ZooKeeper before blocking.
	"zookeeper.max.in.flight.requests"?: *10 | int & >=1 & <=2147483647

	// Zookeeper session timeout
	"zookeeper.session.timeout.ms"?: *18000 | int & >=-2147483648 & <=2147483647

	// Set client to use secure ACLs
	"zookeeper.set.acl"?: *false | bool

	// Specifies the enabled cipher suites to be used in ZooKeeper TLS negotiation (csv). Overrides any explicit value set via the zookeeper.ssl.ciphersuites system property (note the single word "ciphersuites"). The default value of null means the list of enabled cipher suites is determined by the Java runtime being used.
	"zookeeper.ssl.cipher.suites"?: *null | [...string] | null

	// Set client to use TLS when connecting to ZooKeeper. An explicit value overrides any value set via the zookeeper.client.secure system property (note the different name). Defaults to false if neither is set; when true, zookeeper.clientCnxnSocket must be set (typically to org.apache.zookeeper.ClientCnxnSocketNetty); other values to set may include zookeeper.ssl.cipher.suites, zookeeper.ssl.crl.enable, zookeeper.ssl.enabled.protocols, zookeeper.ssl.endpoint.identification.algorithm, zookeeper.ssl.keystore.location, zookeeper.ssl.keystore.password, zookeeper.ssl.keystore.type, zookeeper.ssl.ocsp.enable, zookeeper.ssl.protocol, zookeeper.ssl.truststore.location, zookeeper.ssl.truststore.password, zookeeper.ssl.truststore.type
	"zookeeper.ssl.client.enable"?: *false | bool

	// Specifies whether to enable Certificate Revocation List in the ZooKeeper TLS protocols. Overrides any explicit value set via the zookeeper.ssl.crl system property (note the shorter name).
	"zookeeper.ssl.crl.enable"?: *false | bool

	// Specifies the enabled protocol(s) in ZooKeeper TLS negotiation (csv). Overrides any explicit value set via the zookeeper.ssl.enabledProtocols system property (note the camelCase). The default value of null means the enabled protocol will be the value of the zookeeper.ssl.protocol configuration property.
	"zookeeper.ssl.enabled.protocols"?: *null | [...string] | null

	// Specifies whether to enable hostname verification in the ZooKeeper TLS negotiation process, with (case-insensitively) "https" meaning ZooKeeper hostname verification is enabled and an explicit blank value meaning it is disabled (disabling it is only recommended for testing purposes). An explicit value overrides any "true" or "false" value set via the zookeeper.ssl.hostnameVerification system property (note the different name and values; true implies https and false implies blank).
	"zookeeper.ssl.endpoint.identification.algorithm"?: *"HTTPS" | string

	// Keystore location when using a client-side certificate with TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.keyStore.location system property (note the camelCase).
	"zookeeper.ssl.keystore.location"?: *null | string | null

	// Keystore password when using a client-side certificate with TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.keyStore.password system property (note the camelCase). Note that ZooKeeper does not support a key password different from the keystore password, so be sure to set the key password in the keystore to be identical to the keystore password; otherwise the connection attempt to Zookeeper will fail.
	"zookeeper.ssl.keystore.password"?: *null | string | null

	// Keystore type when using a client-side certificate with TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.keyStore.type system property (note the camelCase). The default value of null means the type will be auto-detected based on the filename extension of the keystore.
	"zookeeper.ssl.keystore.type"?: *null | string | null

	// Specifies whether to enable Online Certificate Status Protocol in the ZooKeeper TLS protocols. Overrides any explicit value set via the zookeeper.ssl.ocsp system property (note the shorter name).
	"zookeeper.ssl.ocsp.enable"?: *false | bool

	// Specifies the protocol to be used in ZooKeeper TLS negotiation. An explicit value overrides any value set via the same-named zookeeper.ssl.protocol system property.
	"zookeeper.ssl.protocol"?: *"TLSv1.2" | string

	// Truststore location when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.trustStore.location system property (note the camelCase).
	"zookeeper.ssl.truststore.location"?: *null | string | null

	// Truststore password when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.trustStore.password system property (note the camelCase).
	"zookeeper.ssl.truststore.password"?: *null | string | null

	// Truststore type when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.trustStore.type system property (note the camelCase). The default value of null means the type will be auto-detected based on the filename extension of the truststore.
	"zookeeper.ssl.truststore.type"?: *null | string | null

	...
}

#Combined: {
	// Listeners to publish to ZooKeeper for clients to use, if different than the listeners config property. In IaaS environments, this may need to be different from the interface to which the broker binds. If this is not set, the value for listeners will be used. Unlike listeners, it is not valid to advertise the 0.0.0.0 meta-address. Also unlike listeners, there can be duplicated ports in this property, so that one listener can be configured to advertise another listener's address. This can be useful in some cases where external load balancers are used.
	// "advertised.listeners"?: *null | string | null

	// The alter configs policy class that should be used for validation. The class should implement the org.apache.kafka.server.policy.AlterConfigPolicy interface.
	"alter.config.policy.class.name"?: *null | string | null

	// The number of samples to retain in memory for alter log dirs replication quotas
	"alter.log.dirs.replication.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for alter log dirs replication quotas
	"alter.log.dirs.replication.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// validator: non-null string
	// The fully qualified name of a class that implements org.apache.kafka.server.authorizer.Authorizer interface, which is used by the broker for authorization.
	"authorizer.class.name"?: *"" | string

	// Enable auto creation of topic on the server.
	"auto.create.topics.enable"?: *true | bool

	// Deprecated. Whether to automatically include JmxReporter even if it's not listed in metric.reporters. This configuration will be removed in Kafka 4.0, users should instead include org.apache.kafka.common.metrics.JmxReporter in metric.reporters in order to enable the JmxReporter.
	"auto.include.jmx.reporter"?: *true | bool

	// Enables auto leader balancing. A background thread checks the distribution of partition leaders at regular intervals, configurable by leader.imbalance.check.interval.seconds. If the leader imbalance exceeds leader.imbalance.per.broker.percentage, leader rebalance to the preferred leader for partitions is triggered.
	"auto.leader.rebalance.enable"?: *true | bool

	// The number of threads to use for various background processing tasks
	"background.threads"?: *10 | int & >=1 & <=2147483647

	// The length of time in milliseconds between broker heartbeats. Used when running in KRaft mode.
	"broker.heartbeat.interval.ms"?: *2000 | int & >=-2147483648 & <=2147483647

	// The broker id for this server. If unset, a unique broker id will be generated.To avoid conflicts between ZooKeeper generated broker id's and user configured broker id's, generated broker ids start from reserved.broker.max.id + 1.
	"broker.id"?: *-1 | int & >=-2147483648 & <=2147483647

	// Enable automatic broker id generation on the server. When enabled the value configured for reserved.broker.max.id should be reviewed.
	"broker.id.generation.enable"?: *true | bool

	// Rack of the broker. This will be used in rack aware replication assignment for fault tolerance. Examples: RACK1, us-east-1d
	"broker.rack"?: *null | string | null

	// The length of time in milliseconds that a broker lease lasts if no heartbeats are made. Used when running in KRaft mode.
	"broker.session.timeout.ms"?: *9000 | int & >=-2147483648 & <=2147483647

	// The fully qualified name of a class that implements the ClientQuotaCallback interface, which is used to determine quota limits applied to client requests. By default, the &lt;user&gt; and &lt;client-id&gt; quotas that are stored in ZooKeeper are applied. For any given request, the most specific quota that matches the user principal of the session and the client-id of the request is applied.
	"client.quota.callback.class"?: *null | string | null

	// validator: [1,...,9] or -1
	// The compression level to use if compression.type is set to 'gzip'.
	"compression.gzip.level"?: *-1 | int & >=-2147483648 & <=2147483647

	// The compression level to use if compression.type is set to 'lz4'.
	"compression.lz4.level"?: *9 | int & >=1 & <=17

	// Specify the final compression type for a given topic. This configuration accepts the standard compression codecs ('gzip', 'snappy', 'lz4', 'zstd'). It additionally accepts 'uncompressed' which is equivalent to no compression; and 'producer' which means retain the original compression codec set by the producer.
	"compression.type"?: *"producer" | string & ("uncompressed" | "zstd" | "lz4" | "snappy" | "gzip" | "producer")

	// The compression level to use if compression.type is set to 'zstd'.
	"compression.zstd.level"?: *3 | int & >=-131072 & <=22

	// Connection close delay on failed authentication: this is the time (in milliseconds) by which connection close will be delayed on authentication failure. This must be configured to be less than connections.max.idle.ms to prevent connection timeout.
	"connection.failed.authentication.delay.ms"?: *100 | int & >=0 & <=2147483647

	// Idle connections timeout: the server socket processor threads close the connections that idle more than this
	"connections.max.idle.ms"?: *600000 | int & >=-9223372036854775808 & <=9223372036854775807

	// When explicitly set to a positive number (the default is 0, not a positive number), a session lifetime that will not exceed the configured value will be communicated to v2.2.0 or later clients when they authenticate. The broker will disconnect any such connection that is not re-authenticated within the session lifetime and that is then subsequently used for any purpose other than re-authentication. Configuration names can optionally be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.oauthbearer.connections.max.reauth.ms=3600000
	"connections.max.reauth.ms"?: *0 | int & >=-9223372036854775808 & <=9223372036854775807

	// Name of listener used for communication between controller and brokers. A broker will use the control.plane.listener.name to locate the endpoint in listeners list, to listen for connections from the controller. For example, if a broker's config is: listeners = INTERNAL://192.1.1.8:9092, EXTERNAL://10.1.1.5:9093, CONTROLLER://192.1.1.8:9094listener.security.protocol.map = INTERNAL:PLAINTEXT, EXTERNAL:SSL, CONTROLLER:SSLcontrol.plane.listener.name = CONTROLLER On startup, the broker will start listening on "192.1.1.8:9094" with security protocol "SSL". On the controller side, when it discovers a broker's published endpoints through ZooKeeper, it will use the control.plane.listener.name to find the endpoint, which it will use to establish connection to the broker. For example, if the broker's published endpoints on ZooKeeper are: "endpoints" : ["INTERNAL://broker1.example.com:9092","EXTERNAL://broker1.example.com:9093","CONTROLLER://broker1.example.com:9094"] and the controller's config is: listener.security.protocol.map = INTERNAL:PLAINTEXT, EXTERNAL:SSL, CONTROLLER:SSLcontrol.plane.listener.name = CONTROLLER then the controller will use "broker1.example.com:9094" with security protocol "SSL" to connect to the broker. If not explicitly configured, the default value will be null and there will be no dedicated endpoints for controller connections. If explicitly configured, the value cannot be the same as the value of inter.broker.listener.name.
	"control.plane.listener.name"?: *null | string | null

	// Enable controlled shutdown of the server.
	"controlled.shutdown.enable"?: *true | bool

	// Controlled shutdown can fail for multiple reasons. This determines the number of retries when such failure happens
	"controlled.shutdown.max.retries"?: *3 | int & >=-2147483648 & <=2147483647

	// Before each retry, the system needs time to recover from the state that caused the previous failure (Controller fail over, replica lag etc). This config determines the amount of time to wait before retrying.
	"controlled.shutdown.retry.backoff.ms"?: *5000 | int & >=-9223372036854775808 & <=9223372036854775807

	// A comma-separated list of the names of the listeners used by the controller. This is required if running in KRaft mode. When communicating with the controller quorum, the broker will always use the first listener in this list. Note: The ZooKeeper-based controller should not set this configuration.
	// "controller.listener.names"?: *null | string | null

	// The duration in milliseconds that the leader will wait for writes to accumulate before flushing them to disk.
	"controller.quorum.append.linger.ms"?: *25 | int & >=-2147483648 & <=2147483647

	// validator: non-empty list
	// List of endpoints to use for bootstrapping the cluster metadata. The endpoints are specified in comma-separated list of {host}:{port} entries. For example: localhost:9092,localhost:9093,localhost:9094.
	// "controller.quorum.bootstrap.servers"?: *[] | [...string]

	// Maximum time in milliseconds before starting new elections. This is used in the binary exponential backoff mechanism that helps prevent gridlocked elections
	"controller.quorum.election.backoff.max.ms"?: *1000 | int & >=-2147483648 & <=2147483647

	// Maximum time in milliseconds to wait without being able to fetch from the leader before triggering a new election
	"controller.quorum.election.timeout.ms"?: *1000 | int & >=-2147483648 & <=2147483647

	// Maximum time without a successful fetch from the current leader before becoming a candidate and triggering an election for voters; Maximum time a leader can go without receiving valid fetch or fetchSnapshot request from a majority of the quorum before resigning.
	"controller.quorum.fetch.timeout.ms"?: *2000 | int & >=-2147483648 & <=2147483647

	// The configuration controls the maximum amount of time the client will wait for the response of a request. If the response is not received before the timeout elapses the client will resend the request if necessary or fail the request if retries are exhausted.
	"controller.quorum.request.timeout.ms"?: *2000 | int & >=-2147483648 & <=2147483647

	// The amount of time to wait before attempting to retry a failed request to a given topic partition. This avoids repeatedly sending requests in a tight loop under some failure scenarios. This value is the initial backoff value and will increase exponentially for each failed request, up to the retry.backoff.max.ms value.
	"controller.quorum.retry.backoff.ms"?: *20 | int & >=-2147483648 & <=2147483647

	// validator: non-empty list
	// Map of id/endpoint information for the set of voters in a comma-separated list of {id}@{host}:{port} entries. For example: 1@localhost:9092,2@localhost:9093,3@localhost:9094
	// "controller.quorum.voters"?: *[] | [...string]

	// The number of samples to retain in memory for controller mutation quotas
	"controller.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for controller mutations quotas
	"controller.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// The socket timeout for controller-to-broker channels.
	"controller.socket.timeout.ms"?: *30000 | int & >=-2147483648 & <=2147483647

	// The create topic policy class that should be used for validation. The class should implement the org.apache.kafka.server.policy.CreateTopicPolicy interface.
	"create.topic.policy.class.name"?: *null | string | null

	// The replication factor for automatically created topics, and for topics created with -1 as the replication factor
	"default.replication.factor"?: *1 | int & >=-2147483648 & <=2147483647

	// Scan interval to remove expired delegation tokens.
	"delegation.token.expiry.check.interval.ms"?: *3600000 | int & >=1 & <=9223372036854775807

	// The token validity time in milliseconds before the token needs to be renewed. Default value 1 day.
	"delegation.token.expiry.time.ms"?: *86400000 | int & >=1 & <=9223372036854775807

	// DEPRECATED: An alias for delegation.token.secret.key, which should be used instead of this config.
	"delegation.token.master.key"?: *null | string | null

	// The token has a maximum lifetime beyond which it cannot be renewed anymore. Default value 7 days.
	"delegation.token.max.lifetime.ms"?: *604800000 | int & >=1 & <=9223372036854775807

	// Secret key to generate and verify delegation tokens. The same key must be configured across all the brokers. If using Kafka with KRaft, the key must also be set across all controllers. If the key is not set or set to empty string, brokers will disable the delegation token support.
	"delegation.token.secret.key"?: *null | string | null

	// The purge interval (in number of requests) of the delete records request purgatory
	"delete.records.purgatory.purge.interval.requests"?: *1 | int & >=-2147483648 & <=2147483647

	// Enables delete topic. Delete topic through the admin tool will have no effect if this config is turned off
	"delete.topic.enable"?: *true | bool

	// A comma-separated list of listener names which may be started before the authorizer has finished initialization. This is useful when the authorizer is dependent on the cluster itself for bootstrapping, as is the case for the StandardAuthorizer (which stores ACLs in the metadata log.) By default, all listeners included in controller.listener.names will also be early start listeners. A listener should not appear in this list if it accepts external traffic.
	"early.start.listeners"?: *null | string | null

	// Enable the Eligible leader replicas
	"eligible.leader.replicas.enable"?: *false | bool

	// The maximum number of bytes we will return for a fetch request. Must be at least 1024.
	"fetch.max.bytes"?: *57671680 | int & >=1024 & <=2147483647

	// The purge interval (in number of requests) of the fetch request purgatory
	"fetch.purgatory.purge.interval.requests"?: *1000 | int & >=-2147483648 & <=2147483647

	// The server side assignors as a list of full class names. The first one in the list is considered as the default assignor to be used in the case where the consumer does not specify an assignor.
	"group.consumer.assignors"?: *["org.apache.kafka.coordinator.group.assignor.UniformAssignor", "org.apache.kafka.coordinator.group.assignor.RangeAssignor"] | [...string]

	// The heartbeat interval given to the members of a consumer group.
	"group.consumer.heartbeat.interval.ms"?: *5000 | int & >=1 & <=2147483647

	// The maximum heartbeat interval for registered consumers.
	"group.consumer.max.heartbeat.interval.ms"?: *15000 | int & >=1 & <=2147483647

	// The maximum allowed session timeout for registered consumers.
	"group.consumer.max.session.timeout.ms"?: *60000 | int & >=1 & <=2147483647

	// The maximum number of consumers that a single consumer group can accommodate. This value will only impact the new consumer coordinator. To configure the classic consumer coordinator check group.max.size instead.
	"group.consumer.max.size"?: *2147483647 | int & >=1 & <=2147483647

	// The minimum heartbeat interval for registered consumers.
	"group.consumer.min.heartbeat.interval.ms"?: *5000 | int & >=1 & <=2147483647

	// The minimum allowed session timeout for registered consumers.
	"group.consumer.min.session.timeout.ms"?: *45000 | int & >=1 & <=2147483647

	// The timeout to detect client failures when using the consumer group protocol.
	"group.consumer.session.timeout.ms"?: *45000 | int & >=1 & <=2147483647

	// The duration in milliseconds that the coordinator will wait for writes to accumulate before flushing them to disk. Transactional writes are not accumulated.
	"group.coordinator.append.linger.ms"?: *10 | int & >=0 & <=2147483647

	// The list of enabled rebalance protocols. Supported protocols: consumer,classic,share,unknown. The consumer rebalance protocol is in early access and therefore must not be used in production.
	"group.coordinator.rebalance.protocols"?: *["classic"] | [...("consumer" | "classic" | "share" | "unknown")]

	// The number of threads used by the group coordinator.
	"group.coordinator.threads"?: *1 | int & >=1 & <=2147483647

	// The amount of time the group coordinator will wait for more consumers to join a new group before performing the first rebalance. A longer delay means potentially fewer rebalances, but increases the time until processing begins.
	"group.initial.rebalance.delay.ms"?: *3000 | int & >=-2147483648 & <=2147483647

	// The maximum allowed session timeout for registered consumers. Longer timeouts give consumers more time to process messages in between heartbeats at the cost of a longer time to detect failures.
	"group.max.session.timeout.ms"?: *1800000 | int & >=-2147483648 & <=2147483647

	// The maximum number of consumers that a single consumer group can accommodate.
	"group.max.size"?: *2147483647 | int & >=1 & <=2147483647

	// The minimum allowed session timeout for registered consumers. Shorter timeouts result in quicker failure detection at the cost of more frequent consumer heartbeating, which can overwhelm broker resources.
	"group.min.session.timeout.ms"?: *6000 | int & >=-2147483648 & <=2147483647

	// The maximum number of delivery attempts for a record delivered to a share group.
	"group.share.delivery.count.limit"?: *5 | int & >=2 & <=10

	// The heartbeat interval given to the members of a share group.
	"group.share.heartbeat.interval.ms"?: *5000 | int & >=1 & <=2147483647

	// The maximum number of share groups.
	"group.share.max.groups"?: *10 | int & >=1 & <=100

	// The maximum heartbeat interval for share group members.
	"group.share.max.heartbeat.interval.ms"?: *15000 | int & >=1 & <=2147483647

	// The record acquisition lock maximum duration in milliseconds for share groups.
	"group.share.max.record.lock.duration.ms"?: *60000 | int & >=30000 & <=3600000

	// The maximum allowed session timeout for share group members.
	"group.share.max.session.timeout.ms"?: *60000 | int & >=1 & <=2147483647

	// The maximum number of members that a single share group can accommodate.
	"group.share.max.size"?: *200 | int & >=10 & <=1000

	// The minimum heartbeat interval for share group members.
	"group.share.min.heartbeat.interval.ms"?: *5000 | int & >=1 & <=2147483647

	// The record acquisition lock minimum duration in milliseconds for share groups.
	"group.share.min.record.lock.duration.ms"?: *15000 | int & >=1000 & <=30000

	// The minimum allowed session timeout for share group members.
	"group.share.min.session.timeout.ms"?: *45000 | int & >=1 & <=2147483647

	// Share-group record lock limit per share-partition.
	"group.share.partition.max.record.locks"?: *200 | int & >=100 & <=10000

	// The record acquisition lock duration in milliseconds for share groups.
	"group.share.record.lock.duration.ms"?: *30000 | int & >=1000 & <=60000

	// The timeout to detect client failures when using the share group protocol.
	"group.share.session.timeout.ms"?: *45000 | int & >=1 & <=2147483647

	// When initially registering with the controller quorum, the number of milliseconds to wait before declaring failure and exiting the broker process.
	"initial.broker.registration.timeout.ms"?: *60000 | int & >=-2147483648 & <=2147483647

	// Name of listener used for communication between brokers. If this is unset, the listener name is defined by security.inter.broker.protocolIt is an error to set this and security.inter.broker.protocol properties at the same time.
	// "inter.broker.listener.name"?: *null | string | null

	// validator: [0.8.0, 0.8.1, 0.8.2, 0.9.0, 0.10.0-IV0, 0.10.0-IV1, 0.10.1-IV0, 0.10.1-IV1, 0.10.1-IV2, 0.10.2-IV0, 0.11.0-IV0, 0.11.0-IV1, 0.11.0-IV2, 1.0-IV0, 1.1-IV0, 2.0-IV0, 2.0-IV1, 2.1-IV0, 2.1-IV1, 2.1-IV2, 2.2-IV0, 2.2-IV1, 2.3-IV0, 2.3-IV1, 2.4-IV0, 2.4-IV1, 2.5-IV0, 2.6-IV0, 2.7-IV0, 2.7-IV1, 2.7-IV2, 2.8-IV0, 2.8-IV1, 3.0-IV0, 3.0-IV1, 3.1-IV0, 3.2-IV0, 3.3-IV0, 3.3-IV1, 3.3-IV2, 3.3-IV3, 3.4-IV0, 3.5-IV0, 3.5-IV1, 3.5-IV2, 3.6-IV0, 3.6-IV1, 3.6-IV2, 3.7-IV0, 3.7-IV1, 3.7-IV2, 3.7-IV3, 3.7-IV4, 3.8-IV0, 3.9-IV0, 4.0-IV0, 4.0-IV1]
	// Specify which version of the inter-broker protocol will be used. . This is typically bumped after all brokers were upgraded to a new version. Example of some valid values are: 0.8.0, 0.8.1, 0.8.1.1, 0.8.2, 0.8.2.0, 0.8.2.1, 0.9.0.0, 0.9.0.1 Check MetadataVersion for the full list.
	"inter.broker.protocol.version"?: *"3.9-IV0" | string

	// The metrics polling interval (in seconds) which can be used in kafka.metrics.reporters implementations.
	"kafka.metrics.polling.interval.secs"?: *10 | int & >=1 & <=2147483647

	// A list of classes to use as Yammer metrics custom reporters. The reporters should implement kafka.metrics.KafkaMetricsReporter trait. If a client wants to expose JMX operations on a custom reporter, the custom reporter needs to additionally implement an MBean trait that extends kafka.metrics.KafkaMetricsReporterMBean trait so that the registered MBean is compliant with the standard MBean convention.
	"kafka.metrics.reporters"?: *[] | [...string]

	// The frequency with which the partition rebalance check is triggered by the controller
	"leader.imbalance.check.interval.seconds"?: *300 | int & >=1 & <=9223372036854775807

	// The ratio of leader imbalance allowed per broker. The controller would trigger a leader balance if it goes above this value per broker. The value is specified in percentage.
	"leader.imbalance.per.broker.percentage"?: *10 | int & >=-2147483648 & <=2147483647

	// Map between listener names and security protocols. This must be defined for the same security protocol to be usable in more than one port or IP. For example, internal and external traffic can be separated even if SSL is required for both. Concretely, the user could define listeners with names INTERNAL and EXTERNAL and this property as: INTERNAL:SSL,EXTERNAL:SSL. As shown, key and value are separated by a colon and map entries are separated by commas. Each listener name should only appear once in the map. Different security (SSL and SASL) settings can be configured for each listener by adding a normalised prefix (the listener name is lowercased) to the config name. For example, to set a different keystore for the INTERNAL listener, a config with name listener.name.internal.ssl.keystore.location would be set. If the config for the listener name is not set, the config will fallback to the generic config (i.e. ssl.keystore.location). Note that in KRaft a default mapping from the listener names defined by controller.listener.names to PLAINTEXT is assumed if no explicit mapping is provided and no other security protocol is in use.
	// "listener.security.protocol.map"?: *"SASL_SSL:SASL_SSL,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT" | string

	// Listener List - Comma-separated list of URIs we will listen on and the listener names. If the listener name is not a security protocol, listener.security.protocol.map must also be set. Listener names and port numbers must be unique unless %n one listener is an IPv4 address and the other listener is %n an IPv6 address (for the same port).%n Specify hostname as 0.0.0.0 to bind to all interfaces.%n Leave hostname empty to bind to default interface.%n Examples of legal listener lists:%n PLAINTEXT://myhost:9092,SSL://:9091%n CLIENT://0.0.0.0:9092,REPLICATION://localhost:9093%n PLAINTEXT://127.0.0.1:9092,SSL://[::1]:9092%n
	// "listeners"?: *"PLAINTEXT://:9092" | string

	// The amount of time to sleep when there are no logs to clean
	"log.cleaner.backoff.ms"?: *15000 | int & >=0 & <=9223372036854775807

	// The total memory used for log deduplication across all cleaner threads
	"log.cleaner.dedupe.buffer.size"?: *134217728 | int & >=-9223372036854775808 & <=9223372036854775807

	// The amount of time to retain tombstone message markers for log compacted topics. This setting also gives a bound on the time in which a consumer must complete a read if they begin from offset 0 to ensure that they get a valid snapshot of the final stage (otherwise tombstones messages may be collected before a consumer completes their scan).
	"log.cleaner.delete.retention.ms"?: *86400000 | int & >=0 & <=9223372036854775807

	// Enable the log cleaner process to run on the server. Should be enabled if using any topics with a cleanup.policy=compact including the internal offsets topic. If disabled those topics will not be compacted and continually grow in size.
	"log.cleaner.enable"?: *true | bool

	// Log cleaner dedupe buffer load factor. The percentage full the dedupe buffer can become. A higher value will allow more log to be cleaned at once but will lead to more hash collisions
	"log.cleaner.io.buffer.load.factor"?: *0.9 | number

	// The total memory used for log cleaner I/O buffers across all cleaner threads
	"log.cleaner.io.buffer.size"?: *524288 | int & >=0 & <=2147483647

	// The log cleaner will be throttled so that the sum of its read and write i/o will be less than this value on average
	"log.cleaner.io.max.bytes.per.second"?: *1.7976931348623157E308 | number

	// The maximum time a message will remain ineligible for compaction in the log. Only applicable for logs that are being compacted.
	"log.cleaner.max.compaction.lag.ms"?: *9223372036854775807 | int & >=1 & <=9223372036854775807

	// The minimum ratio of dirty log to total log for a log to eligible for cleaning. If the log.cleaner.max.compaction.lag.ms or the log.cleaner.min.compaction.lag.ms configurations are also specified, then the log compactor considers the log eligible for compaction as soon as either: (i) the dirty ratio threshold has been met and the log has had dirty (uncompacted) records for at least the log.cleaner.min.compaction.lag.ms duration, or (ii) if the log has had dirty (uncompacted) records for at most the log.cleaner.max.compaction.lag.ms period.
	"log.cleaner.min.cleanable.ratio"?: *0.5 | number & >=0 & <=1

	// The minimum time a message will remain uncompacted in the log. Only applicable for logs that are being compacted.
	"log.cleaner.min.compaction.lag.ms"?: *0 | int & >=0 & <=9223372036854775807

	// The number of background threads to use for log cleaning
	"log.cleaner.threads"?: *1 | int & >=0 & <=2147483647

	// The default cleanup policy for segments beyond the retention window. A comma separated list of valid policies. Valid policies are: "delete" and "compact"
	"log.cleanup.policy"?: *["delete"] | [...("compact" | "delete")]

	// The directory in which the log data is kept (supplemental for log.dirs property)
	"log.dir"?: *"/tmp/kafka-logs" | string

	// If the broker is unable to successfully communicate to the controller that some log directory has failed for longer than this time, the broker will fail and shut down.
	"log.dir.failure.timeout.ms"?: *30000 | int & >=1 & <=9223372036854775807

	// A comma-separated list of the directories where the log data is stored. If not set, the value in log.dir is used.
	"log.dirs"?: *null | string | null

	// The number of messages accumulated on a log partition before messages are flushed to disk.
	"log.flush.interval.messages"?: *9223372036854775807 | int & >=1 & <=9223372036854775807

	// The maximum time in ms that a message in any topic is kept in memory before flushed to disk. If not set, the value in log.flush.scheduler.interval.ms is used
	"log.flush.interval.ms"?: *null | int & >=-9223372036854775808 & <=9223372036854775807 | null

	// The frequency with which we update the persistent record of the last flush which acts as the log recovery point.
	"log.flush.offset.checkpoint.interval.ms"?: *60000 | int & >=0 & <=2147483647

	// The frequency in ms that the log flusher checks whether any log needs to be flushed to disk
	"log.flush.scheduler.interval.ms"?: *9223372036854775807 | int & >=-9223372036854775808 & <=9223372036854775807

	// The frequency with which we update the persistent record of log start offset
	"log.flush.start.offset.checkpoint.interval.ms"?: *60000 | int & >=0 & <=2147483647

	// The interval with which we add an entry to the offset index.
	"log.index.interval.bytes"?: *4096 | int & >=0 & <=2147483647

	// The maximum size in bytes of the offset index
	"log.index.size.max.bytes"?: *10485760 | int & >=4 & <=2147483647

	// The maximum size of local log segments that can grow for a partition before it gets eligible for deletion. Default value is -2, it represents `log.retention.bytes` value to be used. The effective value should always be less than or equal to `log.retention.bytes` value.
	"log.local.retention.bytes"?: *-2 | int & >=-2 & <=9223372036854775807

	// The number of milliseconds to keep the local log segments before it gets eligible for deletion. Default value is -2, it represents `log.retention.ms` value is to be used. The effective value should always be less than or equal to `log.retention.ms` value.
	"log.local.retention.ms"?: *-2 | int & >=-2 & <=9223372036854775807

	// This configuration controls whether down-conversion of message formats is enabled to satisfy consume requests. When set to false, broker will not perform down-conversion for consumers expecting an older message format. The broker responds with UNSUPPORTED_VERSION error for consume requests from such older clients. This configurationdoes not apply to any message format conversion that might be required for replication to followers.
	"log.message.downconversion.enable"?: *true | bool

	// validator: [0.8.0, 0.8.1, 0.8.2, 0.9.0, 0.10.0-IV0, 0.10.0-IV1, 0.10.1-IV0, 0.10.1-IV1, 0.10.1-IV2, 0.10.2-IV0, 0.11.0-IV0, 0.11.0-IV1, 0.11.0-IV2, 1.0-IV0, 1.1-IV0, 2.0-IV0, 2.0-IV1, 2.1-IV0, 2.1-IV1, 2.1-IV2, 2.2-IV0, 2.2-IV1, 2.3-IV0, 2.3-IV1, 2.4-IV0, 2.4-IV1, 2.5-IV0, 2.6-IV0, 2.7-IV0, 2.7-IV1, 2.7-IV2, 2.8-IV0, 2.8-IV1, 3.0-IV0, 3.0-IV1, 3.1-IV0, 3.2-IV0, 3.3-IV0, 3.3-IV1, 3.3-IV2, 3.3-IV3, 3.4-IV0, 3.5-IV0, 3.5-IV1, 3.5-IV2, 3.6-IV0, 3.6-IV1, 3.6-IV2, 3.7-IV0, 3.7-IV1, 3.7-IV2, 3.7-IV3, 3.7-IV4, 3.8-IV0, 3.9-IV0, 4.0-IV0, 4.0-IV1]
	// Specify the message format version the broker will use to append messages to the logs. The value should be a valid MetadataVersion. Some examples are: 0.8.2, 0.9.0.0, 0.10.0, check MetadataVersion for more details. By setting a particular message format version, the user is certifying that all the existing messages on disk are smaller or equal than the specified version. Setting this value incorrectly will cause consumers with older versions to break as they will receive messages with a format that they don't understand.
	"log.message.format.version"?: *"3.0-IV1" | string

	// This configuration sets the allowable timestamp difference between the message timestamp and the broker's timestamp. The message timestamp can be later than or equal to the broker's timestamp, with the maximum allowable difference determined by the value set in this configuration. If log.message.timestamp.type=CreateTime, the message will be rejected if the difference in timestamps exceeds this specified threshold. This configuration is ignored if log.message.timestamp.type=LogAppendTime.
	"log.message.timestamp.after.max.ms"?: *9223372036854775807 | int & >=0 & <=9223372036854775807

	// This configuration sets the allowable timestamp difference between the broker's timestamp and the message timestamp. The message timestamp can be earlier than or equal to the broker's timestamp, with the maximum allowable difference determined by the value set in this configuration. If log.message.timestamp.type=CreateTime, the message will be rejected if the difference in timestamps exceeds this specified threshold. This configuration is ignored if log.message.timestamp.type=LogAppendTime.
	"log.message.timestamp.before.max.ms"?: *9223372036854775807 | int & >=0 & <=9223372036854775807

	// [DEPRECATED] The maximum difference allowed between the timestamp when a broker receives a message and the timestamp specified in the message. If log.message.timestamp.type=CreateTime, a message will be rejected if the difference in timestamp exceeds this threshold. This configuration is ignored if log.message.timestamp.type=LogAppendTime.The maximum timestamp difference allowed should be no greater than log.retention.ms to avoid unnecessarily frequent log rolling.
	"log.message.timestamp.difference.max.ms"?: *9223372036854775807 | int & >=0 & <=9223372036854775807

	// Define whether the timestamp in the message is message create time or log append time. The value should be either CreateTime or LogAppendTime.
	"log.message.timestamp.type"?: *"CreateTime" | string & ("CreateTime" | "LogAppendTime")

	// Should pre allocate file when create new segment? If you are using Kafka on Windows, you probably need to set it to true.
	"log.preallocate"?: *false | bool

	// The maximum size of the log before deleting it
	"log.retention.bytes"?: *-1 | int & >=-9223372036854775808 & <=9223372036854775807

	// The frequency in milliseconds that the log cleaner checks whether any log is eligible for deletion
	"log.retention.check.interval.ms"?: *300000 | int & >=1 & <=9223372036854775807

	// The number of hours to keep a log file before deleting it (in hours), tertiary to log.retention.ms property
	"log.retention.hours"?: *168 | int & >=-2147483648 & <=2147483647

	// The number of minutes to keep a log file before deleting it (in minutes), secondary to log.retention.ms property. If not set, the value in log.retention.hours is used
	"log.retention.minutes"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The number of milliseconds to keep a log file before deleting it (in milliseconds), If not set, the value in log.retention.minutes is used. If set to -1, no time limit is applied.
	"log.retention.ms"?: *null | int & >=-9223372036854775808 & <=9223372036854775807 | null

	// The maximum time before a new log segment is rolled out (in hours), secondary to log.roll.ms property
	"log.roll.hours"?: *168 | int & >=1 & <=2147483647

	// The maximum jitter to subtract from logRollTimeMillis (in hours), secondary to log.roll.jitter.ms property
	"log.roll.jitter.hours"?: *0 | int & >=0 & <=2147483647

	// The maximum jitter to subtract from logRollTimeMillis (in milliseconds). If not set, the value in log.roll.jitter.hours is used
	"log.roll.jitter.ms"?: *null | int & >=-9223372036854775808 & <=9223372036854775807 | null

	// The maximum time before a new log segment is rolled out (in milliseconds). If not set, the value in log.roll.hours is used
	"log.roll.ms"?: *null | int & >=-9223372036854775808 & <=9223372036854775807 | null

	// The maximum size of a single log file
	"log.segment.bytes"?: *1073741824 | int & >=14 & <=2147483647

	// The amount of time to wait before deleting a file from the filesystem. If the value is 0 and there is no file to delete, the system will wait 1 millisecond. Low value will cause busy waiting
	"log.segment.delete.delay.ms"?: *60000 | int & >=0 & <=9223372036854775807

	// The maximum connection creation rate we allow in the broker at any time. Listener-level limits may also be configured by prefixing the config name with the listener prefix, for example, listener.name.internal.max.connection.creation.rate.Broker-wide connection rate limit should be configured based on broker capacity while listener limits should be configured based on application requirements. New connections will be throttled if either the listener or the broker limit is reached, with the exception of inter-broker listener. Connections on the inter-broker listener will be throttled only when the listener-level rate limit is reached.
	"max.connection.creation.rate"?: *2147483647 | int & >=0 & <=2147483647

	// The maximum number of connections we allow in the broker at any time. This limit is applied in addition to any per-ip limits configured using max.connections.per.ip. Listener-level limits may also be configured by prefixing the config name with the listener prefix, for example, listener.name.internal.max.connections.per.ip. Broker-wide limit should be configured based on broker capacity while listener limits should be configured based on application requirements. New connections are blocked if either the listener or broker limit is reached. Connections on the inter-broker listener are permitted even if broker-wide limit is reached. The least recently used connection on another listener will be closed in this case.
	"max.connections"?: *2147483647 | int & >=0 & <=2147483647

	// The maximum number of connections we allow from each ip address. This can be set to 0 if there are overrides configured using max.connections.per.ip.overrides property. New connections from the ip address are dropped if the limit is reached.
	"max.connections.per.ip"?: *2147483647 | int & >=0 & <=2147483647

	// A comma-separated list of per-ip or hostname overrides to the default maximum number of connections. An example value is "hostName:100,127.0.0.1:200"
	"max.connections.per.ip.overrides"?: *"" | string

	// The maximum number of total incremental fetch sessions that we will maintain. FetchSessionCache is sharded into 8 shards and the limit is equally divided among all shards. Sessions are allocated to each shard in round-robin. Only entries within a shard are considered eligible for eviction.
	"max.incremental.fetch.session.cache.slots"?: *1000 | int & >=0 & <=2147483647

	// The maximum number of partitions can be served in one request.
	"max.request.partition.size.limit"?: *2000 | int & >=1 & <=2147483647

	// The largest record batch size allowed by Kafka (after compression if compression is enabled). If this is increased and there are consumers older than 0.10.2, the consumers' fetch size must also be increased so that they can fetch record batches this large. In the latest message format version, records are always grouped into batches for efficiency. In previous message format versions, uncompressed records are not grouped into batches and this limit only applies to a single record in that case.This can be set per topic with the topic level max.message.bytes config.
	"message.max.bytes"?: *1048588 | int & >=0 & <=2147483647

	// This configuration determines where we put the metadata log for clusters in KRaft mode. If it is not set, the metadata log is placed in the first log directory from log.dirs.
	"metadata.log.dir"?: *null | string | null

	// This is the maximum number of bytes in the log between the latest snapshot and the high-watermark needed before generating a new snapshot. The default value is 20971520. To generate snapshots based on the time elapsed, see the metadata.log.max.snapshot.interval.ms configuration. The Kafka node will generate a snapshot when either the maximum time interval is reached or the maximum bytes limit is reached.
	"metadata.log.max.record.bytes.between.snapshots"?: *20971520 | int & >=1 & <=9223372036854775807

	// This is the maximum number of milliseconds to wait to generate a snapshot if there are committed records in the log that are not included in the latest snapshot. A value of zero disables time based snapshot generation. The default value is 3600000. To generate snapshots based on the number of metadata bytes, see the metadata.log.max.record.bytes.between.snapshots configuration. The Kafka node will generate a snapshot when either the maximum time interval is reached or the maximum bytes limit is reached.
	"metadata.log.max.snapshot.interval.ms"?: *3600000 | int & >=0 & <=9223372036854775807

	// The maximum size of a single metadata log file.
	"metadata.log.segment.bytes"?: *1073741824 | int & >=12 & <=2147483647

	// The maximum time before a new metadata log file is rolled out (in milliseconds).
	"metadata.log.segment.ms"?: *604800000 | int & >=-9223372036854775808 & <=9223372036854775807

	// This configuration controls how often the active controller should write no-op records to the metadata partition. If the value is 0, no-op records are not appended to the metadata partition. The default value is 500
	"metadata.max.idle.interval.ms"?: *500 | int & >=0 & <=2147483647

	// The maximum combined size of the metadata log and snapshots before deleting old snapshots and log files. Since at least one snapshot must exist before any logs can be deleted, this is a soft limit.
	"metadata.max.retention.bytes"?: *104857600 | int & >=-9223372036854775808 & <=9223372036854775807

	// The number of milliseconds to keep a metadata log file or snapshot before deleting it. Since at least one snapshot must exist before any logs can be deleted, this is a soft limit.
	"metadata.max.retention.ms"?: *604800000 | int & >=-9223372036854775808 & <=9223372036854775807

	// A list of classes to use as metrics reporters. Implementing the org.apache.kafka.common.metrics.MetricsReporter interface allows plugging in classes that will be notified of new metric creation. The JmxReporter is always included to register JMX statistics.
	"metric.reporters"?: *[] | [...string]

	// The number of samples maintained to compute metrics.
	"metrics.num.samples"?: *2 | int & >=1 & <=2147483647

	// The highest recording level for metrics.
	"metrics.recording.level"?: *"INFO" | string

	// The window of time a metrics sample is computed over.
	"metrics.sample.window.ms"?: *30000 | int & >=1 & <=9223372036854775807

	// When a producer sets acks to "all" (or "-1"), min.insync.replicas specifies the minimum number of replicas that must acknowledge a write for the write to be considered successful. If this minimum cannot be met, then the producer will raise an exception (either NotEnoughReplicas or NotEnoughReplicasAfterAppend).When used together, min.insync.replicas and acks allow you to enforce greater durability guarantees. A typical scenario would be to create a topic with a replication factor of 3, set min.insync.replicas to 2, and produce with acks of "all". This will ensure that the producer raises an exception if a majority of replicas do not receive a write.
	"min.insync.replicas"?: *1 | int & >=1 & <=2147483647

	// The node ID associated with the roles this process is playing when process.roles is non-empty. This is required configuration when running in KRaft mode.
	// "node.id"?: *-1 | int & >=-2147483648 & <=2147483647

	// The number of threads that the server uses for processing requests, which may include disk I/O
	"num.io.threads"?: *8 | int & >=1 & <=2147483647

	// The number of threads that the server uses for receiving requests from the network and sending responses to the network. Noted: each listener (except for controller listener) creates its own thread pool.
	"num.network.threads"?: *3 | int & >=1 & <=2147483647

	// The default number of log partitions per topic
	"num.partitions"?: *1 | int & >=1 & <=2147483647

	// The number of threads per data directory to be used for log recovery at startup and flushing at shutdown
	"num.recovery.threads.per.data.dir"?: *1 | int & >=1 & <=2147483647

	// The number of threads that can move replicas between log directories, which may include disk I/O
	"num.replica.alter.log.dirs.threads"?: *null | int & >=-2147483648 & <=2147483647 | null

	// Number of fetcher threads used to replicate records from each source broker. The total number of fetchers on each broker is bound by num.replica.fetchers multiplied by the number of brokers in the cluster.Increasing this value can increase the degree of I/O parallelism in the follower and leader broker at the cost of higher CPU and memory utilization.
	"num.replica.fetchers"?: *1 | int & >=-2147483648 & <=2147483647

	// The maximum size for a metadata entry associated with an offset commit.
	"offset.metadata.max.bytes"?: *4096 | int & >=-2147483648 & <=2147483647

	// DEPRECATED: The required acks before the commit can be accepted. In general, the default (-1) should not be overridden.
	"offsets.commit.required.acks"?: *-1 | int & >=-32768 & <=32767

	// Offset commit will be delayed until all replicas for the offsets topic receive the commit or this timeout is reached. This is similar to the producer request timeout.
	"offsets.commit.timeout.ms"?: *5000 | int & >=1 & <=2147483647

	// Batch size for reading from the offsets segments when loading offsets into the cache (soft-limit, overridden if records are too large).
	"offsets.load.buffer.size"?: *5242880 | int & >=1 & <=2147483647

	// Frequency at which to check for stale offsets
	"offsets.retention.check.interval.ms"?: *600000 | int & >=1 & <=9223372036854775807

	// For subscribed consumers, committed offset of a specific partition will be expired and discarded when 1) this retention period has elapsed after the consumer group loses all its consumers (i.e. becomes empty); 2) this retention period has elapsed since the last time an offset is committed for the partition and the group is no longer subscribed to the corresponding topic. For standalone consumers (using manual assignment), offsets will be expired after this retention period has elapsed since the time of last commit. Note that when a group is deleted via the delete-group request, its committed offsets will also be deleted without extra retention period; also when a topic is deleted via the delete-topic request, upon propagated metadata update any group's committed offsets for that topic will also be deleted without extra retention period.
	"offsets.retention.minutes"?: *10080 | int & >=1 & <=2147483647

	// Compression codec for the offsets topic - compression may be used to achieve "atomic" commits.
	"offsets.topic.compression.codec"?: *0 | int & >=-2147483648 & <=2147483647

	// The number of partitions for the offset commit topic (should not change after deployment).
	"offsets.topic.num.partitions"?: *50 | int & >=1 & <=2147483647

	// The replication factor for the offsets topic (set higher to ensure availability). Internal topic creation will fail until the cluster size meets this replication factor requirement.
	"offsets.topic.replication.factor"?: *3 | int & >=1 & <=32767

	// The offsets topic segment bytes should be kept relatively small in order to facilitate faster log compaction and cache loads.
	"offsets.topic.segment.bytes"?: *104857600 | int & >=1 & <=2147483647

	// The Cipher algorithm used for encoding dynamically configured passwords.
	"password.encoder.cipher.algorithm"?: *"AES/CBC/PKCS5Padding" | string

	// The iteration count used for encoding dynamically configured passwords.
	"password.encoder.iterations"?: *4096 | int & >=1024 & <=2147483647

	// The key length used for encoding dynamically configured passwords.
	"password.encoder.key.length"?: *128 | int & >=8 & <=2147483647

	// The SecretKeyFactory algorithm used for encoding dynamically configured passwords. Default is PBKDF2WithHmacSHA512 if available and PBKDF2WithHmacSHA1 otherwise.
	"password.encoder.keyfactory.algorithm"?: *null | string | null

	// The old secret that was used for encoding dynamically configured passwords. This is required only when the secret is updated. If specified, all dynamically encoded passwords are decoded using this old secret and re-encoded using password.encoder.secret when broker starts up.
	"password.encoder.old.secret"?: *null | string | null

	// The secret used for encoding dynamically configured passwords for this broker.
	"password.encoder.secret"?: *null | string | null

	// The fully qualified name of a class that implements the KafkaPrincipalBuilder interface, which is used to build the KafkaPrincipal object used during authorization. If no principal builder is defined, the default behavior depends on the security protocol in use. For SSL authentication, the principal will be derived using the rules defined by ssl.principal.mapping.rules applied on the distinguished name from the client certificate if one is provided; otherwise, if client authentication is not required, the principal name will be ANONYMOUS. For SASL authentication, the principal will be derived using the rules defined by sasl.kerberos.principal.to.local.rules if GSSAPI is in use, and the SASL authentication ID for other mechanisms. For PLAINTEXT, the principal will be ANONYMOUS.
	"principal.builder.class"?: *"class org.apache.kafka.common.security.authenticator.DefaultKafkaPrincipalBuilder" | string

	// The roles that this process plays: 'broker', 'controller', or 'broker,controller' if it is both. This configuration is only applicable for clusters in KRaft (Kafka Raft) mode (instead of ZooKeeper). Leave this config undefined or empty for ZooKeeper clusters.
	// "process.roles"?: *[] | [...("broker" | "controller")]

	// The time in ms that a topic partition leader will wait before expiring producer IDs. Producer IDs will not expire while a transaction associated to them is still ongoing. Note that producer IDs may expire sooner if the last write from the producer ID is deleted due to the topic's retention settings. Setting this value the same or higher than delivery.timeout.ms can help prevent expiration during retries and protect against message duplication, but the default should be reasonable for most use cases.
	"producer.id.expiration.ms"?: *86400000 | int & >=1 & <=2147483647

	// The purge interval (in number of requests) of the producer request purgatory
	"producer.purgatory.purge.interval.requests"?: *1000 | int & >=-2147483648 & <=2147483647

	// The number of queued bytes allowed before no more requests are read
	"queued.max.request.bytes"?: *-1 | int & >=-9223372036854775808 & <=9223372036854775807

	// The number of queued requests allowed for data-plane, before blocking the network threads
	"queued.max.requests"?: *500 | int & >=1 & <=2147483647

	// The number of samples to retain in memory for client quotas
	"quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for client quotas
	"quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// The maximum amount of time the server will wait before answering the remote fetch request
	"remote.fetch.max.wait.ms"?: *500 | int & >=1 & <=2147483647

	// The total size of the space allocated to store index files fetched from remote storage in the local storage.
	"remote.log.index.file.cache.total.size.bytes"?: *1073741824 | int & >=1 & <=9223372036854775807

	// validator: The default value of -1 means that this will be set to the configured value of remote.log.manager.thread.pool.size, if available; otherwise, it defaults to 10.
	// Size of the thread pool used in scheduling tasks to copy segments. The default value of -1 means that this will be set to the configured value of remote.log.manager.thread.pool.size, if available; otherwise, it defaults to 10.
	"remote.log.manager.copier.thread.pool.size"?: *-1 | int & >=-2147483648 & <=2147483647

	// The maximum number of bytes that can be copied from local storage to remote storage per second. This is a global limit for all the partitions that are being copied from local storage to remote storage. The default value is Long.MAX_VALUE, which means there is no limit on the number of bytes that can be copied per second.
	"remote.log.manager.copy.max.bytes.per.second"?: *9223372036854775807 | int & >=1 & <=9223372036854775807

	// The number of samples to retain in memory for remote copy quota management. The default value is 11, which means there are 10 whole windows + 1 current window.
	"remote.log.manager.copy.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for remote copy quota management. The default value is 1 second.
	"remote.log.manager.copy.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// validator: The default value of -1 means that this will be set to the configured value of remote.log.manager.thread.pool.size, if available; otherwise, it defaults to 10.
	// Size of the thread pool used in scheduling tasks to clean up remote log segments. The default value of -1 means that this will be set to the configured value of remote.log.manager.thread.pool.size, if available; otherwise, it defaults to 10.
	"remote.log.manager.expiration.thread.pool.size"?: *-1 | int & >=-2147483648 & <=2147483647

	// The maximum number of bytes that can be fetched from remote storage to local storage per second. This is a global limit for all the partitions that are being fetched from remote storage to local storage. The default value is Long.MAX_VALUE, which means there is no limit on the number of bytes that can be fetched per second.
	"remote.log.manager.fetch.max.bytes.per.second"?: *9223372036854775807 | int & >=1 & <=9223372036854775807

	// The number of samples to retain in memory for remote fetch quota management. The default value is 11, which means there are 10 whole windows + 1 current window.
	"remote.log.manager.fetch.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for remote fetch quota management. The default value is 1 second.
	"remote.log.manager.fetch.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// Interval at which remote log manager runs the scheduled tasks like copy segments, and clean up remote log segments.
	"remote.log.manager.task.interval.ms"?: *30000 | int & >=1 & <=9223372036854775807

	// Deprecated. Size of the thread pool used in scheduling tasks to copy segments, fetch remote log indexes and clean up remote log segments.
	"remote.log.manager.thread.pool.size"?: *10 | int & >=1 & <=2147483647

	// The maximum size of custom metadata in bytes that the broker should accept from a remote storage plugin. If custom metadata exceeds this limit, the updated segment metadata will not be stored, the copied data will be attempted to delete, and the remote copying task for this topic-partition will stop with an error.
	"remote.log.metadata.custom.metadata.max.bytes"?: *128 | int & >=0 & <=2147483647

	// validator: non-empty string
	// Fully qualified class name of `RemoteLogMetadataManager` implementation.
	"remote.log.metadata.manager.class.name"?: *"org.apache.kafka.server.log.remote.metadata.storage.TopicBasedRemoteLogMetadataManager" | string

	// Class path of the `RemoteLogMetadataManager` implementation. If specified, the RemoteLogMetadataManager implementation and its dependent libraries will be loaded by a dedicated classloader which searches this class path before the Kafka broker class path. The syntax of this parameter is same as the standard Java class path string.
	"remote.log.metadata.manager.class.path"?: *null | string | null

	// validator: non-empty string
	// Prefix used for properties to be passed to RemoteLogMetadataManager implementation. For example this value can be `rlmm.config.`.
	"remote.log.metadata.manager.impl.prefix"?: *"rlmm.config." | string

	// validator: non-empty string
	// Listener name of the local broker to which it should get connected if needed by RemoteLogMetadataManager implementation.
	"remote.log.metadata.manager.listener.name"?: *null | string | null

	// Maximum remote log reader thread pool task queue size. If the task queue is full, fetch requests are served with an error.
	"remote.log.reader.max.pending.tasks"?: *100 | int & >=1 & <=2147483647

	// Size of the thread pool that is allocated for handling remote log reads.
	"remote.log.reader.threads"?: *10 | int & >=1 & <=2147483647

	// validator: non-empty string
	// Fully qualified class name of `RemoteStorageManager` implementation.
	"remote.log.storage.manager.class.name"?: *null | string | null

	// Class path of the `RemoteStorageManager` implementation. If specified, the RemoteStorageManager implementation and its dependent libraries will be loaded by a dedicated classloader which searches this class path before the Kafka broker class path. The syntax of this parameter is same as the standard Java class path string.
	"remote.log.storage.manager.class.path"?: *null | string | null

	// validator: non-empty string
	// Prefix used for properties to be passed to RemoteStorageManager implementation. For example this value can be `rsm.config.`.
	"remote.log.storage.manager.impl.prefix"?: *"rsm.config." | string

	// Whether to enable tiered storage functionality in a broker or not. Valid values are `true` or `false` and the default value is false. When it is true broker starts all the services required for the tiered storage functionality.
	"remote.log.storage.system.enable"?: *false | bool

	// The amount of time to sleep when fetch partition error occurs.
	"replica.fetch.backoff.ms"?: *1000 | int & >=0 & <=2147483647

	// The number of bytes of messages to attempt to fetch for each partition. This is not an absolute maximum, if the first record batch in the first non-empty partition of the fetch is larger than this value, the record batch will still be returned to ensure that progress can be made. The maximum record batch size accepted by the broker is defined via message.max.bytes (broker config) or max.message.bytes (topic config).
	"replica.fetch.max.bytes"?: *1048576 | int & >=0 & <=2147483647

	// Minimum bytes expected for each fetch response. If not enough bytes, wait up to replica.fetch.wait.max.ms (broker config).
	"replica.fetch.min.bytes"?: *1 | int & >=-2147483648 & <=2147483647

	// Maximum bytes expected for the entire fetch response. Records are fetched in batches, and if the first record batch in the first non-empty partition of the fetch is larger than this value, the record batch will still be returned to ensure that progress can be made. As such, this is not an absolute maximum. The maximum record batch size accepted by the broker is defined via message.max.bytes (broker config) or max.message.bytes (topic config).
	"replica.fetch.response.max.bytes"?: *10485760 | int & >=0 & <=2147483647

	// The maximum wait time for each fetcher request issued by follower replicas. This value should always be less than the replica.lag.time.max.ms at all times to prevent frequent shrinking of ISR for low throughput topics
	"replica.fetch.wait.max.ms"?: *500 | int & >=-2147483648 & <=2147483647

	// The frequency with which the high watermark is saved out to disk
	"replica.high.watermark.checkpoint.interval.ms"?: *5000 | int & >=-9223372036854775808 & <=9223372036854775807

	// If a follower hasn't sent any fetch requests or hasn't consumed up to the leaders log end offset for at least this time, the leader will remove the follower from isr
	"replica.lag.time.max.ms"?: *30000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The fully qualified class name that implements ReplicaSelector. This is used by the broker to find the preferred read replica. By default, we use an implementation that returns the leader.
	"replica.selector.class"?: *null | string | null

	// The socket receive buffer for network requests to the leader for replicating data
	"replica.socket.receive.buffer.bytes"?: *65536 | int & >=-2147483648 & <=2147483647

	// The socket timeout for network requests. Its value should be at least replica.fetch.wait.max.ms
	"replica.socket.timeout.ms"?: *30000 | int & >=-2147483648 & <=2147483647

	// The number of samples to retain in memory for replication quotas
	"replication.quota.window.num"?: *11 | int & >=1 & <=2147483647

	// The time span of each sample for replication quotas
	"replication.quota.window.size.seconds"?: *1 | int & >=1 & <=2147483647

	// The configuration controls the maximum amount of time the client will wait for the response of a request. If the response is not received before the timeout elapses the client will resend the request if necessary or fail the request if retries are exhausted.
	"request.timeout.ms"?: *30000 | int & >=-2147483648 & <=2147483647

	// Max number that can be used for a broker.id
	"reserved.broker.max.id"?: *1000 | int & >=0 & <=2147483647

	// The fully qualified name of a SASL client callback handler class that implements the AuthenticateCallbackHandler interface.
	"sasl.client.callback.handler.class"?: *null | string | null

	// The list of SASL mechanisms enabled in the Kafka server. The list may contain any mechanism for which a security provider is available. Only GSSAPI is enabled by default.
	"sasl.enabled.mechanisms"?: *["GSSAPI"] | [...string]

	// JAAS login context parameters for SASL connections in the format used by JAAS configuration files. JAAS configuration file format is described here. The format for the value is: loginModuleClass controlFlag (optionName=optionValue)*;. For brokers, the config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.jaas.config=com.example.ScramLoginModule required;
	"sasl.jaas.config"?: *null | string | null

	// Kerberos kinit command path.
	"sasl.kerberos.kinit.cmd"?: *"/usr/bin/kinit" | string

	// Login thread sleep time between refresh attempts.
	"sasl.kerberos.min.time.before.relogin"?: *60000 | int & >=-9223372036854775808 & <=9223372036854775807

	// A list of rules for mapping from principal names to short names (typically operating system usernames). The rules are evaluated in order and the first rule that matches a principal name is used to map it to a short name. Any later rules in the list are ignored. By default, principal names of the form {username}/{hostname}@{REALM} are mapped to {username}. For more details on the format please see security authorization and acls. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the principal.builder.class configuration.
	"sasl.kerberos.principal.to.local.rules"?: *["DEFAULT"] | [...string]

	// The Kerberos principal name that Kafka runs as. This can be defined either in Kafka's JAAS config or in Kafka's config.
	"sasl.kerberos.service.name"?: *null | string | null

	// Percentage of random jitter added to the renewal time.
	"sasl.kerberos.ticket.renew.jitter"?: *0.05 | number

	// Login thread will sleep until the specified window factor of time from last refresh to ticket's expiry has been reached, at which time it will try to renew the ticket.
	"sasl.kerberos.ticket.renew.window.factor"?: *0.8 | number

	// The fully qualified name of a SASL login callback handler class that implements the AuthenticateCallbackHandler interface. For brokers, login callback handler config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.login.callback.handler.class=com.example.CustomScramLoginCallbackHandler
	"sasl.login.callback.handler.class"?: *null | string | null

	// The fully qualified name of a class that implements the Login interface. For brokers, login config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.login.class=com.example.CustomScramLogin
	"sasl.login.class"?: *null | string | null

	// The (optional) value in milliseconds for the external authentication provider connection timeout. Currently applies only to OAUTHBEARER.
	"sasl.login.connect.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The (optional) value in milliseconds for the external authentication provider read timeout. Currently applies only to OAUTHBEARER.
	"sasl.login.read.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The amount of buffer time before credential expiration to maintain when refreshing a credential, in seconds. If a refresh would otherwise occur closer to expiration than the number of buffer seconds then the refresh will be moved up to maintain as much of the buffer time as possible. Legal values are between 0 and 3600 (1 hour); a default value of 300 (5 minutes) is used if no value is specified. This value and sasl.login.refresh.min.period.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.buffer.seconds"?: *300 | int & >=-32768 & <=32767

	// The desired minimum time for the login refresh thread to wait before refreshing a credential, in seconds. Legal values are between 0 and 900 (15 minutes); a default value of 60 (1 minute) is used if no value is specified. This value and sasl.login.refresh.buffer.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.min.period.seconds"?: *60 | int & >=-32768 & <=32767

	// Login refresh thread will sleep until the specified window factor relative to the credential's lifetime has been reached, at which time it will try to refresh the credential. Legal values are between 0.5 (50%) and 1.0 (100%) inclusive; a default value of 0.8 (80%) is used if no value is specified. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.window.factor"?: *0.8 | number

	// The maximum amount of random jitter relative to the credential's lifetime that is added to the login refresh thread's sleep time. Legal values are between 0 and 0.25 (25%) inclusive; a default value of 0.05 (5%) is used if no value is specified. Currently applies only to OAUTHBEARER.
	"sasl.login.refresh.window.jitter"?: *0.05 | number

	// The (optional) value in milliseconds for the maximum wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to OAUTHBEARER.
	"sasl.login.retry.backoff.max.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the initial wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to OAUTHBEARER.
	"sasl.login.retry.backoff.ms"?: *100 | int & >=-9223372036854775808 & <=9223372036854775807

	// SASL mechanism used for communication with controllers. Default is GSSAPI.
	"sasl.mechanism.controller.protocol"?: *"GSSAPI" | string

	// SASL mechanism used for inter-broker communication. Default is GSSAPI.
	"sasl.mechanism.inter.broker.protocol"?: *"GSSAPI" | string

	// The (optional) value in seconds to allow for differences between the time of the OAuth/OIDC identity provider and the broker.
	"sasl.oauthbearer.clock.skew.seconds"?: *30 | int & >=-2147483648 & <=2147483647

	// The (optional) comma-delimited setting for the broker to use to verify that the JWT was issued for one of the expected audiences. The JWT will be inspected for the standard OAuth "aud" claim and if this value is set, the broker will match the value from JWT's "aud" claim to see if there is an exact match. If there is no match, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.expected.audience"?: *null | [...string] | null

	// The (optional) setting for the broker to use to verify that the JWT was created by the expected issuer. The JWT will be inspected for the standard OAuth "iss" claim and if this value is set, the broker will match it exactly against what is in the JWT's "iss" claim. If there is no match, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.expected.issuer"?: *null | string | null

	// The (optional) value in milliseconds for the broker to wait between refreshing its JWKS (JSON Web Key Set) cache that contains the keys to verify the signature of the JWT.
	"sasl.oauthbearer.jwks.endpoint.refresh.ms"?: *3600000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the maximum wait between attempts to retrieve the JWKS (JSON Web Key Set) from the external authentication provider. JWKS retrieval uses an exponential backoff algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
	"sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The (optional) value in milliseconds for the initial wait between JWKS (JSON Web Key Set) retrieval attempts from the external authentication provider. JWKS retrieval uses an exponential backoff algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
	"sasl.oauthbearer.jwks.endpoint.retry.backoff.ms"?: *100 | int & >=-9223372036854775808 & <=9223372036854775807

	// The OAuth/OIDC provider URL from which the provider's JWKS (JSON Web Key Set) can be retrieved. The URL can be HTTP(S)-based or file-based. If the URL is HTTP(S)-based, the JWKS data will be retrieved from the OAuth/OIDC provider via the configured URL on broker startup. All then-current keys will be cached on the broker for incoming requests. If an authentication request is received for a JWT that includes a "kid" header claim value that isn't yet in the cache, the JWKS endpoint will be queried again on demand. However, the broker polls the URL every sasl.oauthbearer.jwks.endpoint.refresh.ms milliseconds to refresh the cache with any forthcoming keys before any JWT requests that include them are received. If the URL is file-based, the broker will load the JWKS file from a configured location on startup. In the event that the JWT includes a "kid" header value that isn't in the JWKS file, the broker will reject the JWT and authentication will fail.
	"sasl.oauthbearer.jwks.endpoint.url"?: *null | string | null

	// The OAuth claim for the scope is often named "scope", but this (optional) setting can provide a different name to use for the scope included in the JWT payload's claims if the OAuth/OIDC provider uses a different name for that claim.
	"sasl.oauthbearer.scope.claim.name"?: *"scope" | string

	// The OAuth claim for the subject is often named "sub", but this (optional) setting can provide a different name to use for the subject included in the JWT payload's claims if the OAuth/OIDC provider uses a different name for that claim.
	"sasl.oauthbearer.sub.claim.name"?: *"sub" | string

	// The URL for the OAuth/OIDC identity provider. If the URL is HTTP(S)-based, it is the issuer's token endpoint URL to which requests will be made to login based on the configuration in sasl.jaas.config. If the URL is file-based, it specifies a file containing an access token (in JWT serialized form) issued by the OAuth/OIDC identity provider to use for authorization.
	"sasl.oauthbearer.token.endpoint.url"?: *null | string | null

	// The fully qualified name of a SASL server callback handler class that implements the AuthenticateCallbackHandler interface. Server callback handlers must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.plain.sasl.server.callback.handler.class=com.example.CustomPlainCallbackHandler.
	"sasl.server.callback.handler.class"?: *null | string | null

	// The maximum receive size allowed before and during initial SASL authentication. Default receive size is 512KB. GSSAPI limits requests to 64K, but we allow upto 512KB by default for custom SASL mechanisms. In practice, PLAIN, SCRAM and OAUTH mechanisms can use much smaller limits.
	"sasl.server.max.receive.size"?: *524288 | int & >=-2147483648 & <=2147483647

	// Security protocol used to communicate between brokers. Valid values are: PLAINTEXT, SSL, SASL_PLAINTEXT, SASL_SSL. It is an error to set this and inter.broker.listener.name properties at the same time.
	"security.inter.broker.protocol"?: *"PLAINTEXT" | string & ("PLAINTEXT" | "SSL" | "SASL_PLAINTEXT" | "SASL_SSL")

	// A list of configurable creator classes each returning a provider implementing security algorithms. These classes should implement the org.apache.kafka.common.security.auth.SecurityProviderCreator interface.
	"security.providers"?: *null | string | null

	// The maximum amount of time the client will wait for the socket connection to be established. The connection setup timeout will increase exponentially for each consecutive connection failure up to this maximum. To avoid connection storms, a randomization factor of 0.2 will be applied to the timeout resulting in a random range between 20% below and 20% above the computed value.
	"socket.connection.setup.timeout.max.ms"?: *30000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The amount of time the client will wait for the socket connection to be established. If the connection is not built before the timeout elapses, clients will close the socket channel. This value is the initial backoff value and will increase exponentially for each consecutive connection failure, up to the socket.connection.setup.timeout.max.ms value.
	"socket.connection.setup.timeout.ms"?: *10000 | int & >=-9223372036854775808 & <=9223372036854775807

	// The maximum number of pending connections on the socket. In Linux, you may also need to configure somaxconn and tcp_max_syn_backlog kernel parameters accordingly to make the configuration takes effect.
	"socket.listen.backlog.size"?: *50 | int & >=1 & <=2147483647

	// The SO_RCVBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
	"socket.receive.buffer.bytes"?: *102400 | int & >=-2147483648 & <=2147483647

	// The maximum number of bytes in a socket request
	"socket.request.max.bytes"?: *104857600 | int & >=1 & <=2147483647

	// The SO_SNDBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
	"socket.send.buffer.bytes"?: *102400 | int & >=-2147483648 & <=2147483647

	// Indicates whether changes to the certificate distinguished name should be allowed during a dynamic reconfiguration of certificates or not.
	"ssl.allow.dn.changes"?: *false | bool

	// Indicates whether changes to the certificate subject alternative names should be allowed during a dynamic reconfiguration of certificates or not.
	"ssl.allow.san.changes"?: *false | bool

	// A list of cipher suites. This is a named combination of authentication, encryption, MAC and key exchange algorithm used to negotiate the security settings for a network connection using TLS or SSL network protocol. By default all the available cipher suites are supported.
	"ssl.cipher.suites"?: *[] | [...string]

	// Configures kafka broker to request client authentication. The following settings are common: ssl.client.auth=required If set to required client authentication is required. ssl.client.auth=requested This means client authentication is optional. unlike required, if this option is set client can choose not to provide authentication information about itself ssl.client.auth=none This means client authentication is not needed.
	"ssl.client.auth"?: *"none" | string & ("required" | "requested" | "none")

	// The list of protocols enabled for SSL connections. The default is 'TLSv1.2,TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. With the default value for Java 11, clients and servers will prefer TLSv1.3 if both support it and fallback to TLSv1.2 otherwise (assuming both support at least TLSv1.2). This default should be fine for most cases. Also see the config documentation for `ssl.protocol`.
	"ssl.enabled.protocols"?: *["TLSv1.2", "TLSv1.3"] | [...string]

	// The endpoint identification algorithm to validate server hostname using server certificate.
	"ssl.endpoint.identification.algorithm"?: *"https" | string

	// The class of type org.apache.kafka.common.security.auth.SslEngineFactory to provide SSLEngine objects. Default value is org.apache.kafka.common.security.ssl.DefaultSslEngineFactory. Alternatively, setting this to org.apache.kafka.common.security.ssl.CommonNameLoggingSslEngineFactory will log the common name of expired SSL certificates used by clients to authenticate at any of the brokers with log level INFO. Note that this will cause a tiny delay during establishment of new connections from mTLS clients to brokers due to the extra code for examining the certificate chain provided by the client. Note further that the implementation uses a custom truststore based on the standard Java truststore and thus might be considered a security risk due to not being as mature as the standard one.
	"ssl.engine.factory.class"?: *null | string | null

	// The password of the private key in the key store file or the PEM key specified in 'ssl.keystore.key'.
	"ssl.key.password"?: *null | string | null

	// The algorithm used by key manager factory for SSL connections. Default value is the key manager factory algorithm configured for the Java Virtual Machine.
	"ssl.keymanager.algorithm"?: *"SunX509" | string

	// Certificate chain in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with a list of X.509 certificates
	"ssl.keystore.certificate.chain"?: *null | string | null

	// Private key in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with PKCS#8 keys. If the key is encrypted, key password must be specified using 'ssl.key.password'
	"ssl.keystore.key"?: *null | string | null

	// The location of the key store file. This is optional for client and can be used for two-way authentication for client.
	"ssl.keystore.location"?: *null | string | null

	// The store password for the key store file. This is optional for client and only needed if 'ssl.keystore.location' is configured. Key store password is not supported for PEM format.
	"ssl.keystore.password"?: *null | string | null

	// The file format of the key store file. This is optional for client. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
	// "ssl.keystore.type"?: *"JKS" | string

	// A list of rules for mapping from distinguished name from the client certificate to short name. The rules are evaluated in order and the first rule that matches a principal name is used to map it to a short name. Any later rules in the list are ignored. By default, distinguished name of the X.500 certificate will be the principal. For more details on the format please see security authorization and acls. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the principal.builder.class configuration.
	"ssl.principal.mapping.rules"?: *"DEFAULT" | string

	// The SSL protocol used to generate the SSLContext. The default is 'TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. This value should be fine for most use cases. Allowed values in recent JVMs are 'TLSv1.2' and 'TLSv1.3'. 'TLS', 'TLSv1.1', 'SSL', 'SSLv2' and 'SSLv3' may be supported in older JVMs, but their usage is discouraged due to known security vulnerabilities. With the default value for this config and 'ssl.enabled.protocols', clients will downgrade to 'TLSv1.2' if the server does not support 'TLSv1.3'. If this config is set to 'TLSv1.2', clients will not use 'TLSv1.3' even if it is one of the values in ssl.enabled.protocols and the server only supports 'TLSv1.3'.
	"ssl.protocol"?: *"TLSv1.3" | string

	// The name of the security provider used for SSL connections. Default value is the default security provider of the JVM.
	"ssl.provider"?: *null | string | null

	// The SecureRandom PRNG implementation to use for SSL cryptography operations.
	"ssl.secure.random.implementation"?: *null | string | null

	// The algorithm used by trust manager factory for SSL connections. Default value is the trust manager factory algorithm configured for the Java Virtual Machine.
	"ssl.trustmanager.algorithm"?: *"PKIX" | string

	// Trusted certificates in the format specified by 'ssl.truststore.type'. Default SSL engine factory supports only PEM format with X.509 certificates.
	"ssl.truststore.certificates"?: *null | string | null

	// The location of the trust store file.
	"ssl.truststore.location"?: *null | string | null

	// The password for the trust store file. If a password is not set, trust store file configured will still be used, but integrity checking is disabled. Trust store password is not supported for PEM format.
	"ssl.truststore.password"?: *null | string | null

	// The file format of the trust store file. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
	"ssl.truststore.type"?: *"JKS" | string

	// The maximum size (after compression if compression is used) of telemetry metrics pushed from a client to the broker. The default value is 1048576 (1 MB).
	"telemetry.max.bytes"?: *1048576 | int & >=1 & <=2147483647

	// The interval at which to rollback transactions that have timed out
	"transaction.abort.timed.out.transaction.cleanup.interval.ms"?: *10000 | int & >=1 & <=2147483647

	// The maximum allowed timeout for transactions. If a client’s requested transaction time exceed this, then the broker will return an error in InitProducerIdRequest. This prevents a client from too large of a timeout, which can stall consumers reading from topics included in the transaction.
	"transaction.max.timeout.ms"?: *900000 | int & >=1 & <=2147483647

	// Enable verification that checks that the partition has been added to the transaction before writing transactional records to the partition
	"transaction.partition.verification.enable"?: *true | bool

	// The interval at which to remove transactions that have expired due to transactional.id.expiration.ms passing
	"transaction.remove.expired.transaction.cleanup.interval.ms"?: *3600000 | int & >=1 & <=2147483647

	// Batch size for reading from the transaction log segments when loading producer ids and transactions into the cache (soft-limit, overridden if records are too large).
	"transaction.state.log.load.buffer.size"?: *5242880 | int & >=1 & <=2147483647

	// The minimum number of replicas that must acknowledge a write to transaction topic in order to be considered successful.
	"transaction.state.log.min.isr"?: *2 | int & >=1 & <=2147483647

	// The number of partitions for the transaction topic (should not change after deployment).
	"transaction.state.log.num.partitions"?: *50 | int & >=1 & <=2147483647

	// The replication factor for the transaction topic (set higher to ensure availability). Internal topic creation will fail until the cluster size meets this replication factor requirement.
	"transaction.state.log.replication.factor"?: *3 | int & >=1 & <=32767

	// The transaction topic segment bytes should be kept relatively small in order to facilitate faster log compaction and cache loads
	"transaction.state.log.segment.bytes"?: *104857600 | int & >=1 & <=2147483647

	// The time in ms that the transaction coordinator will wait without receiving any transaction status updates for the current transaction before expiring its transactional id. Transactional IDs will not expire while a the transaction is still ongoing.
	"transactional.id.expiration.ms"?: *604800000 | int & >=1 & <=2147483647

	// Indicates whether to enable replicas not in the ISR set to be elected as leader as a last resort, even though doing so may result in data lossNote: In KRaft mode, when enabling this config dynamically, it needs to wait for the unclean leader election thread to trigger election periodically (default is 5 minutes). Please run `kafka-leader-election.sh` with `unclean` option to trigger the unclean leader election immediately if needed.
	"unclean.leader.election.enable"?: *false | bool

	// Typically set to org.apache.zookeeper.ClientCnxnSocketNetty when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the same-named zookeeper.clientCnxnSocket system property.
	"zookeeper.clientCnxnSocket"?: *null | string | null

	// Specifies the ZooKeeper connection string in the form hostname:port where host and port are the host and port of a ZooKeeper server. To allow connecting through other ZooKeeper nodes when that ZooKeeper machine is down you can also specify multiple hosts in the form hostname1:port1,hostname2:port2,hostname3:port3. The server can also have a ZooKeeper chroot path as part of its ZooKeeper connection string which puts its data under some path in the global ZooKeeper namespace. For example to give a chroot path of /chroot/path you would give the connection string as hostname1:port1,hostname2:port2,hostname3:port3/chroot/path.
	"zookeeper.connect"?: *null | string | null

	// The max time that the client waits to establish a connection to ZooKeeper. If not set, the value in zookeeper.session.timeout.ms is used
	"zookeeper.connection.timeout.ms"?: *null | int & >=-2147483648 & <=2147483647 | null

	// The maximum number of unacknowledged requests the client will send to ZooKeeper before blocking.
	"zookeeper.max.in.flight.requests"?: *10 | int & >=1 & <=2147483647

	// Enable ZK to KRaft migration
	"zookeeper.metadata.migration.enable"?: *false | bool

	// Zookeeper session timeout
	"zookeeper.session.timeout.ms"?: *18000 | int & >=-2147483648 & <=2147483647

	// Set client to use secure ACLs
	"zookeeper.set.acl"?: *false | bool

	// Specifies the enabled cipher suites to be used in ZooKeeper TLS negotiation (csv). Overrides any explicit value set via the zookeeper.ssl.ciphersuites system property (note the single word "ciphersuites"). The default value of null means the list of enabled cipher suites is determined by the Java runtime being used.
	"zookeeper.ssl.cipher.suites"?: *null | [...string] | null

	// Set client to use TLS when connecting to ZooKeeper. An explicit value overrides any value set via the zookeeper.client.secure system property (note the different name). Defaults to false if neither is set; when true, zookeeper.clientCnxnSocket must be set (typically to org.apache.zookeeper.ClientCnxnSocketNetty); other values to set may include zookeeper.ssl.cipher.suites, zookeeper.ssl.crl.enable, zookeeper.ssl.enabled.protocols, zookeeper.ssl.endpoint.identification.algorithm, zookeeper.ssl.keystore.location, zookeeper.ssl.keystore.password, zookeeper.ssl.keystore.type, zookeeper.ssl.ocsp.enable, zookeeper.ssl.protocol, zookeeper.ssl.truststore.location, zookeeper.ssl.truststore.password, zookeeper.ssl.truststore.type
	"zookeeper.ssl.client.enable"?: *false | bool

	// Specifies whether to enable Certificate Revocation List in the ZooKeeper TLS protocols. Overrides any explicit value set via the zookeeper.ssl.crl system property (note the shorter name).
	"zookeeper.ssl.crl.enable"?: *false | bool

	// Specifies the enabled protocol(s) in ZooKeeper TLS negotiation (csv). Overrides any explicit value set via the zookeeper.ssl.enabledProtocols system property (note the camelCase). The default value of null means the enabled protocol will be the value of the zookeeper.ssl.protocol configuration property.
	"zookeeper.ssl.enabled.protocols"?: *null | [...string] | null

	// Specifies whether to enable hostname verification in the ZooKeeper TLS negotiation process, with (case-insensitively) "https" meaning ZooKeeper hostname verification is enabled and an explicit blank value meaning it is disabled (disabling it is only recommended for testing purposes). An explicit value overrides any "true" or "false" value set via the zookeeper.ssl.hostnameVerification system property (note the different name and values; true implies https and false implies blank).
	"zookeeper.ssl.endpoint.identification.algorithm"?: *"HTTPS" | string

	// Keystore location when using a client-side certificate with TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.keyStore.location system property (note the camelCase).
	"zookeeper.ssl.keystore.location"?: *null | string | null

	// Keystore password when using a client-side certificate with TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.keyStore.password system property (note the camelCase). Note that ZooKeeper does not support a key password different from the keystore password, so be sure to set the key password in the keystore to be identical to the keystore password; otherwise the connection attempt to Zookeeper will fail.
	"zookeeper.ssl.keystore.password"?: *null | string | null

	// Keystore type when using a client-side certificate with TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.keyStore.type system property (note the camelCase). The default value of null means the type will be auto-detected based on the filename extension of the keystore.
	"zookeeper.ssl.keystore.type"?: *null | string | null

	// Specifies whether to enable Online Certificate Status Protocol in the ZooKeeper TLS protocols. Overrides any explicit value set via the zookeeper.ssl.ocsp system property (note the shorter name).
	"zookeeper.ssl.ocsp.enable"?: *false | bool

	// Specifies the protocol to be used in ZooKeeper TLS negotiation. An explicit value overrides any value set via the same-named zookeeper.ssl.protocol system property.
	"zookeeper.ssl.protocol"?: *"TLSv1.2" | string

	// Truststore location when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.trustStore.location system property (note the camelCase).
	"zookeeper.ssl.truststore.location"?: *null | string | null

	// Truststore password when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.trustStore.password system property (note the camelCase).
	"zookeeper.ssl.truststore.password"?: *null | string | null

	// Truststore type when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the zookeeper.ssl.trustStore.type system property (note the camelCase). The default value of null means the type will be auto-detected based on the filename extension of the truststore.
	"zookeeper.ssl.truststore.type"?: *null | string | null

	...
}
