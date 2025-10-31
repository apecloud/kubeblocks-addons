# reference: https://github.com/chengshiwen/influxdb-cluster/wiki/Configure-Data-Nodes
[coordinator]
  log-queries-after = "0s"

[meta]
  dir = "/var/lib/influxdb/meta"

[data]
  dir = "/var/lib/influxdb/data"
  engine = "tsm1"
  wal-dir = "/var/lib/influxdb/wal"

[hinted-handoff]
  dir = "/var/lib/influxdb/hh"
