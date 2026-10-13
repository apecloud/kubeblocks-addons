#!/bin/bash
last_modification_time=0
function sync_user_xml() {
	local dir=/bitnami/clickhouse/etc/users.d/default
	while true; do
		sleep 3
		link_file=$(readlink -f "${dir}/user.xml")
		modification_time=$(date -d "$(ls -l --time-style=full-iso "${link_file}" | awk '{print $6 " " $7}')" +%s)
		if [ $modification_time -ne $last_modification_time ]; then
			last_modification_time=$modification_time
			echo "$(date) INFO: user.xml file has been modified, syncing..." >>/tmp/sync_user_xml.log
			cp -f "${dir}/user.xml" /opt/bitnami/clickhouse/etc/users.d/user.xml
		fi
	done
}

function chown_data_dir() {
	data_dir=/bitnami/clickhouse/data
	if [ ! -d "${data_dir}" ]; then
		return
	fi
	uid=$(ls -nd ${data_dir} | awk '{print $3}')
	if [ "${uid}" == "1001" ]; then
		echo "$(date) INFO: chown data dir to root:root"
		chown -R root:root ${data_dir}
	fi
}

sync_user_xml &
chown_data_dir
scripts_dir=/opt/bitnami/scripts
sed -i 's/^export CLICKHOUSE_DAEMON_USER="clickhouse"/CLICKHOUSE_DAEMON_USER="root"/' ${scripts_dir}/clickhouse-env.sh
sed -i 's/^export CLICKHOUSE_DAEMON_GROUP="clickhouse"/CLICKHOUSE_DAEMON_GROUP="root"/' ${scripts_dir}/clickhouse-env.sh

# When coordinated by an external ZooKeeper cluster (withZookeeper mode), the
# configured <root> path must exist before ClickHouse starts, otherwise it
# fails with "ZooKeeper root doesn't exist". Create it idempotently for the
# primary ZooKeeper and every auxiliary ZooKeeper cluster.
# Only the pod with ordinal 0 performs the creation to avoid concurrent
# create races; other pods just start once the root already exists.

pod_ordinal="${CURRENT_POD_NAME##*-}"
if [[ "$pod_ordinal" == "0" && -n "${CLICKHOUSE_ZOOKEEPER_POD_FQDNS:-}" && -n "${KB_CLUSTER_NAME:-}" ]]; then
	source /scripts/common.sh
	zk_root="/clickhouse_${KB_CLUSTER_NAME}"
	echo "$(date) INFO: ensuring ZooKeeper root ${zk_root} exists"
	if [[ -n "${CLICKHOUSE_ZOOKEEPER_POD_FQDNS:-}" ]]; then
		zk_create_root "$CLICKHOUSE_ZOOKEEPER_POD_FQDNS" "$zk_root"
	fi
	for i in 1 2 3 4 5 6 7; do
		aux_var="CLICKHOUSE_AUX_ZOOKEEPER_${i}_POD_FQDNS"
		if [[ -n "${!aux_var:-}" ]]; then
			zk_create_root "${!aux_var}" "$zk_root"
		fi
	done
fi

exec ${scripts_dir}/clickhouse/entrypoint.sh ${scripts_dir}/clickhouse/run.sh
