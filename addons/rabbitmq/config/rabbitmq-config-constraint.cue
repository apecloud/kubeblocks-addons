// Copyright (C) 2022-2024 ApeCloud Co., Ltd
//
// This file is part of KubeBlocks project
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// RabbitMQ parameter constraints for KubeBlocks Reconfigure OpsRequest.
// Config format: sysctl (key = value), parsed as properties.
// Reference: https://www.rabbitmq.com/docs/configure#config-file

#RabbitMQParameter: {

	// Maximum number of channels allowed per AMQP 0-9-1 connection.
	// 0 means unlimited. Default 2048.
	channel_max?: int & >=0 & <=131072 | *2048

	// Heartbeat timeout value in seconds. Negotiated between client and
	// server at connection time. 0 disables heartbeats. Default 60.
	heartbeat?: int & >=0 & <=65535 | *60

	// Memory high watermark as a fraction of available RAM.
	// When used memory exceeds this ratio RabbitMQ raises a memory alarm
	// and blocks publishing connections. Default 0.4 (40%).
	"vm_memory_high_watermark.relative"?: float & >0 & <=1 | *0.4

	...
}

configuration: #RabbitMQParameter & {
}
