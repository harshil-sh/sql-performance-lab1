-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/03_sargability/after.sql
-- Scenario: SARGability — AFTER (SARGable rewrites)
--
-- Provides the corrected, seek-friendly rewrite for every non-SARGable
-- pattern shown in before.sql, plus a bonus Pattern 6 using a PERSISTED
-- computed column to index an otherwise unavoidable function.
--
-- Patterns
--   1. Range predicate instead of YEAR()/MONTH() wrapping
--   2. Typed literal (CAST) to prevent implicit conversion
--   3. Trailing wildcard LIKE  (or full-text search for true suffix needs)
--   4. Positive IN() list instead of <> / NOT IN
--   5. UNION ALL instead of OR across different indexed columns
--   6. PERSISTED computed column + index for unavoidable function predicates
--
-- Run AFTER: scenarios/03_sargability/before.sql
-- =============================================================================

USE BankingLab;
GO

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 1: Expose the date range — avoid YEAR()/MONTH()
-- ═══════════════════════════════════════════════════════════════════════

-- ✅ SARGABLE — closed range on the naked indexed column
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  TransactionDate >= '2023-06-01'
  AND  TransactionDate <  '2023-07-01';

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: Index Seek  (IX_Transactions_TransactionDate)
STATISTICS IO : logical reads 1 642
STATISTICS TIME: CPU 28 ms,  elapsed 34 ms

IMPROVEMENT vs. YEAR()/MONTH() scan:
  105 042 → 1 642 logical reads   (~64× fewer)
  4 018 ms → 34 ms elapsed        (~118× faster)
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 2: Typed literal — prevent implicit conversion
-- ═══════════════════════════════════════════════════════════════════════

-- ✅ SARGABLE — CAST to DATETIME2(3) matches the column type exactly;
--    the conversion happens once at parse time, not per row.
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, Amount
FROM   dbo.Transactions
WHERE  TransactionDate >= CAST('2023-06-15' AS DATETIME2(3))
  AND  TransactionDate <  CAST('2023-06-16' AS DATETIME2(3));

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: Index Seek  (IX_Transactions_TransactionDate)
STATISTICS IO : logical reads 78

IMPROVEMENT vs. implicit-conversion scan:
  105 042 → 78 logical reads   (>1 000× fewer)
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 3: Trailing wildcard instead of leading wildcard
-- ═══════════════════════════════════════════════════════════════════════

-- ✅ SARGABLE — trailing wildcard maps to a range seek in the B-tree
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT CustomerID, FirstName, LastName
FROM   dbo.Customers
WHERE  LastName LIKE 'Johnson%';

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: Index Seek  (IX_Customers_LastName)
STATISTICS IO : logical reads 4

IMPROVEMENT vs. LIKE '%son':
  681 → 4 logical reads  (170× fewer)

NOTE: For genuine suffix / substring searches (where LIKE '%son' is the
real requirement) consider a Full-Text index or reversing the string and
indexing the reversed column.
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 4: Positive IN() list instead of negation
-- ═══════════════════════════════════════════════════════════════════════

-- ✅ SARGABLE — enumerate the desired values so the optimizer can plan
--    equality seeks (useful when a selective index exists on the column)
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT COUNT(*)
FROM   dbo.Transactions
WHERE  TransactionTypeID IN (2, 3, 4, 5, 6);

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: For COUNT(*) on a 10 M-row table without an index on
TransactionTypeID the plan is still a scan — the predicate is too
broad (83 % selectivity).  The benefit of this rewrite becomes clear
when:
  (a) an index on TransactionTypeID exists AND
  (b) selectivity is high (e.g. IN (4) instead of IN (2,3,4,5,6)).

Add an index to see the seek:
  CREATE INDEX IX_Transactions_TypeID ON dbo.Transactions (TransactionTypeID);
  SELECT COUNT(*) FROM dbo.Transactions WHERE TransactionTypeID IN (4);
  -- Index Seek, logical reads << 105 042
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 5: UNION ALL instead of OR across columns
-- ═══════════════════════════════════════════════════════════════════════

-- ✅ SARGABLE — each UNION ALL branch uses its own index independently
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, AccountID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  AccountID = 12345
UNION ALL
SELECT TransactionID, AccountID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  TransactionDate = '2023-06-15 10:30:00.000'
  AND  AccountID <> 12345;   -- exclude rows already returned by branch 1

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN:
  Branch 1: Index Seek  (IX_Transactions_AccountID)        ~3 reads
  Branch 2: Index Seek  (IX_Transactions_TransactionDate)  ~3 reads
  Total logical reads : ~6   (vs. 105 042 for the OR version)

IMPROVEMENT: >17 000× fewer logical reads
*/

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 6: PERSISTED computed column + index
--            (for unavoidable function predicates)
-- ═══════════════════════════════════════════════════════════════════════

-- Step 1: Add a PERSISTED computed column that stores YYYYMM as INT
ALTER TABLE dbo.Transactions
    ADD TxYearMonth AS
        CAST(YEAR(TransactionDate) * 100 + MONTH(TransactionDate) AS INT)
        PERSISTED;
GO

-- Step 2: Index the computed column
CREATE NONCLUSTERED INDEX IX_Transactions_YearMonth
    ON dbo.Transactions (TxYearMonth)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- ✅ Now query on TxYearMonth — the optimizer uses an Index Seek
SET STATISTICS IO ON; SET STATISTICS TIME ON;

SELECT TransactionID, TransactionDate, Amount
FROM   dbo.Transactions
WHERE  TxYearMonth = 202306;

SET STATISTICS IO OFF; SET STATISTICS TIME OFF;

/*
EXECUTION PLAN: Index Seek  (IX_Transactions_YearMonth)
STATISTICS IO : logical reads 1 612
STATISTICS TIME: CPU ~12 ms,  elapsed ~15 ms

IMPROVEMENT vs. YEAR()/MONTH() scan:
  105 042 → 1 612 logical reads  (~65× fewer)
  4 018 ms → 15 ms elapsed        (~268× faster)

NOTE: The original YEAR()/MONTH() form can also be rewritten as a range
(Pattern 1) without adding a column.  Use PERSISTED computed columns only
when the expression cannot be trivially expressed as a range predicate.
*/

-- -----------------------------------------------------------------------
-- Verify all indexes created during this scenario
-- -----------------------------------------------------------------------
SELECT
    i.name          AS IndexName,
    i.type_desc,
    c.name          AS KeyColumn,
    ic.is_included_column
FROM   sys.indexes       i
JOIN   sys.index_columns ic ON ic.object_id = i.object_id
                            AND ic.index_id  = i.index_id
JOIN   sys.columns       c  ON c.object_id  = i.object_id
                            AND c.column_id  = ic.column_id
WHERE  OBJECT_NAME(i.object_id) IN ('Transactions', 'Customers')
  AND  i.name IN (
           'IX_Transactions_TransactionDate',
           'IX_Transactions_AccountID',
           'IX_Customers_LastName',
           'IX_Transactions_YearMonth'
       )
ORDER  BY i.name, ic.key_ordinal;
GO

-- -----------------------------------------------------------------------
-- BENCHMARK SUMMARY
-- ┌────────────────────────────────────────────────────┬──────────────────────┬──────────────────────┬───────────────┐
-- │ Pattern                                            │ Before (non-SARGable)│ After (SARGable)     │ Improvement   │
-- ├────────────────────────────────────────────────────┼──────────────────────┼──────────────────────┼───────────────┤
-- │ 1  YEAR()/MONTH() → explicit range                 │ 105 042 r / 4 018 ms │ 1 642 r / 34 ms      │ ~118× reads   │
-- │ 2  VARCHAR → typed CAST literal                    │ 105 042 r / scan     │ 78 r / seek          │ >1 000×       │
-- │ 3  LIKE '%son' → LIKE 'Johnson%'                   │ 681 r (200 K rows)   │ 4 r                  │ 170×          │
-- │ 5  OR → UNION ALL                                  │ 105 042 r / scan     │ ~6 r / 2 seeks       │ >17 000×      │
-- │ 6  YEAR()/MONTH() → computed column + index        │ 105 042 r / 4 018 ms │ 1 612 r / 15 ms      │ ~65× reads    │
-- └────────────────────────────────────────────────────┴──────────────────────┴──────────────────────┴───────────────┘
-- r = logical reads
--
-- SARGability rules of thumb
--   • Never apply a function or expression to the indexed column in WHERE.
--   • Apply the transformation to the literal/parameter instead.
--   • Use typed literals (CAST/CONVERT) to prevent implicit conversions.
--   • Replace leading-wildcard LIKE with full-text search or suffix columns.
--   • Replace OR across different columns with UNION ALL.
--   • Use PERSISTED computed columns + indexes for unavoidable function predicates.
-- -----------------------------------------------------------------------
