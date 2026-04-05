<<<<<<< HEAD
# Scenario 02: Covering Indexes

## Description

Demonstrates how adding `INCLUDE` columns to a non-clustered index eliminates costly Key Lookups. When a query projects columns that are not stored in the index key, the engine must perform one random I/O back to the clustered index per qualifying row. Covering the index removes this overhead entirely.

## How to Run

1. Run `before.sql` — ensures only the bare key-only index exists and executes baseline queries.
2. Run `optimization.sql` — creates the covering index with `INCLUDE` columns.
3. Run `after.sql` — re-runs the same queries to confirm Key Lookup elimination.

## Environment

| Setting | Value |
|---------|-------|
| SQL Server version | <!-- e.g. SQL Server 2022 Developer Edition --> |
| Hardware | <!-- e.g. 16-core / 64 GB RAM, NVMe SSD --> |
| Table row count | <!-- e.g. 10,000,000 --> |

## Performance Results

### Before (key-only index `IX_Transactions_AccountID`)

| Query | Execution Plan | Logical Reads | Elapsed Time |
|-------|---------------|---------------|--------------|
| Q1 — `AccountID = 42000` (~17 rows) | <!-- e.g. Index Seek + Key Lookup × 17 --> | <!-- e.g. 20 --> | <!-- e.g. 2 ms --> |
| Q2 — `AccountID BETWEEN 1 AND 200` (~3,400 rows) | <!-- e.g. Index Seek + Key Lookup × 3,400 --> | <!-- e.g. 6,817 --> | <!-- e.g. 22 ms --> |

### After (covering index `IX_Transactions_AccountID_Covering`)

| Query | Execution Plan | Logical Reads | Elapsed Time |
|-------|---------------|---------------|--------------|
| Q1 — `AccountID = 42000` (~17 rows) | <!-- e.g. Index Seek only (no Key Lookup) --> | <!-- e.g. 3 --> | <!-- e.g. 0 ms --> |
| Q2 — `AccountID BETWEEN 1 AND 200` (~3,400 rows) | <!-- e.g. Index Seek only (range scan) --> | <!-- e.g. 85 --> | <!-- e.g. 1 ms --> |

### Summary

| Query | Before reads | After reads | Improvement |
|-------|-------------|------------|-------------|
| Q1 (~17 rows) | <!-- TODO --> | <!-- TODO --> | <!-- e.g. 6.7× --> |
| Q2 (~3,400 rows) | <!-- TODO --> | <!-- TODO --> | <!-- e.g. 80× --> |

### Index Storage Trade-off

| Index | Estimated Size |
|-------|---------------|
| `IX_Transactions_AccountID` (key only) | <!-- e.g. ~80 MB --> |
| `IX_Transactions_AccountID_Covering` (key + includes) | <!-- e.g. ~240 MB --> |

<!-- Key observations:
  - Key Lookup cost is proportional to result-set size, not table size.
  - Covering the index stores INCLUDE columns at the leaf level — no clustered index visit needed.
  - Balance I/O savings against write amplification and storage overhead on INSERT/UPDATE workloads.
-->

## Next Step

See [scenarios/03_sargability/](../03_sargability/) to learn how predicate rewrites affect index usability.
=======
# Scenario: 02 covering indexes

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
