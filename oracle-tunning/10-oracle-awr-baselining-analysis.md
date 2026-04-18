# Oracle Automatic Workload Repository: Performance Baselining and Analysis

**By Donald K. Burleson**

---

## Introduction: The Power of Historical Analysis

One of Oracle's most powerful features is also one of the most underutilized: the Automatic Workload Repository (AWR). Most DBAs capture AWR snapshots but never analyze them. Big mistake.

At Manhattan Associates, I use AWR to solve problems that happened yesterday, last week, or even last month. AWR is your time machine for performance analysis.

**The Bottom Line**: If you're not using AWR, you're flying blind when performance problems occur.

---

## Chapter 1: Understanding AWR Basics

### How AWR Works

```sql
-- Check AWR settings
SELECT 
    snap_interval,
    retention,
    top_sql_count,
    most_recent_snap_id,
    last_snap_time
FROM dba_hist_wr_control;
```

**Default**: Snapshots every 60 minutes, retained for 8 days.

### Taking Manual Snapshots

```sql
-- Take a manual snapshot
BEGIN
    DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT();
END;
/

-- View snapshot range
SELECT 
    snap_id,
    begin_interval_time,
    end_interval_time
FROM dba_hist_snapshot
WHERE snap_id BETWEEN 100 AND 200
ORDER BY snap_id;
```

### Generating AWR Reports

```sql
-- Generate text AWR report
@?/rdbms/admin/awrgrpt.sql

-- Or use SQL to get key metrics
SELECT 
    snap_id,
    begin_interval_time,
    end_interval_time,
    snap_level
FROM dba_hist_snapshot
ORDER BY snap_id DESC;
```

---

## Chapter 2: Key AWR Views and Metrics

### The Essential Views

```sql
-- Top SQL by elapsed time
SELECT * FROM table(DBMS_WORKLOAD_REPOSITORY.AWR_SQL_REPORT_HTML(
    DBID => (SELECT DBID FROM V$DATABASE),
    SNAP_ID => 150,
    SNAP_ID_END => 151,
    OPTIONS => 0
));
```

### Core Performance Metrics

```sql
-- Get wait event summary for a period
SELECT 
    event,
    wait_class,
    total_waits,
    time_waited_micro / 1000000 AS time_waited_sec
FROM dba_hist_system_event
WHERE snap_id BETWEEN 150 AND 151
  AND wait_class != 'Idle'
ORDER BY time_waited_micro DESC;
```

### Load Profile Metrics

```sql
-- Load profile over time
SELECT 
    snap_id,
    to_char(begin_interval_time, 'MM/DD HH24:MI') AS time,
    round(elapsed_time_total / 60, 2) AS elapsed_min,
    round(parse_calls_total / nullif(executions_total, 0), 2) AS parses_per_exec,
    round(user_calls_total / nullif(executions_total, 0), 2) AS calls_per_exec,
    round(disk_reads_total / nullif(executions_total, 0), 2) AS reads_per_exec
FROM dba_hist_sysmetric_summary
WHERE metric_name = 'SQL Service Response Time'
ORDER BY snap_id;
```

---

## Chapter 3: Creating Performance Baselines

### The Baseline Concept

A baseline captures "good" performance to compare against "bad" performance:

```sql
-- Create a baseline for a good period
BEGIN
    DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE(
        start_snap_id => 100,
        end_snap_id   => 110,
        baseline_name => 'WMS_NORMAL_LOAD'
    );
END;
/
```

### Using Baselines for Comparison

```sql
-- Compare current performance to baseline
SELECT 
    b1.snap_id AS baseline_snap,
    b2.snap_id AS compare_snap,
    b1.value - b2.value AS change
FROM (
    SELECT snap_id, value 
    FROM dba_hist_sysmetric_history
    WHERE metric_name = 'Database Time'
      AND snap_id = 110
) b1
CROSS JOIN (
    SELECT snap_id, value 
    FROM dba_hist_sysmetric_history
    WHERE metric_name = 'Database Time'
      AND snap_id = 160
) b2;
```

### Automatic Baseline Types

```sql
-- Create moving window baseline
BEGIN
    DBMS_WORKLOAD_REPOSITORY.MODIFY_BASELINE_WINDOW_SIZE(
        window_size => 7
    );
END;
/
```

---

## Chapter 4: AWR Analysis in Practice

### Case Study: The Morning Slowdown

At a 3PL client, every morning between 8-9 AM, the system was slow. Here's how AWR revealed the problem:

**Step 1: Get snapshots around the problem time**

```sql
SELECT snap_id, begin_interval_time
FROM dba_hist_snapshot
WHERE begin_interval_time 
    BETWEEN TO_DATE('2024-03-15 07:30', 'YYYY-MM-DD HH24:MI') 
    AND TO_DATE('2024-03-15 09:30', 'YYYY-MM-DD HH24:MI')
ORDER BY snap_id;
```

**Step 2: Generate AWR report for that hour**

```sql
-- AWR showed:
-- Wait Event Summary:
-- db file sequential read: 45% of time  <-- INDEX problem!
-- log file sync: 25% of time             <-- Too many commits
-- enq: TX - row lock: 20% of time        <-- Concurrent updates
```

**Step 3: Find the problematic SQL**

```sql
SELECT 
    sql_id,
    substr(sql_text, 1, 100) AS sql_text,
    executions,
    elapsed_time_sec,
    ROUND(elapsed_time_sec / NULLIF(executions, 0), 3) AS secs_per_exec
FROM dba_hist_sqlstat
WHERE snap_id BETWEEN 115 AND 120
  AND elapsed_time_sec > 10
ORDER BY elapsed_time_sec DESC;
```

**Solution Found**: A missing index on (status, order_date) causing full table scans during the morning batch!

---

## Chapter 5: Advanced AWR Techniques

### SQL Tuning with AWR

```sql
-- Find SQL that regressed
SELECT 
    s.sql_id,
    s.parsing_schema_name,
    s.sql_text,
    b.value AS before_sec,
    a.value AS after_sec,
    ROUND((a.value - b.value) / NULLIF(b.value, 0) * 100, 2) AS pct_change
FROM dba_hist_sqlstat b
JOIN dba_hist_sqlstat a ON s.sql_id = b.sql_id
WHERE b.snap_id = 100
  AND a.snap_id = 150
  AND a.value > b.value * 1.5
ORDER BY pct_change DESC;
```

### Instance Efficiency Metrics

```sql
-- Key instance metrics from AWR
SELECT 
    metric_name,
    value,
    unit
FROM dba_hist_sysmetric_summary
WHERE metric_name IN (
    'Buffer Cache Hit Ratio',
    'Library Cache Hit Ratio',
    'Redo Logspace Wait Ratio',
    'Executions per Sec',
    'User Calls per Sec'
)
ORDER BY metric_name;
```

### Segment-Level Analysis

```sql
-- Top segments by I/O
SELECT 
    owner,
    segment_name,
    segment_type,
    logical_reads,
    physical_reads,
    buffer_gets,
    ROUND(physical_reads / NULLIF(logical_reads, 0) * 100, 2) AS pct_physical
FROM dba_hist_seg_stat
WHERE snap_id BETWEEN 150 AND 160
ORDER BY physical_reads DESC
FETCH FIRST 20 ROWS ONLY;
```

---

## Conclusion: Make AWR Your Friend

**Donald Sez**: "AWR is the most valuable performance tool Oracle gives you. Use it to understand history, create baselines, and solve problems you can't reproduce in the moment."

At Manhattan Associates:
1. **Take frequent snapshots** - Hourly minimum
2. **Create baselines** - For normal operation
3. **Review daily** - Key metrics
4. **Archive important periods** - Before snapshots expire
5. **Use for post-mortem** - Every performance issue should start with AWR

---

**Next**: "OracleHints: The Complete Guide to Query Optimization Hints" - When and how to use hints for performance tuning.