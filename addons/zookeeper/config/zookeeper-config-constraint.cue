// Copyright (C) 2022-2023 ApeCloud Co., Ltd
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

#ZookeeperParameter: {
	// the length of a single tick, which is the basic time unit used by ZooKeeper, as measured in milliseconds. It is used to regulate heartbeats, and timeouts. For example, the minimum session timeout will be two ticks.
	"tickTime": int & >=1 & <=100000 | *2000

	// Amount of time, in ticks (see tickTime), to allow followers to connect and sync to a leader. Increased this value as needed, if the amount of data managed by ZooKeeper is large.
	"initLimit": int | *10

	// Amount of time, in ticks (see tickTime), to allow followers to sync with ZooKeeper. If followers fall too far behind a leader, they will be dropped.
	"syncLimit": int | *30

	// the port to listen for client connections; that is, the port that clients attempt to connect to.
	"clientPort": int & >=1 & <=65535 | *2181

	// Limits the number of concurrent connections (at the socket level) that a single client, identified by IP address, may make to a single member of the ZooKeeper ensemble. This is used to prevent certain classes of DoS attacks, including file descriptor exhaustion. The default is 60. Setting this to 0 entirely removes the limit on concurrent connections.
	"maxClientCnxns"?: int & >=0 & <=2000 | *60

	// New in 3.3.0: the maximum session timeout in milliseconds that the server will allow the client to negotiate.
	"maxSessionTimeout"?: int & >=1 & <=600000 | *20

	// The minimum session timeout in milliseconds that the server will allow the client to negotiate.
	// Default is 2 times the tickTime. Maximum should be 20 times the tickTime.
	"minSessionTimeout": int & >=1 & <=600000 | *2

	// the location where ZooKeeper will store the in-memory database snapshots and, unless specified otherwise, the transaction log of updates to the database.Be careful where you put the transaction log. A dedicated transaction log device is key to consistent good performance. Putting the log on a busy device will adversely effect performance.
	"dataDir": string | *"/zookeeper/data"

	// This option will direct the machine to write the transaction log to the dataLogDir rather than the dataDir. This allows a dedicated log device to be used, and helps avoid competition between logging and snapshots.
	"dataLogDir": string | *"/zookeeper/log"

	// When set to false, a single server can be started in replicated mode, a lone participant can run with observers, and a cluster can reconfigure down to one node, and up from one node.
	"standaloneEnabled": bool | *false

	// This controls the enabling or disabling of Dynamic Reconfiguration feature
	"reconfigEnabled": bool | *true

	// A list of comma separated Four Letter Words commands that user wants to use
	"4lw.commands.whitelist": string | *"srvr, mntr, ruok, conf"

	// The time interval in hours for which the purge task has to be triggered. Set to a positive integer (1 and above) to enable the auto purging. Defaults to 0.
	"autopurge.purgeInterval": int & >=0 | *0

	// The number of requests that can be queued by ZooKeeper.
	// Default is 1000. Increase this if dealing with large bursts of requests.
	"globalOutstandingLimit": int & >=1 & <=20000 | *1000

	// The time in milliseconds that ZooKeeper waits before starting shutdown when a shutdown is requested.
	// Default is 5000ms (5 seconds). This allows pending requests to complete.
	"preAllocSize": int & >=1 & <=100000 | *65536

	// The number of snapshots to retain in dataDir.
	// Default is 3. Minimum value is 3 for recovery purposes.
	"autopurge.snapRetainCount": int & >=3 & <=30 | *3

}
