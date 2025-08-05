# acl config
{{- if hasKey $.cluster.metadata.annotations "kubeblocks.io/extra-env" -}}
{{- $extraEnv := index $.cluster.metadata.annotations "kubeblocks.io/extra-env" | fromJson -}}
{{- if hasKey $extraEnv "ENABLE_ACL" }}
aclEnable={{ $extraEnv.ENABLE_ACL }}
{{- end -}}
{{- if hasKey $extraEnv "ENABLE_DLEDGER" }}
enableDLegerCommitLog={{ $extraEnv.ENABLE_DLEDGER }}
{{- end -}}
{{- end }}

# common configs
traceOn=true
autoCreateTopicEnable=false
autoCreateSubscriptionGroup=true
enableIncrementalTopicCreation=true
generateConfigForScaleOutEnable=false
enableNotifyAfterPopOrderLockRelease=true
autoMessageVersionOnTopicLen=true
enableNameServerAddressResolve=true
listenPort={{ .BROKER_PORT }}

# Store config
flushDiskType=SYNC_FLUSH

# Enable SQL92
enablePropertyFilter=true

transactionCheckInterval=60000

waitTimeMillsInSendQueue=900
maxMessageSize=5242880

# stream
# litePullMessageEnable=true

brokerClusterName={{ .KB_CLUSTER_NAME }}
brokerName={{ .KB_COMP_NAME }}
