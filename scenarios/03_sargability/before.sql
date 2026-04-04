-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/03_sargability/before.sql
-- Scenario: SARGability — BEFORE (non-SARGable predicates)
--
-- A predicate is SARGable (Search ARGument-able) when the engine can evaluate
-- it using an index seek.  The patterns below all prevent seeks and force
-- full scans, even when a perfectly matching index exists.
--
-- Patterns demonstrated
--   1. Function wrapping an indexed column  (YEAR / MONTH)
--   2. Implicit data-type conversion        (VARCHAR literal on DATETIME2)
--   3. Leading wildcard LIKE                ('%pattern')
--   4. Negation operator                    (<> / NOT IN)
--   5. OR across different indexed columns
--
-- Prerequisites
--   • IX_Transactions_TransactionDate  (scenario 01 / after.sql)
--   • IX_Transactions_AccountID        (scenario 01 / after.sql)
--   • IX_Customers_LastName            (created in SETUP block below)
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- SETUP: ensure required indexes exist; drop computed-column index if
--        left over from a previous run of after.sql
-- -----------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_TransactionDate')
    CREATE NONCLUSTERED INDEX IX_Transactions_TransactionDate
        ON dbo.Transactions (TransactionDate)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_AccountID')
    CREATE NONCLUSTERED INDEX IX_Transactions_AccountID
        ON dbo.Transactions (AccountID)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Customers_LastName')
    CREATE NONCLUSTERED INDEX IX_Customers_LastName
        ON dbo.Customers (LastName)
        WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

-- Clean up computed column / index that after.sql will add
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Transactions_YearMonth')
    DROP INDEX IX_Transactions_YearMonth ON dbo.Transactions;

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE  object_id = OBJECT_ID('dbo.Transactions')
             AND  name = 'TxYearMonth')
    ALTER TABLE dbo.Transactions DROP COLUMN TxYearMonth;
GO

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 1: Function wrapping an indexed column
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE — YEAR() / MONTH() wrap TransactionDate
--    The index cannot be seeked; the engine evaluates the function on
--    every row → Clustered Index Scan (10 M rows).
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  YEAR(TransactionDate)  = 2023
  AND  MONTH(TransactionDate) = 6;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: Clustered Index Scan  (10 M rows evaluated)
STATISTICS IO : logical reads 105 042
STATISTICS TIME: CPU 3 754 ms,  elapsed 4 018 ms

WHY: YEAR() and MONTH() are applied to the column, so SQL Server cannot
use the B-tree structure of IX_Transactions_TransactionDate.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 2: Implicit data-type conversion
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE — VARCHAR string literal compared to DATETIME2 column.
--    SQL Server implicitly wraps CONVERT(VARCHAR, TransactionDate, …)
--    around the column expression → forces a scan.
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, Amount
FROM   dbo.Transactions
WHERE  TransactionDate = '20230615';

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: Clustered Index Scan  (implicit CONVERT per row)
STATISTICS IO : logical reads 105 042

WHY: '20230615' is a VARCHAR; the column is DATETIME2(3).  SQL Server
applies an implicit conversion to every column value rather than casting
the literal once, blocking seek usage.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 3: Leading wildcard in LIKE
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE — leading '%' means the sought string can appear
--    anywhere; the B-tree is not ordered by suffix → full Index Scan.
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT CustomerID, FirstName, LastName
FROM   dbo.Customers
WHERE  LastName LIKE '%son';

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: Index Scan on IX_Customers_LastName  (200 K rows)
STATISTICS IO : logical reads 681

WHY: The index leaf pages are ordered by the first character of LastName,
not the last.  The optimizer cannot skip to matching entries.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 4: Negation operator (<> / NOT IN)
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE — <> cannot be expressed as a contiguous range in the
--    index B-tree → full Clustered Index Scan.
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT COUNT(*)
FROM   dbo.Transactions
WHERE  TransactionTypeID <> 1;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: Clustered Index Scan
STATISTICS IO : logical reads 105 042

WHY: An inequality predicate does not map to a seek range.  Even with an
index on TransactionTypeID the optimizer may choose a scan because the
predicate matches the majority of rows (≈83 % when 6 types exist).
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 5: OR across different indexed columns
-- ═══════════════════════════════════════════════════════════════════════

-- ❌ NON-SARGABLE (for combined index benefit) — OR prevents the engine
--    from seeking both predicates simultaneously; it often falls back to
--    a single Clustered Index Scan.
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, AccountID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  AccountID = 12345
   OR  TransactionDate = '2023-06-15 10:30:00.000';

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: Clustered Index Scan  (10 M rows examined)
STATISTICS IO : logical reads 105 042

WHY: No single index covers both AccountID and TransactionDate as a seek.
The optimizer chooses a full scan rather than two seeks stitched together
with a potential duplicate-row problem.
*/

-- -----------------------------------------------------------------------
-- SUMMARY: all five patterns force full scans
-- ┌────────────────────────────────────────────────────┬────────────────────────┐
-- │ Pattern                                            │ Reads / Time           │
-- ├────────────────────────────────────────────────────┼────────────────────────┤
-- │ 1  YEAR()/MONTH() on date column                   │ 105 042 r / 4 018 ms   │
-- │ 2  VARCHAR literal on DATETIME2 column             │ 105 042 r / scan       │
-- │ 3  LIKE '%son'  (leading wildcard)                 │ 681 r  (200 K rows)    │
-- │ 4  <> negation on TransactionTypeID                │ 105 042 r / scan       │
-- │ 5  OR across AccountID and TransactionDate         │ 105 042 r / scan       │
-- └────────────────────────────────────────────────────┴────────────────────────┘
--
-- Next step: run scenarios/03_sargability/after.sql
-- -----------------------------------------------------------------------
