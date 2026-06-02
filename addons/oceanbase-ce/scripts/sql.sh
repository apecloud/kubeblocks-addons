#!/usr/bin/env bash

#
# Copyright (c) 2023 OceanBase
# ob-operator is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#          http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.
#

OB_MYSQL_BIN=${OB_MYSQL_BIN:-}
if [ -z "$OB_MYSQL_BIN" ]; then
  if command -v mysql &>/dev/null; then
    OB_MYSQL_BIN="mysql"
  elif [ -x "/kb_tools/obtools" ]; then
    OB_MYSQL_BIN="/kb_tools/obtools"
  fi
fi

function _ob_sql {
  local host="$1" user="$2" port="$3" passwd="$4" db="$5" query="$6" batch="${7:-}"
  if [ "$OB_MYSQL_BIN" = "mysql" ]; then
    local args=(-h"$host" -u"$user" -P"$port" -A)
    [ -n "$passwd" ] && args+=(-p"$passwd")
    [ -n "$db" ] && args+=(-D"$db")
    [ -n "$batch" ] && args+=(-B)
    mysql "${args[@]}" -e "$query"
  elif [ "$OB_MYSQL_BIN" = "/kb_tools/obtools" ]; then
    local clean_query="${query%\\G}"
    local args=(--host "$host" -u "$user" -P "$port")
    [ -n "$passwd" ] && args+=(-p "$passwd")
    [ -n "$db" ] && args+=(-D "$db")
    /kb_tools/obtools execute "${args[@]}" -e "$clean_query"
  else
    echo "FATAL: No MySQL client available (mysql or /kb_tools/obtools)" >&2
    return 1
  fi
}

function conn_local_wo_passwd {
  _ob_sql "127.0.0.1" "root" "$OB_SERVICE_PORT" "" "" "$1"
}

function conn_local {
  echo "[DEBUG] $1"
  _ob_sql "127.0.0.1" "root" "$OB_SERVICE_PORT" "$OB_ROOT_PASSWD" "" "$1"
}

function conn_local_obdb {
  _ob_sql "127.0.0.1" "root" "$OB_SERVICE_PORT" "$OB_ROOT_PASSWD" "oceanbase" "$1"
}

function conn_remote {
  _ob_sql "$1" "root" "$OB_SERVICE_PORT" "$OB_ROOT_PASSWD" "" "$2"
}

function conn_local_as_mysql_tenant {
  _ob_sql "127.0.0.1" "root@$1" "$OB_SERVICE_PORT" "" "" "$2"
}

function conn_local_as_user {
  echo "[DEBUG] conn_local_as_user: host=127.0.0.1 user=$2@$1 port=$OB_SERVICE_PORT"
  _ob_sql "127.0.0.1" "$2@$1" "$OB_SERVICE_PORT" "$4" "" "$3"
}

function conn_remote_batch {
  _ob_sql "$1" "root" "$OB_SERVICE_PORT" "$OB_ROOT_PASSWD" "oceanbase" "$2" "batch"
}