-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/05_keyset_pagination/before.sql
<<<<<<< HEAD
-- Scenario: Keyset Pagination — BEFORE (OFFSET/FETCH baseline)
--
-- Demonstrates the O(n) page-traversal cost of OFFSET n ROWS FETCH NEXT k ROWS.
-- Even with an optimal composite index, the engine must skip every row before
-- the requested offset on every call — cost grows linearly with page depth.
--
-- The composite sort index (IX_Transactions_Date_ID) is created in SETUP so
-- that OFFSET/FETCH operates under the best possible conditions.  The
-- degradation shown is therefore purely algorithmic, not a missing-index problem.
--
-- Run BEFORE: scenarios/05_keyset_pagination/optimization.sql
=======
-- Scenario: Keyset Pagination - BEFORE
--
-- Baseline pagination using OFFSET/FETCH. Cost grows with page depth.
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
-- =============================================================================

USE BankingLab;
GO

<<<<<<< HEAD
-- -----------------------------------------------------------------------
-- SETUP: create the composite sort index so OFFSET has optimal support.
--        Drop it first only if re-running to reset a fragmented state.
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
-- Query 1: Page 1 — OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY
--
-- The engine reads from the very first leaf page and stops after 25 rows.
-- Cost is essentially a seek + 25 rows — identical to keyset at this depth.
--
-- Expected plan : Index Seek (IX_Transactions_Date_ID) → Top
-- Expected I/O  : 3 logical reads
-- Expected time : 0 ms
-- ═══════════════════════════════════════════════════════════════════════
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount
FROM   dbo.Transactions
ORDER  BY TransactionDate, TransactionID
OFFSET 0 ROWS FETCH NEXT 25 ROWS ONLY;

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

NOTE: Page 1 is indistinguishable from keyset.  The difference only
emerges as the offset grows — the engine cannot jump to row N; it must
count forward from row 1 every time.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- Query 2: Page 2 000 — OFFSET 49 975 ROWS FETCH NEXT 25 ROWS ONLY
--
-- The engine traverses all 49 975 leaf entries before returning 25 rows.
-- Despite a covering index, every skipped row still costs a page read.
--
-- Expected plan : Index Scan (IX_Transactions_Date_ID) → Top
-- Expected I/O  : ~392 logical reads
-- Expected time : ~49 ms
-- ═══════════════════════════════════════════════════════════════════════
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount
FROM   dbo.Transactions
ORDER  BY TransactionDate, TransactionID
OFFSET 49975 ROWS FETCH NEXT 25 ROWS ONLY;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Top  (25 rows, skip 49 975)
         └─ Index Scan  (IX_Transactions_Date_ID)    ← scan, not seek
              Actual rows read : 50 000
              Logical reads    : 392

STATISTICS IO : Table 'Transactions'. Scan count 1, logical reads 392
STATISTICS TIME: CPU 31 ms,  elapsed 49 ms

WHY: The optimizer must materialise 49 975 index rows before it can
return row 49 976.  It cannot "skip ahead" in a B-tree — every skipped
row still crosses a leaf page boundary, accumulating reads linearly.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- Query 3: Page 100 000 — OFFSET 2 499 975 ROWS FETCH NEXT 25 ROWS ONLY
--
-- At this depth the engine traverses 2.5 million index leaf entries.
-- The entire first quarter of the index is read just to discard it.
--
-- Expected plan : Index Scan (IX_Transactions_Date_ID) → Top
-- Expected I/O  : ~19 617 logical reads
-- Expected time : ~2 461 ms
-- ═══════════════════════════════════════════════════════════════════════
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount
FROM   dbo.Transactions
ORDER  BY TransactionDate, TransactionID
=======
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_Date_ID')
    DROP INDEX IX_Transactions_Date_ID ON dbo.Transactions;
GO

DECLARE @PageSize INT = 25;

-- Page 1
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount, Description
FROM dbo.Transactions
ORDER BY TransactionDate, TransactionID
OFFSET 0 ROWS FETCH NEXT @PageSize ROWS ONLY;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- Deep page (OFFSET cost becomes significant)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, AccountID, Amount, Description
FROM dbo.Transactions
ORDER BY TransactionDate, TransactionID
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
OFFSET 2499975 ROWS FETCH NEXT 25 ROWS ONLY;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
<<<<<<< HEAD

/*
EXECUTION PLAN
──────────────────────────────────────────────────────────────
  SELECT
    └─ Top  (25 rows, skip 2 499 975)
         └─ Index Scan  (IX_Transactions_Date_ID)
              Actual rows read : 2 500 000
              Logical reads    : 19 617

STATISTICS IO : Table 'Transactions'. Scan count 1, logical reads 19 617
STATISTICS TIME: CPU 2 198 ms,  elapsed 2 461 ms

COST GROWTH (linear with page depth):
  Page       1  → OFFSET         0  →      3 reads /    0 ms
  Page   2 000  → OFFSET    49 975  →    392 reads /   49 ms
  Page 100 000  → OFFSET 2 499 975  → 19 617 reads / 2 461 ms

Every page request at depth N re-reads the same N−1 pages as the
previous request.  Doubling the page number doubles the cost.
*/

-- -----------------------------------------------------------------------
-- BONUS: Total row count via COUNT(*) — another common pattern that scans
--
-- Expected I/O  : ~19 812 logical reads  (full index scan)
-- Expected time : ~2 243 ms
-- -----------------------------------------------------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT COUNT(*) AS TotalRows FROM dbo.Transactions;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
STATISTICS IO : Table 'Transactions'. Scan count 5, logical reads 19 812
STATISTICS TIME: CPU 1 847 ms,  elapsed 2 243 ms

Compare with approximate catalog count (after.sql):
  sys.dm_db_partition_stats → 2 reads, <1 ms, ±0.1% accuracy.
*/

-- -----------------------------------------------------------------------
-- SUMMARY
-- ┌───────────────────────────────────────────┬────────────────────────────┐
-- │ Query                                     │ Logical Reads / Elapsed    │
-- ├───────────────────────────────────────────┼────────────────────────────┤
-- │ OFFSET/FETCH page 1     (offset 0)        │     3 reads /     0 ms     │
-- │ OFFSET/FETCH page 2 000 (offset 49 975)   │   392 reads /    49 ms     │
-- │ OFFSET/FETCH page 100 K (offset 2 499 975)│ 19 617 reads / 2 461 ms    │
-- │ COUNT(*) total rows                       │ 19 812 reads / 2 243 ms    │
-- └───────────────────────────────────────────┴────────────────────────────┘
--
-- Next step: run scenarios/05_keyset_pagination/optimization.sql
-- -----------------------------------------------------------------------
=======
GO
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
