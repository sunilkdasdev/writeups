# Oracle Wait Events: The Complete Diagnostic Guide

**By Donald K. Burleson**

---

## Introduction: Every Performance Problem Has a Wait

In my decades of Oracle consulting, I've learned that performance is simply about wait time. A query that's slow is waiting for something—whether it's disk I/O, CPU, locks, or network. Understanding wait events is the key to diagnosing any performance problem.

At Manhattan Associates, when a client says "the system is slow," the first thing I check is wait events. 95% of the time, the wait event points directly to the problem.

---

## Chapter 1: Understanding Wait Events

### The Wait Event Model

```sql
-- Get current wait events for your session
SELECT 
    sid,
    serial#,
    username,
    program,
    event,
    state,
    wait_time,
    seconds_in_wait
FROM v$session 
WHERE sid = (SELECT sid FROM v$mystat WHERE ROWNUM = 1);
```

**The State Machine:**
- **WAITING**: Currently waiting
- **WAITED KNOWN TIME**: Waited for known duration
- **WAITED SHORT TIME**: Waited briefly

### System-Wide Wait Analysis

```sql
-- Top wait events in the database
SELECT 
    event,
    wait_class,
    total_waits,
    time_waited,
    ROUND(time_waited / 1000, 2) AS secs_waited,
    ROUND(average_wait / 100, 2) AS avg_wait_ms
FROM v$system_event
WHERE wait_class != 'Idle'
ORDER BY time_waited DESC;
```

---

## Chapter 2: The Top Wait Events Explained

### 1. db file sequential read

**What it is**: Single block index or table access (most common)
**When it's normal**: Reading index root/branch blocks, small tables
**When it's a problem**: Thousands of sequential reads per query

```sql
-- Find queries doing sequential reads
SELECT 
    sql_id,
    sql_text,
    executions,
    rows_processed,
    buffer_gets,
    ROUND(buffer_gets / NULLIF(executions, 0)) AS gets_per_exec
FROM v$sqlarea
WHERE sql_id IN (
    SELECT sql_id 
    FROM v$active_session_history 
    WHERE event = 'db file sequential read'
);
```

**Solution**: Add indexes, reduce index depth, use covering indexes

### 2. db file scattered read

**What it is**: Multi-block full table scan reads
**When it's normal**: Large table scans, data warehouse queries
**When it's a problem**: In OLTP, this usually means missing index

```sql
-- Full table scans consuming time
SELECT 
    sql_id,
    sql_text,
    executions,
    buffer_gets,
    ROUND(buffer_gets / NULLIF(executions, 0)) AS gets_per_exec
FROM v$sqlarea
WHERE sql_text LIKE '%' || 'wms_orders' || '%'
  AND sql_text LIKE '%FTS%'
ORDER BY buffer_gets DESC;
```

### 3. log file sync

**What it is**: Waiting for redo log write to complete
**Cause**: Transaction commit, LGWR writing to disk

```sql
-- Check log sync times
SELECT 
    SUBSTR(to_char(sample_time, 'HH24:MI:SS'), 1, 8) AS time,
    event,
    wait_time,
    p1 AS "Log (file#)",
    p2 AS "Block#"
FROM v$active_session_history
WHERE event = 'log file sync'
  AND sample_time > SYSDATE - INTERVAL '30' MINUTE;
```

**Solutions:**
- Commit less frequently (batch commits)
- Use COMMIT NOWAIT
- More/faster redo logs
- Use COMMIT WRITE BATCH

### 4. enq: TX - row lock contention

**What it is**: Two sessions trying to modify the same row
**Classic case**: Same order being updated by two processes

```sql
-- Find blocking sessions
SELECT 
    s1.sid AS waiting_sid,
    s1.username AS waiting_user,
    s1.lockwait AS wait_event,
    s2.sid AS blocking_sid,
    s2.username AS blocking_user
FROM v$session s1
JOIN v$session s2 ON s1.blocking_session = s2.sid;
```

**Solutions:**
- Application redesign (serialize access)
- Use optimistic locking
- Identify and resolve long transactions

### 5. buffer busy waits

**What it is**: Waiting for a buffer to become available

```sql
-- What's causing buffer busy waits?
SELECT 
    p1 AS file_id,
    p2 AS block_id,
    p3 AS class_code,
    COUNT(*) AS wait_count
FROM v$session_wait
WHERE event = 'buffer busy waits'
GROUP BY p1, p2, p3;

-- Find the object
SELECT 
    relative_fno,
    owner,
    segment_name,
    segment_type
FROM dba_extents
WHERE file_id = &file_id
  AND &block_id BETWEEN block_id AND block_id + blocks - 1;
```

**Solutions:**
- Increase FREELISTS
- Use ASSM (automatic segment space management)
- Reduce contention on hot blocks

---

## Chapter 3: Wait Event Analysis in Practice

### Real Case: WMS Inventory Update Taking 30 Minutes

**Problem**: Inventory update process was taking 30+ minutes

**ASH Analysis:**

```sql
SELECT 
    event,
    COUNT(*) AS waits,
    AVG(wait_time) AS avg_wait_ms
FROM v$active_session_history
WHERE sample_time > SYSDATE - INTERVAL '30' MINUTE
  AND session_type = 'FOREGROUND'
GROUP BY event
ORDER BY COUNT(*) DESC;
```

**Result:**
```
EVENT                          WAYS    AVG_WAIT_MS
------------------------- ---------- ------------
db file sequential read      45000          15
enq: TX - row lock            32000          100
log file sync                  8000          200
```

**Analysis:**
1. 45,000 sequential reads = missing index!
2. 32,000 row locks = concurrent updates fighting!
3. 8,000 log syncs = too many commits!

**Solutions:**
1. Added composite index on (location_id, sku_id, quantity)
2. Changed to batch update instead of row-by-row
3. Changed COMMIT frequency from per-row to per-1000

**Result**: 30 minutes → 3 minutes!

---

## Chapter 4: Interpreting Wait Event Patterns

### Pattern 1: I/O Bound

```
Top events: db file sequential read, db file scattered read
```

**Diagnosis**: Slow disk or missing indexes
**Fix**: Add indexes, tune I/O subsystem, use SSD

### Pattern 2: Lock Contention

```
Top events: enq: TX - row lock contention, enq: TM - contention
```

**Diagnosis**: Concurrent access to same rows
**Fix**: Redesign application, use optimistic locking

### Pattern 3: CPU Bound

```
Top events: None (or very short waits), high CPU usage
```

**Diagnosis**: Complex queries, missing statistics, bad plans
**Fix**: Tune SQL, gather stats, use hints

### Pattern 4: Redo Log Bottleneck

```
Top events: log file sync, log file parallel write
```

**Diagnosis**: Too many commits, slow disk for redo
**Fix**: Batch commits, faster redo disks, increase log buffers

---

## Chapter 5: Advanced Wait Event Analysis

### ASH for Historical Analysis

```sql
-- What ran during the problem period?
SELECT 
    sql_id,
    event,
    COUNT(*) AS wait_count,
    AVG(wait_time) AS avg_wait
FROM v$active_session_history
WHERE sample_time BETWEEN 
    TO_DATE('2024-03-15 14:00', 'YYYY-MM-DD HH24:MI') AND
    TO_DATE('2024-03-15 14:30', 'YYYY-MM-DD HH24:MI')
GROUP BY sql_id, event
ORDER BY COUNT(*) DESC;
```

### Finding SQL with Most Waits

```sql
-- Top SQL by wait time
SELECT 
    h.sql_id,
    s.sql_text,
    h.event,
    COUNT(*) AS wait_count,
    SUM(h.wait_time) AS total_wait_ms
FROM v$active_session_history h
JOIN v$sqlarea s ON h.sql_id = s.sql_id
WHERE h.sample_time > SYSDATE - INTERVAL '1' HOUR
GROUP BY h.sql_id, s.sql_text, h.event
ORDER BY SUM(h.wait_time) DESC;
```

### Identifying Wait Cascades

```sql
-- Find queries that wait for other queries
SELECT 
    blocking_session AS blocker_sid,
    blocked_session AS waiter_sid,
    COUNT(*) AS wait_count
FROM v$active_session_history
WHERE blocking_session IS NOT NULL
  AND sample_time > SYSDATE - INTERVAL '30' MINUTE
GROUP BY blocking_session, blocked_session
ORDER BY COUNT(*) DESC;
```

---

## Conclusion: Waits Tell the Story

**Donald Sez**: "Every performance problem has a signature in the wait events. Learn to read that signature and you'll diagnose any problem in minutes."

At Manhattan Associates:
1. **Start with wait events** - Never guess what's slow
2. **Use ASH for history** - v$system_event only shows current
3. **Focus on top events** - Fix the biggest wait first
4. **Look for patterns** - I/O, locks, CPU, redo

---

**Next**: "Oracle Automatic Workload Repository: Performance Baselining and Analysis" - How to use AWR for long-term performance analysis.