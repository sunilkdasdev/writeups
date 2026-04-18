# Elasticsearch: The Complete Guide for Enterprise Search

**By Donald K. Burleson**

---

## Introduction: Why Elasticsearch?

Elasticsearch has become the backbone of enterprise search and analytics. It's not just a search engine—it's a distributed document store, analytics engine, and vector database.

At Manhattan Associates, we use Elasticsearch for full-text search, logging, metrics, and real-time analytics. This guide covers everything you need.

---

## Chapter 1: Core Concepts

### What is Elasticsearch?

```
┌─────────────────────────────────────────────────────────────┐
│                      Elasticsearch Cluster                  │
├─────────────────────────────────────────────────────────────┤
│  Node 1 (Master)  │  Node 2 (Data)  │  Node 3 (Data)       │
│  ─────────────    │  ─────────────  │  ─────────────      │
│  Shard 0 (P)      │  Shard 0 (R)     │  Shard 1 (P)         │
│  Shard 1 (R)      │  Shard 1 (R)     │  Shard 0 (R)         │
└─────────────────────────────────────────────────────────────┘
         P = Primary | R = Replica
```

### Key Terminology

| Term | Definition |
|------|------------|
| Index | Collection of documents (like database) |
| Document | JSON record (like row) |
| Shard | Subdivision of index (horizontal scaling) |
| Node | Elasticsearch instance |
| Cluster | Group of nodes |

### Creating an Index

```json
PUT /orders
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 2
  },
  "mappings": {
    "properties": {
      "order_id": { "type": "keyword" },
      "customer_id": { "type": "keyword" },
      "total": { "type": "float" },
      "status": { "type": "keyword" },
      "order_date": { "type": "date" },
      "items": {
        "type": "nested",
        "properties": {
          "sku": { "type": "keyword" },
          "quantity": { "type": "integer" },
          "price": { "type": "float" }
        }
      }
    }
  }
}
```

---

## Chapter 2: Indexing Documents

### Index a Single Document

```json
POST /orders/_doc/ORD-12345
{
  "order_id": "ORD-12345",
  "customer_id": "CUST-567",
  "total": 199.99,
  "status": "COMPLETED",
  "order_date": "2024-01-15T10:30:00Z",
  "items": [
    {
      "sku": "SKU-001",
      "quantity": 2,
      "price": 49.99
    },
    {
      "sku": "SKU-002",
      "quantity": 3,
      "price": 33.33
    }
  ]
}
```

### Bulk Indexing

```json
POST /orders/_bulk
{"index":{"_id":"ORD-111"}}
{"order_id":"ORD-111","customer_id":"CUST-1","total":100,"status":"PENDING"}
{"index":{"_id":"ORD-222"}}
{"order_id":"ORD-222","customer_id":"CUST-2","total":200,"status":"PENDING"}
{"index":{"_id":"ORD-333"}}
{"order_id":"ORD-333","customer_id":"CUST-3","total":300,"status":"COMPLETED"}
```

### Java API

```java
// Create client
RestClient restClient = RestClient.builder(
    new HttpHost("localhost", 9200, "http")
).build();

RestHighLevelClient client = new RestHighLevelClient(restClient);

// Index document
IndexRequest request = new IndexRequest("orders")
    .id("ORD-12345")
    .source(jsonMap, XContentType.JSON);

IndexResponse response = client.index(request, RequestOptions.DEFAULT);

// Bulk index
BulkRequest bulkRequest = new BulkRequest();
for (Order order : orders) {
    bulkRequest.add(new IndexRequest("orders")
        .id(order.getOrderId())
        .source(mapper.writeValueAsString(order), XContentType.JSON));
}

BulkResponse bulkResponse = client.bulk(bulkRequest, RequestOptions.DEFAULT);
```

---

## Chapter 3: Searching Documents

### Match Query

```json
GET /orders/_search
{
  "query": {
    "match": {
      "status": "COMPLETED"
    }
  }
}
```

### Term Query (Exact)

```json
GET /orders/_search
{
  "query": {
    "term": {
      "order_id": "ORD-12345"
    }
  }
}
```

### Bool Query

```json
GET /orders/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "status": "COMPLETED" } }
      ],
      "filter": [
        { "range": { "total": { "gte": 100 } } }
      ],
      "must_not": [
        { "term": { "customer_id": "CUST-999" } }
      ],
      "should": [
        { "match": { "items.sku": "SKU-001" } }
      ]
    }
  }
}
```

### Pagination

```json
GET /orders/_search
{
  "from": 20,
  "size": 10,
  "query": { "match_all": {} }
}
```

### Sort

```json
GET /orders/_search
{
  "query": { "match_all": {} },
  "sort": [
    { "order_date": { "order": "desc" } },
    { "total": { "order": "desc" } }
  ]
}
```

---

## Chapter 4: Aggregations

### Metric Aggregations

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "avg_total": { "avg": { "field": "total" } },
    "max_total": { "max": { "field": "total" } },
    "min_total": { "min": { "field": "total" } },
    "total_orders": { "value_count": { "field": "order_id" } }
  }
}
```

### Bucket Aggregations

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "by_status": {
      "terms": {
        "field": "status",
        "size": 10
      }
    },
    "by_date": {
      "date_histogram": {
        "field": "order_date",
        "calendar_interval": "day"
      }
    }
  }
}
```

### Nested Aggregations

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "by_status": {
      "terms": { "field": "status" },
      "aggs": {
        "avg_total": { "avg": { "field": "total" } },
        "by_customer": {
          "terms": { "field": "customer_id", "size": 5 }
        }
      }
    }
  }
}
```

### Pipeline Aggregations

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "by_date": {
      "date_histogram": {
        "field": "order_date",
        "calendar_interval": "day"
      },
      "aggs": {
        "daily_total": { "sum": { "field": "total" } }
      }
    },
    "avg_daily": {
      "avg_bucket": {
        "buckets_path": "by_date>daily_total"
      }
    }
  }
}
```

---

## Chapter 5: Text Analysis

### Custom Analyzers

```json
PUT /products
{
  "settings": {
    "analysis": {
      "analyzer": {
        "whitespace_lower": {
          "type": "custom",
          "tokenizer": "whitespace",
          "filter": ["lowercase"]
        },
        "search_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "stop"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "whitespace_lower",
        "search_analyzer": "search_analyzer"
      }
    }
  }
}
```

### Tokenizers

```json
PUT /orders
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "custom_ngram": {
          "type": "ngram",
          "min_gram": 3,
          "max_gram": 5
        }
      }
    }
  }
}
```

### Relevance Tuning

```json
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        {
          "match": {
            "name": {
              "query": "wireless mouse",
              "boost": 3
            }
          }
        }
      ],
      "should": [
        {
          "match": {
            "description": "wireless mouse"
          }
        }
      ]
    }
  }
}
```

---

## Chapter 6: Java Client Deep Dive

### Search Queries

```java
// Match query
SearchRequest searchRequest = new SearchRequest("orders");
SearchSourceBuilder sourceBuilder = new SearchSourceBuilder();
sourceBuilder.query(QueryBuilders.matchQuery("status", "COMPLETED"));

// Bool query with multiple conditions
BoolQueryBuilder boolQuery = QueryBuilders.boolQuery();
boolQuery.must(QueryBuilders.termQuery("customer_id", "CUST-123"));
boolQuery.filter(QueryBuilders.rangeQuery("total").gte(100));
boolQuery.should(QueryBuilders.matchQuery("items.sku", "SKU-001"));

sourceBuilder.query(boolQuery);
searchRequest.source(sourceBuilder);

// Execute
SearchResponse response = client.search(searchRequest, RequestOptions.DEFAULT);

// Process results
for (SearchHit hit : response.getHits()) {
    Map<String, Object> source = hit.getSourceAsMap();
    System.out.println(hit.getId() + ": " + source.get("order_id"));
}
```

### Aggregations

```java
SearchSourceBuilder sourceBuilder = new SearchSourceBuilder();
sourceBuilder.size(0);

// Terms aggregation
TermsAggregationBuilder statusAgg = AggregationBuilders
    .terms("by_status")
    .field("status")
    .size(10);
sourceBuilder.aggregation(statusAgg);

// Avg aggregation
AvgAggregationBuilder avgTotal = AggregationBuilders
    .avg("avg_total")
    .field("total");
sourceBuilder.aggregation(avgTotal);

searchRequest.source(sourceBuilder);

SearchResponse response = client.search(searchRequest, RequestOptions.DEFAULT);

// Parse results
Terms statusTerms = response.getAggregations().get("by_status");
for (Terms.Bucket bucket : statusTerms.getBuckets()) {
    System.out.println(bucket.getKey() + ": " + bucket.getDocCount());
}

Avg avgTotalAgg = response.getAggregations().get("avg_total");
System.out.println("Average: " + avgTotalAgg.getValue());
```

---

## Conclusion

**Donald Sez**: "Elasticsearch is deceptively powerful—master the query DSL to unlock its full potential."

At Manhattan Associates:
1. **Design mappings carefully** - Schema changes are expensive
2. **Use filters over queries** - Filters are cached
3. **Right-size shards** - 50GB target per shard
4. **Monitor with _cluster/health** - Catch issues early

---

**Next**: "Elasticsearch Performance Deep Dive: Optimizing for Speed" - Advanced performance tuning for large datasets.