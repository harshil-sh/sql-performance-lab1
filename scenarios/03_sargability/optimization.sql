-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/03_sargability/optimization.sql
-- Scenario: SARGability — OPTIMIZATION (schema changes for Pattern 6)
--
-- Patterns 1–5 are addressed by rewriting the query (no schema change needed).
-- Pattern 6 requires a PERSISTED computed column and a supporting index so
-- that an otherwise unavoidable function predicate can use an Index Seek.
--
-- Run AFTER: scenarios/03_sargability/before.sql
-- Run BEFORE: scenarios/03_sargability/after.sql
-- =============================================================================

USE BankingLab;
GO

-- ═══════════════════════════════════════════════════════════════════════
-- PATTERN 6: PERSISTED computed column + index
--            Use when the function predicate cannot be rewritten as a range.
-- ═══════════════════════════════════════════════════════════════════════

-- Step 1: Add a PERSISTED computed column that stores YYYYMM as INT.
--         PERSISTED means the value is stored on disk and kept in sync
--         with TransactionDate by the engine — it can be indexed.
ALTER TABLE dbo.Transactions
    ADD TxYearMonth AS
        CAST(YEAR(TransactionDate) * 100 + MONTH(TransactionDate) AS INT)
        PERSISTED;
GO

-- Step 2: Create a non-clustered index on the computed column.
--         Queries that filter on TxYearMonth = <YYYYMM> will now seek.
CREATE NONCLUSTERED INDEX IX_Transactions_YearMonth
    ON dbo.Transactions (TxYearMonth)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
-- VERIFICATION: confirm the computed column and index exist
-- -----------------------------------------------------------------------
SELECT
    c.name              AS ColumnName,
    c.is_computed,
    c.is_persisted,
    cc.definition       AS ComputedExpression
FROM   sys.columns          c
JOIN   sys.computed_columns cc ON cc.object_id = c.object_id
                               AND cc.column_id  = c.column_id
WHERE  c.object_id = OBJECT_ID('dbo.Transactions')
  AND  c.name = 'TxYearMonth';

SELECT
    i.name          AS IndexName,
    i.type_desc,
    c.name          AS KeyColumn
FROM   sys.indexes       i
JOIN   sys.index_columns ic ON ic.object_id = i.object_id
                            AND ic.index_id  = i.index_id
JOIN   sys.columns       c  ON c.object_id  = i.object_id
                            AND c.column_id  = ic.column_id
WHERE  OBJECT_NAME(i.object_id) = 'Transactions'
  AND  i.name = 'IX_Transactions_YearMonth';
GO

-- Next step: run scenarios/03_sargability/after.sql
