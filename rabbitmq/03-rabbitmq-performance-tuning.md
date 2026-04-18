# RabbitMQ Performance Tuning: Optimizing for Throughput

**By Donald K. Burleson**

---

## Introduction: When Performance Matters

In high-volume systems, every millisecond counts. At Manhattan Associates, we process 50,000 messages per second during peak—performance tuning is critical.

---

## Chapter 1: Producer Optimization

### 1. Connection Pooling

```java
// BAD: New connection per message
Connection connection = factory.newConnection();
Channel channel = connection.createChannel();
channel.basicPublish(...);
connection.close();

// GOOD: Reuse connections
Connection connection = factory.newConnection();
Channel channel = connection.createChannel();
// Use same channel for many messages

// BETTER: Connection pool
Pool<Connection> connectionPool = ConnectionPool.builder()
    .connectionFactory(factory)
    .maxSize(20)
    .build();
```

### 2. Publisher Confirms

```java
// Enable confirms for reliability
channel.confirmSelect();

// Async confirm handler
channel.addConfirmListener((seq, multiple) -> {
    // Message confirmed
}, (seq, multiple) -> {
    // Message nacked - handle failure
});

// Sync wait (simpler but slower)
channel.waitForConfirmsOrDie(5000);

// Batch confirms for throughput
for (int i = 0; i < 1000; i++) {
    channel.basicPublish(exchange, routingKey, null, message);
}
channel.waitForConfirms();
```

### 3. Message Batching

```java
// Batch publish for throughput
Map<String, Object> batch = new HashMap<>();
channel.confirmSelect();

for (Message msg : messages) {
    channel.basicPublish(exchange, routingKey, 
        MessageProperties.PERSISTENT, msg.getBytes());
    
    // Batch ack every 100 messages
    if (i % 100 == 0) {
        channel.waitForConfirms();
    }
}
channel.waitForConfirms();
```

---

## Chapter 2: Consumer Optimization

### Prefetch Tuning

```java
// Prefetch = number of unacked messages
// Lower = more fair distribution
// Higher = better throughput

// Fair distribution (1 message at a time)
channel.basicQos(1);

// High throughput (100 messages)
channel.basicQos(100);

// Dynamic prefetch based on processing time
int prefetch = calculateOptimalPrefetch(avgProcessingTime);
channel.basicQos(prefetch);
```

### Concurrency Patterns

```java
// Single consumer with thread pool
ExecutorService executor = Executors.newFixedThreadPool(10);

Consumer consumer = new DefaultConsumer(channel) {
    @Override
    public void handleDelivery(String consumerTag,
            Envelope envelope,
            AMQP.BasicProperties properties,
            byte[] body) {
        executor.submit(() -> processMessage(body));
    }
};

channel.basicConsume(queue, false, consumer);
```

### Manual Acknowledgment

```java
// Process then ack - don't ack before processing!
channel.basicConsume(queue, false, (msg) -> {
    try {
        processMessage(msg.getBody());
        
        // ACK after successful processing
        channel.basicAck(msg.getEnvelope().getDeliveryTag(), false);
    } catch (Exception e) {
        // Requeue on failure
        channel.basicNack(msg.getEnvelope().getDeliveryTag(), false, true);
        
        // Or don't requeue - send to DLQ
        // channel.basicNack(deliveryTag, false, false);
    }
});
```

---

## Chapter 3: Queue Design

### Queue Types Comparison

| Type | Throughput | Memory | Use Case |
|------|------------|--------|----------|
| Classic | High | Medium | General purpose |
| Lazy | Medium | Low | Large messages, memory constrained |
| Quorum | Medium | Medium | HA with data safety |
| Stream | Medium | High | Retention, replay |

### Lazy Queue Implementation

```java
Map<String, Object> args = new HashMap<>();
args.put("x-queue-mode", "lazy");
args.put("x-max-length-bytes", 10_737_418_240); // 10GB max
args.put("x-overflow", "reject-publish"); // or "drop-head"

channel.queueDeclare("orders.lazy", true, false, false, args);
```

### Queue Splitting

```java
// BEFORE: Single queue, bottleneck
// Queue: orders - 100k msgs, 5 consumers, 20k msgs each

// AFTER: Multiple queues, parallel consumption
// Queue: orders.1 - 20k msgs, consumer1
// Queue: orders.2 - 20k msgs, consumer2
// Queue: orders.3 - 20k msgs, consumer3
// Queue: orders.4 - 20k msgs, consumer4
// Queue: orders.5 - 20k msgs, consumer5

// Hash routing
String queueNum = String.valueOf(orderId.hashCode() % 5 + 1);
channel.basicPublish("", "orders." + queueNum, null, msg);
```

---

## Chapter 4: Exchange Optimization

### Exchange Selection

| Exchange | Performance | Use Case |
|----------|-------------|----------|
| Direct | Fastest | Exact routing key match |
| Fanout | Fast | Broadcast to all queues |
| Topic | Moderate | Pattern-based routing |
| Headers | Slower | Multiple attributes |

### Avoid Topic When Possible

```java
// SLOW: Topic with wildcards
channel.basicPublish("orders.topic", "order.created.us.east", msg);

// FAST: Direct exchange with specific keys
channel.basicPublish("orders.direct", "order.created.us.east", msg);
```

### Exchange Design

```java
// Consolidate similar message types
// BAD: Multiple topic exchanges
// GOOD: Single direct with named keys
channel.exchangeDeclare("warehouse", "direct", true);
channel.basicPublish("warehouse", "sku.updated", ...);
channel.basicPublish("warehouse", "order.created", ...);
channel.basicPublish("warehouse", "inventory.adjusted", ...);
```

---

## Chapter 5: Memory and Disk

### Memory Thresholds

```bash
# Default 40% - tune based on workload
vm_memory_high_watermark.relative = 0.70

# For memory-intensive workloads
vm_memory_high_watermark.absolute = 8GB
```

### Disk Space Alerts

```bash
# Default 50% free - critical threshold
disk_free_limit.absolute = 10GB

# Monitor disk
rabbitmqctl status | grep "disk space"
```

### Memory-Mapped Queues

```bash
# Enable mmap for large queues
queue_index_embed_msgs_below = 4096
```

---

## Chapter 6: Network Optimization

### TCP Tuning

```java
ConnectionFactory factory = new ConnectionFactory();
// TCP buffer size
factory.setSocketProperties(socketConfig);

// Nagle's algorithm - disable for low latency
factory.setTcpNoDelay(true);

// Keep-alive
factory.setConnectionTimeout(60000);

// Frame max - larger frames = fewer round trips
factory.setFrameMax(131072);
```

### Connection URLs

```java
// Single connection string with multiple hosts
ConnectionFactory factory = new ConnectionFactory();
factory.setUri("amqp://user:pass@node1:5672,node2:5672,node3:5672?connect_timeout=5000");

// Or with load balancer
factory.setHost("lb.internal");
factory.setPort(5672);
factory.setAutomaticRecoveryEnabled(true);
```

---

## Chapter 7: Monitoring Performance

### Key Metrics

```bash
# Message rate
rabbitmqctl list_queues name messages messages_acc_rate messages_deliver_rate

# Queue growth
rabbitmqctl list_queues name messages message_bytes

# Consumer lag
rabbitmqctl list_consumers queue_name deliver_rate

# Channel operations
rabbitmqctl list_channels message_count_unacked prefetch_count
```

### Performance Benchmarks

```java
// Benchmark producer
Stopwatch sw = Stopwatch.start();
for (int i = 0; i < 10000; i++) {
    channel.basicPublish(exchange, routingKey, null, msg);
}
channel.waitForConfirms();
System.out.println("Time: " + sw.elapsed(TimeUnit.MILLISECONDS));
System.out.println("Rate: " + (10000 / (sw.elapsedMillis() / 1000.0)));
```

---

## Conclusion

**Donald Sez**: "Tune iteratively—measure, adjust, measure again."

At Manhattan Associates:
1. **Batch messages** - Reduce round trips
2. **Proper prefetch** - Balance fairness and throughput
3. **Lazy queues** - For memory-constrained scenarios
4. **Monitor continuously** - Production performance differs from test