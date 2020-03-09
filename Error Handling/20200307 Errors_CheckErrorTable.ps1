#------------------------------------------------------------------------------------------------------/
# This script will read the error log table on all servers on server list (specified in the script) for 
# errors.  It will generate a text file at the location specified in the script.
#
#------------------------------------------------------------------------------------------------------/

#Setup output file

$path = get-location
$OutFile = "$($path)\Temp Files\Errors - Check Error Tables.txt"
out-file $OutFile

#Instantiate variables

$Sqlconnection = new-object system.data.sqlclient.sqlconnection
$Sqlcmd = new-object system.data.sqlclient.sqlcommand
$Sqladapter = new-object system.data.sqlclient.sqldataadapter

$importfile = "$($path)\AllServersReporting.csv" 

# Write current datetime stamp at top of output file
Get-Date | out-file $OutFile -Append

Import-CSV $importfile | ForEach-Object {
  	$svrName= $_.Server
	$IntegratedSecurity = $_.IntegratedSecurity
	$Account = $_.Account
	$Password = $_.Password

	"=========================================================================================" | out-file $OutFile -Append
	"Server: $svrname " | out-file $OutFile -Append
      	"=========================================================================================" | out-file $OutFile -Append

	if ($IntegratedSecurity -eq 1)	
	{
		$Sqlconnection.connectionstring = "Server=$svrname; database=master; integrated security=true"
	}
	else
	{
		$Sqlconnection.connectionstring = "Server=$svrname; database=master; User ID=$Account; Password=$Password"
	}
	$Sqlcmd.commandtext = "
		declare @SQL nvarchar(max);
		set @SQL = N'declare @SQL nvarchar(max);';
		create table ##LogTableData (
			  LogTableDatabase sysname
			, LogInsertDate datetime
			, ObjectId int
			, ErrorDatabase sysname
			, SystemErrorMessage nvarchar(4000)
			, UserMessage nvarchar(4000)
			, UserInfoMessage nvarchar(4000)
		);
		select @SQL = @SQL + N'if exists (
			select 1 
			from [' + name + N'].[sys].[tables] t
			inner join [' + name + N'].[sys].[schemas] s on s.schema_id = t.schema_id
			where t.name = ''ApplicationErrorLog'' and s.name = ''Admin'')
			begin;
				set @SQL = N''insert into ##LogTableData (
					  LogTableDatabase
					, LogInsertDate
					, ObjectId
					, ErrorDatabase 
					, SystemErrorMessage 
					, UserMessage 
					, UserInfoMessage)
					select 
						''''' + name + ''''' 
						, el.LogInsertDate
						, el.ObjectId
						, d.name 
						, el.SystemErrorMessage
						, substring(el.UserMessage,1,4000) as UserMessage
						, substring(el.UserInfoMessage,1,4000) as UserInfoMessage
					from [' + name + N'].[Admin].[ApplicationErrorLog] el
					left join sys.databases d on d.database_id = el.DatabaseId
					where el.LogInsertDate >= dateadd(day,-1,getdate()) 
					and d.state = 0
					and el.IsAdminAlert = 1
					--and (el.SystemErrorMessage is not null or UserMessage is not null)
					--order by el.LogInsertDate desc;''
				exec sp_executesql @SQL;
			end;
			'
		from sys.databases 
		where database_id > 4 and [state] = 0

		--select @SQL 
		exec sp_executesql @SQL;
		select * from ##LogTableData order by LogTableDatabase, LogInsertDate desc;
		drop table ##LogTableData;"
	$Sqlcmd.connection = $Sqlconnection
	$Sqladapter.selectcommand = $Sqlcmd
	$DataSet = new-object system.data.dataset
	$Sqladapter.fill($Dataset)
	$Sqlconnection.close()
	
	$Dataset.tables[0] `
		| format-table -AutoSize `
		| out-string -Width 4096 `
		| out-file $OutFile -Append
}

"******* End of log" | out-file $OutFile -Append
