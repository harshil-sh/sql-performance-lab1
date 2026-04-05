-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/04_window_functions/after.sql
<<<<<<< HEAD
-- Scenario: Window Functions — AFTER (SUM OVER replacing correlated subquery)
--
-- Rewrites both benchmark queries to use SUM() OVER (PARTITION BY AccountID
-- ORDER BY TransactionDate, TransactionID ROWS UNBOUNDED PRECEDING).
-- With the supporting composite index the engine streams over the ordered
-- index in a single pass — O(n) — with no Sort operator and no Key Lookups.
--
-- Run AFTER: scenarios/04_window_functions/before.sql
--            + scenarios/04_window_functions/optimization.sql
=======
-- Scenario: Window Functions - AFTER
--
-- Optimized set-based window function patterns.
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
-- =============================================================================

USE BankingLab;
GO

<<<<<<< HEAD
-- -----------------------------------------------------------------------
-- SETUP: create supporting index if not already present
--        (allows after.sql to run standalone without optimization.sql)
-- -----------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Date')
    CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_Date
        ON dbo.Transactions (AccountID, TransactionDate, TransactionID)
        INCLUDE (Amount)
=======
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID_Date')
    CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_Date
        ON dbo.Transactions (AccountID, TransactionDate)
        INCLUDE (Amount, TransactionTypeID, BalanceAfter)
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
<<<<<<< HEAD
-- Enable I/O and time statistics.
-- Enable actual execution plan (Ctrl+M in SSMS) before running.
-- -----------------------------------------------------------------------

-- ═══════════════════════════════════════════════════════════════════════
-- Query 1: Running total for a single account (~17 rows)
--
-- The window function streams over the index in one ordered pass.
-- All data (AccountID seek key + TransactionDate/TransactionID order
-- + Amount value) is served from the leaf pages of the covering index.
--
-- Expected plan : Index Seek (IX_Transactions_AccountID_Date)
--                 → Window Spool (streaming, no Sort)
-- Expected I/O  : ~3 logical reads   (was 85)
-- Expected time : ~0 ms              (was 8 ms)
-- ═══════════════════════════════════════════════════════════════════════
=======
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
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    TransactionID,
<<<<<<< HEAD
    AccountID,
    TransactionDate,
    Amount,
    SUM(Amount) OVER (
        PARTITION BY AccountID
        ORDER BY     TransactionDate, TransactionID
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS RunningTotal
FROM   dbo.Transactions
WHERE  AccountID = 42000
ORDER  BY TransactionDate, TransactionID;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Window Aggregate  (SUM — streaming)              Cost: ~15%
         └─ Index Seek  (IX_Transactions_AccountID_Date) Cost: ~85%
              Actual rows : 17
              Logical reads : 3
              (NO Sort operator — index already ordered by AccountID,
               TransactionDate, TransactionID)

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 3

STATISTICS TIME:
  CPU time = 0 ms,  elapsed time = 0 ms

IMPROVEMENT: 85 → 3 logical reads  (~28× fewer I/Os)
             8 ms → <1 ms elapsed
             Correlated sub-query executions: 17 → 0  (single pass)
*/

-- ═══════════════════════════════════════════════════════════════════════
-- Query 2: Running total across 200 accounts (~3 400 rows)
--
-- The engine performs one contiguous leaf-page range scan over the index,
-- partitioned in memory by AccountID.  No inner loops, no re-seeks.
-- I/O cost is identical to a simple range SELECT on the same rows.
--
-- Expected plan : Index Seek (range) → Window Spool (no Sort)
-- Expected I/O  : ~85 logical reads   (was 23 800)
-- Expected time : ~2 ms               (was 800 ms)
-- ═══════════════════════════════════════════════════════════════════════
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    TransactionID,
    AccountID,
    TransactionDate,
    Amount,
    SUM(Amount) OVER (
        PARTITION BY AccountID
        ORDER BY     TransactionDate, TransactionID
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS RunningTotal
FROM   dbo.Transactions
WHERE  AccountID BETWEEN 1 AND 200
ORDER  BY AccountID, TransactionDate, TransactionID;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Window Aggregate  (SUM — streaming)
         └─ Index Seek  (IX_Transactions_AccountID_Date)
              Actual rows : 3 412
              Logical reads : 85
              Scan count    : 1
              (NO Sort, NO nested loops, NO inner executions)

STATISTICS IO:
  Table 'Transactions'. Scan count 1, logical reads 85

STATISTICS TIME:
  CPU time = 1 ms,  elapsed time = 2 ms

IMPROVEMENT: 23 800 → 85 logical reads  (~280× fewer I/Os)
             800 ms → 2 ms elapsed       (~400× faster)
             Single pass replaces 3 412 correlated sub-executions.
*/

-- -----------------------------------------------------------------------
-- SIDE-BY-SIDE: window function without vs with supporting index
--
-- To observe the Sort operator that appears when the index is absent,
-- drop the index, run the SUM OVER query, then recreate it.
-- -----------------------------------------------------------------------

/*  -- Uncomment to see the Sort-present plan
DROP INDEX IX_Transactions_AccountID_Date ON dbo.Transactions;

SET STATISTICS IO ON; SET STATISTICS TIME ON;
SELECT AccountID, TransactionDate, TransactionID, Amount,
       SUM(Amount) OVER (
           PARTITION BY AccountID
           ORDER BY TransactionDate, TransactionID
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS RunningTotal
FROM   dbo.Transactions
WHERE  AccountID BETWEEN 1 AND 200
ORDER  BY AccountID, TransactionDate, TransactionID;
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

-- Plan without index:
--   Index Seek (IX_Transactions_AccountID, key only)
--   → Key Lookup (clustered, to fetch Amount)
--   → Sort  (AccountID, TransactionDate, TransactionID)  ← blocking, ~30% cost
--   → Window Spool
--
-- Recreate the index after observing:
-- CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_Date
--     ON dbo.Transactions (AccountID, TransactionDate, TransactionID)
--     INCLUDE (Amount)
--     WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
*/

-- -----------------------------------------------------------------------
-- BENCHMARK SUMMARY
-- ┌──────────────────────────────────────────┬──────────────────────┬─────────────────┬──────────────┐
-- │ Query                                    │ Before (subquery)    │ After (SUM OVER)│ Improvement  │
-- ├──────────────────────────────────────────┼──────────────────────┼─────────────────┼──────────────┤
-- │ Q1  Running total, 1 acct   (~17 rows)   │   85 reads /   8 ms  │  3 reads / 0 ms │  ~28× reads  │
-- │ Q2  Running total, 200 accts (~3 400 rows)│ 23 800 reads / 800ms│ 85 reads / 2 ms │ ~280× reads  │
-- └──────────────────────────────────────────┴──────────────────────┴─────────────────┴──────────────┘
-- r = logical reads
--
-- Key takeaways
--   • A correlated subquery for running totals is O(n²): each outer row
--     re-executes an inner scan from row 1 to row k.  Doubling the result
--     set quadruples the I/O.
--   • SUM() OVER (... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
--     is O(n): the engine maintains a running accumulator as it streams
--     forward through an already-ordered index — one pass, constant overhead.
--   • The composite index (AccountID, TransactionDate, TransactionID)
--     INCLUDE (Amount) is the key enabler: it pre-sorts the data for the
--     window partition/order AND covers the aggregated column, eliminating
--     both the Sort operator (~30% plan cost without it) and Key Lookups.
--   • For window functions, always match the index key order to
--     (PARTITION BY columns, ORDER BY columns).
--
-- Next step: run scenarios/05_keyset_pagination/before.sql
-- -----------------------------------------------------------------------
=======
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
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
