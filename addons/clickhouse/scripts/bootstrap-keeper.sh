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
chown_data_dir
HOSTNAME="$(hostname -s)"
export CH_KEEPER_ID=$((${HOSTNAME##*-} + 1))
scripts_dir=/opt/bitnami/scripts
sed -i 's/^export CLICKHOUSE_DAEMON_USER="clickhouse"/CLICKHOUSE_DAEMON_USER="root"/' ${scripts_dir}/clickhouse-env.sh
sed -i 's/^export CLICKHOUSE_DAEMON_GROUP="clickhouse"/CLICKHOUSE_DAEMON_GROUP="root"/' ${scripts_dir}/clickhouse-env.sh
exec ${scripts_dir}/clickhouse/entrypoint.sh ${scripts_dir}/clickhouse/run.sh -- --listen_host=0.0.0.0