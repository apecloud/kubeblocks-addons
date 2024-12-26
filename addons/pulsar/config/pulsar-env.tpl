export PULSAR_GC="-XX:+UseG1GC -XX:MaxGCPauseMillis=10 -XX:+ParallelRefProcEnabled -XX:+UnlockExperimentalVMOptions -XX:+DoEscapeAnalysis -XX:ParallelGCThreads=4 -XX:ConcGCThreads=4 -XX:G1NewSizePercent=50 -XX:+DisableExplicitGC -XX:-ResizePLAB -XX:+ExitOnOutOfMemoryError -XX:+PerfDisableSharedMem -XshowSettings:vm -Ddepth=64"
{{- $maxDirectMemorySize := "" }}
{{- $phyMemory := getContainerMemory ( index $.podSpec.containers 0 ) }}
{{- if gt $phyMemory 0 }}
  {{- $phyMemoryMB := div $phyMemory ( mul 1024 1024 ) }}
  {{- $maxDirectMemorySize = printf "-XX:MaxDirectMemorySize=%dm" (div ( mul $phyMemoryMB 3 ) 4 ) }}
{{- end }}
export PULSAR_MEM="-XX:MinRAMPercentage=25 -XX:MaxRAMPercentage=50 {{ $maxDirectMemorySize }}"