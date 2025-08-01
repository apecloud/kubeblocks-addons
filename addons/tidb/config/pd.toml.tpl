# full example can be seen at:
# https://github.com/tikv/pd/blob/release-7.5/conf/config.toml

[security]
# Path of file that contains list of trusted SSL CAs. if set, following four settings shouldn't be empty
cacert-path = ""
# Path of file that contains X509 certificate in PEM format.
cert-path = ""
# Path of file that contains X509 key in PEM format.
key-path = ""
# A CN which must be provided by a client
cert-allowed-cn = ["example.com"]
# Whether or not to enable redact log.
redact-info-log = false

[security.encryption]
# Encryption method to use for PD data. One of "plaintext", "aes128-ctr", "aes192-ctr" and "aes256-ctr".
# Defaults to "plaintext" if not set.
data-encryption-method = "plaintext"
# Specifies how often PD rotates data encryption key. Default is 7 days.
data-key-rotation-period = "168h"

# Specifies master key if encryption is enabled. There are three types of master key:
#
#   * "plaintext":
#
#     Plaintext as a master key means no master key is given and only applicable when
#     encryption is not enabled, i.e. data-encryption-method = "plaintext". This type doesn't
#     have sub-config items. Example:
#     
#     [security.encryption.master-key]
#     type = "plaintext"
#
#   * "kms":
#
#     Use a KMS service to supply a master key. Currently, only AWS KMS is supported. This type of
#     master key is recommended for production use. Example:
#
#     [security.encryption.master-key]
#     type = "kms"
#     ## KMS CMK key id. Must be a valid KMS CMK where the TiKV process has access to.
#     ## In production is recommended to grant access of the CMK to TiKV using IAM.
#     key-id = "1234abcd-12ab-34cd-56ef-1234567890ab"
#     ## AWS region of the KMS CMK.
#     region = "us-west-2"
#     ## (Optional) AWS KMS service endpoint. Only required when non-default KMS endpoint is
#     ## desired.
#     endpoint = "https://kms.us-west-2.amazonaws.com"
#
#   * "file":
#
#     Supply a custom encryption key stored in a file. It is recommended NOT to use in production,
#     as it breaks the purpose of encryption at rest unless the file is stored in tempfs.
#     The file must contain a 256-bits (32 bytes, regardless of key length implied by 
#     data-encryption-method) key encoded as a hex string and end with a newline ("\n"). Example:
#
#     [security.encryption.master-key]
#     type = "file"
#     path = "/path/to/master/key/file"
[security.encryption.master-key]
type = "plaintext"

[log]
level = "info"
# log format, one of json, text, console
format = "text"

[log.file]
# Usually it is set through command line.
filename = ""
# max log file size in MB
max-size = 300
# max log file keep days
max-days = 0
# maximum number of old log files to retain
max-backups = 0

[pd-server]
# The metric storage is the cluster metric storage. This is use for query metric data.
# Currently we use prometheus as metric storage, we may use PD/TiKV as metric storage later.
# For usability, recommended to temporarily set it to the prometheus address, eg: http://127.0.0.1:9090
metric-storage = ""
# There are some values supported: "auto", "none", or a specific address, default: "auto".
dashboard-address = "auto"

[schedule]
# Controls the size limit of Region Merge.
max-merge-region-size = 20
# Specifies the upper limit of the Region Merge key.
max-merge-region-keys = 200000
# Controls the time interval between the split and merge operations on the same Region.
split-merge-interval = "1h"
# When PD fails to receive the heartbeat from a store after the specified period of time,
# it adds replicas at other nodes.
max-store-down-time = "30m"
# Controls the time interval between write hot regions info into leveldb
hot-regions-write-interval= "10m"
# The day of hot regions data to be reserved. 0 means close.
hot-regions-reserved-days= 7
# The number of Leader scheduling tasks performed at the same time.
leader-schedule-limit = 4
# The number of Region scheduling tasks performed at the same time.
region-schedule-limit = 2048
# The number of Replica scheduling tasks performed at the same time.
replica-schedule-limit = 64
# The number of the Region Merge scheduling tasks performed at the same time.
# Set this parameter to 0 to disable Region Merge.
merge-schedule-limit = 8
# The number of hot Region scheduling tasks performed at the same time.
hot-region-schedule-limit = 4
# There are some policies supported: ["count", "size"], default: "count"
leader-schedule-policy = "count"
# When the score difference between the leader or Region of the two stores is
# less than specified multiple times of the Region size, it is considered in balance by PD.
# If it equals 0.0, PD will automatically adjust it.
tolerant-size-ratio = 0.0
# The threshold ratio above which the capacity of the store is insufficient.
# If the space occupancy ratio of a store exceeds this threshold value,
# PD avoids migrating data to this store as much as possible.
low-space-ratio = 0.8

# The default version of balance Region score calculation.
region-score-formula-version = "v2"

# These three parameters control the merge scheduler behavior.
# If it is true, it means a Region can only be merged into the next Region of it.
enable-one-way-merge = false
# If it is true, it means two Regions within different tables can be merged.
# This option only works when the key type is "table".
enable-cross-table-merge = false

# Whether or not to enable joint consensus.
enable-joint-consensus = true

[replication]
# The number of replicas for each Region.
max-replicas = 3
# The label keys specified the location of a store.
# The placement priorities are implied by the order of label keys.
# For example, ["zone", "rack"] means that we should place replicas to
# different zones first, then to different racks if we don't have enough zones.
location-labels = []
# Strictly checks if the label of TiKV is matched with location labels.
strictly-match-label = false

# isolation-level is used to isolate replicas explicitly and forcibly if it's not empty.
# Its value must be empty or one of location-labels.
# Example:
# location-labels = ["zone", "rack", "host"]
# isolation-level = "zone"
# With configuration like above, PD ensures that all replicas be placed in different zones.
# Even if a zone is down, PD will not try to make up replicas in other zone
# because other zones already have replicas on it.
isolation-level = ""

# Whether or not to enable placement rules.
enable-placement-rules = true

[dashboard]
# Configurations below are for the TiDB Dashboard embedded in the PD.

# The path of the CA certificate used to verify the TiDB server in TLS.
tidb-cacert-path = ""
# The path of the certificate used to connect to TiDB server in TLS.
tidb-cert-path = ""
# The path of the certificate private key.
tidb-key-path = ""

# The public path prefix to serve Dashboard URLs. It can be set when Dashboard
# is running behind a reverse proxy. Do not configure it if you access
# Dashboard directly.
public-path-prefix = "/dashboard"

# When enabled, the request will be proxied to the instance running Dashboard
# internally instead of result in a 307 redirection.
internal-proxy = false

# When enabled, usage data will be sent to PingCAP for improving user experience.
enable-telemetry = false

[keyspaces]
# pre-alloc is used to pre-allocate keyspaces during pd bootstrap.
# Its value should be a list of strings, denotting the name of the keyspaces.
# Example:
# pre-alloc = ["admin", "user1", "user2"]
pre-alloc = []
