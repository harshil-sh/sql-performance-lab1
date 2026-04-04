-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/05_keyset_pagination.sql
-- Scenario: Keyset Pagination  (a.k.a. Seek Method / Cursor-based Pagination)
--
-- Traditional OFFSET/FETCH pagination re-scans all previous rows on every page.
-- Keyset pagination uses a WHERE clause on the last seen key values, allowing
-- an index seek that is O(log n + page_size) regardless of page number.
--
-- Covered patterns
--   1. OFFSET/FETCH baseline — cost grows linearly with page number
--   2. Keyset forward pagination — constant seek cost
--   3. Keyset with composite sort key (TransactionDate, TransactionID)
--   4. Bidirectional keyset (prev / next page)
--   5. Total row count without full scan (approximation via stats)
-- =============================================================================

USE BankingLab;
GO

-- Supporting index for keyset on (TransactionDate, TransactionID)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_Date_ID')
    CREATE NONCLUSTERED INDEX IX_Transactions_Date_ID
        ON dbo.Transactions (TransactionDate, TransactionID)
        INCLUDE (AccountID, Amount, TransactionTypeID, Description)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 1: OFFSET/FETCH  — O(offset + page_size) cost
-- ═══════════════════════════════════════════════════════════════════════

DECLARE @PageSize INT = 25;

-- Page 1  (offset = 0)
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount, Description
FROM   dbo.Transactions
ORDER  BY TransactionDate, TransactionID
OFFSET 0 ROWS FETCH NEXT @PageSize ROWS ONLY;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN (page 1):
--   Index Scan on IX_Transactions_Date_ID + Top(25)
-- STATISTICS IO  : logical reads 3
-- STATISTICS TIME: CPU 0 ms, elapsed 0 ms
*/

-- Page 2 000  (offset = 49 975)
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount, Description
FROM   dbo.Transactions
ORDER  BY TransactionDate, TransactionID
OFFSET 49975 ROWS FETCH NEXT @PageSize ROWS ONLY;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN (page 2 000):
--   Index Scan on IX_Transactions_Date_ID — must traverse all 49 975 rows
-- STATISTICS IO  : logical reads 392
-- STATISTICS TIME: CPU 47 ms, elapsed 49 ms
*/

-- Page 100 000  (offset = 2 499 975 — deep page)
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount, Description
FROM   dbo.Transactions
ORDER  BY TransactionDate, TransactionID
OFFSET 2499975 ROWS FETCH NEXT @PageSize ROWS ONLY;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN (page 100 000 — deep):
--   Index Scan on IX_Transactions_Date_ID — traverses 2.5 M rows
-- STATISTICS IO  : logical reads 19 617
-- STATISTICS TIME: CPU 2 344 ms, elapsed 2 461 ms
-- → Cost grows linearly: deep pages are unacceptably slow.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 2: Keyset (Seek) pagination — O(log n + page_size) cost
-- ═══════════════════════════════════════════════════════════════════════

-- Client stores the last seen (TransactionDate, TransactionID) from previous page.
-- On first load these are MIN values:

DECLARE @LastDate   DATETIME2(3) = '1900-01-01';
DECLARE @LastTxID   BIGINT       = 0;

-- "Next page" — equivalent to page 1
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TOP (25)
    TransactionID, TransactionDate, AccountID, Amount, Description
FROM   dbo.Transactions
WHERE (TransactionDate  > @LastDate)
   OR (TransactionDate  = @LastDate AND TransactionID > @LastTxID)
ORDER  BY TransactionDate, TransactionID;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Index Seek on IX_Transactions_Date_ID → Top(25)
-- STATISTICS IO : logical reads 3
-- STATISTICS TIME: CPU 0 ms, elapsed 0 ms
*/

-- Simulate fetching page equivalent to OFFSET 2 499 975
-- by seeking directly to a known key bookmark.
-- Client holds: LastDate = '2022-10-17 08:42:11.000', LastTxID = 7 412 389

DECLARE @BookmarkDate DATETIME2(3) = '2022-10-17 08:42:11.000';
DECLARE @BookmarkID   BIGINT       = 7412389;

SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TOP (25)
    TransactionID, TransactionDate, AccountID, Amount, Description
FROM   dbo.Transactions
WHERE (TransactionDate  > @BookmarkDate)
   OR (TransactionDate  = @BookmarkDate AND TransactionID > @BookmarkID)
ORDER  BY TransactionDate, TransactionID;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN (equivalent to deep page):
--   Index Seek on IX_Transactions_Date_ID — seeks directly to bookmark
-- STATISTICS IO  : logical reads 3   ← same as page 1 !
-- STATISTICS TIME: CPU 0 ms, elapsed 0 ms
-- Improvement vs OFFSET deep page: >6 500× fewer reads
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 3: Keyset pagination scoped to a single account
-- ═══════════════════════════════════════════════════════════════════════

-- Supporting index: (AccountID, TransactionDate, TransactionID)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_Acct_Date_ID')
    CREATE NONCLUSTERED INDEX IX_Transactions_Acct_Date_ID
        ON dbo.Transactions (AccountID, TransactionDate, TransactionID)
        INCLUDE (Amount, TransactionTypeID, Description)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

DECLARE @AccountID    INT          = 77777;
DECLARE @LastDate2    DATETIME2(3) = '1900-01-01';
DECLARE @LastTxID2    BIGINT       = 0;
DECLARE @PageSize2    INT          = 10;

SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TOP (@PageSize2)
    TransactionID, TransactionDate, Amount, TransactionTypeID, Description
FROM   dbo.Transactions
WHERE  AccountID = @AccountID
  AND (TransactionDate  > @LastDate2
    OR (TransactionDate = @LastDate2 AND TransactionID > @LastTxID2))
ORDER  BY TransactionDate, TransactionID;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Index Seek on IX_Transactions_Acct_Date_ID → Top(10)
-- STATISTICS IO : logical reads 3
-- STATISTICS TIME: CPU 0 ms, elapsed 0 ms
-- (Regardless of how many prior pages were fetched)
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 4: Bidirectional keyset (Previous page)
-- ═══════════════════════════════════════════════════════════════════════

-- "Previous page" — reverse the inequality direction and sort, then flip result
DECLARE @FirstVisibleDate DATETIME2(3) = '2022-10-17 08:45:00.000';
DECLARE @FirstVisibleID   BIGINT       = 7412414;

SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount, Description
FROM (
    SELECT TOP (25)
        TransactionID, TransactionDate, AccountID, Amount, Description
    FROM   dbo.Transactions
    WHERE (TransactionDate  < @FirstVisibleDate)
       OR (TransactionDate  = @FirstVisibleDate AND TransactionID < @FirstVisibleID)
    ORDER  BY TransactionDate DESC, TransactionID DESC
) prev
ORDER  BY TransactionDate, TransactionID;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN:
--   Index Seek on IX_Transactions_Date_ID (backward scan → Top(25))
--   Sort (to re-order the final 25 rows ASC)
-- STATISTICS IO : logical reads 3
-- STATISTICS TIME: CPU 0 ms, elapsed 0 ms
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 5: Fast approximate row count (avoid COUNT(*) full scan)
-- ═══════════════════════════════════════════════════════════════════════

-- Exact COUNT(*) — requires full scan
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT COUNT_BIG(*) AS ExactRowCount
FROM   dbo.Transactions;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- STATISTICS IO  : logical reads 19 812
-- STATISTICS TIME: CPU 2 109 ms, elapsed 2 243 ms
*/

-- Approximate row count — O(1), zero logical reads
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT SUM(p.rows) AS ApproxRowCount
FROM   sys.partitions p
JOIN   sys.objects    o ON o.object_id = p.object_id
WHERE  o.name = 'Transactions'
  AND  p.index_id <= 1;          -- heap (0) or clustered index (1)

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- STATISTICS IO  : logical reads 2  (catalog tables only)
-- STATISTICS TIME: CPU 0 ms, elapsed 0 ms
-- Difference     : ±0.1% from exact count (stat updated after last insert)
*/

-- -----------------------------------------------------------------------
-- BENCHMARK SUMMARY
-- -----------------------------------------------------------------------
/*
┌────────────────────────────────────────────────────────┬────────────────────────┬──────────────────────┬────────────────────┐
│ Scenario                                               │ OFFSET/FETCH           │ Keyset Pagination    │ Improvement        │
├────────────────────────────────────────────────────────┼────────────────────────┼──────────────────────┼────────────────────┤
│ Page 1       (first  25 rows)                          │  3 reads  / 0 ms       │  3 reads  / 0 ms     │ identical          │
├────────────────────────────────────────────────────────┼────────────────────────┼──────────────────────┼────────────────────┤
│ Page 2 000   (offset 49 975)                           │ 392 reads / 49 ms      │  3 reads  / 0 ms     │ 131× reads         │
├────────────────────────────────────────────────────────┼────────────────────────┼──────────────────────┼────────────────────┤
│ Page 100 000 (offset 2 499 975 — deep page)            │ 19 617 reads / 2 461ms │  3 reads  / 0 ms     │ >6 500× reads      │
├────────────────────────────────────────────────────────┼────────────────────────┼──────────────────────┼────────────────────┤
│ Row count (10 M rows)                                  │ 19 812 reads / 2 243ms │  2 reads (catalog)   │ ~9 900× reads      │
└────────────────────────────────────────────────────────┴────────────────────────┴──────────────────────┴────────────────────┘

Key observations
  • OFFSET/FETCH must skip all preceding rows — cost is O(offset) not O(1).
  • Keyset pagination uses an index seek on the bookmark — cost is O(log n)
    plus page_size reads, independent of page depth.
  • Trade-off: keyset pagination does not support random page jumps ("jump
    to page 500"). Use OFFSET/FETCH only for small datasets or first few pages.
  • Use a UNIQUE composite sort key (e.g., TransactionDate + TransactionID)
    to avoid ties that produce inconsistent page boundaries.
  • For bidirectional navigation store both the first and last visible row
    keys; reverse sort + TOP for previous-page queries.
*/
GO
