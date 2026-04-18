# Oracle Query Rewrite Techniques: Making Bad SQL Good

**By Donald K. Burleson**

---

## Introduction: The Art of Rewriting

After 30+ years of Oracle consulting, I've learned this fundamental truth: most SQL performance problems can be solved by rewriting the query, not by adding hardware or indexes.

At Manhattan Associates, I've seen queries that took 30 minutes rewritten to run in 3 seconds—simply by changing the approach. In this guide, I'll show you the exact techniques that have saved our clients millions of dollars in hardware costs.

**The Mindset**: Don't blame the optimizer. Rewrite your code to give the optimizer better options.

---

## Chapter 1: Subquery Conversion Techniques

### The IN vs. EXISTS Trap

Here's a mistake I see constantly:

```sql
-- INEFFICIENT: IN with subquery
SELECT * FROM wms_inventory i
WHERE i.sku_id IN (
    SELECT sku_id 
    FROM wms_cycle_count 
    WHERE cycle_count_id = :cc_id
);
```

**The Problem**: The subquery runs for EVERY row in inventory!

**The Fix: EXISTS**

```sql
-- EFFICIENT: EXISTS
SELECT * FROM wms_inventory i
WHERE EXISTS (
    SELECT 1 
    FROM wms_cycle_count c
    WHERE c.sku_id = i.sku_id
      AND c.cycle_count_id = :cc_id
);
```

**Why it's faster**: EXISTS stops as soon as it finds ONE match. IN must complete the entire subquery.

**Even better: JOIN**

```sql
-- MOST EFFICIENT: Explicit JOIN
SELECT i.*
FROM wms_inventory i
JOIN wms_cycle_count c ON i.sku_id = c.sku_id
WHERE c.cycle_count_id = :cc_id;
```

### The NOT IN vs. NOT EXISTS Disaster

```sql
-- DANGEROUS: NOT IN with nulls
SELECT * FROM wms_orders o
WHERE o.order_id NOT IN (
    SELECT order_id 
    FROM wms_picked_orders
);
```

**Problem**: If ANY picked_order.order_id is NULL, the entire query returns ZERO rows!

**The Fix: NOT EXISTS**

```sql
-- SAFE: NOT EXISTS
SELECT * FROM wms_orders o
WHERE NOT EXISTS (
    SELECT 1 
    FROM wms_picked_orders p
    WHERE p.order_id = o.order_id
);
```

**Or: LEFT JOIN with NULL check**

```sql
-- ALSO SAFE: LEFT JOIN
SELECT o.*
FROM wms_orders o
LEFT JOIN wms_picked_orders p ON o.order_id = p.order_id
WHERE p.order_id IS NULL;
```

---

## Chapter 2: The DECODE and CASE Revolution

### Replacing OR with DECODE

```sql
-- SLOW: Multiple OR conditions
SELECT * FROM wms_orders
WHERE status = 'PENDING'
   OR status = 'PROCESSING'
   OR status = 'PICKING';
```

**The Problem**: This becomes a full table scan—Oracle can't use an index effectively with OR.

**The Fix: IN or DECODE**

```sql
-- FAST: IN operator
SELECT * FROM wms_orders
WHERE status IN ('PENDING', 'PROCESSING', 'PICKING');

-- Or use DECODE for transformations
SELECT 
    order_id,
    DECODE(status, 
        'PENDING', 'Active',
        'PROCESSING', 'Active', 
        'SHIPPED', 'Completed',
        'Unknown') AS status_desc
FROM wms_orders;
```

### CASE for Complex Logic

```sql
-- Complex conditional with CASE
SELECT 
    order_id,
    quantity,
    CASE 
        WHEN quantity > 100 THEN 'Bulk Order'
        WHEN quantity > 10 THEN 'Standard Order'
        ELSE 'Small Order'
    END AS order_type
FROM wms_order_lines;
```

**Advanced: CASE in WHERE**

```sql
-- Conditional WHERE (avoid!)
-- BAD: Different WHERE for different conditions
SELECT * FROM wms_inventory 
WHERE (amount > 100 AND region = 'NE')
   OR (amount <= 100 AND region = 'SW');

-- BETTER: Always True condition
SELECT * FROM wms_inventory 
WHERE CASE 
    WHEN region = 'NE' THEN amount 
    ELSE 0 
END > 100;
```

**Actually, BEST: Separate queries or UNION**

```sql
-- BEST: UNION ALL with separate WHERE
SELECT * FROM wms_inventory WHERE amount > 100 AND region = 'NE'
UNION ALL
SELECT * FROM wms_inventory WHERE amount <= 100 AND region = 'SW';
```

---

## Chapter 3: Eliminating Functions on Indexed Columns

### The Date Function Trap

```sql
-- BROKEN: Function prevents index usage
SELECT * FROM wms_order_headers
WHERE TRUNC(order_date) = TRUNC(SYSDATE);

-- Index on order_date = USELESS here!
```

**Why**: TRUNC(order_date) applies a function to every row—full table scan required.

**The Fix: Range Scan**

```sql
-- FIXED: Use date range
SELECT * FROM wms_order_headers
WHERE order_date >= TRUNC(SYSDATE)
  AND order_date < TRUNC(SYSDATE) + 1;

-- Plan now shows INDEX RANGE SCAN!
```

### The String Function Trap

```sql
-- BROKEN: UPPER prevents index
SELECT * FROM wms_sku 
WHERE UPPER(sku_desc) = 'ELECTRONICS';

-- BROKEN: SUBSTR prevents index  
SELECT * FROM wms_orders 
WHERE SUBSTR(tracking_number, 1, 3) = '1Z9';

-- Fix 1: Function-based index
CREATE INDEX wms_sku_upper_desc_idx ON wms_sku(UPPER(sku_desc));

-- Fix 2: Don't use function
SELECT * FROM wms_orders 
WHERE tracking_number LIKE '1Z9%';
```

### The Mathematical Trap

```sql
-- BROKEN: Math on column
SELECT * FROM wms_inventory 
WHERE quantity * unit_price > 1000;

-- FIXED: Rearrange the math
SELECT * FROM wms_inventory 
WHERE quantity > 1000 / unit_price;

-- Or: Create virtual column
ALTER TABLE wms_inventory 
ADD (total_value NUMBER GENERATED ALWAYS AS (quantity * unit_price));

CREATE INDEX wms_inv_total_val_idx ON wms_inventory(total_value);
```

---

## Chapter 4: The DISTINCT and UNION Trap

### When DISTINCT is Unnecessary

```sql
-- UNNECESSARY: DISTINCT on unique join
SELECT DISTINCT h.order_id, h.order_date
FROM wms_order_headers h
JOIN wms_order_lines l ON h.order_id = l.order_id
WHERE h.status = 'PENDING';
```

**The Problem**: If order_id is unique in headers, DISTINCT adds sorting overhead.

**The Fix**: Remove DISTINCT if not needed.

### UNION vs. UNION ALL

```sql
-- SLOW: UNION (implicit DISTINCT + SORT)
SELECT order_id, sku_id FROM wms_orders WHERE status = 'PENDING'
UNION
SELECT order_id, sku_id FROM wms_orders WHERE status = 'PROCESSING';

-- FAST: UNION ALL (no dedup)
SELECT order_id, sku_id FROM wms_orders WHERE status = 'PENDING'
UNION ALL
SELECT order_id, sku_id FROM wms_orders WHERE status = 'PROCESSING';
```

**When to use UNION**: When you NEED to eliminate duplicates
**When to use UNION ALL**: When you know there's no overlap, or you don't care

### The Case for MINUS

```sql
-- Harder: Find orders NOT in picking
SELECT order_id FROM wms_order_headers
MINUS
SELECT order_id FROM wms_pick_tasks;

-- Equivalent but sometimes faster:
SELECT h.order_id 
FROM wms_order_headers h
WHERE NOT EXISTS (
    SELECT 1 FROM wms_pick_tasks p 
    WHERE p.order_id = h.order_id
);
```

**Test both!** MINUS can be faster with good indexes.

---

## Chapter 5: Hints and Query Transformation

### Automatic Query Transformations

Oracle automatically rewrites some queries:

```sql
-- Oracle automatically converts this:
SELECT * FROM wms_orders o1
WHERE EXISTS (
    SELECT 1 FROM wms_order_lines l
    WHERE l.order_id = o1.order_id
      AND l.quantity > 10
);

-- Into a SEMI-JOIN!
```

**You can see this in the execution plan:**
```
|   1 |   NESTED LOOPS SEMI        |                |
```

### Forcing Transformation with Hints

```sql
-- Force subquery unnesting
SELECT /*+ UNNEST */ * FROM wms_orders o
WHERE EXISTS (
    SELECT 1 FROM wms_order_lines l 
    WHERE l.order_id = o.order_id
);

-- Prevent transformation
SELECT /*+ NO_UNNEST */ * FROM wms_orders o
WHERE EXISTS (
    SELECT 1 FROM wms_order_lines l 
    WHERE l.order_id = o.order_id
);
```

### The PUSH_PRED Hint

```sql
-- Push WHERE into view
SELECT /*+ PUSH_PRED(v) */ *
FROM (
    SELECT o.order_id, o.status, l.sku_id
    FROM wms_orders o
    JOIN wms_order_lines l ON o.order_id = l.order_id
) v
WHERE v.status = 'PENDING';
```

---

## Chapter 6: Real-World Rewrites for WMS

### Case Study: The Slow Inventory Report

**Before Rewrite (45 seconds):**

```sql
SELECT 
    (SELECT SUM(quantity) FROM wms_inventory i 
     WHERE i.sku_id = s.sku_id) AS total_qty,
    (SELECT SUM(quantity * unit_cost) FROM wms_inventory i 
     WHERE i.sku_id = s.sku_id) AS total_value,
    s.sku_id, s.sku_desc
FROM wms_sku s
WHERE s.active = 'Y';
```

**Problem**: Correlated subqueries run 50,000 times!

**After Rewrite (3 seconds):**

```sql
SELECT 
    SUM(i.quantity) AS total_qty,
    SUM(i.quantity * i.unit_cost) AS total_value,
    s.sku_id, s.sku_desc
FROM wms_sku s
LEFT JOIN wms_inventory i ON s.sku_id = i.sku_id
WHERE s.active = 'Y'
GROUP BY s.sku_id, s.sku_desc;
```

**Why it's faster**: Single scan of inventory, one GROUP BY.

### Case Study: The Complex Status Query

**Before (8 seconds):**

```sql
SELECT order_id, status, order_date
FROM wms_orders
WHERE status IN ('PENDING', 'PROCESSING', 'PICKING')
  AND order_date > SYSDATE - 30
MINUS
SELECT order_id, status, order_date
FROM wms_orders
WHERE status = 'CANCELLED'
  AND cancel_date > SYSDATE - 30;
```

**After (0.5 seconds):**

```sql
SELECT order_id, status, order_date
FROM wms_orders
WHERE status IN ('PENDING', 'PROCESSING', 'PICKING')
  AND order_date > SYSDATE - 30
  AND NOT EXISTS (
      SELECT 1 FROM wms_orders o2
      WHERE o2.order_id = wms_orders.order_id
        AND o2.status = 'CANCELLED'
        AND o2.cancel_date > SYSDATE - 30
  );
```

---

## Conclusion: Rewrite First, Tune Second

**Donald Sez**: "Before you blame Oracle, rewrite your query to give it a fair chance."

The Manhattan Associates rewrite checklist:
1. **Avoid functions on columns** - Use range scans instead
2. **Use EXISTS not IN** - For correlated subqueries
3. **Use JOINs over subqueries** - When possible
4. **Use UNION ALL not UNION** - Unless you need dedup
5. **Test alternate approaches** - The first version isn't always best

---

**Next**: "Oracle Performance Tuning: The Complete Toolkit" - Advanced tools and techniques for solving the toughest Oracle performance problems.