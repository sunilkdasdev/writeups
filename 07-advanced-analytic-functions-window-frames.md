# Advanced Oracle Analytic Functions: Window Frames Deep Dive

**By Donald K. Burleson**

---

## Introduction: The Frame Matters

In my decades of teaching Oracle, the #1 confusion I see is around window frames. What's the difference between ROWS and RANGE? When do I use UNBOUNDED PRECEDING vs. CURRENT ROW? Let me demystify this once and for all.

At Manhattan Associates, we use window frames to calculate everything from running totals to rolling averages. Get this right, and your analytics will be bulletproof. Get it wrong, and your numbers will be mysteriously incorrect.

---

## Chapter 1: ROWS vs. RANGE - The Critical Distinction

### The Simple Definition

```sql
ROWS BETWEEN ...      -- Physical row count
RANGE BETWEEN ...     -- Value-based (logical)
```

### Practical Example: The Difference

```sql
CREATE TABLE test_values (
    id NUMBER,
    value NUMBER
);

INSERT INTO test_values VALUES (1, 10);
INSERT INTO test_values VALUES (2, 10);
INSERT INTO test_values VALUES (3, 20);
INSERT INTO test_values VALUES (4, 20);
INSERT INTO test_values VALUES (5, 30);
```

**ROWS (physical):**

```sql
SELECT 
    id, value,
    SUM(value) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) AS running_sum
FROM test_values;

-- Result:
-- ID  VALUE  RUNNING_SUM
-- 1   10     10           (10 + nothing before)
-- 2   10     20           (10 + previous 10)
-- 3   20     30           (20 + previous 10)
-- 4   20     40           (20 + previous 20)
-- 5   30     50           (30 + previous 20)
```

**RANGE (logical, same value):**

```sql
SELECT 
    id, value,
    SUM(value) OVER (ORDER BY id RANGE BETWEEN 1 PRECEDING AND CURRENT ROW) AS running_sum
FROM test_values;

-- Result:
-- ID  VALUE  RUNNING_SUM
-- 1   10     10           (10)
-- 2   10     20           (10 + 10, because value=10 includes both rows!)
-- 3   20     40           (10+10+20, value <= 20 includes IDs 1,2,3!)
-- 4   20     40           (same as ID 3, same value)
-- 5   30     70           (all rows, value <= 30)
```

**Donald Sez**: "RANGE treats all rows with the same value as a group. This is rarely what you want for running totals!"

---

## Chapter 2: Frame Boundary Options

### The Complete Frame Options

```sql
ROWS BETWEEN 
    UNBOUNDED PRECEDING       -- All rows before current
    AND CURRENT ROW           -- Up to and including current
    
ROWS BETWEEN 
    1 PRECEDING               -- Just the previous row
    AND 1 FOLLOWING           -- Just the next row
    
ROWS BETWEEN 
    CURRENT ROW               -- Only current row
    AND UNBOUNDED FOLLOWING  -- All rows after current
    
RANGE BETWEEN 
    UNBOUNDED PRECEDING       -- All rows with value <= current
    AND CURRENT ROW
```

### Common Patterns

**Running Total (most common):**

```sql
SUM(amount) OVER (ORDER BY order_date ROWS UNBOUNDED PRECEDING)
```

**Moving Average (last 3):**

```sql
AVG(amount) OVER (ORDER BY order_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
```

**Centered Average (3 around current):**

```sql
AVG(amount) OVER (ORDER BY order_date ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING)
```

**Running Percentage of Total:**

```sql
SUM(amount) OVER () AS total,
ROUND(RATIO_TO_REPORT(amount) OVER () * 100, 2) AS pct_of_total
```

---

## Chapter 3: The FIRST/LAST Functions

### Problem: Getting Value from Different Row

```sql
-- Want: order date when maximum quantity was picked
-- Can't do this with regular aggregate!
SELECT 
    order_id,
    MAX(quantity) AS max_qty,
    -- How to get the DATE at that max?
    ??????????????
FROM wms_order_lines
GROUP BY order_id;
```

### Solution: FIRST/LAST Aggregate

```sql
-- Using KEEP (DENSE_RANK FIRST/LAST)
SELECT 
    order_id,
    MAX(quantity) AS max_qty,
    MIN(order_date) KEEP (DENSE_RANK FIRST ORDER BY quantity DESC) AS max_qty_date
FROM wms_order_lines
GROUP BY order_id;
```

**This returns the order_date from the row with MAX(quantity)!**

### Real WMS Example: First Pick Location

```sql
-- What location received this SKU first?
SELECT 
    sku_id,
    FIRST_VALUE(location_id) KEEP (DENSE_RANK FIRST ORDER BY receipt_date) AS first_location,
    FIRST_VALUE(receipt_date) KEEP (DENSE_RANK FIRST ORDER BY receipt_date) AS first_date,
    LAST_VALUE(location_id) KEEP (DENSE_RANK LAST ORDER BY receipt_date) AS latest_location
FROM wms_inventory_receipts
GROUP BY sku_id;
```

---

## Chapter 4: ROWS vs. RANGE in Practice

### When to Use Each

| Use | Example |
|-----|---------|
| **ROWS** | Running totals, moving averages, anything where physical row order matters |
| **RANGE** | Cumulative distribution, "all values up to this value" |
| **RANGE UNBOUNDED PRECEDING** | Cumulative distribution (percentile) |

### Example: Cumulative Distribution

```sql
-- What percentile is this order's value?
SELECT 
    order_id,
    order_total,
    PERCENT_RANK() OVER (ORDER BY order_total) AS pct_rank,
    CUME_DIST() OVER (ORDER BY order_total) AS cum_dist
FROM (
    SELECT order_id, SUM(quantity * unit_price) AS order_total
    FROM wms_order_lines
    GROUP BY order_id
);
```

**PERCENT_RANK**: 0 to 1 (rank-1)/(n-1)
**CUME_DIST**: 0 to 1 (count <= current)/total

---

## Chapter 5: Complex Analytic Patterns

### Running Total with Reset

```sql
-- Reset running total when status changes
SELECT 
    order_id,
    status,
    amount,
    SUM(amount) OVER (
        PARTITION BY order_id 
        ORDER BY status_change_date 
        ROWS UNBOUNDED PRECEDING
    ) AS running_amt,
    status,
    LAG(status) OVER (PARTITION BY order_id ORDER BY status_change_date) AS prev_status
FROM wms_order_status_history
ORDER BY order_id, status_change_date;
```

### Detecting State Changes

```sql
-- Find when location utilization crosses threshold
SELECT 
    location_id,
    snapshot_time,
    utilization_pct,
    LAG(utilization_pct) OVER (PARTITION BY location_id ORDER BY snapshot_time) AS prev_pct,
    CASE 
        WHEN utilization_pct >= 80 
         AND (LAG(utilization_pct) OVER (...) < 80) 
        THEN 'BECAME_FULL'
        WHEN utilization_pct < 80 
         AND (LAG(utilization_pct) OVER (...) >= 80) 
        THEN 'BECAME_AVAILABLE'
    END AS state_change
FROM location_utilization_snapshots;
```

### Conditional Aggregation with Analytic

```sql
-- Running total of only PENDING orders
SELECT 
    order_id,
    order_date,
    status,
    amount,
    SUM(CASE WHEN status = 'PENDING' THEN amount ELSE 0 END) 
        OVER (ORDER BY order_date ROWS UNBOUNDED PRECEDING) AS pending_running_total
FROM wms_orders;
```

---

## Chapter 6: Performance Considerations

### When Analytic Functions Are Slow

```sql
-- This can be slow on large tables
SELECT 
    ...,
    SUM(amount) OVER (ORDER BY date ROWS BETWEEN 1000 PRECEDING AND CURRENT ROW)
FROM huge_table;

-- Why? Oracle must sort ALL data first!
-- Solution: Add partition to limit scope
SELECT 
    ...,
    SUM(amount) OVER (PARTITION BY TRUNC(order_date) ORDER BY order_time 
        ROWS BETWEEN 1000 PRECEDING AND CURRENT ROW)
FROM huge_table;
```

### Tuning Analytic Queries

**Tip 1: Index the ORDER BY column**

```sql
CREATE INDEX wms_ord_date_idx ON wms_orders(order_date);
```

**Tip 2: Use RESULT_CACHE for repeated analytics**

```sql
SELECT /*+ RESULT_CACHE */ 
    SUM(amount) OVER () ...
```

**Tip 3: Consider materialized views for repeated patterns**

```sql
CREATE MATERIALIZED VIEW daily_order_mv
REFRESH COMPLETE AS
SELECT 
    TRUNC(order_date) AS day,
    SUM(quantity * unit_price) AS daily_total,
    SUM(quantity * unit_price) OVER (ORDER BY TRUNC(order_date) 
        ROWS UNBOUNDED PRECEDING) AS running_total
FROM wms_order_lines
GROUP BY TRUNC(order_date);
```

---

## Conclusion: Frame Mastery

**Donald Sez**: "The window frame is the secret to analytic function power. Master ROWS UNBOUNDED PRECEDING and you can solve 80% of analytic problems."

At Manhattan Associates:
1. **Default to ROWS** - It's the physical, predictable choice
2. **Use RANGE for distribution** - Percentiles and cumulative %
3. **Remember FIRST/LAST** - For cross-column aggregation
4. **Partition for performance** - Limit the window scope

---

**Next**: "Oracle Performance Deep Dive: Advanced Tuning Techniques" - The most advanced tuning methods for mission-critical WMS systems.