-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/01_missing_indexes/before.sql
-- Scenario: Missing Indexes — BEFORE (baseline)
--
-- Demonstrates the full Clustered Index Scan that every query suffers when
-- no non-clustered indexes exist on the 10 M-row Transactions table.
--
-- Run AFTER: setup/01_schema.sql  and  setup/02_data_generation.sql
-- Run BEFORE: scenarios/01_missing_indexes/after.sql
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- SETUP: drop any relevant non-clustered indexes so the baseline is clean
-- -----------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID')
    DROP INDEX IX_Transactions_AccountID ON dbo.Transactions;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_TransactionDate')
    DROP INDEX IX_Transactions_TransactionDate ON dbo.Transactions;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Date')
    DROP INDEX IX_Transactions_AccountID_Date ON dbo.Transactions;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Covering')
    DROP INDEX IX_Transactions_AccountID_Covering ON dbo.Transactions;
GO

-- -----------------------------------------------------------------------
-- Enable I/O and time statistics.
-- Enable actual execution plan (Ctrl+M in SSMS) before running.
-- -----------------------------------------------------------------------

-- -------------------------------------------------------
-- Query 1: All transactions for a single account
--
-- Expected plan : Clustered Index Scan (reads ALL 10 M rows)
-- Expected I/O  : 105 042 logical reads
-- Expected time : ~1 560 ms elapsed
-- -------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, Amount, TransactionTypeID
FROM   dbo.Transactions
WHERE  AccountID = 12345;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Clustered Index Scan  (dbo.Transactions.PK_Transactions)
         Estimated rows : 16           Actual rows : 18
         Logical reads  : 105 042
         Scan count     : 1

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 105 042

STATISTICS TIME:
  CPU time = 1 234 ms,  elapsed time = 1 560 ms

WHY: No non-clustered index on AccountID.  The engine must read every
data page in the clustered index to find the 18 qualifying rows.
*/

-- -------------------------------------------------------
-- Query 2: Transactions in a one-month date range
--
-- Expected plan : Clustered Index Scan (reads ALL 10 M rows)
-- Expected I/O  : 105 042 logical reads
-- Expected time : ~4 102 ms elapsed
-- -------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, AccountID, Amount, TransactionDate
FROM   dbo.Transactions
WHERE  TransactionDate >= '2023-01-01'
  AND  TransactionDate <  '2023-02-01';

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Clustered Index Scan  (dbo.Transactions.PK_Transactions)
         Estimated rows : 166 666      Actual rows : 167 234
         Logical reads  : 105 042
         Scan count     : 1

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 105 042

STATISTICS TIME:
  CPU time = 3 891 ms,  elapsed time = 4 102 ms

WHY: No non-clustered index on TransactionDate.  The engine reads every
page searching for the ~167 K rows in January 2023.
*/

-- -----------------------------------------------------------------------
-- VERIFICATION: confirm there are no relevant non-clustered indexes
-- -----------------------------------------------------------------------
SELECT
    i.name          AS IndexName,
    i.type_desc     AS IndexType,
    c.name          AS KeyColumn,
    ic.key_ordinal  AS KeyOrdinal
FROM   sys.indexes       i
JOIN   sys.index_columns ic ON ic.object_id = i.object_id
                            AND ic.index_id  = i.index_id
JOIN   sys.columns       c  ON c.object_id  = i.object_id
                            AND c.column_id  = ic.column_id
WHERE  OBJECT_NAME(i.object_id) = 'Transactions'
  AND  i.type_desc <> 'HEAP'
ORDER  BY i.type_desc, i.index_id, ic.key_ordinal;
GO

-- -----------------------------------------------------------------------
-- SUMMARY
-- ┌──────────────────────────────────┬─────────────────────┐
-- │ Query                            │ Logical Reads / ms  │
-- ├──────────────────────────────────┼─────────────────────┤
-- │ Q1  AccountID = 12345            │ 105 042  / 1 560 ms │
-- │ Q2  TransactionDate Jan 2023     │ 105 042  / 4 102 ms │
-- └──────────────────────────────────┴─────────────────────┘
--
-- Next step: run scenarios/01_missing_indexes/after.sql
-- -----------------------------------------------------------------------
