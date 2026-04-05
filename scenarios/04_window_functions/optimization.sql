-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/04_window_functions/optimization.sql
-- Scenario: Window Functions — OPTIMIZATION (composite supporting index)
--
-- Creates a composite non-clustered index on (AccountID, TransactionDate,
-- TransactionID) INCLUDE (Amount).  This index:
--   1. Enables range seeks by AccountID for the window partition.
--   2. Pre-orders leaf pages by (AccountID, TransactionDate, TransactionID),
--      matching the PARTITION BY / ORDER BY of the SUM OVER clause exactly,
--      so the optimizer produces a Window Spool with NO blocking Sort operator.
--   3. Covers Amount in the leaf so the window calculation requires no
--      Key Lookup into the clustered index.
--
-- Run AFTER:  scenarios/04_window_functions/before.sql
-- Run BEFORE: scenarios/04_window_functions/after.sql
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- CREATE SUPPORTING INDEX
-- Key    : AccountID        → satisfies PARTITION BY AccountID
--          TransactionDate  → satisfies ORDER BY TransactionDate (window order)
--          TransactionID    → tie-breaker; guarantees deterministic row order
-- INCLUDE: Amount           → column being aggregated; eliminates Key Lookup
-- -----------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_Date
    ON dbo.Transactions (AccountID, TransactionDate, TransactionID)
    INCLUDE (Amount)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);
GO

-- -----------------------------------------------------------------------
-- VERIFICATION: confirm index and its column layout
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
  AND  i.name = 'IX_Transactions_AccountID_Date'
ORDER  BY ic.is_included_column, ic.key_ordinal;
GO

-- -----------------------------------------------------------------------
-- Index size reference
-- -----------------------------------------------------------------------
SELECT
    i.name                         AS IndexName,
    SUM(a.total_pages) * 8 / 1024  AS SizeMB
FROM   sys.indexes      i
JOIN   sys.partitions   p  ON p.object_id = i.object_id
                           AND p.index_id  = i.index_id
JOIN   sys.allocation_units a ON a.container_id = p.partition_id
WHERE  OBJECT_NAME(i.object_id) = 'Transactions'
  AND  i.name IN ('IX_Transactions_AccountID',
                  'IX_Transactions_AccountID_Date')
GROUP  BY i.name;
GO
-- Typical results:
--   IX_Transactions_AccountID         ~  80 MB  (AccountID key only)
--   IX_Transactions_AccountID_Date    ~ 320 MB  (3-column key + Amount INCLUDE)
-- The extra ~240 MB eliminates the Sort operator and all Key Lookups
-- for every window-function query partitioned by AccountID.

-- Next step: run scenarios/04_window_functions/after.sql
