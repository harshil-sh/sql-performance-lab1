-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/02_covering_indexes/after.sql
-- Scenario: Covering Indexes — AFTER (Key Lookup eliminated)
--
-- Adds INCLUDE columns to the existing AccountID index so that every column
-- projected by the benchmark queries is served directly from the index leaf
-- pages, eliminating all Key Lookups.
--
-- Run AFTER: scenarios/02_covering_indexes/before.sql
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- CREATE COVERING INDEX
-- Key   : AccountID  (search predicate)
-- INCLUDE: all columns referenced in SELECT but not in index key
-- -----------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_Covering
    ON dbo.Transactions (AccountID)
    INCLUDE (TransactionDate, Amount, BalanceAfter, Description)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
-- Re-run the SAME queries — the optimizer now uses the covering index
-- and performs NO Key Lookups.
-- Enable actual execution plan (Ctrl+M) before running.
-- -----------------------------------------------------------------------

-- -------------------------------------------------------
-- Query 1: Single-account lookup (~17 rows)
--
-- Expected plan : Index Seek only (IX_Transactions_AccountID_Covering)
-- Expected I/O  : ~3 logical reads   (was 20)
-- Expected time : ~0 ms              (was 2 ms)
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
    └─ Index Seek  (IX_Transactions_AccountID_Covering) Cost: 100 %
         Actual rows : 17
         Logical reads : 3     ← all data served from leaf pages
         (NO Key Lookup)

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 3

STATISTICS TIME:
  CPU time = 0 ms,  elapsed time = 0 ms

IMPROVEMENT: 20 → 3 logical reads  (6.7× fewer I/Os)
             Key Lookup node gone from plan entirely
*/

-- -------------------------------------------------------
-- Query 2: Range lookup (~3 400 rows)
--
-- Expected plan : Index Seek only — contiguous leaf-page range scan
-- Expected I/O  : ~85 logical reads  (was 6 817)
-- Expected time : ~1 ms              (was 22 ms)
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
    └─ Index Seek  (IX_Transactions_AccountID_Covering)
         Actual rows : 3 412
         Logical reads : 85   ← contiguous leaf-page range scan
         (NO Key Lookup)

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 85

STATISTICS TIME:
  CPU time = 0 ms,  elapsed time = 1 ms

IMPROVEMENT: 6 817 → 85 logical reads  (80× fewer I/Os)
*/

-- -----------------------------------------------------------------------
-- DMV: review index column layout to confirm INCLUDE columns
-- -----------------------------------------------------------------------
SELECT
    i.name                      AS IndexName,
    c.name                      AS ColumnName,
    CASE ic.is_included_column
        WHEN 0 THEN 'Key'
        ELSE        'INCLUDE'
    END                         AS Role,
    ic.key_ordinal,
    ic.index_column_id
FROM   sys.indexes       i
JOIN   sys.index_columns ic ON ic.object_id = i.object_id
                            AND ic.index_id  = i.index_id
JOIN   sys.columns       c  ON c.object_id  = i.object_id
                            AND c.column_id  = ic.column_id
WHERE  OBJECT_NAME(i.object_id) = 'Transactions'
  AND  i.name = 'IX_Transactions_AccountID_Covering'
ORDER  BY ic.is_included_column, ic.key_ordinal;
GO

-- -----------------------------------------------------------------------
-- Storage cost: check index size
-- -----------------------------------------------------------------------
SELECT
    i.name                              AS IndexName,
    SUM(a.total_pages) * 8 / 1024      AS SizeMB
FROM   sys.indexes      i
JOIN   sys.partitions   p  ON p.object_id = i.object_id
                           AND p.index_id  = i.index_id
JOIN   sys.allocation_units a ON a.container_id = p.partition_id
WHERE  OBJECT_NAME(i.object_id) = 'Transactions'
  AND  i.name IN ('IX_Transactions_AccountID',
                  'IX_Transactions_AccountID_Covering')
GROUP  BY i.name;
GO
-- Typical results:
--   IX_Transactions_AccountID           ~  80 MB  (key only)
--   IX_Transactions_AccountID_Covering  ~ 240 MB  (key + includes)
-- Extra ~160 MB buys the elimination of every Key Lookup for this query shape.

-- -----------------------------------------------------------------------
-- BENCHMARK SUMMARY
-- ┌─────────────────────────────────────┬──────────────────────┬──────────────────┬────────────┐
-- │ Query                               │ Before (key-only)    │ After (covering) │ Improvement│
-- ├─────────────────────────────────────┼──────────────────────┼──────────────────┼────────────┤
-- │ Q1  AccountID = 42000  (17 rows)    │ 20 reads  /  2 ms    │ 3 reads  /  0 ms │ 6.7× reads │
-- │ Q2  AccountID 1–200  (~3 400 rows)  │ 6 817 reads  / 22 ms │ 85 reads  / 1 ms │ 80× reads  │
-- └─────────────────────────────────────┴──────────────────────┴──────────────────┴────────────┘
--
-- Key takeaways
--   • A Key Lookup adds one random I/O per qualifying row.  The cost is
--     proportional to result-set size, not table size.
--   • Covering the index with INCLUDE columns stores extra data at the leaf
--     level so the engine never needs to visit the clustered index.
--   • Rule of thumb: INCLUDE every non-key column that appears in SELECT or
--     ORDER BY for the query pattern you are optimising.
--   • Watch index size: INCLUDE adds storage per row; balance I/O savings
--     against write amplification on INSERT/UPDATE workloads.
--
-- Next step: run scenarios/03_sargability/before.sql
-- -----------------------------------------------------------------------
