-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/02_covering_indexes/before.sql
-- Scenario: Covering Indexes — BEFORE (Key Lookup baseline)
--
-- Demonstrates the Key Lookup overhead that occurs when a non-clustered index
-- exists on the key column but does not include all projected columns.
-- The engine must jump back to the clustered index once per qualifying row.
--
-- Prerequisite: IX_Transactions_AccountID must exist.
--   Run scenarios/01_missing_indexes/after.sql first, or the CREATE INDEX
--   guard at the bottom of the SETUP block will create it for you.
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- SETUP: ensure the bare (non-covering) key-only index exists;
--        drop a covering variant if it was left over from earlier runs.
-- -----------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Covering')
    DROP INDEX IX_Transactions_AccountID_Covering ON dbo.Transactions;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID')
    CREATE NONCLUSTERED INDEX IX_Transactions_AccountID
        ON dbo.Transactions (AccountID)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
-- Enable I/O and time statistics.
-- Enable actual execution plan (Ctrl+M) before running.
-- -----------------------------------------------------------------------

-- -------------------------------------------------------
-- Query 1: Single-account lookup — low row count (~17 rows)
--
-- Expected plan : Index Seek (key-only) + Key Lookup per row
-- Expected I/O  : ~20 logical reads
-- Expected time : ~2 ms
-- -------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    TransactionID,
    TransactionDate,
    Amount,
    BalanceAfter,
    Description
FROM   dbo.Transactions
WHERE  AccountID = 42000;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Nested Loops (Inner Join)                  Cost: 100 %
         ├─ Index Seek  (IX_Transactions_AccountID)
         │    Actual rows : 17     Logical reads : 3
         └─ Key Lookup  (PK_Transactions)         ← bottleneck
              Actual rows : 17     Logical reads : 17

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 20

STATISTICS TIME:
  CPU time = 0 ms,  elapsed time = 2 ms

WHY: BalanceAfter and Description are not stored in
IX_Transactions_AccountID, so the engine issues one random
Key Lookup into the clustered index for each of the 17 rows.
At 17 rows this is negligible; the cost becomes visible at scale.
*/

-- -------------------------------------------------------
-- Query 2: Range lookup — high row count (~3 400 rows)
--
-- The lookup overhead grows linearly with row count.
-- Expected plan : Index Seek (key-only) + ~3 400 Key Lookups
-- Expected I/O  : ~6 817 logical reads
-- Expected time : ~22 ms
-- -------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    TransactionID,
    TransactionDate,
    Amount,
    BalanceAfter,
    Description
FROM   dbo.Transactions
WHERE  AccountID BETWEEN 1 AND 200;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Nested Loops (Inner Join)
         ├─ Index Seek  (IX_Transactions_AccountID)
         │    Actual rows : 3 412     Logical reads : 14
         └─ Key Lookup  (PK_Transactions)
              Actual rows : 3 412     Logical reads : 6 803

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 6 817

STATISTICS TIME:
  CPU time = 16 ms,  elapsed time = 22 ms

NOTE: For very large result sets the optimizer may switch to a full
Clustered Index Scan instead of tolerating millions of Key Lookups.
This "tipping point" is typically ~1 % of table rows.
*/

-- -----------------------------------------------------------------------
-- VERIFICATION: confirm covering index does NOT exist
-- -----------------------------------------------------------------------
SELECT
    i.name          AS IndexName,
    c.name          AS ColumnName,
    ic.is_included_column,
    ic.key_ordinal
FROM   sys.indexes       i
JOIN   sys.index_columns ic ON ic.object_id = i.object_id
                            AND ic.index_id  = i.index_id
JOIN   sys.columns       c  ON c.object_id  = i.object_id
                            AND c.column_id  = ic.column_id
WHERE  OBJECT_NAME(i.object_id) = 'Transactions'
  AND  i.name LIKE 'IX_Transactions_AccountID%'
ORDER  BY i.name, ic.key_ordinal, ic.is_included_column;
GO

-- -----------------------------------------------------------------------
-- SUMMARY
-- ┌───────────────────────────────────────────┬────────────────────────┐
-- │ Query                                     │ Logical Reads / ms     │
-- ├───────────────────────────────────────────┼────────────────────────┤
-- │ Q1  AccountID = 42000  (17 rows)          │ 20 reads  /  2 ms      │
-- │ Q2  AccountID 1–200    (~3 400 rows)      │ 6 817 reads  / 22 ms   │
-- └───────────────────────────────────────────┴────────────────────────┘
--
-- Next step: run scenarios/02_covering_indexes/after.sql
-- -----------------------------------------------------------------------
