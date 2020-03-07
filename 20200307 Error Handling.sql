IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = 'Admin')
BEGIN;
	DECLARE @SQL NVARCHAR(MAX) = N'CREATE SCHEMA Admin AUTHORIZATION dbo;';
	EXEC sp_executesql @SQL;
END;
GO
CREATE TABLE [admin].[ApplicationErrorLog](
	[RecordId] [int] IDENTITY(1,1) NOT NULL,
	[LogInsertDate] [datetime] NOT NULL,
	[DatabaseId] [int] NULL,
	[ObjectId] [int] NULL,
	[SystemErrorMessage] [nvarchar](4000) NULL,
	[ErrorLine] [int] NULL,
	[UserMessage] [nvarchar](4000) NULL,
	[UserInfoMessage] [nvarchar](4000) NULL,
	[DatabaseName] [sysname] NULL,
	[ObjectName] [sysname] NULL,
PRIMARY KEY CLUSTERED 
(
	[RecordId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [admin].[ApplicationErrorLog] ADD  DEFAULT (getdate()) FOR [LogInsertDate]
GO
ALTER TABLE [admin].[ApplicationErrorLog] ADD  CONSTRAINT [df_Admin_ApplicationErrorLog_DatabaseName]  DEFAULT (db_name()) FOR [DatabaseName]
GO
CREATE PROC [dbo].[p_Proc_Catch_Log_Error] (
	@ProcedureId int = null
)
as
DECLARE @SchemaName SYSNAME;

SELECT @SchemaName = SCHEMA_NAME([schema_id]) FROM sys.objects WHERE [object_id] = @ProcedureId;

INSERT INTO [admin].[ApplicationErrorLog] (
	  DatabaseId
	, ObjectId
	, SystemErrorMessage
	, ErrorLine
	, DatabaseName
	, ObjectName
)
SELECT 
	  DB_ID()
	, @ProcedureId
	, ERROR_MESSAGE()
	, ERROR_LINE()
	, DB_NAME()
	, @SchemaName + '.' + OBJECT_NAME(@ProcedureId);
GO


