#!/bin/bash
set -euo pipefail

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

function wait_peer_dns_ready() {
	local peers="${CH_KEEPER_POD_FQDN_LIST:-}"
	local attempts=30
	local sleep_seconds=2

	[[ -z "$peers" ]] && return 0

	for peer in ${peers//,/ }; do
		for attempt in $(seq 1 $attempts); do
			if getent hosts "$peer" >/dev/null 2>&1; then
				break
			fi
			if [[ $attempt -eq $attempts ]]; then
				echo "$(date) ERROR: peer DNS $peer is still unresolved after $((attempts * sleep_seconds))s" >&2
				return 1
			fi
			sleep "$sleep_seconds"
		done
	done
}

chown_data_dir
wait_peer_dns_ready
HOSTNAME="$(hostname -s)"
if grep -q "<id>0</id>" /opt/bitnami/clickhouse/etc/conf.d/ch-keeper_00_default_overrides.xml; then
	# compatible old version
	export CH_KEEPER_ID=${HOSTNAME##*-}
else
	export CH_KEEPER_ID=$((${HOSTNAME##*-} + 1))
fi
scripts_dir=/opt/bitnami/scripts
sed -i 's/^export CLICKHOUSE_DAEMON_USER="clickhouse"/CLICKHOUSE_DAEMON_USER="root"/' ${scripts_dir}/clickhouse-env.sh
sed -i 's/^export CLICKHOUSE_DAEMON_GROUP="clickhouse"/CLICKHOUSE_DAEMON_GROUP="root"/' ${scripts_dir}/clickhouse-env.sh
exec ${scripts_dir}/clickhouse/entrypoint.sh ${scripts_dir}/clickhouse/run.sh
