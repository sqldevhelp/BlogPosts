CREATE OR ALTER PROC dbo.Sample_Proc_Log_Business_Error
AS
BEGIN TRY 
    -- Some business checks here

    -- Assume a non-critical business check failed.  This should be logged, but execution should complete
    EXEC [dbo].[p_Proc_Log_Business_Error] @ProcedureId = PROCID, @UserMessage = 'Some non-critical business constraint has been violated'

    -- Continue executing 
    PRINT 'Executing remainder of procedure';
END TRY 
BEGIN CATCH 
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN; 

    EXEC dbo.p_Proc_Catch_Log_Error @ProcedureId = @@PROCID;
END CATCH 
GO
DELETE FROM [admin].[ApplicationErrorLog];
-- 
EXEC dbo.Sample_Proc_Log_Business_Error;

SELECT * FROM [admin].[ApplicationErrorLog];