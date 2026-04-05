<<<<<<< HEAD
# Scenario 05: Keyset Pagination vs OFFSET/FETCH

## Description

Demonstrates the O(n) page-traversal cost of `OFFSET n ROWS FETCH NEXT k ROWS ONLY` and replaces it with keyset pagination (the "seek method"). Even with an optimal composite covering index, OFFSET must count through every skipped row on every request — cost grows linearly with page depth. Keyset pagination stores a bookmark from the last row of each page and uses a `WHERE` clause that the optimizer resolves as a composite index seek, achieving O(log n) constant cost regardless of depth.

## How to Run

1. Run `before.sql` — creates the composite sort index, then executes `OFFSET/FETCH` at three page depths (page 1, 2 000, 100 000) and a `COUNT(*)` total to show linear cost growth.
2. Run `optimization.sql` — verifies the index layout, explains why the keyset `OR` pattern is SARGable, and documents the trade-offs between the two approaches.
3. Run `after.sql` — implements keyset pagination at the same three depths and shows the approximate catalog row count; all keyset reads are constant at 3 logical reads.

## Environment

| Setting | Value |
|---------|-------|
| SQL Server version | <!-- e.g. SQL Server 2022 Developer Edition --> |
| Hardware | <!-- e.g. 16-core / 64 GB RAM, NVMe SSD --> |
| Table row count | <!-- e.g. 10,000,000 --> |
| Page size | 25 rows |

## Supporting Index

`IX_Transactions_Date_ID` on `dbo.Transactions`:

| Column | Role |
|--------|------|
| `TransactionDate` (Key 1) | Primary sort — satisfies `ORDER BY` and keyset seek |
| `TransactionID` (Key 2) | Unique tie-breaker — guarantees deterministic page boundaries |
| `AccountID` (INCLUDE) | Covers projected column — eliminates Key Lookup |
| `Amount` (INCLUDE) | Covers projected column — eliminates Key Lookup |

## Performance Results

### OFFSET/FETCH (before)

| Page | Offset | Execution Plan | Logical Reads | Elapsed Time |
|------|--------|---------------|---------------|--------------|
| Page 1 | 0 | <!-- e.g. Index Seek → Top --> | <!-- e.g. 3 --> | <!-- e.g. 0 ms --> |
| Page 2 000 | 49 975 | <!-- e.g. Index Scan → Top --> | <!-- e.g. 392 --> | <!-- e.g. 49 ms --> |
| Page 100 000 | 2 499 975 | <!-- e.g. Index Scan → Top --> | <!-- e.g. 19,617 --> | <!-- e.g. 2,461 ms --> |
| Total row count | — | <!-- e.g. Index Scan (COUNT) --> | <!-- e.g. 19,812 --> | <!-- e.g. 2,243 ms --> |

### Keyset Pagination (after)

| Equivalent Page | Execution Plan | Logical Reads | Elapsed Time |
|-----------------|---------------|---------------|--------------|
| Page 1 | <!-- e.g. Index Seek → Top --> | <!-- e.g. 3 --> | <!-- e.g. 0 ms --> |
| Page 2 000 equiv. | <!-- e.g. Index Seek (composite range) → Top --> | <!-- e.g. 3 --> | <!-- e.g. 0 ms --> |
| Page 100 000 equiv. | <!-- e.g. Index Seek (composite range) → Top --> | <!-- e.g. 3 --> | <!-- e.g. 0 ms --> |
| Approximate row count | <!-- e.g. sys.dm_db_partition_stats → 2 reads --> | <!-- e.g. 2 --> | <!-- e.g. 0 ms --> |

### Summary

| Page Depth | OFFSET/FETCH reads | Keyset reads | Improvement |
|-----------|-------------------|-------------|-------------|
| Page 1 | <!-- TODO --> | <!-- TODO --> | identical |
| Page 2 000 | <!-- TODO --> | <!-- TODO --> | <!-- e.g. 131× --> |
| Page 100 000 | <!-- TODO --> | <!-- TODO --> | <!-- e.g. >6,500× --> |

## Trade-offs

| Feature | OFFSET/FETCH | Keyset |
|---------|-------------|--------|
| Random page jump | ✅ | ❌ must walk forward |
| Deep-page performance | O(n) — degrades linearly | O(log n) — constant |
| Bidirectional navigation | ✅ trivial | ✅ reverse inequality + sort |
| Stable pages under inserts | ❌ inserts shift rows | ✅ seek is stable |
| Total row count | `COUNT(*)` full scan | Approximate from catalog |
| Client state required | ❌ stateless | ✅ store last (Date, ID) |

<!-- Key observations:
  - The OR-based keyset WHERE clause is SARGable: SQL Server rewrites it as a composite range seek on (TransactionDate, TransactionID).
  - The unique secondary key (TransactionID) is critical — without it, ties on TransactionDate produce non-deterministic page boundaries.
  - The index key order must exactly match ORDER BY direction (both ASC here).
  - For mixed-direction sorts (Date ASC, ID DESC), use UNION ALL with separate seeks.
-->

## Next Step

See [scenarios/06_index_fragmentation/](../06_index_fragmentation/) to understand how B-tree page splits and fragmentation affect physical I/O.
=======
# Scenario: 05 keyset pagination

## Objective
[Add a one-paragraph objective for this scenario.]

## Files
- before.sql
- after.sql
- optimization.sql

## Execution Plan Analysis
### Before
[Paste plan shape, key operators, and bottlenecks.]

### After
[Paste plan shape changes and why they improved performance.]

## Results Table
| Query/Test | Logical Reads (Before) | Logical Reads (After) | CPU Time ms (Before) | CPU Time ms (After) | Notes |
|---|---:|---:|---:|---:|---|
| [Query 1] |  |  |  |  |  |
| [Query 2] |  |  |  |  |  |

## Notes
[Add caveats, assumptions, and environment details.]
>>>>>>> 35ed13f176cabce962f20f6a88667da75306794a
