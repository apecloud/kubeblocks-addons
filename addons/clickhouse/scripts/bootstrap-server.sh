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
exec ${scripts_dir}/clickhouse/entrypoint.sh ${scripts_dir}/clickhouse/run.sh
