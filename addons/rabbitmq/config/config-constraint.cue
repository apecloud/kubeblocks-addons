//Copyright (C) 2022-2023 ApeCloud Co., Ltd
//
//This file is part of KubeBlocks project
//
//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU Affero General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//
//This program is distributed in the hope that it will be useful
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU Affero General Public License for more details.
//
//You should have received a copy of the GNU Affero General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.

#RabbitMQParameter: {
    // Ports or hostname/pair on which to listen for "plain" AMQP 0-9-1 and AMQP 1.0 connections (without TLS). See the [Networking guide](https://www.rabbitmq.com/docs/networking) for more details and examples.
    listeners.tcp?: string | *"5672"
    
    // Ports or hostname/pair on which to listen for TLS-enabled AMQP 0-9-1 and AMQP 1.0 connections. See the [TLS guide](https://www.rabbitmq.com/docs/ssl) for more details and examples.
    listeners.ssl?: string | *"none"
    
    // TLS configuration. See the [TLS guide](https://www.rabbitmq.com/docs/ssl).
    ssl_options.cacertfile?:    string
    ssl_options.certfile?:      string
    ssl_options.keyfile?:       string
    ssl_options.verify?:        string
    ssl_options.fail_if_no_peer_cert?: bool
    
    // Number of Erlang processes that will accept connections for the TCP listeners
    num_acceptors_tcp?: int | *10
    
    // Number of Erlang processes that will accept TLS connections from clients
    num_acceptors_ssl?: int | *10
    
    // Controls what network interface will be used for communication with other cluster members and CLI tools
    distribution_listener_interface?: string | *"0.0.0.0"
    
    // Controls the lower bound of a server port range for cluster communication
    distribution_listener_port_range_min?: int | *25672
    
    // Controls the upper bound of a server port range for cluster communication
    distribution_listener_port_range_max?: int | *25672
    
    // Maximum time for AMQP 0-9-1 handshake (after socket connection and TLS handshake), in milliseconds
    handshake_timeout?: int | *10000
    
    // TLS handshake timeout, in milliseconds
    ssl_handshake_timeout?: int | *5000
    
    // Memory threshold at which the flow control is triggered
    vm_memory_high_watermark.relative?: float | *0.6
    vm_memory_high_watermark.absolute?: string
    
    // Strategy for memory usage reporting
    //   - allocated: uses Erlang memory allocator statistics
    //   - rss: uses operating system RSS memory reporting. This uses OS-specific means and may start short lived child processes.
    //   - legacy: uses legacy memory reporting (how much memory is considered to be used by the runtime). This strategy is fairly inaccurate.
    //   - erlang: same as legacy, preserved for backwards compatibility
    vm_memory_calculation_strategy?: string | "allocated" | "rss" | "legacy" | "erlang" | *"allocated"
    
    // Makes it possible to override the total amount of memory available, as opposed to inferring it from the environment using OS-specific means. This should only be used when actual maximum amount of RAM available to the node doesn't match the value that will be inferred by the node, e.g. due to containerization or similar constraints the node cannot be aware of. The value may be set to an integer number of bytes or, alternatively, in information units (e.g 8GB). For example, when the value is set to 4 GB, the node will believe it is running on a machine with 4 GB of RAM.
    total_memory_available_override_value?: string
    
    // Disk free space limit of the partition on which RabbitMQ is storing data. When available disk space falls below this limit, flow control is triggered. The value can be set relative to the total amount of RAM or as an absolute value in bytes or, alternatively, in information units (e.g 50MB or 5GB):
    disk_free_limit.absolute?: string | *"50MB"
    
    // Controls the granularity of logging. The value is a list of log event category and log level pairs.
    //The level can be one of error (only errors are logged), warning (only errors and warning are logged), info (errors, warnings and informational messages are logged), or debug (errors, warnings, informational messages and debugging messages are logged).
    log_file.level?: string | "error" | "warning" | "info" | "debug" | *"info"
    
    // Maximum number of AMQP 1.0 sessions that can be simultaneously active on an AMQP 1.0 connection.
    session_max_per_connection?: int & >=1 & <=65535 | *64
    
    // Maximum number of AMQP 1.0 links that can be simultaneously active on an AMQP 1.0 session.
    link_max_per_session?: int & >=1 & <=4294967295 | *256
    
    // Maximum permissible number of channels to negotiate with clients, not including a special channel number 0 used in the protocol. Setting to 0 means "unlimited", a dangerous value since applications sometimes have channel leaks. Using more channels increases memory footprint of the broker.
    channel_max?: int | *2047
    
    // Channel operation timeout in milliseconds
    channel_operation_timeout?: int | *15000
    
    // The largest allowed message payload size in bytes
    max_message_size?: int & <=536870912 | *16777216
    
    // Heartbeat timeout in seconds
    heartbeat?: int | *60
    
    // Default virtual host
    default_vhost?: string | *"/"
    
    // Default user name
    default_user?: string | *"guest"
    
    // Default user password
    default_pass?: string | *"guest"
    
    // Default user administrator tag
    default_user_tags.administrator?: bool | *true
    
    // Default user permissions
    default_permissions.configure?: string | *".*"
    default_permissions.read?: string | *".*"
    default_permissions.write?: string | *".*"
    
    // Statistics collection mode. Primarily relevant for the management plugin. Options are:
    //   - none (do not emit statistics events)
    //   - coarse (emit per-queue / per-channel / per-connection statistics)
    //   - fine (also emit per-message statistics)
    collect_statistics?: string | "none" | "coarse" | "fine" | *"none"
    
    // Statistics collection interval in milliseconds
    collect_statistics_interval?: int | *5000
    
    // Management plugin cache multiplier
    management.db_cache_multiplier?: int | *5
    
    // Enable/disable reverse DNS lookups
    reverse_dns_lookups?: bool | *false
    
    // Number of delegate processes for intra-cluster communication
    delegate_count?: int | *16
    
    // Default socket options. You may want to change these when you troubleshoot network issues.
    tcp_listen_options.backlog?: int | *128
    tcp_listen_options.nodelay?: bool | *true
    tcp_listen_options.linger.on?: bool | t*rue
    tcp_listen_options.linger.timeout?: int | *0
    tcp_listen_options.exit_on_close?: bool | *false
    tcp_listen_options.keepalive?: bool | *false
    
    // Network partition handling strategy
    cluster_partition_handling?: string | "ignore" | "autoheal" | "pause_minority" | "pause_if_all_down" | *"ignore"
    
    // Cluster keepalive interval in milliseconds
    cluster_keepalive_interval?: int | *10000
    
    // Size threshold for message embedding in queue index
    queue_index_embed_msgs_below?: int | *4096
    
    // Mnesia table loading retry timeout
    mnesia_table_loading_retry_timeout?: int | *30000
    
    // Mnesia table loading retry limit
    mnesia_table_loading_retry_limit?: int | *10
    
    // Queue leader location strategy
    queue_leader_locator?: string | "balanced" | "client-local" | *"client-local"
    
    // Enable/disable proxy protocol
    proxy_protocol?: bool | *false
    
    // Operator-controlled cluster name
    cluster_name?: string

	// other parameters
	// reference rabbitmq parameters
	...
}

// SectionName is section name
[SectionName=_]: #RabbitMQParameter