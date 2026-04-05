-- =============================================================================
-- SQL Server Performance Lab
<<<<<<< HEAD
-- File: scenarios/05_keyset_pagination/optimization.sql
-- Scenario: Keyset Pagination — OPTIMIZATION (keyset pattern + index analysis)
--
-- The performance problem with OFFSET/FETCH is algorithmic, not an indexing gap.
-- Even with an optimal covering index the engine cannot jump to row N — it must
-- count forward from row 1 on every request.
--
-- The fix is a query rewrite to KEYSET PAGINATION:
--   • The client stores the (TransactionDate, TransactionID) of the LAST row
--     returned on each page.
--   • The next-page query uses a WHERE clause that turns the skip into an
--     index SEEK directly to the continuation point — O(log n), constant cost.
--
-- The supporting index IX_Transactions_Date_ID (created in before.sql SETUP)
-- is already optimal for keyset:
--   Key    (TransactionDate, TransactionID) — seek + unique sort order
--   INCLUDE (AccountID, Amount)            — covers all projected columns
-- No additional index is needed.
--
-- Run AFTER:  scenarios/05_keyset_pagination/before.sql
-- Run BEFORE: scenarios/05_keyset_pagination/after.sql
=======
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
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
-- =============================================================================

USE BankingLab;
GO

<<<<<<< HEAD
-- -----------------------------------------------------------------------
-- Verify the supporting index is in place
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
  AND  i.name = 'IX_Transactions_Date_ID'
ORDER  BY ic.is_included_column, ic.key_ordinal;
GO

-- -----------------------------------------------------------------------
-- Why this index enables keyset seeks
-- -----------------------------------------------------------------------
-- OFFSET/FETCH scans the index from the beginning on every call:
--
--   OFFSET 2 499 975: leaf pages 1 … 19 617 read, rows 1 … 2 499 975 discarded
--
-- Keyset WHERE clause:
--   WHERE (TransactionDate > @LastDate)
--      OR (TransactionDate = @LastDate AND TransactionID > @LastTxID)
--
-- SQL Server rewrites this OR as a single composite range seek:
--   SEEK: (TransactionDate, TransactionID) > (@LastDate, @LastTxID)
--
-- The B-tree descends directly to the first qualifying leaf entry:
--   3 pages read regardless of how deep the continuation point is.
--
-- -----------------------------------------------------------------------
-- The keyset OR pattern IS SARGable because the composite index key order
-- (TransactionDate, TransactionID) matches the inequality direction exactly.
-- A mixed-direction composite key (e.g. Date ASC, ID DESC) would require
-- two separate seeks unified with UNION ALL.
-- -----------------------------------------------------------------------

-- -----------------------------------------------------------------------
-- Index size: confirm the index is covering (no Key Lookups expected)
-- -----------------------------------------------------------------------
SELECT
    i.name                         AS IndexName,
    SUM(a.total_pages) * 8 / 1024  AS SizeMB
FROM   sys.indexes      i
JOIN   sys.partitions   p  ON p.object_id = i.object_id
                           AND p.index_id  = i.index_id
JOIN   sys.allocation_units a ON a.container_id = p.partition_id
WHERE  OBJECT_NAME(i.object_id) = 'Transactions'
  AND  i.name = 'IX_Transactions_Date_ID'
GROUP  BY i.name;
GO
-- Typical: ~160 MB  (10 M rows × (8+8) byte key + (4+9) byte INCLUDE + overhead)

-- -----------------------------------------------------------------------
-- TRADE-OFFS to be aware of before switching to keyset
-- -----------------------------------------------------------------------
/*
  FEATURE                 OFFSET / FETCH        KEYSET
  ──────────────────────  ───────────────────   ──────────────────────
  Random page jump        ✅ OFFSET n           ❌ must walk forward
  Deep-page performance   O(n) — degrades       O(log n) — constant
  Bidirectional           ✅ trivial            ✅ reverse inequality
  Stable pages            ❌ inserts shift rows ✅ seek is stable
  Total row count         COUNT(*) full scan    Approximate from catalog
  Client state required   ❌ stateless          ✅ store last (Date, ID)

  Use keyset for: infinite-scroll feeds, audit logs, any list > ~10 pages.
  Use OFFSET for: admin grids with random-access page jumps, small tables.
*/

-- Next step: run scenarios/05_keyset_pagination/after.sql
=======
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
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
