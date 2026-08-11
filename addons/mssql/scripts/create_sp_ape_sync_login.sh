#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

TMP_DIR="/tmp"
cat >"$TMP_DIR/create_sp_ape_sync_login.sql" << EOF
SET QUOTED_IDENTIFIER ON
GO
USE [master]
GO

IF OBJECT_ID('dbo.sp_ape_remove_link_svr') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_remove_link_svr
GO

CREATE PROCEDURE dbo.sp_ape_remove_link_svr
    @POD_FQDN NVARCHAR(1024)
WITH ENCRYPTION AS
BEGIN
    SET NOCOUNT ON;
	BEGIN TRY
        IF EXISTS(SELECT 1 FROM sys.servers WHERE name = @POD_FQDN)
        BEGIN
            EXEC sp_dropserver @server = @POD_FQDN, @droplogins = 'droplogins'
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrorState INT = ERROR_STATE()
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)
        RETURN -1
    END CATCH
END
go

IF OBJECT_ID('dbo.sp_ape_add_link_svr') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_add_link_svr
GO

CREATE PROCEDURE dbo.sp_ape_add_link_svr
    @POD_FQDN NVARCHAR(1024)
WITH ENCRYPTION AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        EXECUTE AS LOGIN =  'sa';

        IF NOT EXISTS(SELECT 1 FROM sys.servers WHERE name = @POD_FQDN)
        BEGIN
            EXEC sp_addlinkedserver
            @server = @POD_FQDN,
            @srvproduct = N'SQL Server'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'collation compatible', @optvalue = N'false'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'data access', @optvalue = N'true'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN, @optname = N'dist',@optvalue = N'false'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN, @optname = N'pub',@optvalue = N'false'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN, @optname = N'rpc',@optvalue = N'true'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN, @optname = N'rpc out',@optvalue = N'true'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN, @optname = N'sub',@optvalue = N'false'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'connect timeout', @optvalue = N'0'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'collation name', @optvalue = NULL
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'lazy schema validation', @optvalue = N'false'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'query timeout', @optvalue = N'0'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'use remote collation', @optvalue = N'true'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'connect timeout', @optvalue = N'120'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'query timeout', @optvalue = N'120'
            EXEC master.dbo.sp_serveroption @server = @POD_FQDN,@optname = N'remote proc transaction promotion',@optvalue = N'true'
            EXEC master.dbo.sp_addlinkedsrvlogin
            @rmtsrvname = @POD_FQDN,
            @locallogin = NULL,
            @useself = N'false',
            @rmtuser = N'sa',
            @rmtpassword = N'${MSSQL_SA_PASSWORD}'
            PRINT 'Success add a link server: ' + @POD_FQDN
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrorState INT = ERROR_STATE()

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState)
        RETURN -1
    END CATCH
END
GO

IF OBJECT_ID('dbo.sp_ape_sync_login') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_sync_login
GO
CREATE PROCEDURE dbo.sp_ape_sync_login
    @login_name NVARCHAR(255)
WITH ENCRYPTION
AS
BEGIN

    DECLARE @ddl NVARCHAR(MAX)
    EXEC dbo.sp_ape_help_revlogin @login_name=@login_name ,@login_ddl = @ddl OUTPUT

	DECLARE @replica_server_name NVARCHAR(255)
	DECLARE @endpoint_url NVARCHAR(1024)
	DECLARE @fqdn NVARCHAR(1024)
	DECLARE @current_server NVARCHAR(255)
    DECLARE @start_pos INT
    DECLARE @end_pos INT

	-- 声明游标
	DECLARE replica_cursor CURSOR STATIC FOR
	SELECT
	    replica_server_name,
	    endpoint_url
	FROM sys.availability_replicas WITH (NOLOCK)
	WHERE replica_server_name <> @@servername

	OPEN replica_cursor
	FETCH NEXT FROM replica_cursor INTO @replica_server_name, @endpoint_url
	WHILE @@FETCH_STATUS = 0
	BEGIN
        SET @start_pos  = CHARINDEX('//', @endpoint_url) + 2
        SET @end_pos  = CHARINDEX(':', @endpoint_url, @start_pos)
        IF @end_pos > 0
        BEGIN
            SET @fqdn = SUBSTRING(
                @endpoint_url,
                @start_pos,
                @end_pos - @start_pos
            )
        END
        ELSE
        BEGIN
            PRINT 'Warning: Invalid endpoint URL format for server ' + @replica_server_name
        END
	
	    DECLARE @lock_result INT
	    EXEC @lock_result = sp_getapplock
	        @Resource = @fqdn,
	        @LockMode = 'Exclusive',
	        @LockOwner = 'Session',
	        @LockTimeout = 60000
	    IF @lock_result >= 0
	    BEGIN
	        BEGIN TRY
	            EXEC sp_ape_add_link_svr @POD_FQDN = @fqdn;
	            DECLARE @sql NVARCHAR(MAX)
	            EXECUTE AS LOGIN = 'sa';
	            SET @sql = N'EXEC(N''' + REPLACE(@ddl, N'''', N'''''')
	                + N''') AT ' + QUOTENAME(@fqdn) + N';'
	            EXEC(@sql);
	            EXEC sp_ape_remove_link_svr @POD_FQDN = @fqdn;
	        END TRY
	        BEGIN CATCH
	            EXEC sp_ape_remove_link_svr @POD_FQDN = @fqdn;
	            INSERT INTO msdb.dbo.ape_sync_login_log
	                (log_id, login_name, operation_type, message, is_succeeded)
	            VALUES
	                (NEWID(), @login_name, 'SYNC_LOGIN',
	                 'Error syncing to ' + @fqdn + ': ' + ERROR_MESSAGE(), 0)
	        END CATCH
	        EXEC sp_releaseapplock @Resource = @fqdn, @LockOwner = 'Session'
	    END
	    ELSE
	    BEGIN
	        INSERT INTO msdb.dbo.ape_sync_login_log
	            (log_id, login_name, operation_type, message, is_succeeded)
	        VALUES
	            (NEWID(), @login_name, 'SYNC_LOGIN',
	             'Failed to acquire lock for ' + @fqdn + ', skipping', 0)
	    END

	    FETCH NEXT FROM replica_cursor INTO @replica_server_name, @endpoint_url
	END
	CLOSE replica_cursor
    DEALLOCATE replica_cursor
END
GO

IF OBJECT_ID('dbo.sp_ape_kill_login_sessions') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_kill_login_sessions
GO

CREATE PROCEDURE dbo.sp_ape_kill_login_sessions
    @login_name NVARCHAR(255)
WITH ENCRYPTION
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @kill_sessions NVARCHAR(MAX) = '';
    SELECT @kill_sessions += 'KILL ' + CAST(session_id AS NVARCHAR(16)) + ';'
    FROM sys.dm_exec_sessions
    WHERE login_name = @login_name
    EXEC sp_executesql @kill_sessions;
END
GO


IF OBJECT_ID('dbo.sp_ape_cleanup_login_users') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_cleanup_login_users
GO

CREATE PROCEDURE dbo.sp_ape_cleanup_login_users
    @login_name NVARCHAR(255)
WITH ENCRYPTION
AS
BEGIN
	DECLARE @command varchar(max)
	SELECT @command = '
	use ?
	DROP USER IF EXISTS ' + QUOTENAME(@login_name)
	EXEC sp_MSforeachdb @command
END
GO

IF OBJECT_ID('dbo.sp_ape_sync_drop_login') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_sync_drop_login
GO
CREATE PROCEDURE dbo.sp_ape_sync_drop_login
    @login_name NVARCHAR(255),
    @cleanup_users BIT = 1
WITH ENCRYPTION
AS
BEGIN
	DECLARE @replica_server_name NVARCHAR(255)
	DECLARE @endpoint_url NVARCHAR(1024)
	DECLARE @fqdn NVARCHAR(1024)
	DECLARE @current_server NVARCHAR(255)
    DECLARE @start_pos INT
    DECLARE @end_pos INT
    -- 删除主实例各db中的同名user
    IF @cleanup_users = 1
    BEGIN
        exec master.dbo.sp_ape_cleanup_login_users @login_name
    END
	-- 声明游标
	DECLARE replica_cursor CURSOR STATIC FOR
	SELECT
	    replica_server_name,
	    endpoint_url
	FROM sys.availability_replicas WITH (NOLOCK)
	WHERE replica_server_name <> @@servername

	OPEN replica_cursor
	FETCH NEXT FROM replica_cursor INTO @replica_server_name, @endpoint_url
	WHILE @@FETCH_STATUS = 0
	BEGIN
        SET @start_pos  = CHARINDEX('//', @endpoint_url) + 2
        SET @end_pos  = CHARINDEX(':', @endpoint_url, @start_pos)
        IF @end_pos > 0
        BEGIN
            SET @fqdn = SUBSTRING(
                @endpoint_url,
                @start_pos,
                @end_pos - @start_pos
            )
        END
        ELSE
        BEGIN
            PRINT 'Warning: Invalid endpoint URL format for server ' + @replica_server_name
        END
	
	    DECLARE @lock_result_drop INT
	    EXEC @lock_result_drop = sp_getapplock
	        @Resource = @fqdn,
	        @LockMode = 'Exclusive',
	        @LockOwner = 'Session',
	        @LockTimeout = 60000
	    IF @lock_result_drop >= 0
	    BEGIN
	        BEGIN TRY
	            EXEC sp_ape_add_link_svr @POD_FQDN = @fqdn;
	            DECLARE @sql NVARCHAR(MAX)
	            DECLARE @remote_sql NVARCHAR(MAX)
	            DECLARE @login_literal NVARCHAR(1024)
	            EXECUTE AS LOGIN = 'sa';
	            SET @login_literal = N'N''' + REPLACE(@login_name, N'''', N'''''') + N''''
	            SET @remote_sql = N'USE [master];
	                IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ' + @login_literal + N')
	                BEGIN
	                    EXEC master.dbo.sp_ape_kill_login_sessions @login_name = ' + @login_literal + N';
	                    DROP LOGIN ' + QUOTENAME(@login_name) + N';
	                    EXEC master.dbo.sp_ape_cleanup_login_users @login_name = ' + @login_literal + N';
	                END'
	            SET @sql = N'EXEC(N''' + REPLACE(@remote_sql, N'''', N'''''')
	                + N''') AT ' + QUOTENAME(@fqdn) + N';';
	            EXEC(@sql);
	            EXEC sp_ape_remove_link_svr @POD_FQDN = @fqdn;
	        END TRY
	        BEGIN CATCH
	            EXEC sp_ape_remove_link_svr @POD_FQDN = @fqdn;
	            INSERT INTO msdb.dbo.ape_sync_login_log
	                (log_id, login_name, operation_type, message, is_succeeded)
	            VALUES
	                (NEWID(), @login_name, 'DROP_LOGIN',
	                 'Error dropping login on ' + @fqdn + ': ' + ERROR_MESSAGE(), 0)
	        END CATCH
	        EXEC sp_releaseapplock @Resource = @fqdn, @LockOwner = 'Session'
	    END
	    ELSE
	    BEGIN
	        INSERT INTO msdb.dbo.ape_sync_login_log
	            (log_id, login_name, operation_type, message, is_succeeded)
	        VALUES
	            (NEWID(), @login_name, 'DROP_LOGIN',
	             'Failed to acquire lock for ' + @fqdn + ', skipping', 0)
	    END

	    FETCH NEXT FROM replica_cursor INTO @replica_server_name, @endpoint_url
	END
	CLOSE replica_cursor
    DEALLOCATE replica_cursor
END
GO

IF OBJECT_ID('dbo.sp_ape_sync_svrrole') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_sync_svrrole
GO
CREATE PROCEDURE dbo.sp_ape_sync_svrrole
    @command NVARCHAR(255)
WITH ENCRYPTION
AS
BEGIN
	DECLARE @replica_server_name NVARCHAR(255)
	DECLARE @endpoint_url NVARCHAR(1024)
	DECLARE @fqdn NVARCHAR(1024)
	DECLARE @current_server NVARCHAR(255)
    DECLARE @start_pos INT
    DECLARE @end_pos INT
	-- 声明游标
	DECLARE replica_cursor CURSOR STATIC FOR
	SELECT
	    replica_server_name,
	    endpoint_url
	FROM sys.availability_replicas WITH (NOLOCK)
	WHERE replica_server_name <> @@servername

	OPEN replica_cursor
	FETCH NEXT FROM replica_cursor INTO @replica_server_name, @endpoint_url
	WHILE @@FETCH_STATUS = 0
	BEGIN
        SET @start_pos  = CHARINDEX('//', @endpoint_url) + 2
        SET @end_pos  = CHARINDEX(':', @endpoint_url, @start_pos)
        IF @end_pos > 0
        BEGIN
            SET @fqdn = SUBSTRING(
                @endpoint_url,
                @start_pos,
                @end_pos - @start_pos
            )
        END
        ELSE
        BEGIN
            PRINT 'Warning: Invalid endpoint URL format for server ' + @replica_server_name
        END
	
	    DECLARE @lock_result_role INT
	    EXEC @lock_result_role = sp_getapplock
	        @Resource = @fqdn,
	        @LockMode = 'Exclusive',
	        @LockOwner = 'Session',
	        @LockTimeout = 60000
	    IF @lock_result_role >= 0
	    BEGIN
	        BEGIN TRY
	            EXEC sp_ape_add_link_svr @POD_FQDN = @fqdn;
	            DECLARE @sql NVARCHAR(MAX)
	            EXECUTE AS LOGIN = 'sa';
	            SET @sql = N'EXEC(N''' + REPLACE(@command, N'''', N'''''')
	                + N''') AT ' + QUOTENAME(@fqdn) + N';';
	            EXEC(@sql);
	            EXEC sp_ape_remove_link_svr @POD_FQDN = @fqdn;
	        END TRY
	        BEGIN CATCH
	            EXEC sp_ape_remove_link_svr @POD_FQDN = @fqdn;
	            INSERT INTO msdb.dbo.ape_sync_login_log
	                (log_id, login_name, operation_type, message, is_succeeded)
	            VALUES
	                (NEWID(), NULL, 'SYNC_SVRROLE',
	                 'Error syncing server role to ' + @fqdn + ': ' + ERROR_MESSAGE(), 0)
	        END CATCH
	        EXEC sp_releaseapplock @Resource = @fqdn, @LockOwner = 'Session'
	    END
	    ELSE
	    BEGIN
	        INSERT INTO msdb.dbo.ape_sync_login_log
	            (log_id, login_name, operation_type, message, is_succeeded)
	        VALUES
	            (NEWID(), NULL, 'SYNC_SVRROLE',
	             'Failed to acquire lock for ' + @fqdn + ', skipping', 0)
	    END

	    FETCH NEXT FROM replica_cursor INTO @replica_server_name, @endpoint_url
	END
	CLOSE replica_cursor
    DEALLOCATE replica_cursor
END
GO

IF OBJECT_ID('dbo.sp_ape_fix_orphaned_users') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_fix_orphaned_users
GO
CREATE PROCEDURE dbo.sp_ape_fix_orphaned_users
WITH ENCRYPTION
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @db_name NVARCHAR(255)
    DECLARE @fix_sql NVARCHAR(MAX)
    DECLARE @fixed_count INT = 0

    DECLARE db_cursor CURSOR STATIC FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4
      AND name NOT IN ('master', 'tempdb', 'model', 'msdb')

    OPEN db_cursor
    FETCH NEXT FROM db_cursor INTO @db_name
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @fix_sql = N'USE ' + QUOTENAME(@db_name) + N';
                DECLARE @uname NVARCHAR(255)
                DECLARE orphan_cur CURSOR STATIC FOR
                SELECT dp.name
                FROM sys.database_principals dp
                LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
                WHERE dp.type IN (''S'', ''U'', ''G'')
                  AND dp.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'')
                  AND dp.name NOT LIKE ''##%''
                  AND dp.sid IS NOT NULL
                  AND dp.sid <> 0x00
                  AND sp.sid IS NULL
                  AND EXISTS (
                    SELECT 1 FROM sys.server_principals sp2
                    WHERE sp2.name = dp.name AND sp2.type IN (''S'', ''U'', ''G'')
                  )
                OPEN orphan_cur
                FETCH NEXT FROM orphan_cur INTO @uname
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    BEGIN TRY
                        EXEC(''ALTER USER ['' + @uname + ''] WITH LOGIN = ['' + @uname + '']'')
                    END TRY
                    BEGIN CATCH
                        PRINT ''Warning: Could not fix orphaned user '' + @uname + '' in ' + @db_name + ': '' + ERROR_MESSAGE()
                    END CATCH
                    FETCH NEXT FROM orphan_cur INTO @uname
                END
                CLOSE orphan_cur
                DEALLOCATE orphan_cur'
            EXEC sp_executesql @fix_sql
        END TRY
        BEGIN CATCH
            INSERT INTO msdb.dbo.ape_sync_login_log
                (log_id, login_name, operation_type, message, is_succeeded)
            VALUES
                (NEWID(), @db_name, 'FIX_ORPHAN',
                 'Error fixing orphaned users in ' + @db_name + ': ' + ERROR_MESSAGE(), 0)
        END CATCH

        FETCH NEXT FROM db_cursor INTO @db_name
    END
    CLOSE db_cursor
    DEALLOCATE db_cursor
END
GO

IF OBJECT_ID('dbo.sp_ape_export_agent_jobs') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_export_agent_jobs
GO
CREATE PROCEDURE dbo.sp_ape_export_agent_jobs
WITH ENCRYPTION
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @job_name NVARCHAR(255)
    DECLARE @description NVARCHAR(512)
    DECLARE @enabled INT
    DECLARE @step_name NVARCHAR(255)
    DECLARE @step_command NVARCHAR(MAX)
    DECLARE @subsystem NVARCHAR(40)
    DECLARE @database_name NVARCHAR(255)
    DECLARE @step_id INT

    DECLARE job_cursor CURSOR STATIC FOR
    SELECT j.name, ISNULL(j.description, N''), j.enabled
    FROM msdb.dbo.sysjobs j
    WHERE j.name NOT LIKE 'HADR_%'
      AND j.name NOT LIKE 'syspolicy_%'
      AND j.date_created > DATEADD(MINUTE, 30, (
          SELECT create_date FROM sys.databases WHERE name = 'msdb'
      ))

    OPEN job_cursor
    FETCH NEXT FROM job_cursor INTO @job_name, @description, @enabled
    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT 'IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N''' + REPLACE(@job_name, '''', '''''') + ''')'
        PRINT 'BEGIN'
        PRINT '  EXEC msdb.dbo.sp_add_job @job_name = N''' + REPLACE(@job_name, '''', '''''') + ''', @description = N''' + REPLACE(@description, '''', '''''') + ''', @enabled = ' + CAST(@enabled AS NVARCHAR(1))
        PRINT '  EXEC msdb.dbo.sp_add_jobserver @job_name = N''' + REPLACE(@job_name, '''', '''''') + ''''

        DECLARE step_cursor CURSOR STATIC FOR
        SELECT step_id, step_name, command, subsystem, ISNULL(database_name, N'master')
        FROM msdb.dbo.sysjobsteps
        WHERE job_id = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = @job_name)
        ORDER BY step_id

        OPEN step_cursor
        FETCH NEXT FROM step_cursor INTO @step_id, @step_name, @step_command, @subsystem, @database_name
        WHILE @@FETCH_STATUS = 0
        BEGIN
            PRINT '  EXEC msdb.dbo.sp_add_jobstep @job_name = N''' + REPLACE(@job_name, '''', '''''') + ''', @step_id = ' + CAST(@step_id AS NVARCHAR(10)) + ', @step_name = N''' + REPLACE(@step_name, '''', '''''') + ''', @subsystem = N''' + @subsystem + ''', @command = N''' + REPLACE(ISNULL(@step_command, N''), '''', '''''') + ''', @database_name = N''' + REPLACE(@database_name, '''', '''''') + ''''
            FETCH NEXT FROM step_cursor INTO @step_id, @step_name, @step_command, @subsystem, @database_name
        END
        CLOSE step_cursor
        DEALLOCATE step_cursor

        PRINT 'END'
        PRINT 'GO'
        FETCH NEXT FROM job_cursor INTO @job_name, @description, @enabled
    END
    CLOSE job_cursor
    DEALLOCATE job_cursor
END
GO


use [msdb]
GO
-- 创建消息类型
IF NOT EXISTS (
    SELECT *
    FROM sys.service_message_types
    WHERE name = '//ApeCloud/LoginSyncRequestMessage'
)
BEGIN
    CREATE MESSAGE TYPE [//ApeCloud/LoginSyncRequestMessage]
    VALIDATION = WELL_FORMED_XML;
END
GO

IF NOT EXISTS (
    SELECT *
    FROM sys.service_message_types
    WHERE name = '//ApeCloud/LoginSyncRequestReplyMessage'
)
BEGIN
    CREATE MESSAGE TYPE [//ApeCloud/LoginSyncRequestReplyMessage]
    VALIDATION = WELL_FORMED_XML;
END
GO

-- 创建服务契约
IF NOT EXISTS (
    SELECT *
    FROM sys.service_contracts
    WHERE name = '//ApeCloud/LoginSyncContract'
)
BEGIN
CREATE CONTRACT [//ApeCloud/LoginSyncContract]
(
    [//ApeCloud/LoginSyncRequestMessage] SENT BY INITIATOR,
    [//ApeCloud/LoginSyncRequestReplyMessage] SENT BY TARGET
);
END
GO

-- 创建队列
IF NOT EXISTS (
    SELECT *
    FROM sys.service_queues
    WHERE name = 'ApeSyncLoginTarget'
)
BEGIN
    CREATE QUEUE ApeSyncLoginTarget WITH STATUS = ON
END
GO

IF NOT EXISTS (
    SELECT *
    FROM sys.service_queues
    WHERE name = 'ApeSyncLoginInitiator'
)
BEGIN
    CREATE QUEUE ApeSyncLoginInitiator WITH STATUS = ON
END
GO

-- 创建服务
IF EXISTS (
    SELECT *
    FROM sys.services
    WHERE
        name = '//ApeCloud/LoginSyncTarget'
)
BEGIN
    DROP SERVICE [//ApeCloud/LoginSyncTarget]
END
GO
BEGIN
CREATE SERVICE [//ApeCloud/LoginSyncTarget]
ON QUEUE ApeSyncLoginTarget ([//ApeCloud/LoginSyncContract]);
END
GO


IF EXISTS (
    SELECT *
    FROM sys.services
    WHERE
        name = '//ApeCloud/LoginSyncInitiator'
)
BEGIN
    DROP SERVICE [//ApeCloud/LoginSyncInitiator]
END
GO
BEGIN
CREATE SERVICE [//ApeCloud/LoginSyncInitiator]
ON QUEUE ApeSyncLoginInitiator;
END
GO

IF OBJECT_ID('dbo.sp_ape_login_role_sync_message') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_login_role_sync_message
GO

CREATE PROCEDURE dbo.sp_ape_login_role_sync_message
    @login_name NVARCHAR(255),
    @command NVARCHAR(max) = NULL,
    @operation_type NVARCHAR(20)
WITH ENCRYPTION
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @message_body XML,
            @conversation_handle UNIQUEIDENTIFIER;

    -- 验证操作类型
    IF @operation_type NOT IN ('CREATE_LOGIN', 'DROP_LOGIN','ALTER_SERVER_ROLE','ALTER_LOGIN')
    BEGIN
        DECLARE @error_message NVARCHAR(4000)
        SET @error_message = 'Invalid operation type: ' + ISNULL(@operation_type, 'NULL')

        INSERT INTO msdb.dbo.ape_sync_login_log
            (log_id, login_name, operation_type, message, is_succeeded)
        VALUES
            (NEWID(), @login_name, @operation_type, @error_message, 0)

        RAISERROR (@error_message, 16, 1)
        RETURN
    END

    SET @message_body = (
        SELECT @login_name AS LoginName,
               @operation_type AS OperationType,
               @command AS Command
        FOR XML PATH(''), ROOT('LoginSync')
    );

    BEGIN DIALOG CONVERSATION @conversation_handle
    FROM SERVICE [//ApeCloud/LoginSyncInitiator]
    TO SERVICE '//ApeCloud/LoginSyncTarget'
    ON CONTRACT [//ApeCloud/LoginSyncContract]
    WITH ENCRYPTION = OFF;

    SEND ON CONVERSATION @conversation_handle
    MESSAGE TYPE [//ApeCloud/LoginSyncRequestMessage](@message_body);

    END CONVERSATION @conversation_handle;
END;
GO

use [master]
GO

IF EXISTS (
    SELECT *
    FROM sys.server_triggers
    WHERE
        name = '_\$\$_tr_\$\$_ape_alter_login'
)
BEGIN
    DROP TRIGGER _\$\$_tr_\$\$_ape_alter_login ON ALL SERVER;
END;
GO


CREATE TRIGGER _\$\$_tr_\$\$_ape_alter_login ON ALL SERVER
WITH EXEC AS 'sa',
ENCRYPTION
AFTER ALTER_LOGIN AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @role NVARCHAR(60), @ag NVARCHAR(128);
    EXEC master.dbo.sp_ape_get_ag_role @out_role_desc = @role OUTPUT, @out_ag_name = @ag OUTPUT
    IF @role != 'PRIMARY'
    BEGIN
        INSERT INTO msdb.dbo.ape_sync_login_log
            (log_id, message, is_succeeded)
        VALUES
            (NEWID(), 'Event: Skip processing on non-primary node. Current role: ' + @role, 1);
        RETURN;
    END


    DECLARE @login_name NVARCHAR(255),
            @event_data XML,
            @sql NVARCHAR(MAX);
    SET @event_data = EVENTDATA();
    SET @login_name = (
            SELECT
                EVENTDATA().value(
                    '(/EVENT_INSTANCE/ObjectName)[1]',
                    'nvarchar(255)'
                )
        );

    IF @login_name IS NOT NULL
    BEGIN
        SET @sql = N'EXEC msdb.dbo.sp_ape_login_role_sync_message @login_name = '''
                   + REPLACE(@login_name, '''', '''''') + ''', @operation_type = ''ALTER_LOGIN'';';
        EXEC sp_executesql @sql;
    END
END
GO

IF EXISTS (
    SELECT *
    FROM sys.server_triggers
    WHERE
        name = '_\$\$_tr_\$\$_ape_create_login'
)
BEGIN
    DROP TRIGGER _\$\$_tr_\$\$_ape_create_login ON ALL SERVER;
END;
GO


CREATE TRIGGER _\$\$_tr_\$\$_ape_create_login ON ALL SERVER
WITH EXEC AS 'sa',
ENCRYPTION
AFTER CREATE_LOGIN AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @role NVARCHAR(60), @ag NVARCHAR(128);
    EXEC master.dbo.sp_ape_get_ag_role @out_role_desc = @role OUTPUT, @out_ag_name = @ag OUTPUT
    IF @role != 'PRIMARY'
    BEGIN
        INSERT INTO msdb.dbo.ape_sync_login_log
            (log_id, message, is_succeeded)
        VALUES
            (NEWID(), 'Event: Skip processing on non-primary node. Current role: ' + @role, 1);
        RETURN;
    END

    DECLARE @login_name NVARCHAR(255),
            @sql NVARCHAR(MAX);

    SET @login_name = (
            SELECT
                EVENTDATA().value(
                    '(/EVENT_INSTANCE/ObjectName)[1]',
                    'nvarchar(255)'
                )
        );

    IF @login_name IS NOT NULL
    BEGIN
        SET @sql = N'EXEC msdb.dbo.sp_ape_login_role_sync_message @login_name = '''
                   + REPLACE(@login_name, '''', '''''') + ''', @operation_type = ''CREATE_LOGIN'';';
        EXEC sp_executesql @sql;
    END
END
GO


IF EXISTS (
    SELECT *
    FROM sys.server_triggers
    WHERE
        name = '_\$\$_tr_\$\$_ape_drop_login'
)
BEGIN
    DROP TRIGGER _\$\$_tr_\$\$_ape_drop_login ON ALL SERVER;
END;
GO


CREATE TRIGGER _\$\$_tr_\$\$_ape_drop_login ON ALL SERVER
WITH EXEC AS 'sa',
ENCRYPTION
AFTER DROP_LOGIN AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @role NVARCHAR(60), @ag NVARCHAR(128);
    EXEC master.dbo.sp_ape_get_ag_role @out_role_desc = @role OUTPUT, @out_ag_name = @ag OUTPUT
    IF @role != 'PRIMARY'
    BEGIN
        INSERT INTO msdb.dbo.ape_sync_login_log
            (log_id, message, is_succeeded)
        VALUES
            (NEWID(), 'Event: Skip processing on non-primary node. Current role: ' + @role, 1);
        RETURN;
    END

    DECLARE @login_name NVARCHAR(255),
            @sql NVARCHAR(MAX);

    SET @login_name = (
            SELECT
                EVENTDATA().value(
                    '(/EVENT_INSTANCE/ObjectName)[1]',
                    'nvarchar(255)'
                )
        );

    IF @login_name IS NOT NULL
    BEGIN
        SET @sql = N'EXEC msdb.dbo.sp_ape_login_role_sync_message @login_name = '''
                   + REPLACE(@login_name, '''', '''''') + ''', @operation_type = ''DROP_LOGIN'';';
        EXEC sp_executesql @sql;
    END
END
GO


IF EXISTS (
    SELECT *
    FROM sys.server_triggers
    WHERE
        name = '_\$\$_tr_\$\$_ape_alter_server_role'
)
BEGIN
    DROP TRIGGER _\$\$_tr_\$\$_ape_alter_server_role ON ALL SERVER;
END;
GO

CREATE TRIGGER _\$\$_tr_\$\$_ape_alter_server_role ON ALL SERVER
WITH EXEC AS 'sa',
ENCRYPTION
AFTER ADD_SERVER_ROLE_MEMBER,DROP_SERVER_ROLE_MEMBER AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @role NVARCHAR(60), @ag NVARCHAR(128);
        EXEC master.dbo.sp_ape_get_ag_role @out_role_desc = @role OUTPUT, @out_ag_name = @ag OUTPUT
        IF @role != 'PRIMARY'
        BEGIN
            INSERT INTO msdb.dbo.ape_sync_login_log
                (log_id, message, is_succeeded)
            VALUES
                (NEWID(), 'Event: Skip processing on non-primary node. Current role: ' + @role, 1);
            RETURN;
        END

        DECLARE @login_name NVARCHAR(255),
                @role_name NVARCHAR(255),
                @sql NVARCHAR(MAX),
                @command_text NVARCHAR(MAX);

        SET @command_text = EVENTDATA().value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)');

        SET @login_name = SUBSTRING(
            @command_text,
            CHARINDEX('MEMBER', @command_text) + 7,
            CASE
                WHEN CHARINDEX(']', @command_text, CHARINDEX('MEMBER', @command_text)) > 0
                THEN CHARINDEX(']', @command_text, CHARINDEX('MEMBER', @command_text)) - (CHARINDEX('MEMBER', @command_text) + 7)
                ELSE LEN(@command_text) - (CHARINDEX('MEMBER', @command_text) + 7)
            END
        );

        SET @login_name = REPLACE(REPLACE(@login_name, '[', ''), ']', '');
        SET @role_name = EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'nvarchar(255)');

        IF @command_text is NOT NULL
        BEGIN
            SET @sql = N'EXEC msdb.dbo.sp_ape_login_role_sync_message @login_name = '''
                    + REPLACE(@login_name, '''', '''''') + ''', @command = N''' + REPLACE(@command_text, '''', '''''') + ''', @operation_type = ''ALTER_SERVER_ROLE'';';
            EXEC sp_executesql @sql;
        END

    END TRY
    BEGIN CATCH
        INSERT INTO msdb.dbo.ape_sync_login_log
            (log_id, login_name, operation_type, message, is_succeeded)
        VALUES
            (NEWID(),
             ISNULL(@login_name, 'UNKNOWN'),
             'ALTER_SERVER_ROLE_ERROR',
             'Error: ' + ERROR_MESSAGE() + ' Line: ' + CAST(ERROR_LINE() AS NVARCHAR(10)),
             0);
    END CATCH
END
GO




use [msdb]
GO

IF OBJECT_ID('dbo.ape_sync_login_log') IS NOT NULL
    DROP TABLE dbo.ape_sync_login_log
GO

CREATE TABLE dbo.ape_sync_login_log (
    log_id UNIQUEIDENTIFIER NOT NULL,
    login_name NVARCHAR(255) NULL,
    operation_type NVARCHAR(20) NULL,
    message VARCHAR(1024) NULL,
    source_server NVARCHAR(255) DEFAULT @@SERVERNAME,
    is_succeeded BIT DEFAULT 1,
    created_at DATETIME DEFAULT GETDATE()
)
GO

IF OBJECT_ID('dbo.ape_sync_login_dead_letter') IS NULL
BEGIN
    CREATE TABLE dbo.ape_sync_login_dead_letter (
        dead_letter_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        login_name NVARCHAR(255) NULL,
        operation_type NVARCHAR(20) NULL,
        command NVARCHAR(MAX) NULL,
        error_message NVARCHAR(4000) NULL,
        retry_count INT DEFAULT 0,
        created_at DATETIME DEFAULT GETDATE()
    )
END
GO

IF OBJECT_ID('dbo.sp_ape_process_sync_login_and_role') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_process_sync_login_and_role
GO

CREATE PROCEDURE sp_ape_process_sync_login_and_role
WITH EXECUTE AS self,
ENCRYPTION
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE
            @conversation_handle UNIQUEIDENTIFIER,
            @message_body XML,
            @message_type_name NVARCHAR(1024),
            @login_name NVARCHAR(255),
            @operation_type NVARCHAR(20),
            @command NVARCHAR(MAX);

        RECEIVE TOP(1)
            @conversation_handle = conversation_handle,
            @message_body = message_body,
            @message_type_name = message_type_name
        FROM ApeSyncLoginTarget

        IF @@ROWCOUNT = 0
        BEGIN
            INSERT INTO msdb.dbo.ape_sync_login_log
                (log_id, message, is_succeeded)
            VALUES
                (NEWID(), 'Event: No messages found in queue', 1);
            RETURN;
        END

        IF @message_type_name = '//ApeCloud/LoginSyncRequestMessage'
        BEGIN
            SET @login_name = @message_body.value('(/LoginSync/LoginName)[1]', 'NVARCHAR(255)');
            SET @operation_type = @message_body.value('(/LoginSync/OperationType)[1]', 'NVARCHAR(20)');
            SET @command = @message_body.value('(/LoginSync/Command)[1]', 'NVARCHAR(MAX)');

            INSERT INTO msdb.dbo.ape_sync_login_log
                (log_id, login_name, operation_type, message)
            VALUES
                (@conversation_handle, @login_name, @operation_type, 'Event: start sync process');

            EXECUTE AS LOGIN = 'sa';
            IF @operation_type = 'CREATE_LOGIN'
                EXEC master.dbo.sp_ape_sync_login @login_name = @login_name;
            ELSE IF @operation_type = 'DROP_LOGIN'
                EXEC master.dbo.sp_ape_sync_drop_login @login_name = @login_name;
            ELSE IF @operation_type = 'ALTER_SERVER_ROLE'
                EXEC master.dbo.sp_ape_sync_svrrole @command=@command;
            ELSE IF @operation_type = 'ALTER_LOGIN'
            BEGIN
                EXEC master.dbo.sp_ape_sync_drop_login @login_name = @login_name, @cleanup_users = 0;
                EXEC master.dbo.sp_ape_sync_login @login_name = @login_name;
            END

            IF @command IS NOT NULL
            BEGIN
                INSERT INTO msdb.dbo.ape_sync_login_log
                    (log_id, login_name, operation_type, message)
                VALUES
                    (@conversation_handle, @login_name, @operation_type, 'Event: Processing login operation success'+ @command) ;
            END
            ELSE
            BEGIN
                INSERT INTO msdb.dbo.ape_sync_login_log
                    (log_id, login_name, operation_type, message)
                VALUES
                    (@conversation_handle, @login_name, @operation_type, 'Event: Processing login operation success') ;
            END


             END CONVERSATION @conversation_handle;
        END
        ELSE IF @message_type_name = 'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
        BEGIN
            INSERT INTO msdb.dbo.ape_sync_login_log
                (log_id, message)
            VALUES
                (@conversation_handle, 'Event: Service Broker system dialog ended');
            END CONVERSATION @conversation_handle;
        END
    END TRY
    BEGIN CATCH
        IF @conversation_handle IS NOT NULL
        BEGIN
            DECLARE @error_msg NVARCHAR(4000) = ERROR_MESSAGE()
            DECLARE @error_line_num NVARCHAR(10) = CAST(ERROR_LINE() AS NVARCHAR(10))
            DECLARE @max_retries INT = 3

            INSERT INTO msdb.dbo.ape_sync_login_log
                (log_id, login_name, operation_type, message, is_succeeded)
            VALUES
                (@conversation_handle, @login_name, @operation_type,
                 'Event: Error occurred - ' + @error_msg + ' Line: ' + @error_line_num, 0);

            END CONVERSATION @conversation_handle;

            -- Count recent failures for this login+operation to decide retry vs dead letter
            DECLARE @failure_count INT
            SELECT @failure_count = COUNT(*)
            FROM msdb.dbo.ape_sync_login_log
            WHERE login_name = @login_name
              AND operation_type = @operation_type
              AND is_succeeded = 0
              AND created_at > DATEADD(MINUTE, -10, GETDATE())

            IF @failure_count < @max_retries AND @login_name IS NOT NULL
            BEGIN
                -- Re-enqueue the message for retry
                EXEC msdb.dbo.sp_ape_login_role_sync_message
                    @login_name = @login_name,
                    @command = @command,
                    @operation_type = @operation_type

                INSERT INTO msdb.dbo.ape_sync_login_log
                    (log_id, login_name, operation_type, message, is_succeeded)
                VALUES
                    (NEWID(), @login_name, @operation_type,
                     'Event: Re-enqueued for retry (attempt ' + CAST(@failure_count + 1 AS NVARCHAR(5)) + '/' + CAST(@max_retries AS NVARCHAR(5)) + ')', 1)
            END
            ELSE IF @login_name IS NOT NULL
            BEGIN
                -- Max retries exceeded, move to dead letter
                INSERT INTO msdb.dbo.ape_sync_login_dead_letter
                    (login_name, operation_type, command, error_message, retry_count)
                VALUES
                    (@login_name, @operation_type, @command, @error_msg, @failure_count)

                INSERT INTO msdb.dbo.ape_sync_login_log
                    (log_id, login_name, operation_type, message, is_succeeded)
                VALUES
                    (NEWID(), @login_name, @operation_type,
                     'DEAD LETTER: Max retries exceeded (' + CAST(@failure_count AS NVARCHAR(5)) + '). Last error: ' + @error_msg, 0)
            END
        END
    END CATCH
END
GO

-- 绑定队列激活处理过程
use [msdb]
GO
ALTER QUEUE ApeSyncLoginTarget WITH ACTIVATION (
    STATUS = ON,
    PROCEDURE_NAME = sp_ape_process_sync_login_and_role,
    MAX_QUEUE_READERS = 4,
    EXECUTE AS OWNER
)
GO
EOF
