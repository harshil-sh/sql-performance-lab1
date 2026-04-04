-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/04_window_functions/before.sql
-- Scenario: Window Functions - BEFORE
--
-- Baseline approaches that are typically slower than set-based window
-- functions for ranking and running-balance style workloads.
-- =============================================================================

USE BankingLab;
GO

-- Ensure supporting index does not hide baseline behavior for ranking test.
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Date')
    DROP INDEX IX_Transactions_AccountID_Date ON dbo.Transactions;
GO

-- -----------------------------------------------------------------------
-- Baseline 1: Correlated sub-query to fetch top 3 recent transactions/account
-- -----------------------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT t1.AccountID, t1.TransactionID, t1.TransactionDate, t1.Amount
FROM   dbo.Transactions t1
WHERE  t1.AccountID BETWEEN 1 AND 100
  AND  (
      SELECT COUNT(*)
      FROM   dbo.Transactions t2
      WHERE  t2.AccountID = t1.AccountID
        AND  t2.TransactionDate > t1.TransactionDate
  ) < 3
ORDER  BY t1.AccountID, t1.TransactionDate DESC;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- -----------------------------------------------------------------------
-- Baseline 2: Cursor-style running balance (kept commented; expensive style)
-- -----------------------------------------------------------------------
/*
DECLARE @AccountID INT = 55555;
DECLARE @RunBal DECIMAL(18,2) = 0;
DECLARE @TxID BIGINT, @Amount DECIMAL(18,2), @TypeID TINYINT, @TxDate DATETIME2(3);

CREATE TABLE #CursorResult (
    TransactionID BIGINT,
    TransactionDate DATETIME2(3),
    Amount DECIMAL(18,2),
    RunningBalance DECIMAL(18,2)
);

DECLARE bal_cursor CURSOR FAST_FORWARD FOR
    SELECT TransactionID, TransactionDate, Amount, TransactionTypeID
    FROM dbo.Transactions
    WHERE AccountID = @AccountID
    ORDER BY TransactionDate;

OPEN bal_cursor;
FETCH NEXT FROM bal_cursor INTO @TxID, @TxDate, @Amount, @TypeID;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @RunBal = @RunBal + CASE WHEN @TypeID IN (1,5,6) THEN @Amount ELSE -@Amount END;
    INSERT INTO #CursorResult VALUES (@TxID, @TxDate, @Amount, @RunBal);
    FETCH NEXT FROM bal_cursor INTO @TxID, @TxDate, @Amount, @TypeID;
END
CLOSE bal_cursor;
DEALLOCATE bal_cursor;

SELECT * FROM #CursorResult ORDER BY TransactionDate;
DROP TABLE #CursorResult;
*/
GO
