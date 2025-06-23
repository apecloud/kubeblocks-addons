#!/bin/bash

# shellcheck disable=SC2034

java -version
if [ $? -ne 0 ]; then
  echo "[ERROR] Missing java runtime"
  exit 50
fi

if [ -z "${ROCKETMQ_HOME}" ]; then
  echo "[ERROR] Missing env ROCKETMQ_HOME"
  exit 50
fi
if [ -z "${ROCKETMQ_PROCESS_ROLE}" ]; then
  echo "[ERROR] Missing env ROCKETMQ_PROCESS_ROLE"
  exit 50
fi

export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export CLASSPATH=".:${ROCKETMQ_HOME}/conf:${ROCKETMQ_HOME}/lib/*:${CLASSPATH}"

JAVA_OPT="${JAVA_OPT} -server"
if [ -n "$ROCKETMQ_JAVA_OPTIONS_OVERRIDE" ]; then
  JAVA_OPT="${JAVA_OPT} ${ROCKETMQ_JAVA_OPTIONS_OVERRIDE}"
else
  JAVA_OPT="${JAVA_OPT} -XX:+UseG1GC"
  JAVA_OPT="${JAVA_OPT} ${ROCKETMQ_JAVA_OPTIONS_EXT}"
  JAVA_OPT="${JAVA_OPT} ${ROCKETMQ_JAVA_OPTIONS_HEAP}"
fi
JAVA_OPT="${JAVA_OPT} -cp ${CLASSPATH}"

export BROKER_CONF_FILE="$HOME/broker.conf"
export CONTROLLER_CONF_FILE="$HOME/controller.conf"

update_broker_conf() {
  local key=$1
  local value=$2
  sed -i "/^${key} *=/d" ${BROKER_CONF_FILE}
  echo "${key} = ${value}" >> ${BROKER_CONF_FILE}
}

init_broker_role() {
  if [ "${ROCKETMQ_CONF_brokerRole}" = "SLAVE" ]; then
    update_broker_conf "brokerRole" "SLAVE"
  elif [ "${ROCKETMQ_CONF_brokerRole}" = "SYNC_MASTER" ]; then
    update_broker_conf "brokerRole" "SYNC_MASTER"
  else
    update_broker_conf "brokerRole" "ASYNC_MASTER"
  fi
  if echo "${ROCKETMQ_CONF_brokerId}" | grep -E '^[0-9]+$'; then
    update_broker_conf "brokerId" "${ROCKETMQ_CONF_brokerId}"
  fi
}

init_broker_conf() {
  rm -f ${BROKER_CONF_FILE}
  cp /etc/rocketmq/broker-base.conf ${BROKER_CONF_FILE}
  echo "" >> ${BROKER_CONF_FILE}
  echo "# generated config" >> ${BROKER_CONF_FILE}
  broker_name_seq=${HOSTNAME##*-}
  if [ -n "$MY_POD_NAME" ]; then
    broker_name_seq=${MY_POD_NAME##*-}
  fi
  update_broker_conf "brokerName" "broker-g${broker_name_seq}"
  if [ "$enableControllerMode" != "true" ]; then
    init_broker_role
  fi
  echo "[exec] cat ${BROKER_CONF_FILE}"
  cat ${BROKER_CONF_FILE}
}

init_acl_conf() {
  if [ -f /etc/rocketmq/acl/plain_acl.yml ]; then
    rm -f "${ROCKETMQ_HOME}/conf/plain_acl.yml"
    ln -sf "/etc/rocketmq/acl" "${ROCKETMQ_HOME}/conf/acl"
  fi
}

init_controller_conf() {
  rm -f ${CONTROLLER_CONF_FILE}
  cp /etc/rocketmq/base-cm/controller-base.conf ${CONTROLLER_CONF_FILE}
  controllerDLegerSelfId="n${HOSTNAME##*-}"
  if [ -n "$MY_POD_NAME" ]; then
    controllerDLegerSelfId="n${MY_POD_NAME##*-}"
  fi
  sed -i "/^controllerDLegerSelfId *=/d" ${CONTROLLER_CONF_FILE}
  echo "controllerDLegerSelfId = ${controllerDLegerSelfId}" >> ${CONTROLLER_CONF_FILE}
  cat ${CONTROLLER_CONF_FILE}
}

if [ "$ROCKETMQ_PROCESS_ROLE" = "broker" ]; then
  init_broker_conf
  init_acl_conf
  set -x
  java ${JAVA_OPT} org.apache.rocketmq.broker.BrokerStartup -c ${BROKER_CONF_FILE}
elif [ "$ROCKETMQ_PROCESS_ROLE" = "controller" ]; then
  init_controller_conf
  set -x
  java ${JAVA_OPT} org.apache.rocketmq.controller.ControllerStartup -c ${CONTROLLER_CONF_FILE}
elif [ "$ROCKETMQ_PROCESS_ROLE" = "nameserver" ] || [ "$ROCKETMQ_PROCESS_ROLE" = "mqnamesrv" ]; then
  set -x
  if [ "$enableControllerInNamesrv" = "true" ]; then
    init_controller_conf
    java ${JAVA_OPT} org.apache.rocketmq.namesrv.NamesrvStartup -c ${CONTROLLER_CONF_FILE}
  else
    java ${JAVA_OPT} org.apache.rocketmq.namesrv.NamesrvStartup
  fi
elif  [ "$ROCKETMQ_PROCESS_ROLE" = "proxy" ]; then
  set -x
  if [ -f $RMQ_PROXY_CONFIG_PATH ]; then
    java ${JAVA_OPT} org.apache.rocketmq.proxy.ProxyStartup -pc $RMQ_PROXY_CONFIG_PATH
  else
    java ${JAVA_OPT} org.apache.rocketmq.proxy.ProxyStartup
  fi
else
  echo "[ERROR] Missing env ROCKETMQ_PROCESS_ROLE"
  exit 50
fi