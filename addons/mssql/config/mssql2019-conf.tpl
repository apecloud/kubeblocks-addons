{{- $phy_memory := getContainerMemory ( getContainerByName $.podSpec.containers "mssql" ) }}
{{- $memorylimitmb := 1024 }}
{{- if gt $phy_memory 0 }}
{{- $memorylimitmb = div ( mul ( div $phy_memory 1048576 ) 4 ) 5 }}
{{- end }}

[eula]
accepteula = Y

[coredump]
captureminiandfull = true
coredumptype = full
customdumpdirectory = /var/opt/mssql/dumps

[network]
forceencryption = 1
enablekerberos = true
tcpport = {{ $.MSSQL_SERVER_PORT }}

[memory]
memorylimitmb = {{ $memorylimitmb }}
systemmemorylimitpercent = 80
query_memory_grant_percent = 25

[filelocation]
defaultdatadir = /var/opt/mssql/data
defaultlogdir = /var/opt/mssql/log
defaultdumpdir = /var/opt/mssql/dumps
defaultbackupdir = /var/opt/mssql/backup

[sqlagent]
enabled = true
errorlogginglevel = 1
startupwaitforalldb = 1

[telemetry]
customerfeedback = false
userrequestedlocalauditdirectory = /var/opt/mssql/audit

[hadr]
hadrenabled = 1
hadrendpointport = {{ $.MSSQL_HADR_ENDPOINT_PORT }}
hadrendpointname = Hadr_endpoint

[traceflag]
traceflag0 = 1117
traceflag1 = 1118
traceflag2 = 3226
traceflag3 = 4199

[language]
lcid = 1033

[backup]
compressiondefault = 1
buffercount = 50
maxtransfersize = 4194304
blocksize = 65536

[distributedtransaction]
servertcpport = 51000
enablextp = true

[logging]
errorlogfile = /var/opt/mssql/log/errorlog
errorlogretentiondays = 30
errorlogsizeinkb = 102400

[resourcegovernor]
enabled = true

[auditing]
enabled = true
logsize = 102400
filepath = /var/opt/mssql/audit
retention = 30
