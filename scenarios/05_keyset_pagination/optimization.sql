-- =============================================================================
-- SQL Server Performance Lab
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
-- =============================================================================

USE BankingLab;
GO

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
