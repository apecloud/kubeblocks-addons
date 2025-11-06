## for proxy or broker
export PULSAR_EXTRA_OPTS="-Dpulsar.allocator.exit_on_oom=true -Dio.netty.recycler.maxCapacity.default=1000 -Dio.netty.recycler.linkCapacity=1024 -Dnetworkaddress.cache.ttl=60 -XX:ActiveProcessorCount=1 -XshowSettings:vm -Ddepth=64"
export PULSAR_GC="-XX:+UseG1GC -XX:MaxGCPauseMillis=10 -XX:+ParallelRefProcEnabled -XX:+UnlockExperimentalVMOptions -XX:+DoEscapeAnalysis -XX:G1NewSizePercent=50 -XX:+DisableExplicitGC -XX:-ResizePLAB"
{{- $maxDirectMemorySize := "" }}
{{- $phyMemory := default 0 $.PHY_MEMORY | int }}
{{- if gt $phyMemory 0 }}
  {{- $maxDirectMemorySize = printf "-XX:MaxDirectMemorySize=%dm" (mul (div $phyMemory ( mul 1024 1024 10)) 6) }}
{{- end }}
export PULSAR_MEM="-XX:MinRAMPercentage=30 -XX:MaxRAMPercentage=30 {{ $maxDirectMemorySize }}"