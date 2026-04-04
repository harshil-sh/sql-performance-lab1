-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/04_window_functions/after.sql
-- Scenario: Window Functions - AFTER
--
-- Optimized set-based window function patterns.
-- =============================================================================

USE BankingLab;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Date')
    CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_Date
        ON dbo.Transactions (AccountID, TransactionDate)
        INCLUDE (Amount, TransactionTypeID, BalanceAfter)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
-- Optimized 1: ROW_NUMBER() for top 3 recent transactions/account
-- -----------------------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

WITH Ranked AS (
    SELECT
        AccountID,
        TransactionID,
        TransactionDate,
        Amount,
        ROW_NUMBER() OVER (PARTITION BY AccountID ORDER BY TransactionDate DESC) AS rn
    FROM dbo.Transactions
    WHERE AccountID BETWEEN 1 AND 100
)
SELECT AccountID, TransactionID, TransactionDate, Amount
FROM Ranked
WHERE rn <= 3
ORDER BY AccountID, TransactionDate DESC;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- -----------------------------------------------------------------------
-- Optimized 2: SUM OVER for running balance
-- -----------------------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    TransactionID,
    TransactionDate,
    Amount,
    TransactionTypeID,
    SUM(CASE WHEN TransactionTypeID IN (1,5,6) THEN Amount ELSE -Amount END)
        OVER (
            PARTITION BY AccountID
            ORDER BY TransactionDate
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS RunningBalance
FROM dbo.Transactions
WHERE AccountID = 55555
ORDER BY TransactionDate;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
