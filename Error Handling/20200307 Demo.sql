-- Demo item 1: log a non-critical business error
CREATE OR ALTER PROC dbo.Sample_Proc_Log_Business_Error
AS
BEGIN TRY 
    -- Some business checks here

    -- Assume a non-critical business check failed.  This should be logged, but execution should complete
    EXEC [dbo].[p_Proc_Log_Business_Error] @ProcedureId = @@PROCID, @UserMessage = 'Some non-critical business constraint has been violated'

    -- Continue executing 
    PRINT 'Executing remainder of procedure';
END TRY 
BEGIN CATCH 
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN; 

    EXEC dbo.p_Proc_Catch_Log_Error @ProcedureId = @@PROCID;

    THROW;
END CATCH 
GO
DELETE FROM [admin].[ApplicationErrorLog];
GO 
EXEC dbo.Sample_Proc_Log_Business_Error;
GO
SELECT * FROM [admin].[ApplicationErrorLog];
GO

-- Demo item 2: log a critical error
CREATE OR ALTER PROC dbo.Sample_Proc_Log_Critical_Error
AS
BEGIN TRY 
    -- Some business checks here

    -- Continue executing 
    PRINT 'Executing remainder of procedure';

    -- Critical error
    SELECT 1/0;
END TRY 
BEGIN CATCH 
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN; 

    EXEC dbo.p_Proc_Catch_Log_Error @ProcedureId = @@PROCID;

    THROW;
END CATCH 
GO
DELETE FROM [admin].[ApplicationErrorLog];
GO 
EXEC dbo.Sample_Proc_Log_Critical_Error;
GO
SELECT * FROM [admin].[ApplicationErrorLog];
GO