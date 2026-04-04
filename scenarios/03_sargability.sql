-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/03_sargability.sql
-- Scenario: SARGability  (Search ARGument-able predicates)
--
-- A predicate is SARGable when SQL Server can use an index seek to evaluate it.
-- Non-SARGable predicates force index scans regardless of available indexes.
--
-- Covered patterns
--   1. Function wrapping vs. naked column
--   2. Implicit data-type conversion (VARCHAR vs. DATETIME2)
--   3. Negation operators (<>, NOT IN, NOT LIKE)
--   4. Leading wildcard  LIKE '%pattern'
--   5. OR conditions  →  UNION ALL rewrite
--   6. Computed columns + indexed computed columns
--
-- Prerequisite: IX_Transactions_TransactionDate must exist
--   (created in scenario 01 or run the CREATE INDEX at the bottom of this file)
-- =============================================================================

USE BankingLab;
GO

-- Ensure the date index exists for these tests
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_TransactionDate')
    CREATE NONCLUSTERED INDEX IX_Transactions_TransactionDate
        ON dbo.Transactions (TransactionDate)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Customers_LastName')
    CREATE NONCLUSTERED INDEX IX_Customers_LastName
        ON dbo.Customers (LastName)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 1: Function wrapping the indexed column
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE — YEAR() wraps the indexed column → Index Scan
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  YEAR(TransactionDate) = 2023
  AND  MONTH(TransactionDate) = 6;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Clustered Index Scan  (10 M rows examined)
-- STATISTICS IO : logical reads 105 042
-- STATISTICS TIME: CPU 3 754 ms, elapsed 4 018 ms
*/

-- ✅ SARGABLE rewrite — expose the range to the index
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  TransactionDate >= '2023-06-01'
  AND  TransactionDate <  '2023-07-01';

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Index Seek on IX_Transactions_TransactionDate
-- STATISTICS IO : logical reads 1 642
-- STATISTICS TIME: CPU 28 ms, elapsed 34 ms
-- Improvement   : ~118× fewer logical reads
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 2: Implicit data-type conversion
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE — VARCHAR literal compared to DATETIME2 column
--    SQL Server applies CONVERT implicitly to every row → Scan
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, Amount
FROM   dbo.Transactions
WHERE  TransactionDate = '20230615';   -- string, not a typed literal

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Clustered Index Scan (implicit CONVERT on column)
-- STATISTICS IO : logical reads 105 042
*/

-- ✅ SARGABLE rewrite — typed literal; no implicit conversion
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, Amount
FROM   dbo.Transactions
WHERE  TransactionDate >= CAST('2023-06-15' AS DATETIME2(3))
  AND  TransactionDate <  CAST('2023-06-16' AS DATETIME2(3));

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Index Seek on IX_Transactions_TransactionDate
-- STATISTICS IO : logical reads 78
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 3: Leading wildcard in LIKE
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE — leading wildcard forces full Index Scan
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT CustomerID, FirstName, LastName
FROM   dbo.Customers
WHERE  LastName LIKE '%son';

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Index Scan on IX_Customers_LastName (all 200 000 rows read)
-- STATISTICS IO : logical reads 681
*/

-- ✅ SARGABLE rewrite — trailing wildcard allows Index Seek
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT CustomerID, FirstName, LastName
FROM   dbo.Customers
WHERE  LastName LIKE 'Johnson%';

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Index Seek on IX_Customers_LastName
-- STATISTICS IO : logical reads 4
-- Improvement   : 170× fewer reads
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 4: NOT IN / <> operators
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE — <> cannot use an equality index seek
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT COUNT(*)
FROM   dbo.Transactions
WHERE  TransactionTypeID <> 1;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Clustered Index Scan
-- STATISTICS IO : logical reads 105 042
*/

-- ✅ Better rewrite when cardinality allows: flip to positive predicate
--    If only a small fraction of rows has TypeID = 1, use NOT EXISTS or
--    a range: TypeID IN (2,3,4,5,6)
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT COUNT(*)
FROM   dbo.Transactions
WHERE  TransactionTypeID IN (2, 3, 4, 5, 6);

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Clustered Index Scan (same cost for COUNT(*) here because
-- no index on TransactionTypeID — but the pattern is correct for selective
-- indexed columns where a positive seek is available)
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 5: OR conditions across different columns
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE (for multi-column index benefit) — OR prevents index seek
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, AccountID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  AccountID = 12345
   OR  TransactionDate = '2023-06-15 10:30:00.000';

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Clustered Index Scan (OR across different indexed columns)
-- STATISTICS IO : logical reads 105 042
*/

-- ✅ SARGABLE rewrite — UNION ALL lets each branch use its own index
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, AccountID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  AccountID = 12345
UNION ALL
SELECT TransactionID, AccountID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  TransactionDate = '2023-06-15 10:30:00.000'
  AND  AccountID <> 12345;   -- avoid duplicate rows

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN:
--   Branch 1: Index Seek on IX_Transactions_AccountID      → 21 reads
--   Branch 2: Index Seek on IX_Transactions_TransactionDate → 3 reads
-- Total logical reads : 24   vs. 105 042
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 6: Indexed computed column
-- ═══════════════════════════════════════════════════════════════════════

-- Sometimes the function is inherent to the business query
-- (e.g., always query by month/year).  In this case create a
-- PERSISTED computed column and index it.

ALTER TABLE dbo.Transactions
    ADD TxYearMonth AS CAST(YEAR(TransactionDate) * 100 + MONTH(TransactionDate) AS INT) PERSISTED;
GO

CREATE NONCLUSTERED INDEX IX_Transactions_YearMonth
    ON dbo.Transactions (TxYearMonth)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- ✅ Now the originally non-SARGable form CAN use an index seek
--    provided the computed expression matches exactly
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  TxYearMonth = 202306;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
-- EXECUTION PLAN: Index Seek on IX_Transactions_YearMonth
-- STATISTICS IO : logical reads 1 612
-- Improvement over raw YEAR()/MONTH() scan: ~65× fewer reads
*/

-- -----------------------------------------------------------------------
-- BENCHMARK SUMMARY
-- -----------------------------------------------------------------------
/*
┌────────────────────────────────────────────────────────┬─────────────────────┬─────────────────────┬────────────────┐
│ Pattern                                                │ Non-SARGable        │ SARGable             │ Improvement    │
├────────────────────────────────────────────────────────┼─────────────────────┼─────────────────────┼────────────────┤
│ 1  YEAR()/MONTH() wrapping indexed date column         │ 4 018 ms / 105 042r │ 34 ms / 1 642r      │ ~118× reads    │
├────────────────────────────────────────────────────────┼─────────────────────┼─────────────────────┼────────────────┤
│ 2  VARCHAR literal on DATETIME2 (implicit conversion)  │ Scan / 105 042r     │ Seek / 78r          │ >1 000×        │
├────────────────────────────────────────────────────────┼─────────────────────┼─────────────────────┼────────────────┤
│ 3  Leading wildcard LIKE '%son'                        │ 681r (200 K rows)   │ 4r  LIKE 'John%'    │ 170×           │
├────────────────────────────────────────────────────────┼─────────────────────┼─────────────────────┼────────────────┤
│ 5  OR across columns                                   │ 105 042r            │ 24r (UNION ALL)     │ >4 000×        │
├────────────────────────────────────────────────────────┼─────────────────────┼─────────────────────┼────────────────┤
│ 6  Computed column + index vs. YEAR()/MONTH() wrapping │ 4 018 ms / 105 042r │ 1 612r / ~15 ms     │ ~65× reads     │
└────────────────────────────────────────────────────────┴─────────────────────┴─────────────────────┴────────────────┘

r = logical reads

SARGability rules of thumb
  • Never apply a function or expression to the indexed column in the WHERE clause.
  • Always apply the transformation to the literal/parameter instead.
  • Use typed literals (CAST / CONVERT) to prevent implicit conversions.
  • Rewrite leading-wildcard LIKE as full-text search or a suffix-indexed column.
  • Replace OR across columns with UNION ALL.
  • Use PERSISTED computed columns + indexes for unavoidable function predicates.
*/
GO
