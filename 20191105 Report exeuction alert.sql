USE [ReportServer]
GO

create or alter view [dbo].[ExecutionLog3_Extended]
AS
SELECT
    InstanceName,
    COALESCE(CASE(ReportAction)
        WHEN 11 THEN AdditionalInfo.value('(AdditionalInfo/SourceReportUri)[1]', 'nvarchar(max)')
        ELSE C.Path
        END, 'Unknown') AS ItemPath,
    UserName,
    ExecutionId,
    CASE(RequestType)
        WHEN 0 THEN 'Interactive'
        WHEN 1 THEN 'Subscription'
        WHEN 2 THEN 'Refresh Cache'
        ELSE 'Unknown'
        END AS RequestType,
    -- SubscriptionId,
    Format,
    Parameters,
    CASE(ReportAction)
        WHEN 1 THEN 'Render'
        WHEN 2 THEN 'BookmarkNavigation'
        WHEN 3 THEN 'DocumentMapNavigation'
        WHEN 4 THEN 'DrillThrough'
        WHEN 5 THEN 'FindString'
        WHEN 6 THEN 'GetDocumentMap'
        WHEN 7 THEN 'Toggle'
        WHEN 8 THEN 'Sort'
        WHEN 9 THEN 'Execute'
        WHEN 10 THEN 'RenderEdit'
        WHEN 11 THEN 'ExecuteDataShapeQuery'
        WHEN 12 THEN 'RenderMobileReport'
        WHEN 13 THEN 'ConceptualSchema'
        WHEN 14 THEN 'QueryData'
        WHEN 15 THEN 'ASModelStream'
        WHEN 16 THEN 'RenderExcelWorkbook'
        WHEN 17 THEN 'GetExcelWorkbookInfo'
        WHEN 18 THEN 'SaveToCatalog'
        WHEN 19 THEN 'DataRefresh'
        ELSE 'Unknown'
        END AS ItemAction,
    TimeStart,
    TimeEnd,
    TimeDataRetrieval,
    TimeProcessing,
    TimeRendering,
    CASE(Source)
        WHEN 1 THEN 'Live'
        WHEN 2 THEN 'Cache'
        WHEN 3 THEN 'Snapshot'
        WHEN 4 THEN 'History'
        WHEN 5 THEN 'AdHoc'
        WHEN 6 THEN 'Session'
        WHEN 7 THEN 'Rdce'
        ELSE 'Unknown'
        END AS Source,
    Status,
    ByteCount,
    [RowCount],
    AdditionalInfo,
	EL.LogEntryId
FROM ExecutionLogStorage EL WITH(NOLOCK)
LEFT OUTER JOIN Catalog C WITH(NOLOCK) ON (EL.ReportID = C.ItemID)
GO
if exists (select 1 from sys.tables where name = 'Log_ExecutionAlert' and SCHEMA_NAME(schema_id) = 'dbo')
	drop table dbo.Log_ExecutionAlert;
go
create table dbo.Log_ExecutionAlert (
	  [LogEntryId] bigint not null
	, [LogEntryInserted] datetime2 not null
);
go
alter table dbo.Log_ExecutionAlert add constraint pk_Log_ExecutionAlert primary key ([LogEntryId]);
go
alter table dbo.Log_ExecutionAlert add constraint df_Log_ExecutionAlert_LogEntryInserted default getdate() for [LogEntryInserted]
go
create or alter proc dbo.p_Log_Exeuction_Alert
(
	  @DatabaseMailProfileName nvarchar(128)		-- Profile to use for sending Database Mail
	, @OperatorName nvarchar(128)					-- The email address associated with this operator will receive the alert
	, @HoursToLook int								-- Number of hours this proc should look back to find failed executions
)
as
begin try

-- Make sure profile is valid
if not exists (select 1 from msdb.dbo.sysmail_profile where [name] = @DatabaseMailProfileName)
begin;
	throw 51000, 'Database Mail profile does not exist.', 1;
end;

-- Make sure operator is valid
if not exists (select 1 from msdb.dbo.sysoperators o where o.[name] = @OperatorName and o.[enabled] = 1 and replace(isnull(o.[email_address],''),' ','') <> '')
begin;
	throw 51000, 'Operator does not exist or email address is not valid.', 1;
end;

-- Get operator email
declare @OperatorEmail nvarchar(100);
select @OperatorEmail = o.[email_address] from msdb.dbo.sysoperators o where o.[name] = @OperatorName; 

-- Get failed exeuctions
select
	e.[LogEntryId]
into 
	#FailedExecutions
from 
	dbo.ExecutionLog3_Extended e
where
	e.[Status] <> 'rsSuccess'
	and e.[TimeStart] >= DATEADD(hour, -1 * ABS(@HoursToLook), getdate())
	-- Execution is not already logged
	and not exists (
		select 1
		from dbo.Log_ExecutionAlert l
		where l.[LogEntryId] = e.[LogEntryId]
	)
	;

-- Log failed executions and alert
if exists (select 1 from #FailedExecutions)
begin
begin tran;

insert into dbo.Log_ExecutionAlert ([LogEntryId], [LogEntryInserted])
select [LogEntryId], getdate()
from #FailedExecutions;

declare		
	  @Warning nvarchar(800) = 'There have been 1 or more failed report server executions within the last ' + cast(@HoursToLook as nvarchar) + ' hours.  Please check dbo.ExecutionLog3.'
	, @Subject nvarchar(100) = 'Failed report exeuctions (server ' + @@SERVERNAME + ')'
;
   
EXEC msdb..sp_notify_operator
	  @profile_name = @DatabaseMailProfileName
	, @name = @OperatorName
	, @subject = @subject
	, @body = @warning

commit tran;
end
drop table #FailedExecutions;

end try
begin catch
	if @@TRANCOUNT > 0 
		rollback tran;

	if OBJECT_ID('tempdb..#FailedExecutions','U') is not null
		drop table #FailedExecutions;

	-- Add other logging here

	throw;
end catch
go

EXEC dbo.p_Log_Exeuction_Alert
	  @DatabaseMailProfileName = 'Admin'
	, @OperatorName = 'Admin'
	, @HoursToLook = 10

select * from dbo.Log_ExecutionAlert
	