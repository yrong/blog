---
author: Ron
catalog: true
date: 2017-07-08T00:00:00Z
tags:
- golang
- prometheus
title: prometheus v2.0 storage
url: /2017/07/08/prometheus/
---


Writing a Time Series Database from Scratch
<!--more-->


## Design

[Writing a Time Series Database from Scratch](https://fabxc.org/tsdb/)

## On-disk layout

```
./data/01BKGV7JBM69T2G1BGBGM6KB12
./data/01BKGV7JBM69T2G1BGBGM6KB12/meta.json
./data/01BKGV7JBM69T2G1BGBGM6KB12/wal
./data/01BKGV7JBM69T2G1BGBGM6KB12/wal/000002
./data/01BKGV7JBM69T2G1BGBGM6KB12/wal/000001
./data/01BKGTZQ1SYQJTR4PB43C8PD98
./data/01BKGTZQ1SYQJTR4PB43C8PD98/meta.json
./data/01BKGTZQ1SYQJTR4PB43C8PD98/index
./data/01BKGTZQ1SYQJTR4PB43C8PD98/chunks
./data/01BKGTZQ1SYQJTR4PB43C8PD98/chunks/000001
./data/01BKGTZQ1SYQJTR4PB43C8PD98/tombstones
./data/01BKGTZQ1HHWHV8FBJXW1Y3W0K
./data/01BKGTZQ1HHWHV8FBJXW1Y3W0K/meta.json
./data/01BKGTZQ1HHWHV8FBJXW1Y3W0K/wal
./data/01BKGTZQ1HHWHV8FBJXW1Y3W0K/wal/000001
./data/01BKGV7JC0RY8A6MACW02A2PJD
./data/01BKGV7JC0RY8A6MACW02A2PJD/meta.json
./data/01BKGV7JC0RY8A6MACW02A2PJD/index
./data/01BKGV7JC0RY8A6MACW02A2PJD/chunks
./data/01BKGV7JC0RY8A6MACW02A2PJD/chunks/000001
./data/01BKGV7JC0RY8A6MACW02A2PJD/tombstones
```

### disk-space-estimation

> needed_disk_space = retention_time_seconds * ingested_samples_per_second * bytes_per_sample

## metrix

v1.x

```
prometheus_local_storage_memory_series: 时间序列持有的内存当前块数量
prometheus_local_storage_memory_chunks: 在内存中持久块的当前数量
prometheus_local_storage_chunks_to_persist: 当前仍然需要持久化到磁盘的的内存块数量
prometheus_local_storage_persistence_urgency_score: 上述讨论的紧急程度分数
如果Prometheus处于冲动模式下，prometheus_local_storage_rushed_mode值等于1; 否则等于0.
```

v2.x

```
# HELP prometheus_tsdb_blocks_loaded Number of currently loaded data blocks
# TYPE prometheus_tsdb_blocks_loaded gauge
prometheus_tsdb_blocks_loaded 3
# HELP prometheus_tsdb_compaction_chunk_range Final time range of chunks on their first compaction
# TYPE prometheus_tsdb_compaction_chunk_range histogram
prometheus_tsdb_compaction_chunk_range_bucket{le="100"} 0
prometheus_tsdb_compaction_chunk_range_bucket{le="400"} 0
prometheus_tsdb_compaction_chunk_range_bucket{le="1600"} 0
prometheus_tsdb_compaction_chunk_range_bucket{le="6400"} 0
prometheus_tsdb_compaction_chunk_range_bucket{le="25600"} 0
prometheus_tsdb_compaction_chunk_range_bucket{le="102400"} 0
prometheus_tsdb_compaction_chunk_range_bucket{le="409600"} 0
prometheus_tsdb_compaction_chunk_range_bucket{le="1.6384e+06"} 1807
prometheus_tsdb_compaction_chunk_range_bucket{le="6.5536e+06"} 6022
prometheus_tsdb_compaction_chunk_range_bucket{le="2.62144e+07"} 6022
prometheus_tsdb_compaction_chunk_range_bucket{le="+Inf"} 6022
prometheus_tsdb_compaction_chunk_range_sum 1.0056692784e+10
prometheus_tsdb_compaction_chunk_range_count 6022
# HELP prometheus_tsdb_compaction_chunk_samples Final number of samples on their first compaction
# TYPE prometheus_tsdb_compaction_chunk_samples histogram
prometheus_tsdb_compaction_chunk_samples_bucket{le="4"} 0
prometheus_tsdb_compaction_chunk_samples_bucket{le="6"} 0
prometheus_tsdb_compaction_chunk_samples_bucket{le="9"} 0
prometheus_tsdb_compaction_chunk_samples_bucket{le="13.5"} 0
prometheus_tsdb_compaction_chunk_samples_bucket{le="20.25"} 0
prometheus_tsdb_compaction_chunk_samples_bucket{le="30.375"} 0
prometheus_tsdb_compaction_chunk_samples_bucket{le="45.5625"} 0
prometheus_tsdb_compaction_chunk_samples_bucket{le="68.34375"} 1206
prometheus_tsdb_compaction_chunk_samples_bucket{le="102.515625"} 1807
prometheus_tsdb_compaction_chunk_samples_bucket{le="153.7734375"} 6022
prometheus_tsdb_compaction_chunk_samples_bucket{le="230.66015625"} 6022
prometheus_tsdb_compaction_chunk_samples_bucket{le="345.990234375"} 6022
prometheus_tsdb_compaction_chunk_samples_bucket{le="+Inf"} 6022
prometheus_tsdb_compaction_chunk_samples_sum 667104
prometheus_tsdb_compaction_chunk_samples_count 6022
# HELP prometheus_tsdb_compaction_chunk_size Final size of chunks on their first compaction
# TYPE prometheus_tsdb_compaction_chunk_size histogram
prometheus_tsdb_compaction_chunk_size_bucket{le="32"} 0
prometheus_tsdb_compaction_chunk_size_bucket{le="48"} 436
prometheus_tsdb_compaction_chunk_size_bucket{le="72"} 1104
prometheus_tsdb_compaction_chunk_size_bucket{le="108"} 5016
prometheus_tsdb_compaction_chunk_size_bucket{le="162"} 5672
prometheus_tsdb_compaction_chunk_size_bucket{le="243"} 5786
prometheus_tsdb_compaction_chunk_size_bucket{le="364.5"} 5866
prometheus_tsdb_compaction_chunk_size_bucket{le="546.75"} 5978
prometheus_tsdb_compaction_chunk_size_bucket{le="820.125"} 5992
prometheus_tsdb_compaction_chunk_size_bucket{le="1230.1875"} 6022
prometheus_tsdb_compaction_chunk_size_bucket{le="1845.28125"} 6022
prometheus_tsdb_compaction_chunk_size_bucket{le="2767.921875"} 6022
prometheus_tsdb_compaction_chunk_size_bucket{le="+Inf"} 6022
prometheus_tsdb_compaction_chunk_size_sum 589118
prometheus_tsdb_compaction_chunk_size_count 6022
# HELP prometheus_tsdb_compaction_duration Duration of compaction runs.
# TYPE prometheus_tsdb_compaction_duration histogram
prometheus_tsdb_compaction_duration_bucket{le="1"} 9
prometheus_tsdb_compaction_duration_bucket{le="2"} 9
prometheus_tsdb_compaction_duration_bucket{le="4"} 9
prometheus_tsdb_compaction_duration_bucket{le="8"} 9
prometheus_tsdb_compaction_duration_bucket{le="16"} 9
prometheus_tsdb_compaction_duration_bucket{le="32"} 9
prometheus_tsdb_compaction_duration_bucket{le="64"} 9
prometheus_tsdb_compaction_duration_bucket{le="128"} 9
prometheus_tsdb_compaction_duration_bucket{le="256"} 10
prometheus_tsdb_compaction_duration_bucket{le="512"} 10
prometheus_tsdb_compaction_duration_bucket{le="+Inf"} 10
prometheus_tsdb_compaction_duration_sum 244.85386494199997
prometheus_tsdb_compaction_duration_count 10
# HELP prometheus_tsdb_compactions_failed_total Total number of compactions that failed for the partition.
# TYPE prometheus_tsdb_compactions_failed_total counter
prometheus_tsdb_compactions_failed_total 0
# HELP prometheus_tsdb_compactions_total Total number of compactions that were executed for the partition.
# TYPE prometheus_tsdb_compactions_total counter
prometheus_tsdb_compactions_total 10
# HELP prometheus_tsdb_compactions_triggered_total Total number of triggered compactions for the partition.
# TYPE prometheus_tsdb_compactions_triggered_total counter
prometheus_tsdb_compactions_triggered_total 289
# HELP prometheus_tsdb_head_active_appenders Number of currently active appender transactions
# TYPE prometheus_tsdb_head_active_appenders gauge
prometheus_tsdb_head_active_appenders 0
# HELP prometheus_tsdb_head_chunks Total number of chunks in the head block.
# TYPE prometheus_tsdb_head_chunks gauge
prometheus_tsdb_head_chunks 1803
# HELP prometheus_tsdb_head_chunks_created_total Total number of chunks created in the head
# TYPE prometheus_tsdb_head_chunks_created_total gauge
prometheus_tsdb_head_chunks_created_total 7825
# HELP prometheus_tsdb_head_chunks_removed_total Total number of chunks removed in the head
# TYPE prometheus_tsdb_head_chunks_removed_total gauge
prometheus_tsdb_head_chunks_removed_total 6022
# HELP prometheus_tsdb_head_gc_duration_seconds Runtime of garbage collection in the head block.
# TYPE prometheus_tsdb_head_gc_duration_seconds summary
prometheus_tsdb_head_gc_duration_seconds{quantile="0.5"} NaN
prometheus_tsdb_head_gc_duration_seconds{quantile="0.9"} NaN
prometheus_tsdb_head_gc_duration_seconds{quantile="0.99"} NaN
prometheus_tsdb_head_gc_duration_seconds_sum 0.010158025000000001
prometheus_tsdb_head_gc_duration_seconds_count 7
# HELP prometheus_tsdb_head_max_time Maximum timestamp of the head block.
# TYPE prometheus_tsdb_head_max_time gauge
prometheus_tsdb_head_max_time 1.511233867954e+12
# HELP prometheus_tsdb_head_min_time Minimum time bound of the head block.
# TYPE prometheus_tsdb_head_min_time gauge
prometheus_tsdb_head_min_time 1.5112296e+12
# HELP prometheus_tsdb_head_samples_appended_total Total number of appended samples.
# TYPE prometheus_tsdb_head_samples_appended_total counter
prometheus_tsdb_head_samples_appended_total 656889
# HELP prometheus_tsdb_head_series Total number of series in the head block.
# TYPE prometheus_tsdb_head_series gauge
prometheus_tsdb_head_series 601
# HELP prometheus_tsdb_head_series_created_total Total number of series created in the head
# TYPE prometheus_tsdb_head_series_created_total gauge
prometheus_tsdb_head_series_created_total 605
# HELP prometheus_tsdb_head_series_not_found Total number of requests for series that were not found.
# TYPE prometheus_tsdb_head_series_not_found counter
prometheus_tsdb_head_series_not_found 0
# HELP prometheus_tsdb_head_series_removed_total Total number of series removed in the head
# TYPE prometheus_tsdb_head_series_removed_total gauge
prometheus_tsdb_head_series_removed_total 4
# HELP prometheus_tsdb_reloads_failures_total Number of times the database failed to reload black data from disk.
# TYPE prometheus_tsdb_reloads_failures_total counter
prometheus_tsdb_reloads_failures_total 0
# HELP prometheus_tsdb_reloads_total Number of times the database reloaded block data from disk.
# TYPE prometheus_tsdb_reloads_total counter
prometheus_tsdb_reloads_total 11
# HELP prometheus_tsdb_wal_truncate_duration_seconds Duration of WAL truncation.
# TYPE prometheus_tsdb_wal_truncate_duration_seconds summary
prometheus_tsdb_wal_truncate_duration_seconds{quantile="0.5"} NaN
prometheus_tsdb_wal_truncate_duration_seconds{quantile="0.9"} NaN
prometheus_tsdb_wal_truncate_duration_seconds{quantile="0.99"} NaN
prometheus_tsdb_wal_truncate_duration_seconds_sum 0.074209495
prometheus_tsdb_wal_truncate_duration_seconds_count 7
# HELP tsdb_wal_corruptions_total Total number of WAL corruptions.
# TYPE tsdb_wal_corruptions_total counter
tsdb_wal_corruptions_total 0
# HELP tsdb_wal_fsync_duration_seconds Duration of WAL fsync.
# TYPE tsdb_wal_fsync_duration_seconds summary
tsdb_wal_fsync_duration_seconds{quantile="0.5"} 0.002065444
tsdb_wal_fsync_duration_seconds{quantile="0.9"} 0.003979255
tsdb_wal_fsync_duration_seconds{quantile="0.99"} 0.004194255
tsdb_wal_fsync_duration_seconds_sum 32.165841198999935
tsdb_wal_fsync_duration_seconds_count 1712
```

## Benchmarks

- CPU usage reduced to 20% - 40% compared to Prometheus 1.8
- Disk space usage reduced to 33% - 50% compared to Prometheus 1.8
- Disk I/O without much query load is usually <1% on average

![](https://prometheus.io/assets/blog/2017-11-08/resource-comparison-cb3363e2f4f.png)