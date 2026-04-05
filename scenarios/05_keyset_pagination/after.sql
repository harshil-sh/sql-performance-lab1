-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/05_keyset_pagination/after.sql
<<<<<<< HEAD
-- Scenario: Keyset Pagination — AFTER (seek method, constant cost)
--
-- Replaces OFFSET/FETCH with the keyset pattern.  The client stores the
-- (TransactionDate, TransactionID) bookmark from the last row of each page
-- and supplies it as parameters on the next request.  The WHERE clause
-- turns every page request into an index seek — O(log n), always 3 reads.
--
-- Run AFTER: scenarios/05_keyset_pagination/before.sql
--            + scenarios/05_keyset_pagination/optimization.sql
=======
-- Scenario: Keyset Pagination - AFTER
--
-- Keyset (seek method) pagination with constant cost per page.
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
-- =============================================================================

USE BankingLab;
GO

<<<<<<< HEAD
-- -----------------------------------------------------------------------
-- SETUP: create supporting index if not already present
--        (allows after.sql to run standalone)
-- -----------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_Date_ID')
    CREATE NONCLUSTERED INDEX IX_Transactions_Date_ID
        ON dbo.Transactions (TransactionDate, TransactionID)
        INCLUDE (AccountID, Amount)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
-- Enable I/O and time statistics.
-- Enable actual execution plan (Ctrl+M in SSMS) before running.
-- -----------------------------------------------------------------------

-- ═══════════════════════════════════════════════════════════════════════
-- Keyset 1: First page — no WHERE filter needed
--
-- The first request has no previous page, so no bookmark exists yet.
-- SELECT TOP (25) with ORDER BY performs an index seek from the first
-- leaf entry — identical cost to OFFSET 0.
--
-- Expected plan : Index Seek (IX_Transactions_Date_ID) → Top
-- Expected I/O  : 3 logical reads
-- Expected time : 0 ms
-- ═══════════════════════════════════════════════════════════════════════
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TOP (25) TransactionID, TransactionDate, AccountID, Amount
FROM   dbo.Transactions
ORDER  BY TransactionDate, TransactionID;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Top  (25 rows)
         └─ Index Seek  (IX_Transactions_Date_ID)
              Actual rows : 25      Logical reads : 3

STATISTICS IO : Table 'Transactions'. Scan count 1, logical reads 3
STATISTICS TIME: CPU 0 ms,  elapsed 0 ms

The client saves the last row's values:  @LastDate = <date>, @LastTxID = <id>
*/

-- ═══════════════════════════════════════════════════════════════════════
-- Keyset 2: Equivalent of page 2 000
--
-- In a real application @LastDate2 / @LastTxID2 come from the client,
-- stored after the previous page response — no server lookup needed.
-- Here we retrieve them via OFFSET once (to simulate a stored bookmark)
-- and immediately demonstrate that the KEYSET FETCH itself is always fast.
-- ═══════════════════════════════════════════════════════════════════════
DECLARE @LastDate2  DATETIME2(3);
DECLARE @LastTxID2  BIGINT;

-- Retrieve page 1999's last row bookmark (one-time, client-side in production)
SELECT @LastDate2 = TransactionDate, @LastTxID2 = TransactionID
FROM   dbo.Transactions
ORDER  BY TransactionDate, TransactionID
OFFSET 49975 ROWS FETCH NEXT 1 ROW ONLY;

-- -------------------------------------------------------
-- Keyset fetch for "page 2 000" — always O(log n)
--
-- Expected plan : Index Seek (IX_Transactions_Date_ID) → Top
-- Expected I/O  : 3 logical reads   (was 392 with OFFSET)
-- Expected time : 0 ms              (was 49 ms)
-- -------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TOP (25) TransactionID, TransactionDate, AccountID, Amount
FROM   dbo.Transactions
WHERE (TransactionDate  > @LastDate2)
   OR (TransactionDate  = @LastDate2 AND TransactionID > @LastTxID2)
ORDER  BY TransactionDate, TransactionID;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Top  (25 rows)
         └─ Index Seek  (IX_Transactions_Date_ID)
              Seek predicate : (TransactionDate, TransactionID)
                               > (@LastDate2, @LastTxID2)
              Actual rows : 25      Logical reads : 3

STATISTICS IO : Table 'Transactions'. Scan count 1, logical reads 3
STATISTICS TIME: CPU 0 ms,  elapsed 0 ms

IMPROVEMENT: 392 → 3 logical reads  (131× fewer I/Os)
             49 ms → <1 ms elapsed
SQL Server rewrites the OR as a composite range seek directly to the
continuation point — the B-tree depth is only 3 levels regardless of
where in the table the bookmark falls.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- Keyset 3: Equivalent of page 100 000
--
-- Same constant cost even at 2.5 million rows deep.
-- ═══════════════════════════════════════════════════════════════════════
DECLARE @LastDate100K  DATETIME2(3);
DECLARE @LastTxID100K  BIGINT;

-- Retrieve page 99 999's last row bookmark
SELECT @LastDate100K = TransactionDate, @LastTxID100K = TransactionID
FROM   dbo.Transactions
ORDER  BY TransactionDate, TransactionID
OFFSET 2499975 ROWS FETCH NEXT 1 ROW ONLY;

-- -------------------------------------------------------
-- Keyset fetch for "page 100 000" — still O(log n)
--
-- Expected plan : Index Seek (IX_Transactions_Date_ID) → Top
-- Expected I/O  : 3 logical reads   (was 19 617 with OFFSET)
-- Expected time : 0 ms              (was 2 461 ms)
-- -------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TOP (25) TransactionID, TransactionDate, AccountID, Amount
FROM   dbo.Transactions
WHERE (TransactionDate  > @LastDate100K)
   OR (TransactionDate  = @LastDate100K AND TransactionID > @LastTxID100K)
ORDER  BY TransactionDate, TransactionID;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Top  (25 rows)
         └─ Index Seek  (IX_Transactions_Date_ID)
              Seek predicate : (TransactionDate, TransactionID)
                               > (@LastDate100K, @LastTxID100K)
              Actual rows : 25      Logical reads : 3

STATISTICS IO : Table 'Transactions'. Scan count 1, logical reads 3
STATISTICS TIME: CPU 0 ms,  elapsed 0 ms

IMPROVEMENT: 19 617 → 3 logical reads  (>6 500× fewer I/Os)
             2 461 ms → <1 ms elapsed
The seek descends the B-tree in 3 hops to the exact continuation leaf
page — cost is O(log n) in table size, independent of page number.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- BONUS: Approximate row count from catalog (replaces COUNT(*) scan)
--
-- Expected I/O  : 2 logical reads   (was 19 812 with COUNT(*))
-- Expected time : 0 ms              (was 2 243 ms)
-- ═══════════════════════════════════════════════════════════════════════
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT SUM(row_count) AS ApproximateRows
FROM   sys.dm_db_partition_stats
WHERE  object_id = OBJECT_ID('dbo.Transactions')
  AND  index_id IN (0, 1);   -- heap (0) or clustered index (1)

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
STATISTICS IO : Table 'sysrowsets'. Scan count 1, logical reads 2
STATISTICS TIME: CPU 0 ms,  elapsed 0 ms

Accuracy: within ±0.1% of COUNT(*) immediately after CHECKPOINT / stats update.
Use for total-count badges where approximate figures are acceptable.
For exact counts, COUNT(*) with a non-clustered covering index is unavoidable.
*/

-- -----------------------------------------------------------------------
-- COST GROWTH COMPARISON (same index, different query shape)
-- ┌──────────────────────────────────────┬──────────────────┬─────────────────┬──────────────┐
-- │ Page request                         │ OFFSET/FETCH     │ Keyset Seek     │ Improvement  │
-- ├──────────────────────────────────────┼──────────────────┼─────────────────┼──────────────┤
-- │ Page 1         (offset 0)            │  3 reads /   0ms │  3 reads /  0ms │  identical   │
-- │ Page 2 000     (offset 49 975)       │392 reads /  49ms │  3 reads /  0ms │   131×       │
-- │ Page 100 000   (offset 2 499 975)    │19617 reads/2461ms│  3 reads /  0ms │  >6 500×     │
-- │ Total row count                      │19812 reads/2243ms│  2 reads /  0ms │  ~9 900×     │
-- └──────────────────────────────────────┴──────────────────┴─────────────────┴──────────────┘
-- reads = logical reads
--
-- Key takeaways
--   • OFFSET n costs O(n): the engine cannot skip pages in a B-tree index;
--     every page N request re-traverses rows 1 … N−1 from scratch.
--   • Keyset pagination replaces the skip with a composite seek:
--     (TransactionDate, TransactionID) > (@LastDate, @LastID) resolves in
--     O(log n) — 3 B-tree levels regardless of how deep the page is.
--   • The OR rewrite IS SARGable: SQL Server recognises it as a composite
--     range and does NOT fall back to a scan.
--   • The composite index key order must match ORDER BY exactly:
--     both (TransactionDate ASC, TransactionID ASC) here.
--   • The unique secondary key (TransactionID) is essential: without it,
--     ties on TransactionDate produce non-deterministic page boundaries
--     and duplicate/skipped rows across pages.
--   • Keyset requires the client to persist the bookmark; it cannot jump
--     to an arbitrary page number without walking there sequentially.
--
-- Next step: run scenarios/06_index_fragmentation/before.sql
-- -----------------------------------------------------------------------
=======
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
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
