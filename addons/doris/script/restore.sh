set -e
connect_url="mysql -uroot -P9030 -h${DP_DB_HOST} -p${DP_DB_PASSWORD}"
echo "INFO: Specify a backup repository ${backup_repository}"
echo "INFO: Start restore"
echo "INFO: Find the database created by all users in the doris cluster"
databases=$(${connect_url} -e "show databases;")
for db in ${databases};do
  if [ $db != '__internal_schema' ] && [ $db != 'Database' ]  && [ $db != 'information_schema' ];then
    echo "INFO: Start backup database ${db}"
    restore_command="RESTORE SNAPSHOT ${db}.${snapshot_label} FROM ${backup_repository} PROPERTIES ("backup_timestamp"="${backup_timestamp}","replication_num"="${replication_num}");"
    ${connect_url} -e "${restore_command}"
  fi
done
echo "INFO: finish doris cluster all databases restore"
echo "INFO: The loop runs permanently!"
while true; do sleep 1; done

