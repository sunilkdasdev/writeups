# Kafka Performance Deep Dive: Optimizing for Millions of Messages

**By Donald K. Burleson**

---

## Introduction: Performance at Scale

At Manhattan Associates, we process over 100 million messages per hour through Kafka. Performance tuning is critical for cost efficiency and reliability.

---

## Chapter 1: Producer Performance

### Batch Configuration

```java
Properties props = new Properties();
props.put("bootstrap.servers", "kafka-1:9092,kafka-2:9092,kafka-3:9092");

// Batch size - larger = fewer requests
props.put("batch.size", 16384);        // 16KB (default)
props.put("batch.size", 32768);        // 32KB for higher throughput

// Batch linger - wait for batch to fill
props.put("linger.ms", 5);             // wait up to 5ms to fill batch

// Compression
props.put("compression.type", "lz4");  // lz4, snappy, zstd, gzip

// Buffer memory
props.put("buffer.memory", 67108864);  // 64MB (default 32MB)
```

### Buffer Memory Tuning

```java
// High-throughput producer configuration
Properties props = new Properties();
props.put("bootstrap.servers", "kafka-1:9092");
props.put("batch.size", 32768);         // 32KB batches
props.put("linger.ms", 10);             // wait up to 10ms
props.put("buffer.memory", 134217728);  // 128MB buffer
props.put("compression.type", "zstd");  // best compression ratio
props.put("max.in.flight.requests.per.connection", 5);
props.put("retries", 3);
props.put("request.timeout.ms", 30000);
props.put("max.block.ms", 60000);
```

### Performance Results

| Batch Size | Linger | Compression | Throughput |
|-----------|--------|-------------|------------|
| 16KB | 5ms | none | 50 MB/s |
| 32KB | 5ms | none | 80 MB/s |
| 32KB | 10ms | lz4 | 150 MB/s |
| 32KB | 10ms | zstd | 180 MB/s |

---

## Chapter 2: Consumer Performance

### Fetch Configuration

```java
Properties props = new Properties();
props.put("bootstrap.servers", "kafka-1:9092");
props.put("group.id", "high-perf-consumer");

// Fetch size - larger = more data per request
props.put("fetch.min.bytes", 1);              // wait for at least 1 byte
props.put("fetch.max.wait.ms", 500);          // max wait time

// Max bytes per partition
props.put("max.partition.fetch.bytes", 1048576);  // 1MB

// Max records per poll
props.put("max.poll.records", 500);
props.put("max.poll.interval.ms", 300000);
```

### Consumer Parallelism

```java
// More partitions = more parallel consumers
// Rule: partition_count >= consumer_count

// Consumer thread pool
ExecutorService executor = Executors.newFixedThreadPool(10);

List<String> topics = Arrays.asList("orders", "inventory");

KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props);
consumer.subscribe(topics);

while (running) {
    ConsumerRecords<String, String> records = consumer.poll(100);
    
    // Parallelize processing
    records.partitions().forEach(partition -> {
        List<ConsumerRecord<String, String>> partitionRecords = 
            records.records(partition);
        
        executor.submit(() -> {
            for (ConsumerRecord<String, String> record : partitionRecords) {
                processRecord(record);
            }
        });
    });
}
```

### Consumer Lag

```java
// Monitor consumer lag
KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props);
consumer.subscribe(Arrays.asList("orders"));

// Get end offsets
Map<TopicPartition, Long> endOffsets = consumer.endOffsets(
    consumer.partitionsFor("orders").stream()
        .map(pi -> new TopicPartition("orders", pi.partition()))
        .collect(Collectors.toList())
);

// Get current positions
Map<TopicPartition, Long> currentPositions = new HashMap<>();
for (TopicPartition tp : consumer.assignment()) {
    currentPositions.put(tp, consumer.position(tp));
}

// Calculate lag
for (TopicPartition tp : endOffsets.keySet()) {
    long lag = endOffsets.get(tp) - currentPositions.get(tp);
    System.out.println(tp + " lag: " + lag);
}
```

---

## Chapter 3: Broker Tuning

### Socket Server Config

```properties
# server.properties
num.network.threads=8  # process network requests
num.io.threads=16     # process I/O requests
socket.request.max.bytes=104857600  # 100MB
socket.receive.buffer.bytes=102400
socket.send.buffer.bytes=102400
queued.max.requests=500
```

### Log Configuration

```properties
# Log segment config
log.segment.bytes=1073741824        # 1GB segment (default 1GB)
log.segment.ms=604800000             # roll every 7 days
log.retention.hours=168              # 7 days retention
log.retention.bytes=-1                # unlimited (or specify size)
log.index.size.max.bytes=10485760    # 10MB index

# Compression
log.preallocate=false                # pre-allocate files
log.cleaner.enable=true               # enable log compaction
```

### Compression

```properties
# Compression per topic
compression.type=lz4

# GZIP for lower CPU, LZ4 for balanced, ZSTD for best ratio
```

---

## Chapter 4: Partition and Broker Sizing

### Partition Calculation

```java
// Calculate required partitions
// Formula: throughput / (producer_throughput_per_partition * replication_factor)

long targetThroughputMBps = 100;       // 100 MB/s target
long producerThroughputPerPartitionMBps = 30;  // single producer
int replicationFactor = 3;

int partitions = (int) Math.ceil(
    targetThroughputMBps / 
    (producerThroughputPerPartitionMBps * replicationFactor)
);

// partitions = 100 / (30 * 3) = 2 (minimum)
```

### Broker Hardware

| Message Rate | Partitions | Disk | Memory | CPU |
|--------------|------------|------|--------|-----|
| 1M msg/s | 100 | 2TB SSD | 32GB | 8 cores |
| 10M msg/s | 500 | 10TB SSD | 64GB | 16 cores |
| 100M msg/s | 1000 | 50TB SSD | 128GB | 32 cores |

### Scaling Strategy

```bash
# Add partitions to existing topic (can't decrease!)
kafka-topics.sh --alter \
  --topic orders \
  --partitions 12 \
  --bootstrap-server kafka-1:9092

# Rebalance partitions across brokers
kafka-reassign-partitions.sh \
  --reassignment-json-file reassign.json \
  --execute \
  --bootstrap-server kafka-1:9092
```

---

## Chapter 5: Monitoring and Metrics

### Key Metrics

```bash
# Producer metrics
kafka-producer-perf.sh \
  --topic orders \
  --num-records 1000000 \
  --record-size 1000 \
  --throughput 50000 \
  --producer.config producer.properties

# Consumer metrics
kafka-consumer-perf.sh \
  --topic orders \
  --messages 1000000 \
  --consumer.config consumer.properties
```

### JMX Metrics

```java
// MBean: kafka.server:type=ProducerRequestMetrics,name=*
// - producer-rate
// - producer-throttle-time
// - request-size-avg

// MBean: kafka.consumer:type=consumer-fetch-manager-metrics,client-id=*
// - fetch-rate
// - fetch-latency-avg
// - records-lag-max
```

### Prometheus Integration

```yaml
# prometheus.yml
- job_name: 'kafka'
  static_configs:
  - targets: ['kafka-1:7071', 'kafka-2:7071', 'kafka-3:7071']

# Important metrics to alert on
- alert: KafkaConsumerLag
  expr: kafka_consumer_lag_seconds > 300
  for: 5m
- alert: KafkaUnderReplicated
  expr: kafka_partition_underreplicated == 1
  for: 1m
```

---

## Chapter 6: Troubleshooting

### High Latency

```bash
# Check ISR (in-sync replicas)
kafka-topics.sh --describe --topic orders --bootstrap-server kafka-1:9092

# Check consumer lag
kafka-consumer-groups.sh --group inventory-group \
  --bootstrap-server kafka-1:9092 \
  --describe

# Check disk I/O
iostat -x 1
# Look for %util near 100% or await > 100ms
```

### Message Loss

```java
// Ensure producer has proper acknowledgment
props.put("acks", "all");
props.put("min.insync.replicas", "2");
props.put("retries", Integer.MAX_VALUE);
props.put("enable.idempotence", true);
```

### Rebalance Storms

```java
// Avoid by setting session timeout
props.put("session.timeout.ms", 30000);
props.put("heartbeat.interval.ms", 10000);

// Graceful shutdown
Runtime.getRuntime().addShutdownHook(new Thread(() -> {
    consumer.wakeup();
    executor.shutdown();
}));
```

---

## Conclusion

**Donald Sez**: "Performance tuning is iterative—measure, adjust, measure again."

At Manhattan Associates:
1. **Batch and compress** - Best throughput gains
2. **Right-size partitions** - Match your consumer capacity
3. **Monitor lag** - Lead indicator of problems
4. **Test at scale** - Production load reveals surprises