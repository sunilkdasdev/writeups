# Apache Kafka: The Definitive Guide for Distributed Event Streaming

**By Donald K. Burleson**

---

## Introduction: Why Kafka Is the Backbone of Modern Systems

In my consulting career, I've seen Kafka become the backbone of every modern data architecture. It's not just a message queue—it's an event streaming platform that handles trillions of messages daily.

At Manhattan Associates, Kafka powers our real-time inventory tracking, order processing, and analytics pipelines. This guide covers everything from fundamentals to advanced patterns.

---

## Chapter 1: Kafka Architecture Deep Dive

### Core Concepts

**Broker**: The Kafka server that stores messages.

```properties
# broker.properties
listeners=PLAINTEXT://kafka-1:9092
advertised.listeners=PLAINTEXT://kafka-1.internal:9092
```

**Topic**: Logical channel for message streams.

```bash
# Create topic
kafka-topics.sh --create \
  --topic inventory-updates \
  --partitions 3 \
  --replication-factor 3 \
  --bootstrap-servers kafka-1:9092

# List topics
kafka-topics.sh --list --bootstrap-server kafka-1:9092
```

**Partition**: Ordered, immutable sequence within a topic.

```
Topic: orders (3 partitions)
┌─────────────┬─────────────┬─────────────┐
│ Partition 0 │ Partition 1 │ Partition 2 │
│ [0,1,2,3..] │ [0,1,2,3..] │ [0,1,2,3..] │
└─────────────┴─────────────┴─────────────┘
```

**Consumer Group**: Set of consumers that share messages.

```java
// Consumer configuration
Properties props = new Properties();
props.put("bootstrap.servers", "kafka-1:9092");
props.put("group.id", "inventory-consumers");
props.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
props.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");

KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props);
consumer.subscribe(Arrays.asList("inventory-updates"));
```

---

## Chapter 2: Producers and Messages

### Simple Producer

```java
Properties props = new Properties();
props.put("bootstrap.servers", "kafka-1:9092");
props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
props.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");

Producer<String, String> producer = new KafkaProducer<>(props);

// Send message
ProducerRecord<String, String> record = new ProducerRecord<>(
    "orders",           // topic
    "order-123",       // key
    "{\"status\":\"created\"}" // value
);

producer.send(record);
producer.flush();
producer.close();
```

### Key Design

```java
// Key determines partition!
ProducerRecord<String, String> record1 = new ProducerRecord<>("orders", "key-A", "msg1");
ProducerRecord<String, String> record2 = new ProducerRecord<>("orders", "key-A", "msg2");
// Both go to SAME partition - guaranteed order for same key

// No key = round-robin partitioning
ProducerRecord<String, String> record = new ProducerRecord<>("orders", null, "msg");
```

### Async Send with Callbacks

```java
// Async with callback
producer.send(new ProducerRecord<>("orders", key, value),
    (metadata, exception) -> {
        if (exception != null) {
            // Handle failure
            exception.printStackTrace();
        } else {
            // Success - metadata contains partition and offset
            System.out.println("Sent to " + 
                metadata.topic() + ":" + 
                metadata.partition() + "@" + 
                metadata.offset());
        }
    });
```

---

## Chapter 3: Consumers and Offsets

### Consumer Poll Loop

```java
while (running) {
    ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
    
    for (ConsumerRecord<String, String> record : records) {
        processOrder(record.key(), record.value(), record.offset());
    }
}
```

### Offset Management

```java
// Manual offset commit - exact once semantics
consumer.subscribe(Arrays.asList("orders"));

while (running) {
    ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
    
    for (ConsumerRecord<String, String> record : records) {
        processRecord(record);
        
        // Commit offset after processing
        consumer.commitSync(Collections.singletonMap(
            record.topicPartition(), 
            new OffsetAndMetadata(record.offset() + 1)
        ));
    }
}
```

### Auto Commit

```java
// Enable auto commit (default)
props.put("enable.auto.commit", "true");
props.put("auto.commit.interval.ms", "5000");

// Or disable for manual control
props.put("enable.auto.commit", "false");
```

### Seeking Offsets

```java
// Seek to beginning
consumer.seekToBeginning(Collections.singletonList(new TopicPartition("orders", 0)));

// Seek to end
consumer.seekToEnd(Collections.singletonList(new TopicPartition("orders", 0)));

// Seek to specific offset
consumer.seek(new TopicPartition("orders", 0), 100L);

// Replay from timestamp
Map<TopicPartition, Long> timestamps = new HashMap<>();
timestamps.put(new TopicPartition("orders", 0), 
    Instant.now().minusSeconds(3600).toEpochMilli());
Map<TopicPartition, OffsetAndTimestamp> results = 
    consumer.offsetsForTimes(timestamps);
consumer.seek(results.get(new TopicPartition("orders", 0)).offset());
```

---

## Chapter 4: Replication and Fault Tolerance

### Replication Factor

```bash
# Create with RF=3
kafka-topics.sh --create \
  --topic inventory \
  --partitions 6 \
  --replication-factor 3 \
  --bootstrap-servers kafka-1:9092
```

### ISR (In-Sync Replicas)

```
┌─────────────────────────────────────────────────────┐
│                    Broker 1 (Leader)                 │
│  Partition 0: offset 0-1000                          │
│  ISR: [Broker1, Broker2, Broker3]                  │
└─────────────────────────────────────────────────────┘
          │                 │                 │
          ▼                 ▼                 ▼
     ┌─────────┐      ┌─────────┐      ┌─────────┐
     │Broker 2 │      │Broker 3 │      │Broker 1 │
     │ (ISR)   │      │ (ISR)   │      │ (ISR)   │
     │ LAG=0   │      │ LAG=0   │      │ LAG=0   │
     └─────────┘      └─────────┘      └─────────┘

If Broker2 falls behind (LAG > replica.lag.time.ms), 
it's removed from ISR.
```

### Producer Acknowledgments

```java
// acks=0 - Fire and forget (no guarantee)
props.put("acks", "0");

// acks=1 - Leader acknowledgment only (default)
props.put("acks", "1");

// acks=all - ISR acknowledgment (safe)
props.put("acks", "all");
props.put("min.insync.replicas", "2");
```

### Leader Election

```bash
# Configure unclean leader election (data loss possible but available)
unclean.leader.election.enable=false  // safer
unclean.leader.election.enable=true   // more available

# Check leader
kafka-topics.sh --describe --topic orders --bootstrap-server kafka-1:9092
```

---

## Chapter 5: Partition Strategy

### Partition Count Selection

```java
// Rule: partitions >= consumer count for parallel processing
// Start with 3-6, scale as needed

// Calculate: throughput / (consumer_throughput * replication_factor)
// Example: 100MB/s producer, 10MB/s per consumer, RF=3
// partitions = 100 / (10 * 3) = 4
```

### Key-Based Partitioning

```java
// Partition by key hash (default)
int partition = Math.abs(key.hashCode()) % numPartitions;

// Custom partitioner
public class OrderPartitioner implements Partitioner {
    @Override
    public int partition(String topic, Object key, byte[] keyBytes, 
                        Object value, byte[] valueBytes, Cluster cluster) {
        // Route high-priority orders to first partition
        if (key.toString().startsWith("PRI-")) {
            return 0;
        }
        // Others round-robin
        return Math.abs(key.hashCode()) % cluster.partitionsForTopic(topic).size();
    }
}
```

### Rebalancing

```java
// Rebalance listener
consumer.subscribe(Arrays.asList("orders"), new ConsumerRebalanceListener() {
    @Override
    public void onPartitionsRevoked(Collection<TopicPartition> partitions) {
        // Save offsets before rebalance
        consumer.commitSync(currentOffsets);
    }
    
    @Override
    public void onPartitionsAssigned(Collection<TopicPartition> partitions) {
        // Resume from saved position or beginning
    }
});
```

---

## Chapter 6: Kafka Connect and Stream Processing

### Kafka Connect

```json
// source-connector.json
{
  "name": "jdbc-source",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "tasks.max": "4",
    "connection.url": "jdbc:oracle:thin:@localhost:1521:orcl",
    "table.whitelist": "orders,order_lines",
    "mode": "incrementing",
    "incrementing.column.name": "order_id",
    "topic.prefix": "db."
  }
}
```

```bash
# Start connector
curl -X POST -H "Content-Type: application/json" \
  --data @source-connector.json \
  http://localhost:8083/connectors
```

### Kafka Streams

```java
// Simple stream processing
Properties props = new Properties();
props.put(StreamsConfig.APPLICATION_ID_CONFIG, "order-processor");
props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "kafka-1:9092");

StreamsBuilder builder = new StreamsBuilder();

// Read from source
KStream<String, Order> orders = builder.stream("orders");

// Filter high-value orders
KStream<String, Order> highValue = orders.filter(
    (key, order) -> order.getTotal() > 1000
);

// Aggregate by region
KTable<String, Double> regionTotal = orders
    .groupBy((key, order) -> order.getRegion())
    .aggregate(
        () -> 0.0,
        (key, order, total) -> total + order.getTotal()
    );

// Write to output
regionTotal.toStream().to("order-totals");

KafkaStreams streams = new KafkaStreams(builder.build(), props);
streams.start();
```

---

## Chapter 7: Schema Registry

### Avro Schema

```json
// order.avsc
{
  "type": "record",
  "name": "Order",
  "fields": [
    {"name": "order_id", "type": "string"},
    {"name": "customer_id", "type": "string"},
    {"name": "total", "type": "double"},
    {"name": "status", "type": "string"},
    {"name": "created_at", "type": {"type": "long", "logicalType": "timestamp-millis"}}
  ]
}
```

### Schema Registry Integration

```java
// Configure schema registry
props.put("schema.registry.url", "http://schema-registry:8081");
props.put("key.serializer", "io.confluent.kafka.serializers.KafkaAvroSerializer");
props.put("value.serializer", "io.confluent.kafka.serializers.KafkaAvroSerializer");

// Producer uses Avro
ProducerRecord<String, Order> record = new ProducerRecord<>(
    "orders", 
    order.getOrderId(), 
    order  // Avro object serializes automatically
);
```

---

## Chapter 8: Security

### SASL/SSL Configuration

```properties
# Server: server.properties
listeners=PLAINTEXT://0.0.0.0:9092,SASL_PLAINTEXT://0.0.0.0:9093

# SASL mechanism
sasl.mechanism.inter.broker.protocol=PLAIN
security.inter.broker.protocol=SASL_PLAINTEXT

# JAAS config
listener.name.sasl_plaintext.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
  username="admin" password="admin-secret";
```

```java
// Client configuration
props.put("security.protocol", "SASL_PLAINTEXT");
props.put("sasl.mechanism", "PLAIN");
props.put("sasl.jaas.config", 
    "org.apache.kafka.common.security.plain.PlainLoginModule required " +
    "username=\"producer\" password=\"producer-secret\";");
```

### ACLs

```bash
# Allow producer
kafka-acls.sh --authorizer-properties zookeeper.connect=zookeeper:2181 \
  --add --allow-principal User:producer \
  --operation Write --topic orders

# Allow consumer group
kafka-acls.sh --authorizer-properties zookeeper.connect=zookeeper:2181 \
  --add --allow-principal User:consumer \
  --operation Read --group inventory-consumers
```

---

## Conclusion

**Donald Sez**: "Kafka is deceptively simple—master its nuances to build truly scalable systems."

At Manhattan Associates:
1. **Design for failure** - Replication is your friend
2. **Monitor consumer lag** - Catch issues early
3. **Use schemas** - Schema registry prevents surprises
4. **Partition wisely** - Key selection determines parallelism

---

**Next**: "Kafka Performance Deep Dive: Optimizing for Millions of Messages" - Advanced tuning for high-throughput systems.