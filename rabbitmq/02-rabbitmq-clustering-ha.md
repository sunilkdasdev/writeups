# RabbitMQ Clustering and High Availability: Production Guide

**By Donald K. Burleson**

---

## Introduction: Why HA Matters for RabbitMQ

In production environments, message brokers are critical infrastructure. A single point of failure can bring down your entire system.

At Manhattan Associates, we've built highly available RabbitMQ clusters that survive node failures without losing messages. This guide shows how.

---

## Chapter 1: Clustering Fundamentals

### Understanding RabbitMQ Clustering

```bash
# Verify cluster status
rabbitmqctl cluster_status

# Expected output:
# Cluster name: rabbit@warehouse-1
# Running Nodes: rabbit@warehouse-1, rabbit@warehouse-2, rabbit@warehouse-3
# Partitions: none
```

### Setting Up a 3-Node Cluster

```bash
# Node 1 - Initial node
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl start_app

# Node 2 - Join cluster
rabbitmqctl stop_app
rabbitmqctl join_cluster rabbit@warehouse-1
rabbitmqctl start_app

# Node 3 - Join cluster
rabbitmqctl stop_app
rabbitmqctl join_cluster rabbit@warehouse-1
rabbitmqctl start_app
```

### Cluster Communication

```
┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│  Node 1     │◄─────►│  Node 2     │◄─────►│  Node 3     │
│  (RAM)      │       │  (Disc)     │       │  (Disc)     │
└─────────────┘       └─────────────┘       └─────────────┘
     │                      │                      │
     └──────────────────────┼──────────────────────┘
                            │
                    Erlang distribution
                    (port 25672)
```

---

## Chapter 2: Queue Mirroring Deep Dive

### The Mirroring Problem

By default, queues live on ONE node. If that node fails, messages are lost!

```java
// Before: Messages on node that crashes = LOST
channel.queueDeclare("orders", true, false, false, null);
// This queue exists on ONE node only!
```

### Classic Mirroring

```bash
# Mirror to all nodes
rabbitmqctl set_policy ha-all "^ha\." \
  '{"ha-mode":"all","ha-sync-mode":"automatic"}'

# Mirror to exactly N nodes
rabbitmqctl set_policy ha-two "^orders\." \
  '{"ha-mode":"exactly","ha-params":2,"ha-sync-mode":"automatic"}'
```

**Policy configuration:**
- `ha-mode`: all, exactly, nodes
- `ha-params`: number of replicas for "exactly"
- `ha-sync-mode`: manual or automatic
- `ha-promote-on-shutdown`: when leader stops

### Mirroring Behavior

```
┌──────────────────────────────────────────────────────────────┐
│                    Mirrored Queue                             │
├──────────────────────────────────────────────────────────────┤
│  Master (on Node 1)  ◄─── sync ──►  Slave 1 (Node 2)       │
│                              ◄─── sync ──►  Slave 2 (Node 3)│
└──────────────────────────────────────────────────────────────┘

Producer ──► Master (stores) ──► Replicates to slaves
Consumer ◄─── Master ◄─── (can read from any slave in 3.8+)
```

### Automatic Synchronization

```java
// Producer - not aware of mirroring
channel.basicPublish("orders", "create", null, order.getBytes());

// When master fails, slave promoted automatically
// New master continues serving
```

---

## Chapter 3: Quorum Queues (The Modern Approach)

### Why Quorum Queues?

- **Built-in replication** - No special policies needed
- **Data safety** - Majority acknowledgment required
- **Simpler HA** - Replace queue mirroring

### Creating Quorum Queues

```java
Map<String, Object> args = new HashMap<>();
args.put("x-queue-type", "quorum");
args.put("x-quorum-initial-group-size", 3);
args.put("x-quorum-minimum-online-quorum", 2);

channel.queueDeclare("orders.ha", true, false, false, args);
```

### CLI Creation

```bash
rabbitmqctl set_quorum_queue_priority orders.ha 10
rabbitmqctl set_queue_type_selector orders.ha quorum
```

### Quorum Queue Behavior

```
┌────────────────────────────────────────────────────────────┐
│              Quorum Queue (3 replicas)                     │
├────────────────────────────────────────────────────────────┤
│  Leader (Node 1)   ◄─── Raft ──►  Follower (Node 2)     │
│                                  ◄─── Raft ──► Follower    │
│                                                              │
│  Writes require majority (2 of 3) acknowledgment           │
└────────────────────────────────────────────────────────────┘
```

### Comparison: Classic vs Quorum

| Feature | Classic Mirroring | Quorum Queues |
|---------|------------------|---------------|
| Replication | Master/Slave | Raft consensus |
| Acknowledgment | Async | Synchronous |
| Data safety | Configurable | Guaranteed |
| Memory usage | Higher | Lower |
| Recovery | Manual promotion | Automatic |

---

## Chapter 4: Network Partitions

### What Happens During Partition?

```
Normal:                    Partition:
A ◄─── B ◄─── C            A ◄─── ✗ ───► B ◄─── ✗ ◄──► C

All connected              A and B see each other
                           C sees itself
                           B and C see each other
                           (Three partitions!)
```

### Handling Strategies

**1. pause_minority**

```bash
# In rabbitmq.conf
cluster_partition_handling = pause_minority

# Smaller partition pauses until partition resolves
```

**2. autoheal**

```bash
cluster_partition_handling = autoheal

# When partition detected:
# 1. Stop minority partition
# 2. Restart minority nodes
# 3. Rejoin cluster
```

**3. ignore**

```bash
cluster_partition_handling = ignore

# Partitions not handled - manual intervention needed
# WARNING: Can lead to split-brain!
```

### Detecting Partitions

```bash
# Check for partitions
rabbitmqctl cluster_status

# Look for "partitions" in output
# Running Nodes: rabbit@node1, rabbit@node2
# Partitions: {rabbit@node2,[rabbit@node1]}
```

### Recovery from Partition

```bash
# Force restart to heal
rabbitmqctl force_boot

# Or forget cluster node
rabbitmqctl forget_cluster_node rabbit@failed-node
```

---

## Chapter 5: Load Balancing

### Why Load Balancer?

```
          ┌──────────────┐
          │ Load Balancer│
          └──────┬───────┘
                 │
     ┌───────────┼───────────┐
     ▼           ▼           ▼
  Node 1      Node 2      Node 3
```

### HAProxy Configuration

```haproxy
frontend rabbitmq_front
    bind *:5670
    mode tcp
    default_backend rabbitmq_back

backend rabbitmq_back
    mode tcp
    balance roundrobin
    option tcplog
    option option httpchk
    http-check expect status 200
    server node1 192.168.1.10:5672 check inter 5s rise 2 fall 3
    server node2 192.168.1.11:5672 check inter 5s rise 2 fall 3
    server node3 192.168.1.12:5672 check inter 5s rise 2 fall 3

# Management port
listen rabbitmq_mgmt
    bind *:15672
    mode http
    server node1 192.168.1.10:15672
    server node2 192.168.1.11:15672
    server node3 192.168.1.12:15672
```

### Client Connection HA

```java
// Multiple server addresses
ConnectionFactory factory = new ConnectionFactory();
factory.setHost("rabbitmq-lb.internal");
factory.setPort(5672);
// Or: factory.setAddresses("node1:5672,node2:5672,node3:5672");

// Enable automatic recovery
factory.setAutomaticRecoveryEnabled(true);
factory.setNetworkRecoveryInterval(10000);
```

---

## Chapter 6: Federation for Multi-Region

### When to Use Federation

- Multiple data centers
- Geographic distribution
- Disaster recovery

### Federation Setup

```bash
# Define upstream on local cluster
rabbitmqctl set_parameter federation-upstream dc1 \
  '{"uri":"amqp://rabbit@remote-dc1","expires":3600000}' \
  --vhost /warehouse

# Define upstream on remote cluster
rabbitmqctl set_parameter federation-upstream dc2 \
  '{"uri":"amqp://rabbit@remote-dc2","expires":3600000}' \
  --vhost /warehouse

# Create policy to federate
rabbitmqctl set_policy federate-orders "^orders\." \
  '{"federation-upstream-set":["dc1","dc2"]}' \
  --vhost /warehouse
```

### Federation Topology

```
┌─────────────┐                    ┌─────────────┐
│  DC1        │  ◄─── Federation ──►│  DC2        │
│  (Primary)  │                    │  (DR)       │
│             │                    │             │
│  orders ───────────────────────────► orders    │
│  events  ──────────────────────────► events   │
└─────────────┘                    └─────────────┘
```

---

## Chapter 7: Disaster Recovery

### Backing Up RabbitMQ

```bash
# Export definitions
rabbitmqctl export_definitions /backup/definitions.json

# Export state (messages)
# Note: Can't export actual messages easily!
# Best strategy: Replicate with quorum/federation
```

### Restoring Definitions

```bash
# Stop app on all nodes
rabbitmqctl stop_app

# Reset
rabbitmqctl reset

# Import
rabbitmqctl import_definitions /backup/definitions.json

# Start
rabbitmqctl start_app
```

### Failover Checklist

```bash
# 1. Check cluster status
rabbitmqctl cluster_status

# 2. Identify failed node
# 3. Remove from cluster
rabbitmqctl forget_cluster_node rabbit@failed-node

# 4. Bring up new node
rabbitmqctl join_cluster rabbit@existing-node

# 5. Verify queue mirrors
rabbitmqctl list_queues name policy slave_pids
```

---

## Chapter 8: Monitoring and Alerts

### Key Metrics

```bash
# Queue depth
rabbitmqctl list_queues name messages messages_unacked

# Consumer count
rabbitmqctl list_consumers queue_name

# Disk usage
rabbitmqctl status | grep disk

# Memory
rabbitmqctl status | grep memory

# Cluster partition status
rabbitmqctl cluster_status | grep partitions
```

### Prometheus Monitoring

```yaml
# Enable prometheus plugin
rabbitmq-plugins enable rabbitmq_prometheus

# scrape_configs:
#   - job_name: 'rabbitmq'
#     static_configs:
#       - targets: ['rabbitmq:15672']
```

### Alert Rules

```yaml
groups:
- name: rabbitmq
  rules:
  - alert: RabbitMQQueueFull
    expr: rabbitmq_queue_messages_ready / rabbitmq_queue_messages > 0.9
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Queue {{ $labels.queue }} is 90% full"

  - alert: RabbitMQNodeDown
    expr: up{job="rabbitmq"} == 0
    for: 1m
    labels:
      severity: critical
```

---

## Conclusion

**Donald Sez**: "High availability isn't an afterthought—it's architecture from day one."

At Manhattan Associates:
1. **Use quorum queues** for new implementations
2. **Plan for partitions** - choose correct strategy
3. **Load balance properly** - don't direct to single node
4. **Monitor everything** - detect issues before they cascade

---

**Next**: "RabbitMQ Performance Tuning: Optimizing for Throughput" - Advanced tuning techniques for high-volume messaging.