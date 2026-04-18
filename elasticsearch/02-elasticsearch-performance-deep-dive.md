# Elasticsearch Performance Deep Dive: Optimizing for Speed

**By Donald K. Burleson**

---

## Introduction: Performance at Scale

At Manhattan Associates, our Elasticsearch cluster handles 50,000 queries per second with sub-50ms latency. This guide shares the tuning techniques that make it possible.

---

## Chapter 1: Indexing Performance

### Bulk API Optimization

```json
POST /orders/_bulk
{ "index": { "_id": "1" } }
{ "field1": "value1", "total": 100 }
{ "index": { "_id": "2" } }
{ "field1": "value2", "total": 200 }
```

**Optimal batch size**: 5-15 MB or 1,000-5,000 documents

```java
// Java bulk processor
BulkProcessor.Listener listener = new BulkProcessor.Listener() {
    @Override
    public void beforeBulk(long executionId, BulkRequest request) {}
    
    @Override
    public void afterBulk(long executionId, BulkRequest request, BulkResponse response) {
        if (response.hasFailures()) {
            // Handle failures
        }
    }
    
    @Override
    public void afterBulk(long executionId, BulkRequest request, Throwable failure) {}
};

BulkProcessor bulkProcessor = BulkProcessor.builder(
    (request, bulkListener) -> client.bulkAsync(request, RequestOptions.DEFAULT, bulkListener),
    listener)
    .setBulkActions(1000)           // Execute every 1000 actions
    .setBulkSize(new ByteSizeValue(10, ByteSizeUnit.MB))  // or 10MB
    .setFlushInterval(TimeValue.timeValueSeconds(5))
    .setConcurrentRequests(4)       // Parallelism
    .build();
```

### Refresh and Translog

```json
PUT /orders
{
  "settings": {
    "refresh_interval": "30s",  // Increase during bulk load
    "translog.durability": "async"  // Better performance, some risk
  }
}
```

```java
// During bulk import
client.admin().indices()
    .prepareUpdateSettings("orders")
    .setSettings(Settings.builder()
        .put("refresh_interval", "-1"))
    .get();

// After import
client.admin().indices()
    .prepareUpdateSettings("orders")
    .setSettings(Settings.builder()
        .put("refresh_interval", "1s"))
    .get();
```

### Number of Shards

```json
// For time-series data, start with 1 shard per day
PUT /logs-2024-01-01
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 1
  }
}
```

---

## Chapter 2: Query Performance

### Filter vs Query

```json
// QUERY - scored, slower, cached per-shard
GET /orders/_search
{
  "query": {
    "match": { "status": "pending" }
  }
}

// FILTER - not scored, faster, cached globally
GET /orders/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "pending" } }
      ]
    }
  }
}
```

### Query Caching

```json
GET /orders/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "warehouse_id": "WH-001" } }
      ]
    }
  },
  "cache": true  // Explicit caching
}
```

### Page Size Optimization

```json
// BAD: Large from/size
GET /orders/_search
{
  "from": 10000,
  "size": 100
}

// GOOD: Use search_after for deep pagination
GET /orders/_search
{
  "size": 10,
  "query": { "match_all": {} },
  "sort": [{ "order_date": "desc" }, { "_id": "asc" }]
}

// Then use last document's sort values
GET /orders/_search
{
  "size": 10,
  "query": { "match_all": {} },
  "search_after": ["2024-01-15T10:30:00Z", "ORD-12345"]
}
```

### Pre-Filtering

```json
// Execute slow filters before expensive queries
GET /orders/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "COMPLETED" } },
        { "term": { "warehouse_id": "WH-001" } }
      ],
      "must": [
        { "match": { "items.sku": "SKU-001" } }
      ]
    }
  }
}
```

---

## Chapter 3: Aggregation Performance

### Reduce Cardinality

```json
// Use filter to reduce document set first
GET /orders/_search
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "COMPLETED" } }
      ]
    }
  },
  "aggs": {
    "by_customer": {
      "terms": { "field": "customer_id", "size": 100 }
    }
  }
}
```

### Sampled Aggregations

```json
GET /orders/_search
{
  "size": 0,
  "query": { "match_all": {} },
  "aggs": {
    "by_status": {
      "terms": {
        "field": "status",
        "size": 10,
        "shard_size": 20,
        "shard_min_doc_count": 100,
        "show_term_doc_count_error": true
      }
    }
  }
}
```

### FieldData and Doc Values

```json
// For sorting/aggregations on high-cardinality fields
PUT /orders/_mapping
{
  "properties": {
    "customer_id": {
      "type": "keyword",
      "doc_values": true  // Default, enables aggregation
    }
  }
}

// For text fields, need fielddata (expensive!)
PUT /orders/_mapping
{
  "properties": {
    "description": {
      "type": "text",
      "fielddata": true,
      "eager_global_ordinals": true  // Load on refresh
    }
  }
}
```

---

## Chapter 4: JVM and Memory

### Heap Sizing

```bash
# Start with 50% of available memory
# Elasticsearch requires 50% heap for segment memory

# In jvm.options
-Xms16g
-Xmx16g

# Increase for large datasets
-Xms32g
-Xmx32g
```

### Circuit Breaker

```json
GET /_cluster/settings?flat_settings

# Set field data circuit breaker
PUT /_cluster/settings
{
  "transient": {
    "indices.breaker.fielddata.limit": "40%"
  }
}

# Set request circuit breaker
PUT /_cluster/settings
{
  "transient": {
    "indices.breaker.request.limit": "20%"
  }
}
```

### Field Data Cache

```json
// Limit field data cache
PUT /orders/_settings
{
  "index": {
    "fielddata": {
      "cache": "soft",
      "size": "20%"
    }
  }
}
```

---

## Chapter 5: Shard Strategy

### Shard Sizing Rules

| Index Size | Recommended Shards |
|------------|-------------------|
| < 10 GB | 1 shard |
| 10-50 GB | 1-2 shards |
| 50-100 GB | 2-5 shards |
| > 100 GB | 5+ shards |

### Reindex and Shrink

```json
// Shrink index to fewer shards
POST /orders/_shrink/orders-shrunk
{
  "settings": {
    "index.number_of_shards": 1
  }
}
```

### Force Merge

```json
// After bulk load, force merge to 1 segment
POST /orders/_forcemerge
{
  "max_num_segments": 1,
  "only_expunge_deletes": false
}
```

---

## Chapter 6: Monitoring

### Key Metrics

```json
GET /_cluster/health?wait_for_status=yellow&timeout=50s

GET /_nodes/stats?pretty

GET /_cluster/stats?pretty
```

### Index Stats

```json
GET /orders/_stats?level=shards
```

### Slow Query Logging

```json
PUT /orders/_settings
{
  "index.search.slowlog.threshold.query.warn": "2s",
  "index.search.slowlog.threshold.query.info": "500ms",
  "index.search.slowlog.threshold.fetch.warn": "1s",
  "index.indexing.slowlog.threshold.index.warn": "5s"
}
```

---

## Conclusion

**Donald Sez**: "Performance is measured in production—test with realistic data loads."

At Manhattan Associates:
1. **Batch writes** - Use bulk API properly
2. **Filter over query** - Filters are cached
3. **Right-size shards** - Target 50GB per shard
4. **Monitor continuously** - _cluster/stats is your friend