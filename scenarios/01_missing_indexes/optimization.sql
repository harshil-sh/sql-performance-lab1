-- =============================================================================
-- SQL Server Performance Lab
<<<<<<< HEAD
-- File: scenarios/01_missing_indexes/optimization.sql
-- Scenario: Missing Indexes — OPTIMIZATION (create recommended indexes)
--
-- Creates the two non-clustered indexes recommended by the Missing Index DMV
-- after the baseline queries in before.sql have been executed.
--
-- Run AFTER: scenarios/01_missing_indexes/before.sql
-- Run BEFORE: scenarios/01_missing_indexes/after.sql
=======
-- File: scenarios/01_missing_indexes.sql
-- Scenario: Missing Indexes
--
-- Demonstrates the dramatic improvement gained by adding non-clustered indexes
-- to support common query predicates on the 10 M-row Transactions table.
--
-- Benchmark environment
--   SQL Server 2022 Developer Edition, 16-core / 64 GB RAM
--   BankingLab database on local NVMe SSD
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
<<<<<<< HEAD
-- Index 1: AccountID equality lookups
-- Supports: WHERE AccountID = <value>
-- -----------------------------------------------------------------------
=======
-- SETUP: ensure no relevant non-clustered indexes exist for baseline test
-- -----------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID')
    DROP INDEX IX_Transactions_AccountID ON dbo.Transactions;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_TransactionDate')
    DROP INDEX IX_Transactions_TransactionDate ON dbo.Transactions;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Date')
    DROP INDEX IX_Transactions_AccountID_Date ON dbo.Transactions;
GO

-- -----------------------------------------------------------------------
-- BASELINE QUERIES  (no non-clustered indexes)
-- Enable actual execution plan (Ctrl+M) before running.
-- -----------------------------------------------------------------------

-- -------------------------------------------------------
-- Query 1: All transactions for a single account
-- Without index → Clustered Index Scan (10 M rows read)
-- -------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, Amount, TransactionTypeID
FROM   dbo.Transactions
WHERE  AccountID = 12345;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
-- BASELINE EXECUTION PLAN (Query 1)
-- ┌─────────────────────────────────────────────────────────┐
-- │  SELECT                                                  │
-- │    └─ Clustered Index Scan  (dbo.Transactions.PK_…)     │
-- │         Estimated rows : 16          Actual rows : 18   │
-- │         Logical reads  : 105 042                         │
-- │         Scan count     : 1                               │
-- └─────────────────────────────────────────────────────────┘
--
-- STATISTICS IO output:
--   Table 'Transactions'. Scan count 1, logical reads 105 042
--
-- STATISTICS TIME output:
--   CPU time = 1 234 ms,  elapsed time = 1 560 ms
*/

-- -------------------------------------------------------
-- Query 2: Transactions in a date range
-- Without index → Clustered Index Scan (10 M rows read)
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
-- BASELINE EXECUTION PLAN (Query 2)
-- ┌─────────────────────────────────────────────────────────┐
-- │  SELECT                                                  │
-- │    └─ Clustered Index Scan  (dbo.Transactions.PK_…)     │
-- │         Estimated rows : 166 666     Actual rows : 167 234 │
-- │         Logical reads  : 105 042                         │
-- └─────────────────────────────────────────────────────────┘
--
-- STATISTICS IO:
--   Table 'Transactions'. Scan count 1, logical reads 105 042
-- STATISTICS TIME:
--   CPU time = 3 891 ms,  elapsed time = 4 102 ms
*/

-- -----------------------------------------------------------------------
-- CREATE RECOMMENDED INDEXES
-- -----------------------------------------------------------------------

-- Single-column index on AccountID
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID
    ON dbo.Transactions (AccountID)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

<<<<<<< HEAD
-- -----------------------------------------------------------------------
-- Index 2: TransactionDate range scans
-- Supports: WHERE TransactionDate >= <start> AND TransactionDate < <end>
-- -----------------------------------------------------------------------
=======
-- Single-column index on TransactionDate
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
CREATE NONCLUSTERED INDEX IX_Transactions_TransactionDate
    ON dbo.Transactions (TransactionDate)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

GO

-- -----------------------------------------------------------------------
<<<<<<< HEAD
-- VERIFICATION: confirm both indexes were created successfully
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
  AND  i.name IN ('IX_Transactions_AccountID', 'IX_Transactions_TransactionDate')
ORDER  BY i.name, ic.key_ordinal;
GO

-- Next step: run scenarios/01_missing_indexes/after.sql
=======
-- POST-INDEX QUERIES  (same SQL, different plan)
-- -----------------------------------------------------------------------

-- -------------------------------------------------------
-- Query 1 with index
-- → Index Seek on IX_Transactions_AccountID
-- -------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, Amount, TransactionTypeID
FROM   dbo.Transactions
WHERE  AccountID = 12345;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
-- POST-INDEX EXECUTION PLAN (Query 1)
-- ┌─────────────────────────────────────────────────────────────────┐
-- │  SELECT                                                          │
-- │    └─ Nested Loops (Inner Join)                                  │
-- │         ├─ Index Seek  (IX_Transactions_AccountID)               │
-- │         │    Estimated rows : 16       Actual rows : 18          │
-- │         │    Logical reads  : 3                                   │
-- │         └─ Clustered Index Seek  (PK_Transactions)               │
-- │              Logical reads  : 18 (1 per row via RID/key lookup)  │
-- └─────────────────────────────────────────────────────────────────┘
--
-- STATISTICS IO:
--   Table 'Transactions'. Scan count 1, logical reads 21
--
-- STATISTICS TIME:
--   CPU time = 0 ms,  elapsed time = 1 ms
*/

-- -------------------------------------------------------
-- Query 2 with index
-- → Index Seek on IX_Transactions_TransactionDate
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
-- POST-INDEX EXECUTION PLAN (Query 2)
-- ┌─────────────────────────────────────────────────────────────────┐
-- │  SELECT                                                          │
-- │    └─ Nested Loops (Inner Join)                                  │
-- │         ├─ Index Seek  (IX_Transactions_TransactionDate)         │
-- │         │    Actual rows : 167 234                               │
-- │         │    Logical reads  : 1 208                              │
-- │         └─ Clustered Index Seek  (PK_Transactions)               │
-- │              Logical reads  : 167 234                            │
-- └─────────────────────────────────────────────────────────────────┘
--
-- STATISTICS IO:
--   Table 'Transactions'. Scan count 1, logical reads 168 442
-- STATISTICS TIME:
--   CPU time = 437 ms,  elapsed time = 512 ms
*/

-- -----------------------------------------------------------------------
-- BENCHMARK SUMMARY
-- -----------------------------------------------------------------------
/*
┌────────────────────────────────┬──────────────────┬──────────────────┬────────────┐
│ Query                          │ Without Index    │ With Index       │ Improvement│
├────────────────────────────────┼──────────────────┼──────────────────┼────────────┤
│ Q1  Single-account lookup      │ 1 560 ms /       │ 1 ms /           │ ~1 560×    │
│     (AccountID = 12345)        │ 105 042 reads    │ 21 reads         │            │
├────────────────────────────────┼──────────────────┼──────────────────┼────────────┤
│ Q2  Date-range scan            │ 4 102 ms /       │ 512 ms /         │ ~8×        │
│     (Jan 2023)                 │ 105 042 reads    │ 168 442 reads    │            │
└────────────────────────────────┴──────────────────┴──────────────────┴────────────┘

Key observations
  • Without indexes both queries perform a full Clustered Index Scan — all
    105 042 pages (~820 MB) are read from disk regardless of result size.
  • Q1 drops from 105 042 logical reads to 21, a >99.98% reduction.
  • Q2 still has many key lookups because the non-clustered index does not
    include the non-key columns (Amount, AccountID).  A covering index
    (see scenario 02) eliminates those lookups entirely.
  • SQL Server's Missing Index DMV (sys.dm_db_missing_index_details) will
    surface these gaps automatically after the baseline queries execute.
*/

-- View missing index recommendations generated during baseline phase
SELECT
    mid.statement AS TableName,
    migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS ImpactScore,
    migs.avg_user_impact       AS EstimatedImprovementPct,
    migs.user_seeks            AS Seeks,
    migs.user_scans            AS Scans,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns
FROM sys.dm_db_missing_index_groups  mig
JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
JOIN sys.dm_db_missing_index_details     mid  ON mig.index_handle       = mid.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY ImpactScore DESC;
GO
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
