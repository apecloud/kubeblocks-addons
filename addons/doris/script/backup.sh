set -e
connect_url="mysql -uroot -P9030 -h${DP_DB_HOST} -p${DP_DB_PASSWORD}"
repositories=$(${connect_url} -e "show repositories;") # Query whether a backup repository already exists
found_repostiory=false;
if [ -z "$repositories" ];then
  echo "INFO: The remote repository is created for the first time!"
else
  for repo in ${repositories};do
    if [ $repo =  ${backup_repository} ]; then
      found_repostiory=true;
      echo "INFO: This remote repository already exists!"
      break
    fi
  done
fi
if [ ${found_repostiory} = "false" ]; then
    echo "INFO: Create a remote repository named ${backup_repository} for backup purposes"
    sql_command="CREATE REPOSITORY ${backup_repository} WITH S3 ON LOCATION \"${minio_address}\" PROPERTIES ('AWS_ENDPOINT' = 'http://172.16.58.104:30000','AWS_ACCESS_KEY' = 'minioadmin','AWS_SECRET_KEY' = 'minioadmin','AWS_REGION' = 'us-east-1','use_path_style' = 'true');"
    ${connect_url} -e "${sql_command}"
fi
echo "INFO: Start backup"
echo "INFO: Find the database created by all users in the doris cluster"
databases=$(${connect_url} -e "show databases;")
for db in ${databases};do
  echo "TEST: $db"
  if [ $db != '__internal_schema' ] && [ $db != 'Database' ]  && [ $db != 'information_schema' ];then
     echo "INFO: Start backup database ${db}"
     backup_command="BACKUP SNAPSHOT ${db}.${snapshot_label} TO ${backup_repository}  PROPERTIES ('type' = 'full');"
     ${connect_url} -e "${backup_command}"
  fi
done
echo "INFO: finish doris cluster all databases backup"
echo "INFO: The loop runs permanently!"
while true; do sleep 1; done
