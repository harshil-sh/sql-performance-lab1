-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/05_keyset_pagination/after.sql
-- Scenario: Keyset Pagination - AFTER
--
-- Keyset (seek method) pagination with constant cost per page.
-- =============================================================================

USE BankingLab;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_Date_ID')
    CREATE NONCLUSTERED INDEX IX_Transactions_Date_ID
        ON dbo.Transactions (TransactionDate, TransactionID)
        INCLUDE (AccountID, Amount, TransactionTypeID, Description)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- First page bookmark
DECLARE @LastDate DATETIME2(3) = '1900-01-01';
DECLARE @LastTxID BIGINT = 0;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TOP (25)
    TransactionID, TransactionDate, AccountID, Amount, Description
FROM dbo.Transactions
WHERE (TransactionDate > @LastDate)
   OR (TransactionDate = @LastDate AND TransactionID > @LastTxID)
ORDER BY TransactionDate, TransactionID;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- Deep-page equivalent bookmark (still seek-based)
DECLARE @BookmarkDate DATETIME2(3) = '2022-10-17 08:42:11.000';
DECLARE @BookmarkID BIGINT = 7412389;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TOP (25)
    TransactionID, TransactionDate, AccountID, Amount, Description
FROM dbo.Transactions
WHERE (TransactionDate > @BookmarkDate)
   OR (TransactionDate = @BookmarkDate AND TransactionID > @BookmarkID)
ORDER BY TransactionDate, TransactionID;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
