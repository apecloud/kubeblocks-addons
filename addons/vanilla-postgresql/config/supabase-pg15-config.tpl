# -----------------------------
# PostgreSQL configuration file
# -----------------------------
#
# This file consists of lines of the form:
#
#   name = value
#
# (The "=" is optional.)  Whitespace may be used.  Comments are introduced with
# "#" anywhere on a line.  The complete list of parameter names and allowed
# values can be found in the PostgreSQL documentation.
#
# The commented-out settings shown in this file represent the default values.
# Re-commenting a setting is NOT sufficient to revert it to the default value;
# you need to reload the server.
#
# This file is read on server startup and when the server receives a SIGHUP
# signal.  If you edit the file on a running system, you have to SIGHUP the
# server for the changes to take effect, run "pg_ctl reload", or execute
# "SELECT pg_reload_conf()".  Some parameters, which are marked below,
# require a server shutdown and restart to take effect.
#
# Any parameter can also be given as a command-line option to the server, e.g.,
# "postgres -c log_connections=on".  Some parameters can be changed at run time
# with the "SET" SQL command.
#
# Memory units:  B  = bytes            Time units:  us  = microseconds
#                kB = kilobytes                     ms  = milliseconds
#                MB = megabytes                     s   = seconds
#                GB = gigabytes                     min = minutes
#                TB = terabytes                     h   = hours
#                                                   d   = days

# ----------------------------- Go Template Section ----------------------------- #
{{- $buffer_unit := "B" }}
{{- $shared_buffers := 1073741824 }}
{{- $max_connections := 10000 }}
{{- $autovacuum_max_workers := 3 }}
{{- $phy_memory := getContainerMemory ( index $.podSpec.containers 0 ) }}
{{- $phy_cpu := getContainerCPU ( index $.podSpec.containers 0 ) }}
{{- if gt $phy_memory 0 }}
{{- $shared_buffers = div $phy_memory 4 }}
{{- $max_connections = min ( div $phy_memory 9531392 ) 5000 }}
{{- $autovacuum_max_workers = min ( max ( div $phy_memory 17179869184 ) 3 ) 10 }}
{{- end }}

{{- if ge $shared_buffers 1024 }}
{{- $shared_buffers = div $shared_buffers 1024 }}
{{- $buffer_unit = "kB" }}
{{- end }}

{{- if ge $shared_buffers 1024 }}
{{- $shared_buffers = div $shared_buffers 1024 }}
{{- $buffer_unit = "MB" }}
{{- end }}

{{- if ge $shared_buffers 1024 }}
{{- $shared_buffers = div $shared_buffers 1024 }}
{{ $buffer_unit = "GB" }}
{{- end }}
# ----------------------------- Go Template Section ----------------------------- #


#------------------------------------------------------------------------------
# CONNECTIONS AND AUTHENTICATION
#------------------------------------------------------------------------------

# - Connection Settings -
listen_addresses = '*'

# - Authentication -
authentication_timeout = 1min
password_encryption = scram-sha-256
db_user_namespace = false

# - SSL -

ssl = false
ssl_ca_file = ''
ssl_cert_file = ''
ssl_crl_file = ''
ssl_crl_dir = ''
ssl_key_file = ''
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL' # allowed SSL ciphers
ssl_prefer_server_ciphers = true
ssl_ecdh_curve = 'prime256v1'
ssl_min_protocol_version = 'TLSv1.2'
ssl_max_protocol_version = ''
ssl_dh_params_file = ''
ssl_passphrase_command = ''
ssl_passphrase_command_supports_reload = false


#------------------------------------------------------------------------------
# RESOURCE USAGE (except WAL)
#------------------------------------------------------------------------------

# - Memory -
shared_buffers = '{{ printf "%d%s" $shared_buffers $buffer_unit }}'
work_mem = '{{ printf "%dkB" ( max ( div $phy_memory 4194304 ) 4096 ) }}'

# - Disk -
{{- if gt $phy_memory 0 }}
temp_file_limit = '{{ printf "%dkB" ( div $phy_memory 1024 ) }}'
{{- end }}


#------------------------------------------------------------------------------
# WRITE-AHEAD LOG
#------------------------------------------------------------------------------

# - Settings -
wal_level = logical
wal_buffers = '{{ printf "%dMB" ( div ( min ( max ( div $phy_memory 2097152 ) 2048) 16384 ) 128 ) }}'

# - Checkpoints -
{{- $max_wal_size := min ( max ( div $phy_memory 2097152 ) 4096 ) 32768 }}
{{- $min_wal_size := min ( max ( div $phy_memory 8388608 ) 2048 ) 8192 }}
{{- $data_disk_size := getComponentPVCSizeByName $.component "data" }}
{{/* if data disk lt 5G , set max_wal_size to 256MB */}}
{{- $disk_min_limit := mul 5 1024 1024 1024 }}
{{- if and ( gt $data_disk_size 0 ) ( lt $data_disk_size $disk_min_limit ) }}
{{- $max_wal_size = 256 }}
{{- $min_wal_size = 64 }}
{{- end }}
max_wal_size = '{{- printf "%dMB" $max_wal_size }}'
min_wal_size = '{{- printf "%dMB" $min_wal_size }}'

# - Checkpoints -
checkpoint_completion_target = 0.5
checkpoint_flush_after = 256kB

#------------------------------------------------------------------------------
# REPLICATION
#------------------------------------------------------------------------------

# - Sending Servers -
# Set these on the primary and on any standby that will send replication data.
max_wal_senders = 10
max_replication_slots = 5
max_slot_wal_keep_size = 4096
synchronous_commit = 'off'


#------------------------------------------------------------------------------
# QUERY TUNING
#------------------------------------------------------------------------------

# - Planner Cost Constants -
{{- if gt $phy_memory 0 }}
effective_cache_size = '{{ printf "%dMB" ( div ( div $phy_memory 16384 ) 128 ) }}'
{{- end }}


#------------------------------------------------------------------------------
# REPORTING AND LOGGING
#------------------------------------------------------------------------------

# include = '/etc/postgresql/logging.conf'
{{- block "logsBlock" . }}
{{- if hasKey $.component "enabledLogs" }}
{{- if mustHas "running" $.component.enabledLogs }}
logging_collector = 'True'
log_destination = 'csvlog'
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
{{ end -}}
{{ end -}}
{{ end }}

# - What to Log -
log_line_prefix = '%h %m [%p] %q%u@%d '
log_statement = 'none'
log_timezone = 'UTC'


#------------------------------------------------------------------------------
# AUTOVACUUM
#------------------------------------------------------------------------------

autovacuum_max_workers = '{{ $autovacuum_max_workers }}'
{{- if gt $phy_memory 0 }}
autovacuum_work_mem = '{{ printf "%dkB" ( max ( div $phy_memory 65536 ) 131072 ) }}'
{{- end }}


#------------------------------------------------------------------------------
# CLIENT CONNECTION DEFAULTS
#------------------------------------------------------------------------------

# - Statement Behavior -
row_security = true

# - Locale and Formatting -
timezone = 'UTC'
extra_float_digits = 0

# These settings are initialized by initdb, but they can be changed.
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'

# default configuration for text search
default_text_search_config = 'pg_catalog.english'

# - Shared Library Preloading -
shared_preload_libraries = 'pg_stat_statements, pgaudit, plpgsql, plpgsql_check, pg_cron, pg_net, pgsodium, timescaledb, auto_explain, pg_tle, plan_filter'
jit_provider = 'llvmjit'


#------------------------------------------------------------------------------
# CONFIG FILE INCLUDES
#------------------------------------------------------------------------------

# supautils specific configurations
#include = '/etc/postgresql-custom/supautils.conf'

#------------------------------------------------------------------------------
# CUSTOMIZED OPTIONS
#------------------------------------------------------------------------------

# Add settings for extensions here
auto_explain.log_min_duration = 10s
cron.database_name = 'postgres'
pgsodium.getkey_script= '/usr/lib/postgresql/bin/pgsodium_getkey.sh'
