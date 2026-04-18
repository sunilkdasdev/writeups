# Kafka Streams: Real-Time Stream Processing Guide

**By Donald K. Burleson**

---

## Introduction: Why Kafka Streams?

Kafka Streams is the lightweight, powerful stream processing library built into Kafka. No separate cluster needed—just write Java code.

At Manhattan Associates, we use Kafka Streams for real-time analytics, enrichments, and transformations. This guide shows you how.

---

## Chapter 1: Streams Basics

### Anatomy of a Stream

```java
// Define topology
StreamsBuilder builder = new StreamsBuilder();

// Source: read from Kafka topic
KStream<String, JsonNode> orders = builder.stream("orders-topic");

// Process: transformation
KStream<String, JsonNode> highValue = orders
    .filter((key, order) -> order.get("total").asDouble() > 1000)
    .mapValues(order -> {
        order.put("priority", "HIGH");
        return order;
    });

// Sink: write to Kafka topic
highValue.to("high-value-orders");

// Build and start
KafkaStreams streams = new KafkaStreams(builder.build(), config);
streams.start();
```

### Types of Operations

| Type | Description | Examples |
|------|-------------|----------|
| Stateless | No state between records | map, filter, flatMap |
| Stateful | Maintains aggregation state | aggregate, count, reduce |
| Windowed | Time-based grouping | tumbling, hopping, session |

---

## Chapter 2: Stateless Operations

### Filter

```java
// Filter orders by status
KStream<String, Order> activeOrders = orders
    .filter((key, order) -> "ACTIVE".equals(order.getStatus()));
```

### Map and FlatMap

```java
// Transform to different type
KStream<String, String> orderStrings = orders
    .map((key, order) -> KeyValue.pair(
        order.getOrderId(),
        order.toJson()
    ));

// FlatMap: one record to multiple
KStream<String, LineItem> lineItems = orders
    .flatMap((key, order) -> {
        List<KeyValue<String, LineItem>> items = new ArrayList<>();
        for (LineItem item : order.getLineItems()) {
            items.add(KeyValue.pair(item.getItemId(), item));
        }
        return items;
    });
```

### SelectKey

```java
// Change the key
KStream<String, Order> byCustomer = orders
    .selectKey((key, order) -> order.getCustomerId());
```

---

## Chapter 3: Stateful Operations

### count

```java
// Count orders per customer
KTable<String, Long> orderCount = orders
    .groupBy((key, order) -> order.getCustomerId())
    .count(Materialized.as("order-count-store"));
```

### aggregate

```java
// Aggregate order value by customer
KTable<String, Double> customerTotal = orders
    .groupBy((key, order) -> KeyValue.pair(order.getCustomerId(), order))
    .aggregate(
        () -> 0.0,  // initializer
        (key, order, total) -> total + order.getTotal(),  // adder
        Materialized.<String, Double, KeyValueStore<Bytes, byte[]>>as("customer-total")
            .withValueSerde(Serdes.Double())
    );
```

### reduce

```java
// Reduce to latest value
KTable<String, Order> latestOrder = orders
    .groupByKey()
    .reduce(
        (newOrder, existing) -> newOrder,  // keep latest
        Materialized.as("latest-order-store")
    );
```

---

## Chapter 4: Windowing

### Tumbling Window

```java
// 5-minute non-overlapping windows
KTable<Windowed<String>, Long> countByWindow = orders
    .groupByKey()
    .windowedBy(TimeWindows.of(Duration.ofMinutes(5)))
    .count();
```

### Hopping Window

```java
// 10-minute window, slides every 5 minutes
KTable<Windowed<String>, Long> countByWindow = orders
    .groupByKey()
    .windowedBy(TimeWindows.of(Duration.ofMinutes(10))
        .advanceBy(Duration.ofMinutes(5)))
    .count();
```

### Session Window

```java
// Session window: group events within gap
KTable<Windowed<String>, Long> sessionCount = orders
    .groupByKey()
    .windowedBy(SessionWindows.with(Duration.ofMinutes(30)))
    .count();
```

### Window Retention

```java
// Keep windows for 1 day
KTable<Windowed<String>, Long> count = orders
    .groupByKey()
    .windowedBy(TimeWindows.of(Duration.ofMinutes(5)))
    .until(24 * 60)  // 1440 minutes = 1 day
    .count();
```

---

## Chapter 5: Joining Streams

### KStream-KStream Join

```java
// Join orders with shipments
KStream<String, Order> orders = builder.stream("orders");
KStream<String, Shipment> shipments = builder.stream("shipments");

// Join within 5-minute window
KStream<String, OrderWithShipment> joined = orders
    .join(shipments,
        (order, shipment) -> new OrderWithShipment(order, shipment),
        JoinWindows.of(Duration.ofMinutes(5)),
        Joined.with(Serdes.String(), orderSerde, shipmentSerde)
    );
```

### KStream-KTable Join

```java
// Join with lookup table (KTable)
KTable<String, Customer> customers = builder.table("customer-topic");

KStream<String, OrderWithCustomer> enriched = orders
    .leftJoin(customers,
        (order, customer) -> new OrderWithCustomer(order, customer),
        Joined.with(Serdes.String(), orderSerde, customerSerde)
    );
```

### KTable-KTable Join

```java
// Join two tables
KTable<String, Customer> customers = builder.table("customer-topic");
KTable<String, Address> addresses = builder.table("address-topic");

KTable<String, CustomerWithAddress> enriched = customers
    .join(addresses,
        (customer, address) -> new CustomerWithAddress(customer, address)
    );
```

---

## Chapter 6: Exactly-Once Semantics

### Enable Exactly-Once

```java
Properties props = new Properties();
props.put(StreamsConfig.APPLICATION_ID_CONFIG, "order-processor");
props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "kafka-1:9092");
props.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, "exactly_once_v2");
props.put(StreamsConfig.COMMIT_INTERVAL_MS_CONFIG, 1000);
```

### Idempotent Producer

```java
// Idempotent writes prevent duplicates
props.put("enable.idempotence", true);
props.put("max.in.flight.requests.per.connection", 5);
props.put("acks", "all");
```

### Transactional Processing

```java
// Process and produce in single transaction
streams = new KafkaStreams(builder.build(), props);
streams.setStateListener((newState, oldState) -> {
    if (newState == State.RUNNING && oldState == State.REBALANCING) {
        // Transaction committed
    }
});
```

---

## Chapter 7: Testing Kafka Streams

### TopologyTestDriver

```java
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.TopologyTestDriver;
import org.apache.kafka.streams.test.ConsumerRecordFactory;
import org.apache.kafka.streams.test.OutputVerifier;

Properties config = new Properties();
config.put(StreamsConfig.APPLICATION_ID_CONFIG, "test");
config.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092");
config.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
config.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass());

TopologyTestDriver driver = new TopologyTestDriver(builder.build(), config);

// Send input
ConsumerRecordFactory<String, String> factory = 
    new ConsumerRecordFactory<>(new StringSerializer(), new StringSerializer());
driver.pipeInput(factory.create("input-topic", "key", "value"));

// Verify output
OutputVerifier.compareKeyValue(driver.readOutput("output-topic", Serdes.String(), Serdes.String()),
    "key", "expected-value");

driver.close();
```

---

## Conclusion

**Donald Sez**: "Kafka Streams brings stream processing to developers, not infrastructure teams."

At Manhattan Associates:
1. **Start stateless** - Move to stateful as needed
2. **Use windows wisely** - Memory vs. accuracy tradeoff
3. **Test thoroughly** - TopologyTestDriver catches bugs
4. **Enable exactly-once** - For production reliability