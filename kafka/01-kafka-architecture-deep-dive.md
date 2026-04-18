# Kafka Architecture and Implementation Deep Dive

## Table of Contents

1. [Broker Architecture Internals](#1-broker-architecture-internals)
2. [Partition Leadership and Replication](#2-partition-leadership-and-replication)
3. [Controller and Cluster Coordination](#3-controller-and-cluster-coordination)
4. [Log Storage and Segment Management](#4-log-storage-and-segment-management)
5. [Producer Internals and Batching](#5-producer-internals-and-batching)
6. [Consumer Group Protocol Deep Dive](#6-consumer-group-protocol-deep-dive)
7. [Exactly-Once Semantics Implementation](#7-exactly-once-semantics-implementation)
8. [Kafka Streams Architecture](#8-kafka-streams-architecture)
9. [Security Implementation](#9-security-implementation)
10. [Performance Optimization](#10-performance-optimization)
11. [Troubleshooting Production Issues](#11-troubleshooting-production-issues)

---

## 1. Broker Architecture Internals

### 1.1 Kafka Broker Components

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         KAFKA BROKER ARCHITECTURE                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                        KAFKA BROKER PROCESS                              ││
│  ├─────────────────────────────────────────────────────────────────────────┤│
│  │                                                                         ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐               ││
│  │  │   Request     │  │    Log        │  │    quotas     │               ││
│  │  │   Handler     │  │   Manager     │  │    Manager    │               ││
│  │  │   Pool        │  │               │  │               │               ││
│  │  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘               ││
│  │          │                   │                   │                       ││
│  │          └───────────────────┼───────────────────┘                       ││
│  │                              │                                            ││
│  │  ┌───────────────────────────▼───────────────────────────────────────┐   ││
│  │  │                     Socket Server                               │   ││
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │   ││
│  │  │  │   Acceptor  │──│   Processor │──│  Selector   │               │   ││
│  │  │  │   Thread    │  │   Threads   │  │  (NIO)      │               │   ││
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘               │   ││
│  │  └───────────────────────────────────────────────────────────────────┘   ││
│  │                              │                                            ││
│  └──────────────────────────────┼────────────────────────────────────────────┘│
│                                 │                                             │
│  ┌──────────────────────────────▼────────────────────────────────────────────┐
│  │                     ZOOKEEPER / KRaft                                      │
│  │  - Broker registration and metadata                                       │
│  │  - Partition leadership and ISR tracking                                  │
│  │  - Controller election                                                     │
│  │  - ACLs, quotas, config management                                        │
│  └───────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  MESSAGE FLOW:                                                               │
│  1. Client connects via Socket Server (port 9092)                           │
│  2. Acceptor accepts connection, hands to Processor                        │
│  3. Processor reads request, validates                                      │
│  4. Handler dispatches to appropriate component                            │
│  5. Handler processes, generates response                                   │
│  6. Response written back to client                                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Request Handling Pipeline

```java
// Simplified request processing flow
public class KafkaRequestPipeline {
    
    /**
     * Request Flow:
     * 
     * 1. Client sends Request in Request API Key format
     * 2. KafkaSelector reads bytes from channel
     * 3. NetworkClient decodes request
     * 4. Handler lookup by API key
     * 5. Handler processes (may involve replicas, logs, etc.)
     * 6. Response created
     * 7. NetworkClient encodes response
     * 8. Selector writes to channel
     */
    
    /**
     * Request Types (API Keys):
     * 
     * PRODUCE (0): Send messages to broker
     * FETCH (1): Read messages from broker
     * LIST_OFFSETS (2): Find offset by timestamp
     * METADATA (3): Get topic/partition info
     * OFFSET_COMMIT (8): Commit consumer offset
     * FIND_COORDINATOR (10): Find group coordinator
     * JOIN_GROUP (11): Join consumer group
     * SYNC_GROUP (14): Sync group assignment
     * APIVER_V3 (18): API version info
     * DELETE_RECORD (51): Delete records by offset
     */
    
    /**
     * Request Handler Thread Pool:
     * 
     * KafkaRequestHandlerPool:
     * - num.network.threads = 8 (default)
     * - Each handler is a KafkaRequestHandler
     * - Handlers process requests in parallel
     * - Queue between selector and handlers: requestChannel
     * 
     * requestChannel queue size: queued.max.requests = 500 (default)
     */
}
```

---

## 2. Partition Leadership and Replication

### 2.1 ISR (In-Sync Replicas) Management

```java
// ISR management in broker
public class ISRManagement {
    
    /**
     * What is ISR?
     * 
     * In-Sync Replicas = Replicas that are "caught up" with leader
     * - Partition has leader + N replicas
     * - ISR = subset of replicas that have caught up
     * - Definition of "caught up":
     *   - replica.lag.time.max.ms (default 30s) behind leader
     * 
     * Leader Election Priority:
     * 1. Prefer current leader if in ISR
     * 2. Else prefer replica in ISR with highest offset
     * 3. Else prefer replica outside ISR but caught up
     * 4. Else fail the election
     */
    
    /**
     * ISR Shrink Trigger:
     * - Replica falls behind by > replica.lag.time.max.ms
     * - Replica is down (no heartbeat)
     * - Controller removes from ISR in ZK/KRaft
     * 
     * ISR Grow Trigger:
     * - Replica catches up (within replica.lag.time.max.ms)
     * - Replica sends FetchRequest to leader
     * - Leader updates HW and adds to ISR
     */
    
    /**
     * Configuration:
     * 
     * broker:
     *   replica.lag.time.max.ms = 30000  # Max time without fetch
     *   replica.socket.timeout.ms = 30000
     *   replica.fetch.max.bytes = 1048576  # 1MB
     *   replica.fetch.min.bytes = 1
     *   replica.fetch.wait.max.ms = 500
     */
    
    /**
     * Under Replicated Partitions (URP):
     * 
     * When a replica is not in ISR:
     * - UnderReplicatedPartitions metric increases
     * - Alert if this persists (data risk!)
     * 
     * Causes:
     * - Slow follower (network, CPU, disk I/O)
     * - Follower crashed and restarting
     * - Leader too fast for followers
     * 
     * Resolution:
     * - Add more brokers
     * - Improve follower hardware
     * - Reduce produce ack requirements (acks=1)
     */
}
```

### 2.2 Leader Election Process

```scala
// Leader election logic in Kafka controller
// Simplified from Kafka codebase

class PartitionLeaderElection {
    
    /**
     * Election trigger:
     * 1. Current leader dies (no heartbeat)
     * 2. Controller initiates election
     * 3. ZK/KRaft selects new leader
     * 
     * Election strategy: Unclean leader election (configurable)
     * - controlled.shutdown.enable = true (default)
     * - unclean.leader.election.enable = false (default in 2.4+)
     * 
     * Unsafe election (unclean.election.enable = true):
     * - Choose any replica as leader (not in ISR!)
     * - May lose messages!
     * - Use only when availability > data integrity
     */
    
    /**
     * Preferred Replica Election:
     * 
     * Kafka tries to use the first replica as leader (preferred)
     * - Distribution across brokers for load balancing
     * - Auto.leader.rebalance.enable = true (default)
     * 
     * Trigger manually:
     * kafka-leader-election.sh --bootstrap-server broker:9092 \
     *   --topic test-topic --partition 0 --election-type PREFERRED
     */
}
```

---

## 3. Controller and Cluster Coordination

### 3.1 Controller Responsibilities

```java
// Controller major responsibilities
public class ControllerResponsibilities {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    KAFKA CONTROLLER                                 │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │ 1. Broker Management                                                │
     │    - Register new brokers                                           │
     │    - Remove dead brokers                                             │
     │    - Broker state management                                         │
     │                                                                      │
     │ 2. Topic Management                                                 │
     │    - Create/delete topics                                           │
     │    - Partition reassignment                                          │
     │    - Preferred replica election                                     │
     │                                                                      │
     │ 3. Partition Leadership                                             │
     │    - Trigger leader elections                                        │
     │    - Update ISR in ZK/KRaft                                          │
     │    - Handle broker shutdown                                          │
     │                                                                      │
     │ 4. Group Coordination                                               │
     │    - Partition assignment for consumer groups                       │
     │    - Offset commit tracking                                          │
     │                                                                      │
     │ 5. Configuration Management                                         │
     │    - Topic configs                                                   │
     │    - Broker configs                                                  │
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Controller Election:
     * 
     * - First broker to create /controller ZK node becomes controller
     * - All brokers watch /controller for changes
     * - If controller dies, new election happens
     * - zookeeper.session.timeout.ms = 30s (default)
     * 
     * Note: In KRaft mode (Kafka 2.8+), uses Raft consensus instead of ZK
     */
    
    /**
     * Controller "Storms":
     * 
     * When many partitions lose leaders simultaneously:
     * - Too many leader elections = controller overload
     * - broker.session.timeout.ms = 18s (default)
     * - Solution: Increase timeout, reduce partition count
     * - Or use controlled.shutdown to allow orderly leader transfer
     */
}
```

### 3.2 Partition Assignment Algorithm

```java
// Consumer group partition assignment
public class PartitionAssignment {
    
    /**
     * Assignment Strategies:
     * 
     * 1. Range (default):
     *    - Partitions sorted by partition number
     *    - Consumers sorted by consumer ID
     *    - Assign contiguous ranges to each consumer
     * 
     * 2. Round Robin:
     *    - Distribute partitions evenly across consumers
     *    - Better balance for topics with similar partitions
     * 
     * 3. Sticky Assignor (Kafka 0.11+):
     *    - Maintains previous assignment when possible
     *    - Minimizes partition movements during rebalance
     *    - Recommended for most use cases
     *    - partition.assignment.strategy = 
     *        org.apache.kafka.clients.consumer.StickyAssignor
     */
    
    /**
     * Range Assignment Example:
     * 
     * Topic: orders, partitions: 0,1,2,3,4,5
     * Consumers: C1, C2, C3
     * 
     * Sorted partitions: [0,1,2,3,4,5]
     * Sorted consumers: [C1,C2,C3]
     * 
     * C1 gets: partitions 0,1 (0-1)
     * C2 gets: partitions 2,3 (2-3)
     * C3 gets: partitions 4,5 (4-5)
     * 
     * Issue: C1 gets more if partitions not evenly divisible!
     */
    
    /**
     * Rebalance Trigger:
     * - Consumer joins group
     * - Consumer leaves group
     * - Consumer is considered dead (session timeout)
     * - Topic subscription changes
     * - Partition count changes
     * 
     * Rebalance Protocol:
     * 1. JoinGroup - Members join, elect leader
     * 2. SyncGroup - Leader assigns partitions to members
     * 3. Member gets assigned partitions
     */
}
```

---

## 4. Log Storage and Segment Management

### 4.1 Log Directory Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    KAFKA LOG DIRECTORY STRUCTURE                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  /var/lib/kafka/data/                                                       │
│  ├── topicA-0/                                                              │
│  │   ├── 00000000000000000000.log      # Actual message data              │
│  │   ├── 00000000000000000000.index    # Offset index                     │
│  │   ├── 00000000000000000000.timeindex# Timestamp index                  │
│  │   ├── 00000000000000000000.txnindex# Transaction index                │
│  │   ├── 00000000000000000000.sindex   # Sparse index                     │
│  │   ├── 00000000000000001000.log      # Next segment (rolled)            │
│  │   └── leader-epoch-checkpoint       # Leader epoch history            │
│  │                                                                  │
│  ├── topicA-1/                                                              │
│  │   └── ...                                                              │
│  │                                                                  │
│  └── topicB-0/                                                              │
│      └── ...                                                               │
│                                                                              │
│  Segment Files:                                                              │
│  - .log: Actual data (messages)                                            │
│  - .index: Maps offset to position in .log                                 │
│  - .timeindex: Maps timestamp to offset                                     │
│  - .txnindex: Transaction index for exactly-once                            │
│  - .sindex: Snapshot index for state changes                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Log Segment Rolling

```java
// Log segment management
public class LogSegmentManagement {
    
    /**
     * When does Kafka roll to a new segment?
     * 
     * 1. Size-based (log.segment.bytes = 1GB default):
     *    - Current segment reaches 1GB
     *    - Roll to new segment
     * 
     * 2. Time-based (log.roll.ms = 168 hours default):
     *    - Current segment open for 7 days
     *    - Roll regardless of size
     * 
     * 3. Log append time:
     *    - Based on message timestamp, not wall-clock
     *    - log.message.timestamp.difference.max.ms = 2 hours
     *    - If message 2+ hours newer than last, force roll
     * 
     * 4. Index size:
     *    - log.index.size.max.bytes = 10MB default
     *    - If index fills, force roll
     * 
     * 5. Append Sequence:
     *    - log.roll.jitter.ms = 0 (add jitter to avoid stampede)
     */
    
    /**
     * Segment Naming:
     * 
     * Format: offset of first message in segment
     * Example: 00000000000000000000.log (starts at offset 0)
     *          00000000000000100000.log (starts at offset 10000)
     * 
     * This makes locating segment by offset O(1) - just divide by 
     * segment size!
     */
    
    /**
     * Retention Policies:
     * 
     * log.retention.hours = 168 (7 days)
     * log.retention.check.interval.ms = 300000 (5 minutes)
     * 
     * Cleanup policies:
     * - delete (default): Delete old segments
     * - compact: Delete old versions, keep latest (keyed topics)
     * - delete + compact: Both
     * 
     * Size-based retention:
     * log.retention.bytes = -1 (unlimited)
     * log.retention.check.interval.ms = 300000
     * 
     * Log cleaner (for compaction):
     * log.cleaner.enable = true (default)
     * log.cleaner.min.compaction.lag.ms = 0
     */
}
```

---

## 5. Producer Internals and Batching

### 5.1 Producer Architecture

```java
// Kafka producer internal architecture
public class ProducerInternals {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                      KAFKA PRODUCER                                  │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │                      KafkaProducer                              ││
     │  │                                                                   ││
     │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          ││
     │  │  │   Sender     │  │  Accumulator │  │  Partitioner │          ││
     │  │  │  (IO Thread) │  │  (Batching)  │  │  (Routing)   │          ││
     │  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          ││
     │  │         │                 │                 │                    ││
     │  │         └─────────────────┼─────────────────┘                    ││
     │  │                           │                                      ││
     │  │  ┌───────────────────────▼───────────────────────────────┐     ││
     │  │  │                   RecordAccumulator                   │     ││
     │  │  │  ┌──────────────────────────────────────────────────┐  │     ││
     │  │  │  │ TopicPartition: {                                │  │     ││
     │  │  │  │   queue: [RecordBatch, RecordBatch, ...]        │  │     ││
     │  │  │  │   batchSize: bytes                               │  │     ││
     │  │  │  │   full: boolean                                  │  │     ││
     │  │  │  │ }                                                │  │     ││
     │  │  │  └──────────────────────────────────────────────────┘  │     ││
     │  │  └───────────────────────────────────────────────────────┘     ││
     │  │                                                                   ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Batching Process:
     * 
     * 1. send() called with ProducerRecord
     * 2. Partitioner determines partition
     * 3. Record added to accumulator's deque for that partition
     * 4. If batch is full orlinger.ms timeout, ready for send
     * 5. Sender thread batches ready records per broker
     * 6. Send produce request to broker
     */
    
    /**
     * Accumulator Configuration:
     * 
     * buffer.memory = 32MB (default)
     * - Total memory for batching
     * - If full, send() blocks until space available
     * 
     * batch.size = 16KB (default)
     * - Per-partition batch size
     * - Increase for higher throughput
     * 
     * linger.ms = 0 (default)
     * - Wait time to batch messages
     * - Increase to improve compression/throughput
     * - Set to 5-10ms for high throughput
     * 
     * compression.type = none (default)
     * - lz4, snappy, zstd, gzip
     * - CPU vs bandwidth tradeoff
     * - zstd best compression ratio
     */
}
```

### 5.2 Partitioning Strategies

```java
// Custom partitioner implementation
public class CustomPartitioner implements Partitioner {
    
    /**
     * Default Partitioner (DefaultPartitioner):
     * 
     * - If key != null: hash(key) % partitions
     * - If key == null: sticky partition (round-robin)
     * 
     * This ensures:
     * - Same key always goes to same partition (ordering)
     * - Without key, even distribution
     */
    
    @Override
    public int partition(String topic, Object key, byte[] keyBytes, 
                        Object value, byte[] valueBytes, Cluster cluster) {
        
        List<PartitionInfo> partitions = cluster.partitionsForTopic(topic);
        int numPartitions = partitions.size();
        
        if (keyBytes == null) {
            // No key - use sticky partition
            // Get metadata from producer for next sticky partition
            return stickyPartitionCache.getOrDefault(topic, 0);
        }
        
        // Hash the key
        return Utils.toPositive(Utils.murmur2(keyBytes)) % numPartitions;
    }
    
    /**
     * Custom partitioner for priority queues:
     */
    
    public static class PriorityPartitioner implements Partitioner {
        
        // High priority orders go to first N partitions
        private static final int HIGH_PRIORITY_PARTITIONS = 2;
        
        @Override
        public int partition(String topic, Object key, byte[] keyBytes,
                            Object value, byte[] valueBytes, Cluster cluster) {
            
            if (keyBytes == null) {
                // Round-robin for null keys
                return Utils.toPositive(Utils.murmur2(valueBytes)) % 
                    cluster.partitionsForTopic(topic).size();
            }
            
            // Parse key to extract priority
            // Key format: "priority-orderId" e.g., "HIGH-12345"
            String keyStr = new String(keyBytes);
            
            if (keyStr.startsWith("HIGH-")) {
                // Map to high-priority partitions (0 or 1)
                return Utils.toPositive(Utils.murmur2(
                    keyStr.substring(5).getBytes())) % HIGH_PRIORITY_PARTITIONS;
            } else if (keyStr.startsWith("MEDIUM-")) {
                // Map to medium partitions (2-4)
                int total = cluster.partitionsForTopic(topic).size();
                return HIGH_PRIORITY_PARTITIONS + 
                    (Utils.toPositive(Utils.murmur2(keyStr.substring(7).getBytes())) 
                     % (total - HIGH_PRIORITY_PARTITIONS));
            } else {
                // LOW - all remaining partitions
                return (int) (System.currentTimeMillis() % 
                    cluster.partitionsForTopic(topic).size());
            }
        }
    }
}
```

---

## 6. Consumer Group Protocol Deep Dive

### 6.1 Consumer State Machine

```java
// Consumer group state transitions
public class ConsumerGroupStates {
    
    /**
     * Consumer Group States:
     * 
     * ┌──────────────┐
     * │    EMPTY     │  Initial state, no members
     * └──────┬───────┘
     *        │ members join
     *        ▼
     * ┌──────────────┐
     * │  PREPARING  │  Rebalance in progress
     * │   REBALANCE  │
     * └──────┬───────┘
     *        │ assignment complete
     *        ▼
     * ┌──────────────┐
     * │   STABLE     │  Normal operation
     * └──────┬───────┘
     *        │ member leaves/crashes
     *        ▼
     * ┌──────────────┐
     * │  PREPARING   │  Rebalance starts again
     * │  REBALANCE   │
     * └──────┬───────┘
     *        │
     *        │ all leave
     *        ▼
     * ┌──────────────┐
     * │    EMPTY     │
     * └──────────────┘
     */
    
    /**
     * JoinGroup Request:
     * 
     * - Members send JoinGroup with their subscription
     * - Group coordinator collects all join requests
     * - If first member, they become leader
     * - Wait for all expected members (session.timeout)
     * - Trigger rebalance
     */
    
    /**
     * SyncGroup Request:
     * 
     * - Leader receives partition assignment
     * - Leader sends SyncGroup with assignments
     * - Coordinator sends assignments to all members
     * - Members begin fetching from assigned partitions
     */
    
    /**
     * Rebalance Protocols:
     * 
     * - protocol_type: "consumer" (standard)
     * - protocol_name: "range", "roundrobin", "sticky"
     * 
     * Supported protocols evolved:
     * - 0.9: range, roundrobin
     * - 0.10.2: sticky (added)
     * - 1.0+: Enhanced sticky assignor
     */
}
```

### 6.2 Offset Management

```java
// Offset commit mechanisms
public class OffsetManagement {
    
    /**
     * Offset Storage:
     * 
     * Kafka topics: __consumer_offsets
     * - 50 partitions by default
     * - Compacted topic
     * - Stores: (group, topic, partition) -> offset
     * 
     * Key format: 
     * groupId + topic + partition -> offset + metadata + timestamp
     */
    
    /**
     * Automatic vs Manual Offset:
     * 
     * enable.auto.commit = true (default)
     * - Auto-commit every auto.commit.interval.ms (default 5s)
     * - Simple but can cause duplicate processing
     * 
     * enable.auto.commit = false
     * - Manual commit via commitSync() or commitAsync()
     * - More control, exactly-once support
     */
    
    /**
     * Commit Patterns:
     */
    
    // Sync commit - blocks until committed
    public void syncCommit(Consumer<String, String> consumer) {
        try {
            // Process messages...
            processMessage(record);
            
            // Commit after processing
            consumer.commitSync();
            
            // Or commit specific offsets
            consumer.commitSync(Collections.singletonMap(
                new TopicPartition(record.topic(), record.partition()),
                new OffsetAndMetadata(record.offset() + 1)
            ));
            
        } catch (CommitFailedException e) {
            // Handle - may retry
        }
    }
    
    // Async commit - non-blocking
    public void asyncCommit(Consumer<String, String> consumer) {
        consumer.commitAsync((offsets, exception) -> {
            if (exception != null) {
                // Handle commit failure
                log.error("Commit failed", exception);
            } else {
                // Commit successful
            }
        });
    }
    
    /**
     * Offset Reset Policy:
     * 
     * auto.offset.reset = "latest" (default)
     * - latest: Start from newest available
     * - earliest: Start from oldest
     * - none: Throw exception if no committed offset
     * 
     * Use consumer.seek() to jump to specific offset:
     * consumer.seekToBeginning(Arrays.asList(partition));
     * consumer.seek(new TopicPartition("topic", 0), 500L);
     */
}
```

---

## 7. Exactly-Once Semantics Implementation

### 7.1 Idempotent Producer

```java
// Idempotent producer implementation
public class IdempotentProducer {
    
    /**
     * What is Idempotent Producer?
     * 
     * Enables exactly-once semantics for produce:
     * - Guarantees each message written exactly once
     * - Eliminates duplicates from retry
     * - Requires: Kafka 0.11+
     * 
     * How it works:
     * 1. Each producer gets unique ID (ProducerId)
     * 2. Each batch gets sequence number (SequenceNumber)
     * 3. Broker maintains mapping of (ProducerId, SequenceNumber) -> offset
     * 4. Duplicates detected and discarded at broker
     */
    
    public static Properties createIdempotentConfig() {
        Properties props = new Properties();
        props.put("bootstrap.servers", "broker1:9092");
        
        // Enable idempotence
        props.put("enable.idempotence", true);
        
        // These are automatically set when idempotence is enabled:
        // props.put("max.in.flight.requests.per.connection", 5);
        // props.put("acks", "all");
        // props.put("retries", Integer.MAX_VALUE);
        
        // But can tune:
        // Transaction timeout
        props.put("transaction.timeout.ms", 60000);
        
        return props;
    }
    
    /**
     * Idempotence Guarantees:
     * 
     * - Exactly-once delivery to single partition
     * - Across retries, duplicates eliminated
     * - Order preserved within partition
     * 
     * Limitations:
     * - Per-partition semantics
     * - Requires acks=all
     * - Producer has state, cannot change on restart
     * - Topic needs at least in-sync replicas for produce
     */
}
```

### 7.2 Transactions API

```java
// Kafka transactions for multi-partition exactly-once
public class TransactionalProducer {
    
    /**
     * Transactional Producer:
     * 
     * Enables:
     * - Write to multiple partitions atomically
     * - Exactly-once semantics across partitions
     * - Abort on failure (rollback)
     * 
     * Use cases:
     * - Multi-topic updates
     * - "Read-process-write" patterns
     * - Stream processing with state
     */
    
    public static void demonstrateTransactions(Producer<String, String> producer) {
        
        // Initialize transaction
        producer.initTransactions();
        
        // Start transaction
        producer.beginTransaction();
        
        try {
            // Write to multiple topics
            producer.send(new ProducerRecord<>("orders", key1, order1));
            producer.send(new ProducerRecord<>("inventory", key2, inventoryUpdate));
            producer.send(new ProducerRecord<>("notifications", key3, notification));
            
            // Commit transaction
            producer.commitTransaction();
            
        } catch (Exception e) {
            // Abort transaction
            producer.abortTransaction();
            throw e;
        }
    }
    
    /**
     * Transaction Coordination:
     * 
     * 1. Producer requests transaction ID from broker
     * 2. Coordinator registers transaction ID
     * 3. Producer sends produce requests with TransactionalId
     * 4. Broker tracks transaction state
     * 5. On commit, markers written to partition
     * 6. On abort, transaction rolled back
     * 
     * TransactionalId:
     * - Unique identifier for producer
     * - Enables broker to track producer across restarts
     * - Recovery on failure
     */
    
    /**
     * Consumer Isolation:
     * 
     * Transactional consumer must use:
     * isolation.level = read_committed (vs read_uncommitted)
     * 
     * - read_committed: Only read committed transactions
     * - read_uncommitted: Read all messages including aborted
     * 
     * read_committed returns:
     * - Committed messages only
     * - Additional field: transactionId (which transaction)
     */
}
```

---

## 8. Kafka Streams Architecture

### 8.1 Stream Task Architecture

```java
// Kafka Streams internal architecture
public class StreamArchitecture {
    
    /**
     * ┌─────────────────────────────────────────────────────────────────────┐
     │                    KAFKA STREAMS ARCHITECTURE                       │
     ├─────────────────────────────────────────────────────────────────────┤
     │                                                                      │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │                     StreamsBuilder                               ││
     │  │  - Define topology (sources, transformations, sinks)            ││
     │  │  - Build execution plan                                          ││
     │  │                                                                   ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                              ▼                                        │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │                   StreamsPartitionAssignor                      ││
     │  │  - Distribute tasks across instances                             ││
     │  │  - Rebalance on scaling                                         ││
     │  │                                                                   ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                              │                                        │
     │                              ▼                                        │
     │  ┌──────────────────────────────────────────────────────────────────┐│
     │  │                     KafkaStreams                                 ││
     │  │                                                                   ││
     │  │  ┌──────────────────────────────────────────────────────────────┐ ││
     │  │  │  StreamThread 1                                            │ ││
     │  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐          │ ││
     │  │  │  │   Task 0    │ │   Task 1    │ │   Task 2    │          │ ││
     │  │  │  │ (Partition 0) (Partition 1) (Partition 2)            │ ││
     │  │  │  └─────────────┘ └─────────────┘ └─────────────┘          │ ││
     │  │  │         │             │             │                      │ ││
     │  │  │         └─────────────┴─────────────┘                      │ ││
     │  │  │                   StreamsTask                                │ ││
     │  │  │  - Process records, manage state                            │ ││
     │  │  │  - Store: RocksDB, in-memory                                 │ ││
     │  │  └──────────────────────────────────────────────────────────────┘ ││
     │  │                                                                   ││
     │  └──────────────────────────────────────────────────────────────────┘│
     │                                                                      │
     └─────────────────────────────────────────────────────────────────────┘
     */
    
    /**
     * Task Assignment:
     * 
     * - Number of tasks = max(partitions across all source topics)
     * - Each task owns 1+ partitions
     * - Tasks distributed across StreamThreads
     * - Each instance runs multiple tasks
     * 
     * Example:
     * - Topic A: 3 partitions
     * - Topic B: 2 partitions  
     * - Total tasks = 3 (max of 3 and 2)
     */
    
    /**
     * State Stores:
     * 
     * Persistent state stores (RocksDB):
     * - Windowed stores (aggregations)
     * - Key-value stores (tables)
     * - SSD-backed, configurable
     * 
     * In-memory:
     * - Faster but limited by RAM
     * - Good for small state
     */
}
```

### 8.2 Windowing Deep Dive

```java
// Windowing implementation in Kafka Streams
public class WindowingImplementation {
    
    /**
     * Window Types:
     * 
     * 1. Tumbling (fixed) Windows:
     *    - Non-overlapping, fixed size
     *    - TimeWindows.of(Duration.ofMinutes(5))
     *    - Example: 0-5, 5-10, 10-15
     * 
     * 2. Hopping (sliding) Windows:
     *    - Overlapping, fixed size with advance
     *    - TimeWindows.of(Duration.ofMinutes(10)).advanceBy(Duration.ofMinutes(5))
     *    - Example: 0-10, 5-15, 10-20
     * 
     * 3. Session Windows:
     *    - Group events within gap
     *    - SessionWindows.with(Duration.ofMinutes(30))
     *    - Gap-based, adaptive window sizes
     * 
     * 4. Join Windows:
     *    - For stream joins
     *    - JoinWindows.of(Duration.ofMinutes(5))
     */
    
    /**
     * Time Semantics:
     * 
     * Event-time (default):
     * - Based on message timestamp
     * - Out-of-order handling via watermarks
     * - Windows triggered when watermark passes
     * 
     * Processing-time:
     * - Based on processing time (wall-clock)
     * - Faster but less accurate
     * - Use: event-time = "auto" (default)
     * 
     * Ingestion-time:
     * - Based on broker receive time
     * - Less flexible than event-time
     */
    
    /**
     * Watermarks:
     * 
     * Watermark = "time before which all data has arrived"
     * 
     * - Watermark = max(event-time) - grace_period
     * - Default grace = out-of-orderness
     * - WithWatermark(of(Duration.ofMinutes(5)))
     * 
     * Late data handling:
     * - Data with timestamp < watermark is "late"
     * - late data dropped by default
     * - can emit to "dead letter" topic
     */
    
    /**
     * Example: Session window for user activity
     */
    
    KStream<String, UserAction> userActions = builder.stream("user-actions");
    
    KTable<Windowed<String>, Long> sessionCounts = userActions
        .groupByKey()
        .windowedBy(SessionWindows.with(Duration.ofMinutes(30)))
        .count();
    
    // Result: sessions with activity within 30 minutes grouped together
    // User A: action1 at 10:00, action2 at 10:15 -> window 10:00-10:30
    // User A: action3 at 10:45 -> new window 10:45-11:15 (new session)
}
```

---

## 9. Security Implementation

### 9.1 Authentication Mechanisms

```java
// Kafka security configuration
public class SecurityConfiguration {
    
    /**
     * SASL/SSL Configuration:
     * 
     * ┌─────────────────┬─────────────────────────────────────────────────┐
     │   Mechanism     │  Description                                     │
     ├─────────────────┼─────────────────────────────────────────────────┤
     │ PLAIN           │  Username/password, no encryption                │
     │ SCRAM-SHA-256   │  Password-based, challenge-response              │
     │ SCRAM-SHA-512   │  Stronger SCRAM variant                          │
     │ GSSAPI (Kerberos)│  Enterprise SSO integration                     │
     │ OAUTHBEARER     │  OAuth2 token-based                             │
     └─────────────────┴─────────────────────────────────────────────────┘
     */
    
    /**
     * PLAIN Configuration:
     * 
     * # server.properties
     * listeners=SASL_PLAINTEXT://0.0.0.0:9092
     * security.inter.broker.protocol=SASL_PLAINTEXT
     * sasl.mechanism.inter.broker.protocol=PLAIN
     * 
     * # JAAS config (kafka_server_jaas.conf)
     * KafkaServer {
     *   org.apache.kafka.common.security.plain.PlainLoginModule required
     *   username="admin"
     *   password="admin-secret"
     *   user_admin="admin-secret"
     *   user_producer="producer-secret"
     *   user_consumer="consumer-secret";
     * };
     * 
     * Java client:
     * props.put("security.protocol", "SASL_PLAINTEXT");
     * props.put("sasl.mechanism", "PLAIN");
     * props.put("sasl.jaas.config", 
     *   "org.apache.kafka.common.security.plain.PlainLoginModule required " +
     *   "username=\"producer\" password=\"producer-secret\";");
     */
    
    /**
     * SCRAM-SHA-256 (More secure):
     * 
     * # server.properties
     * sasl.mechanism.inter.broker.protocol=SCRAM-SHA_256
     * 
     * # JAAS
     * KafkaServer {
     *   org.apache.kafka.common.security.scram.ScramLoginModule required
     *   username="admin"
     *   password="admin-secret";
     * };
     * 
     * Advantages:
     * - Passwords not sent in clear
     * - Challenge-response prevents replay
     * - Can store hashed passwords
     */
}
```

### 9.2 Authorization

```java
// Authorization in Kafka
public class KafkaAuthorization {
    
    /**
     * ACL-based Authorization:
     * 
     * ACL format:
     * Principal = User:name
     * Resource = Topic/Group/Cluster/TransactionalId
     * Operation = Read/Write/Create/Delete/Describe/...
     * Permission = Allow/Deny
     * 
     * Command:
     * kafka-acls.sh --authorizer-properties zookeeper.connect=localhost:2181 \
     *   --add --allow-principal User:producer \
     *   --operation Write --topic orders
     */
    
    /**
     * Common ACLs:
     */
    
    // Producer ACL
    // kafka-acls.sh --add \
    //   --allow-principal User:producer \
    //   --producer \
    //   --topic orders \
    //   --group "*"
    
    // Consumer ACL
    // kafka-acls.sh --add \
    //   --allow-principal User:consumer \
    //   --consumer \
    //   --topic orders \
    //   --group order-consumer-group
    
    /**
     * ACL Examples:
     */
    
    // Allow read on topic
    // --operation Read --topic orders
    
    // Allow write on topic
    // --operation Write --topic orders
    
    // Allow describe on topic (metadata)
    // --operation Describe --topic orders
    
    // Allow all operations on group
    // --operation All --group my-group
    
    /**
     * Authorization Plugins:
     * 
     * - Default: Simple ACL authorizer
     * - Ranger: Enterprise authorization
     * - Custom: Implement Authorizer interface
     */
}
```

---

## 10. Performance Optimization

### 10.1 Broker Tuning

```properties
# Kafka broker tuning for high throughput

# Socket server
num.network.threads = 8          # Process network requests
num.io.threads = 16              # Process I/O operations
socket.request.max.bytes = 104857600  # 100MB
socket.receive.buffer.bytes = 102400  # 100KB
socket.send.buffer.bytes = 102400

# Log
log.segment.bytes = 1073741824   # 1GB segment
log.segment.ms = 604800000        # 7 days
log.retention.hours = 168         # 7 days
log.retention.bytes = -1          # Unlimited
log.index.size.max.bytes = 10485760  # 10MB index

# Replication
replica.socket.timeout.ms = 30000
replica.fetch.max.bytes = 1048576
replica.fetch.min.bytes = 1
replica.fetch.wait.max.ms = 500

# Compression
compression.type = lz4  # lz4, snappy, zstd, gzip
```

### 10.2 Producer Tuning

```java
// High-throughput producer configuration
public class ProducerOptimization {
    
    public static Properties optimizedProducer() {
        Properties props = new Properties();
        props.put("bootstrap.servers", "broker1:9092,broker2:9092,broker3:9092");
        
        // Batching
        props.put("batch.size", 32768);         // 32KB (default 16KB)
        props.put("linger.ms", 10);              // 10ms wait (default 0)
        
        // Buffer
        props.put("buffer.memory", 134217728);   // 128MB (default 32MB)
        
        // Compression
        props.put("compression.type", "zstd");   // Best compression
        
        // Performance
        props.put("max.in.flight.requests.per.connection", 5);
        props.put("request.timeout.ms", 30000);
        props.put("retries", Integer.MAX_VALUE);
        
        // Idempotence
        props.put("enable.idempotence", true);
        
        return props;
    }
    
    /**
     * Key tuning parameters:
     * 
     * batch.size:
     * - Larger = more messages per batch
     * - Trade-off: larger batches use more memory
     * - Monitor: batch-size-avg in metrics
     * 
     * linger.ms:
     * - Wait up to N ms to fill batch
     * - Set to 5-10ms for higher throughput
     * - Increase latency slightly
     * 
     * compression.type:
     * - zstd: Best ratio, CPU-intensive
     * - lz4: Good ratio, fast (default)
     * - snappy: Fast, lower ratio
     */
}
```

---

## 11. Troubleshooting Production Issues

### 11.1 Consumer Lag

```bash
# Check consumer lag
kafka-consumer-groups.sh --bootstrap-server broker:9092 \
  --group my-group --describe

# For each partition:
# LAG = current offset - committed offset

# High lag causes:
# - Consumer not keeping up
# - Consumer crashed
# - Rebalancing taking long
# - Slow processing per message

# Fix:
# 1. Scale consumers
# 2. Improve processing logic
# 3. Check for blocking I/O
# 4. Ensure enough parallelism
```

### 11.2 Under-Replicated Partitions

```bash
# Check URP
kafka-topics.sh --describe --topic orders --bootstrap-server broker:9092

# If URP exists:
# - ISR contains only subset of replicas
# - Some replicas not catching up

# Common causes:
# 1. Broker down
# 2. Slow follower (network/disk)
# 3. Full disk
# 4. GC pauses on follower

# Check follower status
kafka-dump-log.sh --files /var/lib/kafka/data/topic-0/00000000000000000000.log \
  --print-data-log | head -20

# Fix:
# 1. Restart dead brokers
# 2. Add brokers
# 3. Improve disk/network
# 4. Tune GC
```

### 11.3 Rebalance Storms

```bash
# When rebalance takes too long or happens frequently

# Cause: session.timeout.ms too short
# - Session timeout should allow for processing time
# - Usually > 30s, maybe 10 minutes

# Cause: consumers leaving unexpectedly
# - Check logs for "Member failed to join"
# - Verify heartbeats

# Solution: sticky assignor
# partition.assignment.strategy=org.apache.kafka.clients.consumer.StickyAssignor

# Increase rebalance timeout
# group.initial.rebalance.delay.ms = 3000
# Allows new members to join before rebalance starts
```

---

This deep-dive guide provides comprehensive technical understanding of Kafka's internals, from broker architecture to production troubleshooting.