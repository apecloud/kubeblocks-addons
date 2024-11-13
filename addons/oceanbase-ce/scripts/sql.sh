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

function conn_local_wo_passwd {
  mysql -h127.0.0.1 -uroot -P $OB_SERVICE_PORT -A -e "$1"
}


function conn_local {
  echo "[DEBUG] $1"
  mysql -h127.0.0.1 -uroot -P $OB_SERVICE_PORT -A -e "$1" -p"$OB_ROOT_PASSWD"
}

function conn_local_obdb {
  mysql -h127.0.0.1 -uroot -P $OB_SERVICE_PORT -A -Doceanbase -e "$1"  -p"$OB_ROOT_PASSWD"
}

function conn_remote {
  mysql -h$1 -uroot -A -p"$OB_ROOT_PASSWD"  -P $OB_SERVICE_PORT -e "$2"
}

function conn_local_as_mysql_tenant {
  mysql -h127.1 -P $OB_SERVICE_PORT -uroot@"$1"  -A -e "$2"
}

function conn_local_as_user {
  echo "[DEBUG] conn_local_as_user:" mysql -h127.1 -P $OB_SERVICE_PORT -u"$2"@"$1" -A -e "$3"
  mysql -h127.1 -P $OB_SERVICE_PORT -u"$2"@"$1" -p"$4" -A -e "$3"
}

function conn_remote_batch {
  mysql -h$1 -uroot -P $OB_SERVICE_PORT -A -Doceanbase -e "$2" -B -p"$OB_ROOT_PASSWD"
}