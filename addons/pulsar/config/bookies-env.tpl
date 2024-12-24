PULSAR_GC: -XX:+UseG1GC -XX:MaxGCPauseMillis=10 -XX:+ParallelRefProcEnabled -XX:+UnlockExperimentalVMOptions -XX:+DoEscapeAnalysis -XX:ParallelGCThreads=4 -XX:ConcGCThreads=4 -XX:G1NewSizePercent=50 -XX:+DisableExplicitGC -XX:-ResizePLAB -XX:+ExitOnOutOfMemoryError -XX:+PerfDisableSharedMem -XshowSettings:vm -Ddepth=64

{{- $MaxDirectMemorySize := "" }}
{{- $phy_memory := getContainerMemory ( index $.podSpec.containers 0 ) }}
{{- if gt $phy_memory 0 }}
  {{- $phy_memory_mb := div $phy_memory ( mul 1024 1024 ) }}
  {{- $MaxDirectMemorySize = printf "-XX:MaxDirectMemorySize=%dm" (div ( mul $phy_memory_mb 3 ) 4 ) }}
{{- end }}
PULSAR_MEM: -XX:MinRAMPercentage=25 -XX:MaxRAMPercentage=50 {{ $MaxDirectMemorySize }}
