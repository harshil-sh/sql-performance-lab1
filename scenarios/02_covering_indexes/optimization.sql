-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/02_covering_indexes/optimization.sql
-- Scenario: Covering Indexes — OPTIMIZATION (add INCLUDE columns)
--
-- Replaces the bare key-only index with a covering index that stores all
-- projected columns at the leaf level, eliminating every Key Lookup.
--
-- Run AFTER: scenarios/02_covering_indexes/before.sql
-- Run BEFORE: scenarios/02_covering_indexes/after.sql
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- CREATE COVERING INDEX
-- Key    : AccountID  (search predicate — same as the bare index)
-- INCLUDE: every non-key column projected by the benchmark queries
--          so that all data is available at the index leaf without
--          a Key Lookup back to the clustered index.
-- -----------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_Covering
    ON dbo.Transactions (AccountID)
    INCLUDE (TransactionDate, Amount, BalanceAfter, Description)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
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
