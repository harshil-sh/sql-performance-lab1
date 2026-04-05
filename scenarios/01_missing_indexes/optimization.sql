-- =============================================================================
-- SQL Server Performance Lab
-- File: scenarios/01_missing_indexes/optimization.sql
-- Scenario: Missing Indexes — OPTIMIZATION (create recommended indexes)
--
-- Creates the two non-clustered indexes recommended by the Missing Index DMV
-- after the baseline queries in before.sql have been executed.
--
-- Run AFTER: scenarios/01_missing_indexes/before.sql
-- Run BEFORE: scenarios/01_missing_indexes/after.sql
-- =============================================================================

USE BankingLab;
GO

-- -----------------------------------------------------------------------
-- Index 1: AccountID equality lookups
-- Supports: WHERE AccountID = <value>
-- -----------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID
    ON dbo.Transactions (AccountID)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

-- -----------------------------------------------------------------------
-- Index 2: TransactionDate range scans
-- Supports: WHERE TransactionDate >= <start> AND TransactionDate < <end>
-- -----------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_Transactions_TransactionDate
    ON dbo.Transactions (TransactionDate)
    WITH (FILLFACTOR = 90, SORT_IN_TEMPDB = ON, ONLINE = ON);

GO

-- -----------------------------------------------------------------------
-- VERIFICATION: confirm both indexes were created successfully
-- -----------------------------------------------------------------------
SELECT
    i.name          AS IndexName,
    i.type_desc     AS IndexType,
    c.name          AS KeyColumn,
    ic.key_ordinal  AS KeyOrdinal
FROM   sys.indexes       i
JOIN   sys.index_columns ic ON ic.object_id = i.object_id
                            AND ic.index_id  = i.index_id
JOIN   sys.columns       c  ON c.object_id  = i.object_id
                            AND c.column_id  = ic.column_id
WHERE  OBJECT_NAME(i.object_id) = 'Transactions'
  AND  i.name IN ('IX_Transactions_AccountID', 'IX_Transactions_TransactionDate')
ORDER  BY i.name, ic.key_ordinal;
GO

-- Next step: run scenarios/01_missing_indexes/after.sql
