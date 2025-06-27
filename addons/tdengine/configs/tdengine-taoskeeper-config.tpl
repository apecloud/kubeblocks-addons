
# The ID of the currently running taoskeeper instance, default is 64.
instanceId = 64

# Listening host, supports IPv4/Ipv6, default is ""
host = ""
# Listening port, default is 6043.
port = 6043

# Go pool size
gopoolsize = 50000

# Interval for metrics
RotationInterval = "15s"

[tdengine]
host = "127.0.0.1"
port = 6041
username = "root"
password = "taosdata"
usessl = false

[metrics]
# Metrics prefix in metrics names.
prefix = "taos"

# Export some tables that are not super table.
tables = []

# Database for storing metrics data.
[metrics.database]
name = "log"

# Database options for db storing metrics data.
[metrics.database.options]
vgroups = 1
buffer = 64
keep = 90
cachemodel = "both"

[environment]
# Whether running in cgroup.
incgroup = false

[log]
# The directory where log files are stored.
# path = "/var/log/taos"
level = "info"
# Number of log file rotations before deletion.
rotationCount = 30
# The number of days to retain log files.
keepDays = 30
# The maximum size of a log file before rotation.
rotationSize = "1GB"
# If set to true, log files will be compressed.
compress = false
# Minimum disk space to reserve. Log files will not be written if disk space falls below this limit.
reservedDiskSize = "1GB"