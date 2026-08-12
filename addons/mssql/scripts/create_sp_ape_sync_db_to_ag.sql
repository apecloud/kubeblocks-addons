
/**
* This script will create a server-level target to add database to ag.
*
**/

/** 
*  PROCEDURE sp_ape_sync_db_to_ag will do the following:
* 1) Switch the database from 'SIMPLE' to 'FULL' recovery.
* 2) Perform a full backup to the default backup path for the server.
* 3) Add the database to the availability group and initialize AlwaysOn.
*
**/
SET QUOTED_IDENTIFIER ON
go

USE [master]
go
IF OBJECT_ID('dbo.sp_ape_sync_db_to_ag') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_sync_db_to_ag
go

CREATE PROCEDURE sp_ape_sync_db_to_ag 
    @AddToGroupName SYSNAME,
    @DatabaseName SYSNAME
WITH ENCRYPTION AS 
BEGIN
    IF @DatabaseName IS NULL OR @AddToGroupName IS NULL
        THROW 50000, 'Database and availability group names are required.', 1;

    -- The audit suffix must still fit in SQL Server's 128-character identifier limit.
    IF LEN(@DatabaseName) > 115
        THROW 50001, 'Database name is too long to create its audit specification.', 1;

    DECLARE @AuditName SYSNAME = @DatabaseName + N'DatabaseAudit';
    DECLARE @QuotedDatabaseName NVARCHAR(258) = QUOTENAME(@DatabaseName);
    DECLARE @QuotedGroupName NVARCHAR(258) = QUOTENAME(@AddToGroupName);
    DECLARE @QuotedAuditName NVARCHAR(258) = QUOTENAME(@AuditName);

    IF @QuotedDatabaseName IS NULL OR @QuotedGroupName IS NULL OR @QuotedAuditName IS NULL
        THROW 50002, 'Database, availability group, or audit name cannot be quoted.', 1;

    DECLARE @audit_sql NVARCHAR(MAX) =
        N'USE ' + @QuotedDatabaseName + N';
            IF NOT EXISTS (
                SELECT 1
                FROM sys.database_audit_specifications 
                WHERE name = @AuditName
            )
            BEGIN
                CREATE DATABASE AUDIT SPECIFICATION ' + @QuotedAuditName + N'
                FOR SERVER AUDIT [kbAuditLog]
                ADD (SELECT, INSERT, UPDATE, DELETE ON DATABASE::' + @QuotedDatabaseName + N' BY PUBLIC)
                WITH (STATE = ON);
            END';
    EXEC sys.sp_executesql @audit_sql, N'@AuditName SYSNAME', @AuditName = @AuditName;

    -- Switch the database to FULL recovery if it was created without it.
    IF (
        SELECT
            recovery_model
        FROM
            sys.databases
        WHERE
            name = @DatabaseName
    ) <> 1 
        BEGIN 
            PRINT 'Changing recovery model to FULL';
            DECLARE @ModeChange NVARCHAR(MAX) = N'ALTER DATABASE ' + @QuotedDatabaseName + N' SET RECOVERY FULL WITH NO_WAIT';
            EXEC sys.sp_executesql @ModeChange;
        END;
    ELSE 
        BEGIN 
            PRINT 'Database is already in FULL recovery mode.'
        END;

  
    DECLARE @TargetFile NVARCHAR(2048) =
        N'/var/opt/mssql/' + CONVERT(NVARCHAR(64), HASHBYTES('SHA2_256', @DatabaseName), 2) + N'.bak';
    
    -- Perform initial backup of the database - Will overwrite any existing file.
    PRINT ' Backing up initial database to ' + @TargetFile;
    DECLARE @BackupCommand NVARCHAR(MAX) = N'BACKUP DATABASE ' + @QuotedDatabaseName + N' TO DISK = @TargetFile';
    PRINT ' Command: ' + @BackupCommand
    EXEC sys.sp_executesql @BackupCommand, N'@TargetFile NVARCHAR(2048)', @TargetFile = @TargetFile;

    -- Add the database to the availability group.
    PRINT ' Joining database to availability group '
    DECLARE @JoinToAG NVARCHAR(MAX) = N'ALTER AVAILABILITY GROUP ' + @QuotedGroupName + N' ADD DATABASE ' + @QuotedDatabaseName;
    EXEC sys.sp_executesql @JoinToAG;
END;
GO

IF EXISTS (
    SELECT *
    FROM sys.server_triggers
    WHERE
        name = '_$$_tr_$$_ape_create_database'
) 
BEGIN
    DROP TRIGGER _$$_tr_$$_ape_create_database ON ALL SERVER;
END;
GO

CREATE TRIGGER _$$_tr_$$_ape_create_database ON ALL SERVER 
WITH EXEC AS 'sa',
ENCRYPTION
AFTER CREATE_DATABASE AS 
BEGIN
    SET NOCOUNT ON;
    DECLARE @role NVARCHAR(60), @ag NVARCHAR(128);
    EXEC master.dbo.sp_ape_get_ag_role @out_role_desc = @role OUTPUT, @out_ag_name = @ag OUTPUT
    IF @role != 'PRIMARY'
    BEGIN
        INSERT INTO msdb.dbo.ape_sync_db_log 
            (log_id, message, is_succeeded)
        VALUES 
            (NEWID(), 'Event: Skip processing on non-primary node. Current role: ' + @role, 1);
        RETURN;
    END      

    DECLARE @DatabaseName SYSNAME;
    DECLARE @AddToGroupName SYSNAME;
    DECLARE @JobName NVARCHAR(128);
    DECLARE @JobDesc NVARCHAR(512);
    DECLARE @JobCommand NVARCHAR(4000);
    SELECT TOP 1 @AddToGroupName = [AG].[name] FROM sys.availability_groups AS [AG]
    SET @DatabaseName = (
            SELECT
                EVENTDATA().value(
                    '(/EVENT_INSTANCE/DatabaseName)[1]',
                    'nvarchar(128)'
                )
        );

    -- We have to use a queue since initial backups cant happen during the CREATE DATABASE trigger firing.
    IF @AddToGroupName IS NOT NULL 
        BEGIN 
            SET @JobName = N'HADR_Add_' + CONVERT(NVARCHAR(36), NEWID());
            SET @JobDesc = N'Add database ' + @DatabaseName + N' to availability group ' + @AddToGroupName;
            SET @JobCommand =
                N'EXEC master.dbo.sp_ape_sync_db_to_ag ' +
                N'@AddToGroupName = N' + QUOTENAME(@AddToGroupName, '''') +
                N', @DatabaseName = N' + QUOTENAME(@DatabaseName, '''') + N';';
            EXEC msdb.dbo.sp_add_job
            @job_name = @JobName,
            @description = @JobDesc,
            @delete_level = 1; -- 作业完成后自动删除
            
            EXEC msdb.dbo.sp_add_jobstep
            @job_name = @JobName,
            @step_name = N'Execute HADR Process',
            @subsystem = N'TSQL',
            @command = @JobCommand;

            EXEC msdb.dbo.sp_add_jobserver
            @job_name = @JobName

            EXEC msdb.dbo.sp_start_job @job_name = @JobName;
            PRINT 'Adding database ' + @DatabaseName +' to available group: ' + @AddToGroupName;
            PRINT 'Job name: ' + @JobName;
        END;
END;
GO

use master
go
IF OBJECT_ID('dbo.sp_ape_drop_db_sync') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_drop_db_sync
GO
CREATE PROCEDURE sp_ape_drop_db_sync
    @db_name SYSNAME
WITH ENCRYPTION
AS
BEGIN
    EXECUTE AS LOGIN =  'sa';
	IF @db_name IS NULL OR @db_name = N''
	    THROW 50001, 'Database name is required.', 1;
		DECLARE @QuotedDatabaseName NVARCHAR(258) = QUOTENAME(@db_name);
	IF @QuotedDatabaseName IS NULL
	    THROW 50001, 'Database name cannot be quoted.', 1;
	DECLARE @replica_server_name NVARCHAR(255)
	DECLARE @endpoint_url NVARCHAR(1024)
	DECLARE @fqdn NVARCHAR(1024)
	DECLARE @QuotedLinkedServer NVARCHAR(258)
	DECLARE @current_server NVARCHAR(255)
    DECLARE @start_pos INT
    DECLARE @end_pos INT
	DECLARE @remote_sql NVARCHAR(MAX)
	DECLARE @sql NVARCHAR(MAX)

	-- 声明游标
	DECLARE ape_db_replica_cursor CURSOR STATIC FOR 
	SELECT 
	    replica_server_name,
	    endpoint_url
	FROM sys.availability_replicas WITH (NOLOCK)
	WHERE replica_server_name <> @@servername

	OPEN ape_db_replica_cursor
	FETCH NEXT FROM ape_db_replica_cursor INTO @replica_server_name, @endpoint_url
	WHILE @@FETCH_STATUS = 0
	BEGIN
	    SET @fqdn = NULL
	    SET @QuotedLinkedServer = NULL
        SET @start_pos  = CHARINDEX('//', @endpoint_url) + 2
        SET @end_pos  = CHARINDEX(':', @endpoint_url, @start_pos)
        IF @end_pos > @start_pos
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
		    SET @QuotedLinkedServer = QUOTENAME(@fqdn);
	    IF @fqdn IS NULL OR @QuotedLinkedServer IS NULL
	        THROW 50002, 'Linked-server endpoint is invalid or too long.', 1;
	    EXEC sp_ape_add_link_svr @POD_FQDN = @fqdn;
        DECLARE @retry_count INT = 6
        BEGIN TRY
	        SET @remote_sql =
	            N'USE master;' +
	            N'RESTORE DATABASE ' + @QuotedDatabaseName + N' WITH RECOVERY;' +
	            N'ALTER DATABASE ' + @QuotedDatabaseName + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' +
	            N'DROP DATABASE ' + @QuotedDatabaseName + N';'
	        SET @sql = N'EXEC (N''' + REPLACE(@remote_sql, N'''', N'''''') +
	            N''') AT ' + @QuotedLinkedServer + N';';
            EXEC(@sql);
        END TRY
        BEGIN CATCH
            INSERT INTO msdb.dbo.ape_sync_db_log 
                        (log_id, db_name, operation_type, message, is_succeeded)
            VALUES 
                        (NEWID(), @db_name, 'DROP_DATABASE', 
                        'Failed to drop database in' + @fqdn + '. Error: ' + ERROR_MESSAGE(), 0)
        END CATCH
        EXEC sp_ape_remove_link_svr @POD_FQDN = @fqdn;
	    FETCH NEXT FROM ape_db_replica_cursor INTO @replica_server_name, @endpoint_url
	END
	CLOSE ape_db_replica_cursor
    DEALLOCATE ape_db_replica_cursor
END
GO


use [msdb]
GO
-- 创建消息类型
IF NOT EXISTS (
    SELECT * 
    FROM sys.service_message_types 
    WHERE name = '//ApeCloud/DBSyncRequestMessage'
)
BEGIN
    CREATE MESSAGE TYPE [//ApeCloud/DBSyncRequestMessage]
    VALIDATION = WELL_FORMED_XML;
END
GO


-- 创建服务契约
IF NOT EXISTS (
    SELECT * 
    FROM sys.service_contracts 
    WHERE name = '//ApeCloud/DBSyncContract'
)        
BEGIN
CREATE CONTRACT [//ApeCloud/DBSyncContract]
(
    [//ApeCloud/DBSyncRequestMessage] SENT BY INITIATOR
);
END
GO

-- 创建队列
IF NOT EXISTS (
    SELECT *
    FROM sys.service_queues
    WHERE name = 'ApeSyncDBTarget'
)
BEGIN
    CREATE QUEUE ApeSyncDBTarget WITH STATUS = ON
END
GO

IF NOT EXISTS (
    SELECT *
    FROM sys.service_queues
    WHERE name = 'ApeSyncDBInitiator'
)
BEGIN
    CREATE QUEUE ApeSyncDBInitiator WITH STATUS = ON
END
GO

-- 创建服务
IF EXISTS (
    SELECT *
    FROM sys.services
    WHERE
        name = '//ApeCloud/DBSyncTarget'
)
BEGIN
    DROP SERVICE [//ApeCloud/DBSyncTarget]
END
GO
BEGIN
CREATE SERVICE [//ApeCloud/DBSyncTarget]
ON QUEUE ApeSyncDBTarget ([//ApeCloud/DBSyncContract]);
END
GO


IF EXISTS (
    SELECT *
    FROM sys.services
    WHERE
        name = '//ApeCloud/DBSyncInitiator'
)
BEGIN
    DROP SERVICE [//ApeCloud/DBSyncInitiator]
END
GO
BEGIN
CREATE SERVICE [//ApeCloud/DBSyncInitiator]
ON QUEUE ApeSyncDBInitiator;
END
GO

IF OBJECT_ID('dbo.sp_ape_db_sync_message') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_db_sync_message
GO
    
CREATE PROCEDURE dbo.sp_ape_db_sync_message
    @db_name SYSNAME,
    @operation_type NVARCHAR(20)
WITH ENCRYPTION
AS
BEGIN
    SET NOCOUNT ON;
	IF @db_name IS NULL OR @db_name = N''
	    THROW 50003, 'Database name is required.', 1;
    DECLARE @message_body XML,
            @conversation_handle UNIQUEIDENTIFIER;

    -- 验证操作类型
    IF @operation_type NOT IN ('DROP_DATABASE')
    BEGIN
        DECLARE @error_message NVARCHAR(4000)
        SET @error_message = 'Invalid operation type: ' + ISNULL(@operation_type, 'NULL')
        
        INSERT INTO msdb.dbo.ape_sync_db_log 
            (log_id, db_name, operation_type, message, is_succeeded)
        VALUES 
            (NEWID(), @db_name, @operation_type, @error_message, 0)
            
        RAISERROR (@error_message, 16, 1)
        RETURN
    END

    SET @message_body = (
        SELECT @db_name AS DBName,
               @operation_type AS OperationType
        FOR XML PATH(''), ROOT('DBSync')
    );

    BEGIN DIALOG CONVERSATION @conversation_handle
    FROM SERVICE [//ApeCloud/DBSyncInitiator]
    TO SERVICE '//ApeCloud/DBSyncTarget'
    ON CONTRACT [//ApeCloud/DBSyncContract]
    WITH ENCRYPTION = OFF;

    SEND ON CONVERSATION @conversation_handle
    MESSAGE TYPE [//ApeCloud/DBSyncRequestMessage](@message_body);

    END CONVERSATION @conversation_handle;
END;
GO

use [master]
GO

IF EXISTS (
    SELECT *
    FROM sys.server_triggers
    WHERE
        name = '_$$_tr_$$_ape_drop_db'
) 
BEGIN
    DROP TRIGGER _$$_tr_$$_ape_drop_db ON ALL SERVER;
END;
GO


CREATE TRIGGER _$$_tr_$$_ape_drop_db ON ALL SERVER 
WITH EXEC AS 'sa',
ENCRYPTION
AFTER DROP_DATABASE AS 
BEGIN
    SET NOCOUNT ON;
    DECLARE @role NVARCHAR(60), @ag NVARCHAR(128);
    EXEC master.dbo.sp_ape_get_ag_role @out_role_desc = @role OUTPUT, @out_ag_name = @ag OUTPUT
    IF @role != 'PRIMARY'
    BEGIN
        INSERT INTO msdb.dbo.ape_sync_db_log 
            (log_id, message, is_succeeded)
        VALUES 
            (NEWID(), 'Event: Skip processing on non-primary node. Current role: ' + @role, 1);
        RETURN;
    END      

    DECLARE @db_name SYSNAME;

    SET @db_name = (
            SELECT
                EVENTDATA().value(
                    '(/EVENT_INSTANCE/DatabaseName)[1]',
                    'nvarchar(255)'
                )
        );

    IF @db_name IS NULL OR @db_name = N''
        THROW 50003, 'DROP_DATABASE event did not include a database name.', 1;

    INSERT INTO msdb.dbo.ape_sync_db_log
        (log_id, db_name, operation_type, message)
    VALUES
        (NEWID(), @db_name, 'DROP_DATABASE', 'Event: start drop database trigger');
    EXEC msdb.dbo.sp_ape_db_sync_message
        @db_name = @db_name,
        @operation_type = N'DROP_DATABASE';
END
GO

use [msdb]
GO

IF OBJECT_ID('dbo.ape_sync_db_log') IS NOT NULL
    DROP TABLE dbo.ape_sync_db_log
GO

CREATE TABLE dbo.ape_sync_db_log (
    log_id UNIQUEIDENTIFIER NOT NULL,    
    db_name NVARCHAR(255) NULL,    
    operation_type NVARCHAR(20) NULL,
    message VARCHAR(1024) NULL,     
    source_server NVARCHAR(255) DEFAULT @@SERVERNAME,  
    is_succeeded BIT DEFAULT 1,       
    created_at DATETIME DEFAULT GETDATE()
)
GO


IF OBJECT_ID('dbo.sp_ape_process_sync_db') IS NOT NULL
    DROP PROCEDURE dbo.sp_ape_process_sync_db
GO

CREATE PROCEDURE sp_ape_process_sync_db
WITH
ENCRYPTION
AS 
BEGIN
    EXECUTE AS LOGIN = 'sa';
    SET NOCOUNT ON;
    DECLARE 
            @conversation_handle UNIQUEIDENTIFIER,
            @message_body XML,
            @message_type_name NVARCHAR(1024),
            @db_name NVARCHAR(255),
            @operation_type NVARCHAR(20);
    BEGIN TRY
        RECEIVE TOP(1)
            @conversation_handle = conversation_handle,
            @message_body = message_body,
            @message_type_name = message_type_name
        FROM ApeSyncDBTarget

        IF @@ROWCOUNT = 0
        BEGIN
            INSERT INTO msdb.dbo.ape_sync_db_log 
                (log_id, message, is_succeeded)
            VALUES 
                (@conversation_handle, 'Event: No messages found in queue', 1);
            RETURN;
        END

        IF @message_type_name = '//ApeCloud/DBSyncRequestMessage'
        BEGIN            
            SET @db_name = @message_body.value('(/DBSync/DBName)[1]', 'NVARCHAR(255)');
            SET @operation_type = @message_body.value('(/DBSync/OperationType)[1]', 'NVARCHAR(20)');
            INSERT INTO msdb.dbo.ape_sync_db_log 
                (log_id, db_name, operation_type, message)
            VALUES 
                (@conversation_handle, @db_name, @operation_type, 'Event: start sync process');
            EXEC master.dbo.sp_ape_drop_db_sync @db_name=@db_name;
            INSERT INTO msdb.dbo.ape_sync_db_log
                    (log_id, db_name, operation_type, message)
            VALUES
                    (@conversation_handle, @db_name, @operation_type, 'Event: Processing sync database operation success') ;        
            IF @conversation_handle IS NOT NULL
            BEGIN
                END CONVERSATION @conversation_handle;
            END
        END
        ELSE IF @message_type_name = 'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
        BEGIN
            INSERT INTO msdb.dbo.ape_sync_db_log 
                (log_id, message)
            VALUES 
                (@conversation_handle, 'Event: Service Broker system dialog ended');
        END
        
    END TRY
    BEGIN CATCH
        IF @conversation_handle IS NOT NULL
        BEGIN
            INSERT INTO msdb.dbo.ape_sync_db_log 
            (log_id, db_name, operation_type, message, is_succeeded)
        VALUES 
            (@conversation_handle,
             @db_name, 
             @operation_type,
             'Event: Error occurred - ' + ERROR_MESSAGE() + ' Line: ' + CAST(ERROR_LINE() AS NVARCHAR(255)),
             0);
            END CONVERSATION @conversation_handle;
        END
    END CATCH
END
GO

-- 绑定队列激活处理过程
use [msdb]
GO
ALTER QUEUE ApeSyncDBTarget WITH ACTIVATION (
    STATUS = ON,
    PROCEDURE_NAME = sp_ape_process_sync_db,
    MAX_QUEUE_READERS = 4,
    EXECUTE AS OWNER
)
GO
