-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/05_keyset_pagination/before.sql
-- Scenario: Keyset Pagination - BEFORE
--
-- Baseline pagination using OFFSET/FETCH. Cost grows with page depth.
-- =============================================================================

USE BankingLab;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_Date_ID')
    DROP INDEX IX_Transactions_Date_ID ON dbo.Transactions;
GO

DECLARE @PageSize INT = 25;

-- Page 1
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount, Description
FROM dbo.Transactions
ORDER BY TransactionDate, TransactionID
OFFSET 0 ROWS FETCH NEXT @PageSize ROWS ONLY;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- Deep page (OFFSET cost becomes significant)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount, Description
FROM dbo.Transactions
ORDER BY TransactionDate, TransactionID
OFFSET 2499975 ROWS FETCH NEXT 25 ROWS ONLY;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
