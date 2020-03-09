use msdb 
go

-- REVIEW AND ADAPT THIS CODE BEFORE DEPLOYING

if exists (select 1 from sys.tables where [name] = 'log_AgentJobsLast' and SCHEMA_NAME([schema_id]) = 'dbo')
	drop table dbo.log_AgentJobsLast 
go
select [job_id], [name], [enabled], getdate() as LastUpdate
into dbo.log_AgentJobsLast
from dbo.sysjobs
go
alter table dbo.log_AgentJobsLast add constraint pk_log_AgentJobsLast primary key ([job_id]);
go
if exists (select 1 from sys.tables where [name] = 'log_AgentJobsAuditHistory' and SCHEMA_NAME([schema_id]) = 'dbo')
	drop table dbo.log_AgentJobsAuditHistory 
go
-- Adapt: make sure this table contains before and after columns for each job attribute you want to track.
create table dbo.log_AgentJobsAuditHistory  (
	  [AuditRowId] int not null identity(1,1)
	, [job_id_before] uniqueidentifier null
	, [job_id_after] uniqueidentifier null
	, [name_before] sysname  null
	, [name_after] sysname null
	, [enabled_before] tinyint null
	, [enabled_after] tinyint null
	-- OTHER JOB ATTRIBUTES HERE
	, [LastUpdate] datetime2 not null
	, [LastUpdateGUID] uniqueidentifier not null
	, [LastUpdateAction] varchar(25) not null
) on [primary]
go
alter table dbo.log_AgentJobsAuditHistory add constraint pk_log_AgentJobsAuditHistory primary key ([AuditRowId]);
go
create or alter proc dbo.p_LogAgentJobs (
	  @MailProfileToSendVia sysname 
	, @OperatorName sysname 
)
as
set nocount on;
begin try

-- Verify operator
if not exists (select 1 from dbo.sysoperators o where o.[name] = @OperatorName and o.[enabled] = 1)
begin;
	throw 51000, 'Admin operator does not exist on this server.  Create or enable Admin operator', 1;
end;

-- Adapt: make sure this table contains before and after columns for each job attribute you want to track.
declare @changes as table (
	  [LastUpdateAction] varchar(25) not null
	, [job_id_before] uniqueidentifier null
	, [job_id_after] uniqueidentifier null
	, [name_before] sysname null
	, [name_after] sysname null
	, [enabled_before] tinyint null
	, [enabled_after] tinyint null
	-- OTHER JOB ATTRIBUTES HERE
	, [LastUpdate] datetime2 not null 
	, [LastUpdateGUID] uniqueidentifier not null
);

declare @LastUpdateGUID uniqueidentifier = newid();

begin tran;

-- Get current jobs
select [job_id], [name], [enabled] 
into #log_AgentJobsCurrent
from dbo.sysjobs;

-- Merge current jobs into last list and get any changes to be logged for review
-- Adapt: make sure this merge statement contains before and after columns for each job attribute you want to track.
merge [dbo].[log_AgentJobsLast] as [target]
using (select * from #log_AgentJobsCurrent) as [source]
	on [source].[job_id] = [target].[job_id]
when matched and [source].[enabled] <> [target].[enabled] or [source].[name] <> [target].[name]
	then update set [target].[enabled] = [source].[enabled], [target].[name] = [source].[name]
when not matched by target 
	then insert ([job_id], [name], [enabled], [LastUpdate])
	values ([source].[job_id], [source].[name], [source].[enabled], getdate())
when not matched by source then delete
output 
	  $action as [LastUpdateAction]
	, deleted.[job_id] as job_id_before
	, inserted.[job_id] as job_id_after
	, deleted.[name] as name_before
	, inserted.[name] as name_after
	, deleted.[enabled] as enabled_before
	, inserted.[enabled] as enabled_after
	, getdate() as LastUpdate
	, @LastUpdateGUID as LastUpdateGUID
into @changes;

-- Insert changes to be logged for review
-- Adapt: make sure this table contains before and after columns for each job attribute you want to track.
insert into [dbo].[log_AgentJobsAuditHistory] (
	  [job_id_before]
	, [job_id_after]
	, [name_before]
	, [name_after]
	, [enabled_before]
	, [enabled_after]
	-- OTHER JOB ATTRIBUTES HERE
	, [LastUpdate]
	, [LastUpdateGUID]
	, [LastUpdateAction]
)
select 
	  [job_id_before]
	, [job_id_after]
	, [name_before]
	, [name_after]
	, [enabled_before]
	, [enabled_after]
	-- OTHER JOB ATTRIBUTES HERE
	, [LastUpdate]
	, [LastUpdateGUID]
	, [LastUpdateAction]
from @changes;

-- If there were any changes, alert
IF exists (select 1 from  [dbo].[log_AgentJobsAuditHistory] where [LastUpdateGUID] = @LastUpdateGUID)
BEGIN 
	DECLARE		
		  @Warning nvarchar(800) = 'One or more jobs on this server has changed.  SELECT * FROM [dbo].[log_AgentJobsAuditHistory] where [LastUpdateGUID] = ''' + cast(@LastUpdateGUID as nvarchar(800)) + ''''
		, @Subject nvarchar(100) = 'Unexpected job change (server ' + @@SERVERNAME + ')'
	;
   
	EXEC msdb..sp_notify_operator
		  @profile_name = @MailProfileToSendVia
		, @name = @OperatorName
		, @subject = @subject
		, @body = @warning
	;
END

commit tran;

drop table #log_AgentJobsCurrent;

end try
begin catch
	if @@TRANCOUNT > 0
		rollback tran;

	if OBJECT_ID('tempdb..#log_AgentJobsCurrent','U') is not null
		 drop table #log_AgentJobsCurrent;

	-- Custom error logging here

	throw;
end catch
go