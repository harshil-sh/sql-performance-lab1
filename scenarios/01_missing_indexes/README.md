<<<<<<< HEAD
# Scenario 01: Missing Indexes

## Description

Demonstrates the dramatic I/O improvement gained by adding non-clustered indexes to support common query predicates on the 10M-row `Transactions` table. Without indexes both queries perform a full Clustered Index Scan reading all ~820 MB of data pages regardless of result size.

## How to Run

1. Run `before.sql` — drops any relevant indexes and executes baseline queries.
2. Run `optimization.sql` — creates the recommended non-clustered indexes.
3. Run `after.sql` — re-runs the same queries to show the improved execution plans.

## Environment

| Setting | Value |
|---------|-------|
| SQL Server version | <!-- e.g. SQL Server 2022 Developer Edition --> |
| Hardware | <!-- e.g. 16-core / 64 GB RAM, NVMe SSD --> |
| Table row count | <!-- e.g. 10,000,000 --> |

## Performance Results

### Before (no non-clustered indexes)

| Query | Execution Plan | Logical Reads | Elapsed Time |
|-------|---------------|---------------|--------------|
| Q1 — `AccountID = 12345` | <!-- e.g. Clustered Index Scan --> | <!-- e.g. 105,042 --> | <!-- e.g. 1,560 ms --> |
| Q2 — `TransactionDate` Jan range | <!-- e.g. Clustered Index Scan --> | <!-- e.g. 105,042 --> | <!-- e.g. 4,102 ms --> |

### After (with `IX_Transactions_AccountID` + `IX_Transactions_TransactionDate`)

| Query | Execution Plan | Logical Reads | Elapsed Time |
|-------|---------------|---------------|--------------|
| Q1 — `AccountID = 12345` | <!-- e.g. Index Seek + Key Lookup --> | <!-- e.g. 21 --> | <!-- e.g. 1 ms --> |
| Q2 — `TransactionDate` Jan range | <!-- e.g. Index Seek + Key Lookups --> | <!-- e.g. 168,442 --> | <!-- e.g. 512 ms --> |

### Summary

| Query | Before | After | Improvement |
|-------|--------|-------|-------------|
| Q1 logical reads | <!-- TODO --> | <!-- TODO --> | <!-- e.g. ~5,000× --> |
| Q2 elapsed time | <!-- TODO --> | <!-- TODO --> | <!-- e.g. ~8× --> |

<!-- Key observations:
  - A single non-clustered index on a selective column can cut reads by >99%.
  - Q2 still has Key Lookup overhead — see scenario 02 (covering indexes) for the full solution.
  - After running before.sql, check sys.dm_db_missing_index_details for DMV recommendations.
-->

## Next Step

See [scenarios/02_covering_indexes/](../02_covering_indexes/) to eliminate the remaining Key Lookup overhead on Q2.
=======
# Scenario: 01 missing indexes

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
