# Distributed Transactions: Deep-Dive into Two-Phase Commit, Three-Phase Commit, and SAGA Patterns

## Introduction

Distributed transactions represent one of the most challenging aspects of building resilient, scalable enterprise systems. When data spans multiple databases, microservices, or geographic regions, the traditional ACID guarantees that we rely upon in monolithic applications become significantly more complex to achieve. This comprehensive article explores the theoretical foundations, practical implementations, and production-grade considerations for distributed transaction management in enterprise environments.

The fundamental problem stems from the CAP theorem, which dictates that a distributed system can only guarantee two of three properties: Consistency, Availability, and Partition tolerance. In partitioned environments, developers must make careful trade-offs between consistency and availability. Understanding distributed transaction patterns is essential for architects and senior engineers building systems that must maintain data integrity across multiple failure domains.

## The Fundamental Challenge of Distributed Atomicity

In a single-node database system, atomicity is achieved through transaction logs and database locks. The database ensures that either all operations within a transaction succeed or none do, maintaining the all-or-nothing guarantee through careful management of disk writes and in-memory structures. When we distribute these operations across multiple independent systems, we lose the benefit of shared memory and shared disk, making atomicity far more difficult to achieve.

Consider a financial transfer operation where we must debit one account and credit another, but these accounts reside in different database partitions. The naive approach of performing each operation independently fails because we cannot guarantee that both will succeed. If the credit operation fails after the debit has committed, we have created money out of thin air. If the debit succeeds but the credit fails, money has disappeared from the system. Neither outcome is acceptable in a production financial system.

The challenge becomes even more pronounced when we consider network failures, node crashes, and the various failure modes that can occur in distributed systems. A node may crash after receiving a request but before processing it, after processing but before responding, or after responding but before the response reaches the caller. Each of these scenarios requires careful handling to maintain consistency.

## Two-Phase Commit Protocol

The Two-Phase Commit (2PC) protocol represents the classic approach to achieving atomicity in distributed systems. First proposed by Jim Gray in 1981, 2PC provides a mechanism for coordinating multiple participants to either commit or abort a distributed transaction. The protocol derives its name from its two distinct phases: a voting phase and a decision phase.

### Phase One: Voting Phase

During the voting phase, the coordinator initiates the commit process by sending a prepare request to all participants in the transaction. Each participant then performs the necessary operations to prepare the transaction, which typically involves acquiring all required locks and writing prepare records to persistent storage. This preparation step is critical because it ensures that each participant can commit its portion of the transaction regardless of what happens next.

When a participant receives a prepare request, it must decide whether it can commit the transaction. If the participant can guarantee that it can commit (all locks acquired, all logs written), it responds with a vote commit message. If any constraint violation, resource shortage, or other condition prevents commitment, the participant responds with a vote abort message. The participant must hold all locks and resources until it receives the final decision from the coordinator.

The prepare phase is where many production systems encounter challenges. Participants must be prepared to handle coordinator failures during this phase. If a participant votes to commit but never receives the final decision, it enters a blocking state where it must hold locks and resources indefinitely. This blocking behavior can cause significant performance degradation and resource exhaustion in production environments with many long-running transactions.

### Phase Two: Decision Phase

After collecting votes from all participants, the coordinator makes a final decision. If all participants vote to commit, the coordinator sends a global commit message to all participants. If any participant votes to abort, or if the coordinator encounters a timeout, it sends a global abort message. Upon receiving the decision, each participant either commits or aborts its local transaction and releases all held resources.

The decision phase introduces additional failure scenarios. If the coordinator fails after sending commit messages to some participants but before sending to others, some participants will commit while others abort, resulting in inconsistency. Similarly, if a participant fails after committing but before acknowledging the commit to the coordinator, the coordinator may believe the transaction aborted while the participant has already committed.

### Production Considerations for Two-Phase Commit

Implementing 2PC in production requires careful attention to timeout values, resource management, and failure recovery. The coordinator must implement robust timeout mechanisms to detect participant failures and make appropriate decisions. However, setting timeouts too aggressively can cause unnecessary aborts due to transient network slowdowns, while setting them too conservatively can prolong blocking states during actual failures.

Most enterprise database systems implement 2PC with additional optimizations. Oracle's Distributed Oracle Database uses a variant called Distributed Lock Management (DLM) that integrates with Oracle's Transaction Manager. IBM's DB2 uses the Two-Phase Commit Protocol extensively in its DataPropagator product for replicating data across mainframe systems. Microsoft SQL Server's Linked Servers feature uses 2PC for distributed queries, with the DTC (Distributed Transaction Coordinator) managing the protocol.

The following Java pseudocode demonstrates a production-grade 2PC implementation using a coordinator pattern:

```java
public class TwoPhaseCommitCoordinator {
    private final TransactionLog transactionLog;
    private final Map<String, Participant> participants;
    private final Duration voteTimeout;
    private final Duration decisionTimeout;
    
    public CompletableFuture<TransactionOutcome> executeTwoPhaseCommit(
            Transaction transaction) {
        
        // Phase 1: Voting
        List<CompletableFuture<Vote>> votes = participants.values().stream()
            .map(p -> p.prepare(transaction))
            .collect(Collectors.toList());
        
        // Wait for all votes with timeout
        CompletableFuture.allOf(votes.toArray(new CompletableFuture[0]))
            .orTimeout(voteTimeout.toMillis(), TimeUnit.MILLISECONDS)
            .exceptionally(ex -> Vote.ABORT);
        
        boolean allCommit = votes.stream()
            .allMatch(v -> v == Vote.COMMIT);
        
        // Phase 2: Decision
        TransactionDecision decision = allCommit 
            ? TransactionDecision.COMMIT 
            : TransactionDecision.ABORT;
        
        // Persist decision to log before sending
        transactionLog.write(new TransactionLogEntry(
            transaction.getId(), decision));
        
        // Send decision to all participants
        List<CompletableFuture<Void>> acknowledgments = participants.values()
            .stream()
            .map(p -> p.decide(decision))
            .collect(Collectors.toList());
        
        return CompletableFuture.allOf(
            acknowledgments.toArray(new CompletableFuture[0]))
            .thenApply(v -> TransactionOutcome.SUCCESS)
            .exceptionally(ex -> TransactionOutcome.FAILED);
    }
}
```

## Three-Phase Commit Protocol

The Three-Phase Commit (3PC) protocol was developed to address the blocking problem inherent in Two-Phase Commit. Named for its three phases (canCommit, preCommit, doCommit), 3PC eliminates the blocking state by introducing an additional phase that ensures all participants know the final decision before any participant proceeds with commit.

### Protocol Phases

In the canCommit phase, the coordinator polls participants to determine whether they can prepare for commit without actually acquiring locks or writing prepare records. This lightweight voting phase allows the coordinator to quickly determine if the transaction can proceed. If any participant responds that it cannot prepare, the coordinator aborts the transaction immediately.

The preCommit phase is analogous to the prepare phase in 2PC. The coordinator sends preCommit messages to all participants, and each participant that can proceed writes a prepare record and acquires necessary locks, then responds with an acknowledgment. This phase ensures that all participants have physically prepared to commit before the coordinator makes the final decision.

The doCommit phase is the actual commit phase. Because all participants have already prepared and acknowledged the preCommit, they can proceed with commit without waiting for any other participant. This eliminates the blocking problem because even if a participant fails during doCommit, it will either recover and commit automatically or be forced to abort by the coordinator after a timeout.

### When Three-Phase Commit Is Appropriate

Three-Phase Commit is appropriate in environments where blocking can have severe consequences. However, the protocol introduces additional network round-trips and assumes that the network does not partition for extended periods. In wide-area network scenarios with high latency, the additional phase can significantly impact performance.

The protocol also assumes that at most one participant can fail during the doCommit phase. If multiple participants fail simultaneously, the protocol may not be able to guarantee consistency. Additionally, 3PC cannot handle network partitions that persist longer than the timeout values, making it unsuitable for certain distributed scenarios.

Most production systems favor 2PC over 3PC due to the additional complexity and latency of 3PC. However, 3PC concepts appear in various forms in modern distributed systems, particularly in consensus algorithms that build upon the foundational ideas.

## SAGA Pattern

The SAGA pattern offers an alternative approach to distributed transactions that sacrifices immediate consistency for availability and performance. Instead of attempting to keep all participants in sync simultaneously, SAGA allows each participant to make local commitments and uses compensating transactions to handle failures.

### Choreography versus Orchestration

SAGA patterns can be implemented in two primary ways: choreographed and orchestrated. In a choreographed SAGA, participants communicate directly with each other through events. When one participant completes its work, it publishes an event that triggers the next participant's work. If a participant fails, it publishes a compensating event that triggers rollback of previously completed work.

In an orchestrated SAGA, a central coordinator manages the sequence of participants. The coordinator sends commands to each participant and handles success and failure responses. When a participant fails, the coordinator orchestrates the compensating transactions. Orchestrated SAGA provides better observability and easier debugging but introduces a single point of failure that must be addressed through coordinator replication.

### Designing Compensating Transactions

The key to successful SAGA implementation is designing proper compensating transactions. Each forward action must have a corresponding compensation that undoes the effects of the forward action. The compensation must be idempotent (safe to execute multiple times), commutative (order-independent), and associative (grouping doesn't matter).

Consider an e-commerce order processing SAGA. The forward flow might include: reserve inventory (compensation: release inventory), charge payment (compensation: refund payment), create shipment (compensation: cancel shipment), and send confirmation (compensation: send cancellation email). Each compensation must handle partial failures gracefully—if the payment refund fails, the system must retry or escalate to manual intervention.

### SAGA Implementation Patterns

Production SAGA implementations typically include several key components. A saga log maintains a record of all saga executions, enabling recovery after coordinator failures. Each saga execution has a unique identifier that links all related messages and events. Compensation handlers are registered for each step and invoked in reverse order when failures occur.

The following example demonstrates an orchestrated SAGA implementation for order processing:

```java
public class OrderProcessingSaga {
    private final SagaLog sagaLog;
    private final InventoryService inventoryService;
    private final PaymentService paymentService;
    private final ShippingService shippingService;
    
    public SagaResult processOrder(Order order) {
        String sagaId = UUID.randomUUID().toString();
        sagaLog.start(sagaId, order);
        
        try {
            // Step 1: Reserve inventory
            InventoryReservation reservation = inventoryService.reserve(
                order.getItems(), sagaId);
            sagaLog.logStep(sagaId, "reserveInventory", reservation);
            
            // Step 2: Process payment
            PaymentCharge charge = paymentService.charge(
                order.getPaymentInfo(), order.getTotal(), sagaId);
            sagaLog.logStep(sagaId, "chargePayment", charge);
            
            // Step 3: Create shipment
            Shipment shipment = shippingService.create(
                order.getShippingAddress(), reservation, sagaId);
            sagaLog.logStep(sagaId, "createShipment", shipment);
            
            sagaLog.complete(sagaId);
            return SagaResult.success(shipment);
            
        } catch (Exception e) {
            return compensate(sagaId, e);
        }
    }
    
    private SagaResult compensate(String sagaId, Exception cause) {
        List<SagaStep> completedSteps = sagaLog.getCompletedSteps(sagaId);
        
        for (int i = completedSteps.size() - 1; i >= 0; i--) {
            SagaStep step = completedSteps.get(i);
            try {
                compensateStep(step);
                sagaLog.logCompensation(sagaId, step);
            } catch (Exception compException) {
                sagaLog.logCompensationFailed(sagaId, step, compException);
                return SagaResult.manualInterventionRequired(
                    sagaId, cause, compException);
            }
        }
        
        sagaLog.abort(sagaId);
        return SagaResult.rolledBack(sagaId, cause);
    }
}
```

## Comparison and Selection Criteria

Choosing between distributed transaction patterns requires careful analysis of system requirements, failure characteristics, and performance constraints. The following analysis provides guidance for selecting the appropriate pattern based on business requirements.

Two-Phase Commit provides strong consistency guarantees but introduces blocking and performance overhead. It is appropriate when immediate consistency is required and system availability can tolerate temporary unavailability during coordinator failures. Financial systems, inventory management, and reservation systems often benefit from 2PC's guarantees.

SAGA pattern provides eventual consistency with better performance and availability characteristics. It is appropriate when the business can tolerate temporary inconsistencies and when compensation logic can be implemented reliably. E-commerce order processing, notification systems, and analytics pipelines frequently use SAGA patterns.

Three-Phase Commit is rarely implemented in production systems due to its complexity and specific failure assumptions. However, understanding 3PC concepts helps when evaluating distributed databases and consensus systems that incorporate similar ideas.

## Conclusion

Distributed transaction management remains one of the most complex challenges in enterprise system design. The choice between Two-Phase Commit, SAGA, and other patterns involves fundamental trade-offs between consistency, availability, and performance. Senior engineers must carefully analyze business requirements, failure scenarios, and performance targets when designing distributed transaction systems.

Modern production systems increasingly favor eventually consistent approaches like SAGA, accepting temporary inconsistencies in exchange for better availability and performance. However, strong consistency remains essential for certain business domains where data integrity cannot be compromised. Understanding the theoretical foundations and practical implementation details of each pattern enables architects to make informed decisions that balance competing requirements effectively.