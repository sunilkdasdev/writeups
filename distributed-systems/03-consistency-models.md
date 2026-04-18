# Consistency Models in Distributed Systems: From ACID to CRDTs

## Introduction

Consistency models define the contract between a distributed system and its clients, specifying what guarantees the system provides about data freshness and ordering. Understanding these models is fundamental to designing and building distributed systems that behave correctly under various failure scenarios.

The choice of consistency model has profound implications for system behavior, performance, and availability. Strong consistency models simplify application development but may sacrifice availability during network partitions. Weaker models enable higher availability and performance but place more complexity on application developers.

This comprehensive exploration examines the theoretical foundations of consistency models, their practical implications, and how modern distributed systems navigate the trade-offs between consistency, availability, and performance.

## The CAP Theorem Revisited

Eric Brewer's CAP theorem, proven theoretically in 2002, states that a distributed system can provide only two of three properties simultaneously: Consistency, Availability, and Partition tolerance. While often stated simply, the theorem requires careful interpretation to apply correctly in system design.

The theorem's precise statement concerns behavior during a network partition. During normal operation (no partition), the system can provide both consistency and availability. However, when a partition occurs, the system must choose between consistency and availability. A CP system chooses consistency, potentially becoming unavailable to some or all clients. An AP system chooses availability, potentially serving stale data.

Importantly, CAP theorem does not specify what happens during normal operation. A system can be both consistent and available when the network is healthy. The choice is about what to sacrifice when partitions occur. In practice, most production systems are CP during partitions (sacrificing availability) but CA during normal operation (providing both).

The CAP theorem's simplicity can be misleading. Modern systems often implement tunable or hybrid approaches, providing strong consistency for some operations while offering eventual consistency for others. The design space is richer than a simple binary choice.

## ACID Consistency

Traditional database systems provide ACID guarantees: Atomicity, Consistency, Isolation, and Durability. While often discussed as a unit, each property addresses a different aspect of transaction behavior. Understanding these properties individually clarifies what applications can rely upon.

Atomicity ensures that a transaction either completes entirely or has no effect at all. If any part of a transaction fails, the entire transaction is rolled back. This all-or-nothing semantics simplifies error handling in applications, as developers need not implement partial completion logic.

Consistency in ACID refers to integrity constraints. A transaction must transform the database from one valid state to another, never violating declared constraints. If a transaction would violate a constraint, it is aborted entirely. This definition differs from the consistency in CAP, which concerns data synchronization across replicas.

Isolation ensures that concurrently executing transactions appear to execute serially. The isolation level determines what anomalies are permitted. Read uncommitted allows dirty reads; read committed allows non-repeatable reads; repeatable read allows phantom reads; serializable provides full isolation.

Durability guarantees that once a transaction commits, its effects survive system failures. In single-node systems, durability typically involves writing to disk before acknowledging the commit. In distributed systems, durability requires replicating the commit to multiple nodes before acknowledgment.

## Eventual Consistency

Eventual consistency guarantees that if no new updates are made to a given data item, eventually all reads will return the last updated value. This weak consistency model permits temporary divergence between replicas but ensures convergence over time.

The eventual in eventual consistency is not well-bounded. In practice, convergence time depends on factors including network latency, replica count, load characteristics, and implementation details. Applications must be designed to handle potentially stale reads for bounded or even unbounded periods.

Eventual consistency enables high availability and low latency because writes need not wait for synchronous replication to all replicas. A write can be acknowledged after persisting to a single node, with asynchronous propagation to other replicas. This approach handles partitions gracefully: the partition with the writable node continues serving writes, and the other partition catches up when connectivity restores.

Dynamo, Cassandra, Riak, and other Amazon-influenced systems popularized eventual consistency at scale. These systems prioritize availability and partition tolerance, accepting the complexity of eventual consistency in exchange for better performance and resilience.

## Linearizability

Linearizability is a consistency model that makes a system appear as if there is a single copy of the data, with all operations appearing to execute atomically at some point between the operation's invocation and response. Linearizability provides the illusion of a single, up-to-date replica, even though the actual implementation may involve multiple replicas.

Formally, linearizability requires that if operation B starts after operation A completes, then B must see either the effect of A or a later state. This real-time ordering constraint distinguishes linearizability from serializability. Linearizability requires actual temporal ordering; serializability only requires a equivalent serial execution.

Linearizable systems are easier to reason about because they provide sequential consistency. Clients can read a value and know that any subsequent read will see at least that value or a newer one. This property simplifies application logic, particularly for operations that depend on prior reads.

Implementing linearizability requires coordination. Most implementations use consensus algorithms like Paxos or Raft, which ensure that all replicas agree on the order of operations. This coordination introduces latency and limits throughput, but provides the strong consistency that many applications require.

ZooKeeper, etcd, and Consul provide linearizable coordination services. Google Spanner provides linearizable transactions across geographically distributed replicas. These systems accept the performance cost in exchange for stronger guarantees.

## Sequential Consistency

Sequential consistency, proposed by Leslie Lamport in 1979, requires that the result of any execution is the same as if the operations of all processors were executed in some sequential order, and the operations of each individual processor appear in this sequence in the order specified by its program.

Unlike linearizability, sequential consistency does not require real-time ordering. If operation A completes before operation B starts in real time, linearizability requires B to see A's effect. Sequential consistency only requires that there exists some valid sequential order that respects each processor's program order.

This distinction matters in distributed systems where network latency varies. Sequential consistency permits optimizations that linearizability forbids, potentially improving performance. However, the weaker guarantees complicate application reasoning.

Many processor memory models provide sequential consistency for single-threaded programs but weaker guarantees for multi-threaded access. Distributed systems like Amazon's S3 historically provided sequential consistency for certain operations, trading some guarantees for performance.

## Causal Consistency

Causal consistency is stronger than eventual consistency but weaker than sequential consistency. It guarantees that causally related operations are seen by all nodes in the same order, while concurrently executed operations may be seen in different orders.

Causal relationships arise when one operation depends on another. If process A writes to a variable and process B reads that value before writing to the same variable, B's write is causally dependent on A's. Causal consistency ensures that all processes see these dependent operations in order.

Concurrent operations—those where neither depends on the other—need not be ordered consistently. Two processes writing to different variables can do so in any order without affecting correctness. Causal consistency captures exactly this distinction, enabling more concurrency than sequential consistency.

Implementing causal consistency requires tracking dependency information. Vector clocks and version vectors are common techniques. Each operation carries metadata describing its causal history, allowing nodes to order operations correctly. This tracking adds complexity and overhead but enables higher performance than fully sequential systems.

## PRAM and Read-Your-Writes Consistency

PRAM (Pipelined Random Access Memory) consistency, also called FIFO consistency, requires that writes from a single source are seen by all processes in the order they were issued. Writes from different sources may be seen in different orders.

PRAM consistency is the weakest consistency model that provides meaningful guarantees for many applications. It ensures that a process's own writes are visible in order, which is essential for basic correctness. A process that writes a value and immediately reads it will see its own write.

Read-your-writes consistency is a specific instance of PRAM consistency that guarantees a process will always see its own previous writes. This property is essential for interactive applications where users expect to see their own updates immediately.

Most eventually consistent systems provide read-your-writes consistency as a baseline. Even if other processes see delayed writes, the writing process sees its writes immediately. This guarantee simplifies application logic considerably.

## Monotonic Reads and Writes

Monotonic reads guarantees that if a process reads a value V, any subsequent reads will return V or a more recent value. This prevents a process from seeing values go backwards in time—a frustrating experience where data appears to unchange or revert.

Monotonic reads is particularly important for applications like social feeds where users expect their view to never go backwards. A user who sees a new post should never later see that post disappear from their feed.

Monotonic writes guarantees that writes from a single process are executed in the order they were issued. This property ensures that a sequence of updates from one client is applied correctly, even if the writes are routed to different replicas.

These monotonicity properties are often implemented using version vectors or timestamps. A client tracks the version it has seen and requests only newer versions from servers. Systems like Dynamo and Cassandra provide these guarantees through careful client library design.

## Client-Side Guarantees and Session Guarantees

The consistency models discussed so far describe system-wide guarantees. However, applications often operate within a session—a sequence of operations from a single client to a possibly changing set of replicas. Session guarantees describe what the system provides within a session.

Session guarantees include read-your-writes, monotonic reads, and monotonic writes, all of which can be implemented on top of eventually consistent storage. The key insight is that consistency guarantees can be provided at the session level even when the underlying storage is eventually consistent.

Implementing session guarantees typically requires client-side tracking. The client maintains information about its recent writes (including version numbers or vector clocks) and includes this information in read requests. Servers can then ensure they provide values that meet the monotonicity requirements.

Session guarantees can be extended across multiple sessions through session tokens. If a client reconnects after a temporary disconnection, it can present its session token and receive continuity guarantees. This approach is used in systems like Dynamo to provide stronger guarantees to clients willing to track session state.

## CRDTs: Conflict-Free Replicated Data Types

CRDTs provide a mathematical framework for building eventually consistent systems that can resolve conflicts automatically, without requiring coordination. By designing data structures with commutative operations, CRDTs ensure that all replicas converge to the same state regardless of the order in which updates are applied.

The key insight behind CRDTs is that some operations commute—changing their order does not affect the final result. For example, incrementing a counter commutes with other increments (the final value is the same regardless of order). By limiting ourselves to such operations, we can guarantee convergence without coordination.

Two families of CRDTs exist: CmRDTs (Commutative Replicated Data Types) and CvRDTs (Convergent Replicated Data Types). CmRDTs specify operations that must be propagated and applied; the operations are designed to commute. CvRDTs specify state that must be merged using a commutative, associative merge function.

Common CRDT implementations include:

- G-Counter: Grow-only counter that only increments
- PN-Counter: Positive-negative counter supporting both increments and decrements
- LWW-Register: Last-writer-wins register taking timestamp as tiebreaker
- OR-Set: Observed-remove set supporting add and remove
- LWW-Map: Last-writer-wins map for key-value storage

CRDTs enable highly available systems with automatic conflict resolution. They are used in collaborative applications (Google Docs, Figma), distributed databases (Riak), and messaging systems (WhatsApp). The trade-off is that applications must be designed around CRDT-friendly operations.

The following example demonstrates a simple LWW-Register implementation:

```java
public class LWWRegister<T> {
    private T value;
    private long timestamp;
    private String nodeId;
    
    public LWWRegister<T> update(T newValue, long newTimestamp) {
        if (newTimestamp > timestamp || 
            (newTimestamp == timestamp && nodeId.compareTo(newValue) > 0)) {
            return new LWWRegister<>(newValue, newTimestamp, nodeId);
        }
        return this;
    }
    
    public LWWRegister<T> merge(LWWRegister<T> other) {
        return update(other.value, other.timestamp);
    }
    
    public T get() {
        return value;
    }
}
```

## Tunable Consistency

Many production systems provide tunable consistency, allowing operators to configure the trade-off between consistency and performance per operation or per collection.

MongoDB allows configuring read concern (local, majority, linearizable) and write concern (unacknowledged, acknowledged, journaled, majority). Operators can choose weak guarantees for better performance or strong guarantees for critical data.

Cassandra provides configurable consistency levels for reads and writes. A write to N nodes with quorum read guarantees strong consistency; writing to one node with default read provides eventual consistency.

Azure Cosmos DB offers multiple consistency models in a hierarchy from strong to eventual, with five well-defined levels: strong, bounded staleness, session, consistent prefix, and eventual. Applications can choose the appropriate level for each operation.

This tunability enables systems to match application requirements. Critical financial transactions can use strong consistency; high-volume analytics can use eventual consistency—all within the same database.

## Choosing a Consistency Model

Selecting the appropriate consistency model requires analyzing application requirements, failure characteristics, and performance targets. The following guidance helps architects make informed decisions.

For applications requiring strong correctness guarantees—financial transactions, inventory management, reservation systems—linearizable consistency is typically necessary. The performance cost is acceptable given the correctness requirements. Systems like Spanner, etcd, or CockroachDB provide these guarantees.

For applications that can tolerate temporary inconsistency—social media feeds, analytics dashboards, caching layers—eventual consistency provides excellent performance and availability. Applications must be designed to handle stale data gracefully.

For collaborative applications—document editing, shared workspaces—CRDTs provide conflict-free collaboration without requiring coordination. The constraint that operations must commute limits the design space but simplifies implementation.

For most applications, a hybrid approach works best. Core business data that requires strong guarantees uses linearizable storage. Supporting data like user preferences, session state, or analytics can use eventually consistent storage. The key is understanding which data requires which guarantees.

## Conclusion

Consistency models define the fundamental trade-offs in distributed systems. From strong consistency through ACID guarantees to weak consistency with CRDTs, each model occupies a point in the design space between coordination cost and application complexity.

Modern distributed systems increasingly embrace hybrid approaches, providing strong consistency for critical operations while offering weaker consistency for scalability. Understanding the guarantees and costs of each model enables architects to make informed decisions that meet application requirements.

As distributed systems continue to evolve, the trend toward flexible, tunable consistency will likely accelerate. Applications will increasingly be able to choose the appropriate consistency level for each operation, balancing correctness, performance, and availability to meet specific business requirements.