#!/bin/bash

source /scripts/util.sh

if [ ! -f "${ROCKETMQ_HOME}"/conf/logback_broker.xml ]; then
    cp -f /kb-config/logback_namesrv.xml "${ROCKETMQ_HOME}"/conf
    cp -f /kb-config/logback_tools.xml "${ROCKETMQ_HOME}"/conf
fi

JAVA_OPT="${JAVA_OPT} -Dcom.sun.management.jmxremote"
JAVA_OPT="${JAVA_OPT} -Dcom.sun.management.jmxremote.port=${JMX_PORT}"
JAVA_OPT="${JAVA_OPT} -Dcom.sun.management.jmxremote.authenticate=false"
JAVA_OPT="${JAVA_OPT} -Dcom.sun.management.jmxremote.ssl=false"
export JAVA_OPT

calculate_heap_sizes
export HEAP_OPTS="-Xms${MAX_HEAP_SIZE} -Xmx${MAX_HEAP_SIZE} -Xmn${HEAP_NEWSIZE} -XX:MaxDirectMemorySize=${MAX_HEAP_SIZE}"

./mqnamesrv -c /kb-config/namesrv.p