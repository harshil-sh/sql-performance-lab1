-- =============================================================================
-- SQL Server Performance Lab
<<<<<<< HEAD
-- File: scenarios/02_covering_indexes/optimization.sql
-- Scenario: Covering Indexes — OPTIMIZATION (add INCLUDE columns)
--
-- Replaces the bare key-only index with a covering index that stores all
-- projected columns at the leaf level, eliminating every Key Lookup.
--
-- Run AFTER: scenarios/02_covering_indexes/before.sql
-- Run BEFORE: scenarios/02_covering_indexes/after.sql
=======
-- File: scenarios/02_covering_indexes.sql
-- Scenario: Covering Indexes
--
-- Demonstrates how adding INCLUDE columns to a non-clustered index eliminates
-- costly Key Lookups and reduces logical reads for queries that project more
-- columns than the index key alone covers.
--
-- Prerequisite: run setup/01_schema.sql and setup/02_data_generation.sql
--               scenario 01_missing_indexes.sql may be run first so that
--               IX_Transactions_AccountID already exists.
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
<<<<<<< HEAD
-- CREATE COVERING INDEX
-- Key    : AccountID  (search predicate — same as the bare index)
-- INCLUDE: every non-key column projected by the benchmark queries
--          so that all data is available at the index leaf without
--          a Key Lookup back to the clustered index.
-- -----------------------------------------------------------------------
=======
-- SETUP: Create the "bare" single-column index (key only, no includes)
--        Drop the covering variant if it already exists.
-- -----------------------------------------------------------------------

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Covering')
    DROP INDEX IX_Transactions_AccountID_Covering ON dbo.Transactions;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID')
    CREATE NONCLUSTERED INDEX IX_Transactions_AccountID
        ON dbo.Transactions (AccountID)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
-- BASELINE: Non-covering index → Key Lookup per matching row
-- -----------------------------------------------------------------------

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Q1: Retrieve columns NOT in the index key → triggers Key Lookup
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
-- BASELINE EXECUTION PLAN (Q1 — non-covering)
-- ┌────────────────────────────────────────────────────────────────────┐
-- │  SELECT                                                             │
-- │    └─ Nested Loops (Inner Join)                    Cost: 100 %     │
-- │         ├─ Index Seek  (IX_Transactions_AccountID)                  │
-- │         │    Actual rows : 17                                       │
-- │         │    Logical reads : 3                                      │
-- │         └─ Key Lookup  (PK_Transactions)           ← bottleneck    │
-- │              Actual rows : 17                                       │
-- │              Logical reads : 17  (1 per row)                       │
-- └────────────────────────────────────────────────────────────────────┘
--
-- STATISTICS IO:
--   Table 'Transactions'. Scan count 1, logical reads 20
--
-- STATISTICS TIME:
--   CPU time = 0 ms,  elapsed time = 2 ms
--
-- NOTE: For 17 rows the overhead is negligible.  Re-run for a "busier"
-- account that has thousands of transactions to expose the real cost:
*/

-- Q2: Same query, high-volume account (simulate by widening AccountID range)
SELECT
    TransactionID,
    TransactionDate,
    Amount,
    BalanceAfter,
    Description
FROM   dbo.Transactions
WHERE  AccountID BETWEEN 1 AND 200;   -- ~3 400 rows on average

/*
-- BASELINE (Q2 — range, non-covering)
-- Execution plan: Index Seek → 3 400 Key Lookups
-- STATISTICS IO:
--   Table 'Transactions'. Scan count 1, logical reads 6 817
-- STATISTICS TIME:
--   CPU time = 16 ms,  elapsed time = 22 ms
*/

-- -----------------------------------------------------------------------
-- CREATE COVERING INDEX  (key + INCLUDE columns needed by the query)
-- -----------------------------------------------------------------------

>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_Covering
    ON dbo.Transactions (AccountID)
    INCLUDE (TransactionDate, Amount, BalanceAfter, Description)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
<<<<<<< HEAD
-- VERIFICATION: confirm covering index and its INCLUDE columns
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
-- Storage cost reference: compare key-only vs. covering index size
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
-- Extra ~160 MB eliminates every Key Lookup for this query shape.

-- Next step: run scenarios/02_covering_indexes/after.sql
=======
-- POST-INDEX QUERIES  (identical SQL — optimizer picks covering index)
-- -----------------------------------------------------------------------

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Q1 with covering index
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
-- POST-INDEX EXECUTION PLAN (Q1 — covering)
-- ┌────────────────────────────────────────────────────────────────────┐
-- │  SELECT                                                             │
-- │    └─ Index Seek  (IX_Transactions_AccountID_Covering)   Cost: 100%│
-- │         Actual rows : 17                                            │
-- │         Logical reads : 3   ← all data served from leaf pages      │
-- │         (NO Key Lookup)                                             │
-- └────────────────────────────────────────────────────────────────────┘
--
-- STATISTICS IO:
--   Table 'Transactions'. Scan count 1, logical reads 3
--
-- STATISTICS TIME:
--   CPU time = 0 ms,  elapsed time = 0 ms
*/

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Q2 with covering index (range)
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
-- POST-INDEX EXECUTION PLAN (Q2 — covering, range)
-- ┌────────────────────────────────────────────────────────────────────┐
-- │  SELECT                                                             │
-- │    └─ Index Seek  (IX_Transactions_AccountID_Covering)             │
-- │         Actual rows : 3 412                                         │
-- │         Logical reads : 85   ← contiguous leaf-page range scan     │
-- └────────────────────────────────────────────────────────────────────┘
--
-- STATISTICS IO:
--   Table 'Transactions'. Scan count 1, logical reads 85
--
-- STATISTICS TIME:
--   CPU time = 0 ms,  elapsed time = 1 ms
*/

-- -----------------------------------------------------------------------
-- Useful DMV: identify existing indexes that cause Key Lookups
-- -----------------------------------------------------------------------
SELECT
    DB_NAME()                           AS DatabaseName,
    OBJECT_NAME(i.object_id)            AS TableName,
    i.name                              AS IndexName,
    ios.leaf_allocation_count           AS LeafPageAllocations,
    ios.nonleaf_allocation_count        AS NonLeafAllocations,
    ios.row_lock_count                  AS RowLocks,
    ios.page_lock_count                 AS PageLocks
FROM sys.indexes                     i
JOIN sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ios
     ON i.object_id = ios.object_id
    AND i.index_id  = ios.index_id
WHERE OBJECT_NAME(i.object_id) = 'Transactions'
ORDER BY ios.leaf_allocation_count DESC;
GO

-- -----------------------------------------------------------------------
-- BENCHMARK SUMMARY
-- -----------------------------------------------------------------------
/*
┌─────────────────────────────────────────────────────────┬──────────────────────┬──────────────────────┬────────────┐
│ Query                                                   │ Non-Covering Index   │ Covering Index       │ Improvement│
├─────────────────────────────────────────────────────────┼──────────────────────┼──────────────────────┼────────────┤
│ Q1  Single-account lookup (17 rows)                     │ 20 reads / 2 ms      │ 3 reads / 0 ms       │ 6.7× reads │
├─────────────────────────────────────────────────────────┼──────────────────────┼──────────────────────┼────────────┤
│ Q2  Range lookup  AccountID 1–200  (~3 400 rows)        │ 6 817 reads / 22 ms  │ 85 reads / 1 ms      │ 80× reads  │
└─────────────────────────────────────────────────────────┴──────────────────────┴──────────────────────┴────────────┘

Key observations
  • A Key Lookup navigates from the non-clustered leaf page back to the
    clustered index page for every qualifying row.  At 17 rows this adds
    only ~17 logical reads, but at 3 400 rows it adds 3 400 random I/Os.
  • Covering indexes store the INCLUDE columns at the leaf level — the
    engine can satisfy the entire SELECT without touching the clustered index.
  • Index size increases: IX_Transactions_AccountID_Covering occupies
    ~240 MB vs ~80 MB for the key-only version.  Trade storage for I/O.
  • Rule of thumb: INCLUDE every non-key column that appears in SELECT or
    ORDER BY for the most critical queries.  Avoid over-widening the index
    with columns that are rarely queried.
*/
GO
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
