# Scenario 06: Index Fragmentation — REBUILD with FILLFACTOR

## Description

Demonstrates two types of index fragmentation and the effect of `REORGANIZE` vs `REBUILD WITH (FILLFACTOR=85)` on physical and logical I/O. A dedicated `FragDemo` table is created with a non-clustered index built at `FILLFACTOR=100`, then 500,000 rows are inserted in random `AccountID` order to cause page splits (logical fragmentation), followed by deletion of 30% of rows to create ghost records (sparse pages). The scenario shows that `REORGANIZE` restores physical page order (physical reads recover) but leaves page density unchanged (logical reads unchanged), while `REBUILD` additionally reclaims ghost records and re-applies fill factor — reducing both logical and physical reads.

## How to Run

1. Run `before.sql` — creates `FragDemo`, inserts 500K rows with random `AccountID` to trigger NCI page splits at `FILLFACTOR=100`, deletes 30% of rows, then measures fragmentation and benchmarks a cold-cache full scan.
2. Run `optimization.sql` — applies `ALTER INDEX … REORGANIZE` to both indexes, then re-measures fragmentation and scan performance to show page-order recovery.
3. Run `after.sql` — applies `ALTER INDEX … REBUILD WITH (FILLFACTOR=85)` to both indexes, then shows the final fragmentation levels, improved logical and physical reads, and the adaptive maintenance script for the entire database.

> **Note:** Use `DBCC DROPCLEANBUFFERS` (requires `sysadmin`) before each benchmark block to evict clean pages from the buffer pool and force storage reads. Without this step, physical read counts will be 0 (data is already cached).

## Environment

| Setting | Value |
|---------|-------|
| SQL Server version | <!-- e.g. SQL Server 2022 Developer Edition --> |
| Hardware | <!-- e.g. 16-core / 64 GB RAM, NVMe SSD --> |
| FragDemo row count (before deletion) | 500,000 |
| FragDemo row count (after 30% deletion) | ~350,000 |

## Fragmentation Results

| Metric | Fragmented | After REORGANIZE | After REBUILD |
|--------|-----------|------------------|---------------|
| NCI `avg_fragmentation_in_percent` | <!-- e.g. 73.42% --> | <!-- e.g. 1.82% --> | <!-- e.g. 0.12% --> |
| CI `avg_fragmentation_in_percent` | <!-- e.g. 21.07% --> | <!-- e.g. 0.54% --> | <!-- e.g. 0.09% --> |
| CI page count | <!-- e.g. 3,521 --> | <!-- e.g. 3,521 (same) --> | <!-- e.g. 2,201 (-37%) --> |
| `ghost_record_count` | <!-- e.g. 150,000+ --> | <!-- e.g. low --> | <!-- e.g. 0 --> |

## Scan Benchmark (cold cache)

| Metric | Fragmented | After REORGANIZE | After REBUILD |
|--------|-----------|------------------|---------------|
| Logical reads | <!-- e.g. 3,521 --> | <!-- e.g. 3,521 (same) --> | <!-- e.g. 2,201 (-37%) --> |
| Physical reads | <!-- e.g. 482 --> | <!-- e.g. 8 (60×) --> | <!-- e.g. 3 (161×) --> |
| Elapsed time | <!-- e.g. 890 ms --> | <!-- e.g. 147 ms --> | <!-- e.g. 102 ms --> |
| Improvement vs. baseline | — | <!-- e.g. 6× faster --> | <!-- e.g. 8.7× faster --> |

## REORGANIZE vs REBUILD

| Feature | REORGANIZE | REBUILD |
|---------|-----------|---------|
| Fixes page logical order | ✅ | ✅ |
| Removes ghost records | Partially | ✅ Fully |
| Re-applies FILLFACTOR | ❌ | ✅ |
| Reduces logical read count | ❌ | ✅ |
| Updates statistics | ❌ | ✅ |
| Online (no table lock) | ✅ Always | ✅ `ONLINE=ON` (Enterprise) |
| Interruptible | ✅ | ❌ |

## Decision Thresholds

| Fragmentation | `page_count` | Recommended Action |
|---|---|---|
| Any | < 100 | `UPDATE STATISTICS` only |
| < 5% | ≥ 100 | No action |
| 5–30% | ≥ 100 | `ALTER INDEX … REORGANIZE` |
| > 30% | ≥ 100 | `ALTER INDEX … REBUILD WITH (FILLFACTOR = 85, ONLINE = ON)` |

<!-- Key observations:
  - FILLFACTOR=100 guarantees page splits on any out-of-order insert: no headroom = immediate split = two ~50%-full pages.
  - REORGANIZE restores physical page ORDER → sequential I/O → physical reads recover dramatically.
  - REORGANIZE does NOT change page DENSITY → logical read count stays the same.
  - REBUILD removes ghost records, applies fill factor, and rebuilds the entire B-tree → both logical and physical reads recover.
  - Fragmentation affects physical I/O most severely on storage-bound systems or after cold-cache events (e.g. morning after a nightly batch that caused many splits/deletes).
-->
