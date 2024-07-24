#!/usr/bin/env bash

idx=${KB_POD_NAME##*-}
if [ $idx -ne 0 ]; then
    exit 0
fi

while true; do
  # we don't use `select 1` here, because the starrocks will return the following error:
  # ERROR 1064 (HY000) at line 1: Backend node not found. Check if any backend node is down.backend
  mysql --connect-timeout=1 -h127.0.0.1 -uroot -P9030 -p${STARROCKS_PASSWORD} -e "show databases"
  if [ $? == 0 ]; then
    break
  fi
  MYSQL_PWD="" mysql --connect-timeout=1 -h127.0.0.1 -uroot -P9030 -e "SET PASSWORD = PASSWORD('${STARROCKS_PASSWORD}')"
  sleep 1
done
