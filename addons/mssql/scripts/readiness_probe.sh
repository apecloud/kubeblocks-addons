#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set -euo pipefail

SQLCMD="${SQLCMD:-/opt/mssql-tools18/bin/sqlcmd}"
MSSQL_SERVER_PORT="${MSSQL_SERVER_PORT:-1433}"
MSSQL_SA_USER="${MSSQL_SA_USER:-sa}"
MSSQL_READINESS_LOGIN_TIMEOUT="${MSSQL_READINESS_LOGIN_TIMEOUT:-3}"
MSSQL_READINESS_QUERY_TIMEOUT="${MSSQL_READINESS_QUERY_TIMEOUT:-3}"
MSSQL_INIT_FLAG="${MSSQL_INIT_FLAG:-/var/opt/mssql/.initialized}"

if [ ! -f "$MSSQL_INIT_FLAG" ]; then
  echo "mssql readiness failed: init flag $MSSQL_INIT_FLAG is missing" >&2
  exit 1
fi

: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD is required for mssql readiness probe}"

"$SQLCMD" \
  -S "127.0.0.1,${MSSQL_SERVER_PORT}" \
  -U "$MSSQL_SA_USER" \
  -P "$MSSQL_SA_PASSWORD" \
  -C -b -V 11 \
  -l "$MSSQL_READINESS_LOGIN_TIMEOUT" \
  -t "$MSSQL_READINESS_QUERY_TIMEOUT" \
  -h -1 -W <<'SQL'
USE [master];
SET NOCOUNT ON;

DECLARE @missing NVARCHAR(MAX) = N'';

IF OBJECT_ID(N'master.dbo.sp_hexadecimal', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_hexadecimal');
IF OBJECT_ID(N'master.dbo.sp_help_revlogin', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_help_revlogin');
IF OBJECT_ID(N'master.dbo.sp_ape_help_revlogin', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_help_revlogin');
IF OBJECT_ID(N'master.dbo.sp_ape_get_ag_role', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_get_ag_role');
IF OBJECT_ID(N'master.dbo.sp_ape_add_link_svr', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_add_link_svr');
IF OBJECT_ID(N'master.dbo.sp_ape_remove_link_svr', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_remove_link_svr');
IF OBJECT_ID(N'master.dbo.sp_ape_sync_login', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_sync_login');
IF OBJECT_ID(N'master.dbo.sp_ape_sync_drop_login', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_sync_drop_login');
IF OBJECT_ID(N'master.dbo.sp_ape_sync_svrrole', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_sync_svrrole');
IF OBJECT_ID(N'master.dbo.sp_ape_kill_login_sessions', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_kill_login_sessions');
IF OBJECT_ID(N'master.dbo.sp_ape_cleanup_login_users', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_cleanup_login_users');
IF OBJECT_ID(N'master.dbo.sp_ape_fix_orphaned_users', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_fix_orphaned_users');
IF OBJECT_ID(N'master.dbo.sp_ape_export_agent_jobs', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_export_agent_jobs');
IF OBJECT_ID(N'master.dbo.sp_ape_sync_db_to_ag', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_sync_db_to_ag');
IF OBJECT_ID(N'master.dbo.sp_ape_drop_db_sync', N'P') IS NULL SET @missing = CONCAT(@missing, N', master.dbo.sp_ape_drop_db_sync');

IF OBJECT_ID(N'msdb.dbo.ape_sync_db_log', N'U') IS NULL SET @missing = CONCAT(@missing, N', msdb.dbo.ape_sync_db_log');
IF OBJECT_ID(N'msdb.dbo.sp_ape_db_sync_message', N'P') IS NULL SET @missing = CONCAT(@missing, N', msdb.dbo.sp_ape_db_sync_message');
IF OBJECT_ID(N'msdb.dbo.sp_ape_process_sync_db', N'P') IS NULL SET @missing = CONCAT(@missing, N', msdb.dbo.sp_ape_process_sync_db');
IF OBJECT_ID(N'msdb.dbo.ape_sync_login_log', N'U') IS NULL SET @missing = CONCAT(@missing, N', msdb.dbo.ape_sync_login_log');
IF OBJECT_ID(N'msdb.dbo.ape_sync_login_dead_letter', N'U') IS NULL SET @missing = CONCAT(@missing, N', msdb.dbo.ape_sync_login_dead_letter');
IF OBJECT_ID(N'msdb.dbo.sp_ape_login_role_sync_message', N'P') IS NULL SET @missing = CONCAT(@missing, N', msdb.dbo.sp_ape_login_role_sync_message');
IF OBJECT_ID(N'msdb.dbo.sp_ape_process_sync_login_and_role', N'P') IS NULL SET @missing = CONCAT(@missing, N', msdb.dbo.sp_ape_process_sync_login_and_role');

IF NOT EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = N'_$$_tr_$$_ape_create_database' AND is_disabled = 0) SET @missing = CONCAT(@missing, N', enabled server trigger _$$_tr_$$_ape_create_database');
IF NOT EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = N'_$$_tr_$$_ape_drop_db' AND is_disabled = 0) SET @missing = CONCAT(@missing, N', enabled server trigger _$$_tr_$$_ape_drop_db');
IF NOT EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = N'_$$_tr_$$_ape_alter_login' AND is_disabled = 0) SET @missing = CONCAT(@missing, N', enabled server trigger _$$_tr_$$_ape_alter_login');
IF NOT EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = N'_$$_tr_$$_ape_create_login' AND is_disabled = 0) SET @missing = CONCAT(@missing, N', enabled server trigger _$$_tr_$$_ape_create_login');
IF NOT EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = N'_$$_tr_$$_ape_drop_login' AND is_disabled = 0) SET @missing = CONCAT(@missing, N', enabled server trigger _$$_tr_$$_ape_drop_login');
IF NOT EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = N'_$$_tr_$$_ape_alter_server_role' AND is_disabled = 0) SET @missing = CONCAT(@missing, N', enabled server trigger _$$_tr_$$_ape_alter_server_role');

IF NOT EXISTS (SELECT 1 FROM msdb.sys.service_message_types WHERE name = N'//ApeCloud/DBSyncRequestMessage') SET @missing = CONCAT(@missing, N', Service Broker message type //ApeCloud/DBSyncRequestMessage');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.service_contracts WHERE name = N'//ApeCloud/DBSyncContract') SET @missing = CONCAT(@missing, N', Service Broker contract //ApeCloud/DBSyncContract');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.service_queues WHERE name = N'ApeSyncDBTarget' AND is_receive_enabled = 1 AND is_activation_enabled = 1) SET @missing = CONCAT(@missing, N', active Service Broker queue ApeSyncDBTarget');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.service_queues WHERE name = N'ApeSyncDBInitiator' AND is_receive_enabled = 1) SET @missing = CONCAT(@missing, N', active Service Broker queue ApeSyncDBInitiator');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.services s JOIN msdb.sys.service_queues q ON s.service_queue_id = q.object_id WHERE s.name = N'//ApeCloud/DBSyncTarget' AND q.name = N'ApeSyncDBTarget') SET @missing = CONCAT(@missing, N', Service Broker service //ApeCloud/DBSyncTarget');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.services s JOIN msdb.sys.service_queues q ON s.service_queue_id = q.object_id WHERE s.name = N'//ApeCloud/DBSyncInitiator' AND q.name = N'ApeSyncDBInitiator') SET @missing = CONCAT(@missing, N', Service Broker service //ApeCloud/DBSyncInitiator');

IF NOT EXISTS (SELECT 1 FROM msdb.sys.service_message_types WHERE name = N'//ApeCloud/LoginSyncRequestMessage') SET @missing = CONCAT(@missing, N', Service Broker message type //ApeCloud/LoginSyncRequestMessage');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.service_message_types WHERE name = N'//ApeCloud/LoginSyncRequestReplyMessage') SET @missing = CONCAT(@missing, N', Service Broker message type //ApeCloud/LoginSyncRequestReplyMessage');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.service_contracts WHERE name = N'//ApeCloud/LoginSyncContract') SET @missing = CONCAT(@missing, N', Service Broker contract //ApeCloud/LoginSyncContract');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.service_queues WHERE name = N'ApeSyncLoginTarget' AND is_receive_enabled = 1 AND is_activation_enabled = 1) SET @missing = CONCAT(@missing, N', active Service Broker queue ApeSyncLoginTarget');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.service_queues WHERE name = N'ApeSyncLoginInitiator' AND is_receive_enabled = 1) SET @missing = CONCAT(@missing, N', active Service Broker queue ApeSyncLoginInitiator');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.services s JOIN msdb.sys.service_queues q ON s.service_queue_id = q.object_id WHERE s.name = N'//ApeCloud/LoginSyncTarget' AND q.name = N'ApeSyncLoginTarget') SET @missing = CONCAT(@missing, N', Service Broker service //ApeCloud/LoginSyncTarget');
IF NOT EXISTS (SELECT 1 FROM msdb.sys.services s JOIN msdb.sys.service_queues q ON s.service_queue_id = q.object_id WHERE s.name = N'//ApeCloud/LoginSyncInitiator' AND q.name = N'ApeSyncLoginInitiator') SET @missing = CONCAT(@missing, N', Service Broker service //ApeCloud/LoginSyncInitiator');

IF LEN(@missing) > 0
BEGIN
    SELECT N'mssql readiness missing dependencies: ' + STUFF(@missing, 1, 2, N'');
    THROW 51000, 'MSSQL addon readiness dependencies are missing or disabled.', 1;
END

SELECT 1;
SQL
