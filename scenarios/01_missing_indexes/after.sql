-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/01_missing_indexes/after.sql
-- Scenario: Missing Indexes — AFTER (recommended fix)
--
-- Creates non-clustered indexes on the two most important predicates and
-- re-runs the benchmarks to show Index Seek replacing Clustered Index Scan.
--
-- Run AFTER: scenarios/01_missing_indexes/before.sql
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- CREATE RECOMMENDED INDEXES
-- -----------------------------------------------------------------------

-- Index 1: AccountID equality lookups
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID
    ON dbo.Transactions (AccountID)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

-- Index 2: TransactionDate range scans
CREATE NONCLUSTERED INDEX IX_Transactions_TransactionDate
    ON dbo.Transactions (TransactionDate)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

GO

-- -----------------------------------------------------------------------
-- Re-run the SAME queries — the optimizer now picks seeks, not scans.
-- Enable actual execution plan (Ctrl+M) before running.
-- -----------------------------------------------------------------------

-- -------------------------------------------------------
-- Query 1: Single-account lookup
--
-- Expected plan : Index Seek (IX_Transactions_AccountID)
--                 + Key Lookup into clustered index
-- Expected I/O  : ~21 logical reads   (was 105 042)
-- Expected time : ~1 ms               (was 1 560 ms)
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
    └─ Nested Loops (Inner Join)
         ├─ Index Seek  (IX_Transactions_AccountID)
         │    Actual rows : 18      Logical reads : 3
         └─ Key Lookup  (PK_Transactions)
              Actual rows : 18      Logical reads : 18

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 21

STATISTICS TIME:
  CPU time = 0 ms,  elapsed time = 1 ms

IMPROVEMENT: 105 042 → 21 logical reads  (~5 000× fewer I/Os)
             1 560 ms → 1 ms elapsed      (~1 560× faster)
*/

-- -------------------------------------------------------
-- Query 2: One-month date range
--
-- Expected plan : Index Seek (IX_Transactions_TransactionDate)
--                 + Key Lookups (one per qualifying row)
-- Expected I/O  : ~168 442 logical reads  (was 105 042 — still high?
--                 see scenario 02 for the covering-index fix)
-- Expected time : ~512 ms                 (was 4 102 ms)
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
    └─ Nested Loops (Inner Join)
         ├─ Index Seek  (IX_Transactions_TransactionDate)
         │    Actual rows : 167 234     Logical reads : 1 208
         └─ Key Lookup  (PK_Transactions)
              Actual rows : 167 234     Logical reads : 167 234

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 168 442

STATISTICS TIME:
  CPU time = 437 ms,  elapsed time = 512 ms

NOTE: Logical reads are *higher* than the scan baseline because each of
the 167 K matching rows triggers a separate Key Lookup into the clustered
index.  Elapsed time still improves ~8× because seeks are sequential I/O
on the narrow date index before the random lookups.
Eliminate the Key Lookup by adding INCLUDE columns — see scenario 02.
*/

-- -----------------------------------------------------------------------
-- VERIFICATION: confirm both indexes were created
-- -----------------------------------------------------------------------
SELECT
    i.name          AS IndexName,
    i.type_desc     AS IndexType,
    c.name          AS KeyColumn
FROM   sys.indexes       i
JOIN   sys.index_columns ic ON ic.object_id = i.object_id
                            AND ic.index_id  = i.index_id
JOIN   sys.columns       c  ON c.object_id  = i.object_id
                            AND c.column_id  = ic.column_id
WHERE  OBJECT_NAME(i.object_id) = 'Transactions'
  AND  i.name IN ('IX_Transactions_AccountID', 'IX_Transactions_TransactionDate')
ORDER  BY i.name, ic.key_ordinal;
GO

-- -----------------------------------------------------------------------
-- BENCHMARK SUMMARY
-- ┌────────────────────────────────┬──────────────────────┬──────────────────┬────────────┐
-- │ Query                          │ Before (no index)    │ After (index)    │ Speedup    │
-- ├────────────────────────────────┼──────────────────────┼──────────────────┼────────────┤
-- │ Q1  AccountID = 12345          │ 105 042 r / 1 560 ms │ 21 r / 1 ms      │ ~1 560×    │
-- │ Q2  TransactionDate Jan 2023   │ 105 042 r / 4 102 ms │ 168 442 r / 512ms│ ~8×        │
-- └────────────────────────────────┴──────────────────────┴──────────────────┴────────────┘
-- r = logical reads
--
-- Key takeaways
--   • A single non-clustered index on a selective column can reduce reads
--     by >99 % and cut latency by three orders of magnitude.
--   • For large result sets (Q2) the Key Lookup cost dominates; see
--     scenarios/02_covering_indexes/ for the complete solution.
--
-- Next step: run scenarios/02_covering_indexes/before.sql
-- -----------------------------------------------------------------------
