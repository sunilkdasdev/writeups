# Consensus Algorithms: Deep-Dive into Paxos and Raft

## Introduction

Consensus algorithms represent the cornerstone of fault-tolerant distributed systems. They enable a collection of unreliable nodes to agree on a single value, despite network failures, node crashes, and malicious behavior. Understanding consensus algorithms is essential for anyone designing or operating distributed databases, coordination services, or replicated state machines.

The consensus problem, formally defined by Leslie Lamport in 1989, requires that several properties be satisfied: agreement (all non-faulty nodes decide on the same value), validity (the decided value must have been proposed by some node), termination (every non-faulty node eventually decides), and integrity (no node decides twice). These simple-sounding requirements become remarkably complex to achieve in the presence of failures.

This article provides an in-depth exploration of Paxos, the foundational consensus algorithm, and Raft, its more accessible successor. We examine the theoretical foundations, implementation details, and production considerations that enable these algorithms to power critical infrastructure across the industry.

## The Paxos Algorithm

Paxos, first described by Leslie Lamport in 1998, has earned a reputation as both profoundly influential and notoriously difficult to understand. The algorithm achieves consensus in an asynchronous network model with crash failures, proving that consensus is solvable even under minimal assumptions about timing and reliability.

### The Basic Paxos Protocol

The basic Paxos algorithm proceeds in two phases, each involving multiple rounds of communication between proposers, acceptors, and learners. The algorithm ensures safety (never agreeing on an incorrect value) while making reasonable progress assumptions.

In phase one, a proposer selects a proposal number (n) that is higher than any proposal number it has used previously. It then sends a prepare request to a majority of acceptors. When an acceptor receives a prepare request with proposal number n, it responds with a promise not to accept any proposal with a number less than n, and if it has previously accepted any proposal, it includes the highest-numbered accepted proposal with its response.

In phase two, if the proposer receives responses from a majority of acceptors, it can proceed to the accept phase. The proposer selects a value—the highest-numbered proposal among the responses if any exists, otherwise any value it chooses. It sends an accept request with proposal number n and value v to a majority of acceptors. When an acceptor receives an accept request, it accepts the proposal if it has not promised to reject a higher-numbered proposal.

The algorithm ensures that once a value has been chosen, any subsequent proposal that receives acceptance must have the same value. This invariance holds because any acceptor that accepts a proposal must have previously promised not to accept proposals with lower numbers, and any later proposer must discover the previously accepted value through its phase one requests.

### Multi-Paxos and the Journal Pattern

Basic Paxos achieves consensus for a single value. Multi-Paxos extends this to a sequence of values by running multiple instances of the basic protocol, creating a replicated log. Each log entry is identified by an index, and the protocol ensures that all nodes agree on the entries in the same order.

The journal pattern, used in production systems like Apache BookKeeper and Google's Spanner, treats the consensus algorithm as a log that can be read and written. Clients append entries to the log, and the consensus algorithm ensures that all replicas agree on the sequence. Applications can read from any replica as long as they read a consistent prefix of the log.

Multi-Paxos optimizes the common case by electing a distinguished proposer (the leader). While a leader is active, it can skip phase one and directly run phase two for successive values. This optimization reduces the number of round-trips from two to one in the common case, significantly improving throughput. However, the algorithm must handle leader election and leaderless operation when the leader fails.

### Implementing Paxos in Production

Production Paxos implementations must address numerous practical concerns that the formal algorithm omits. These include handling disk failures, managing proposal numbers across restarts, detecting and recovering from leader failures, and batching multiple proposals to improve throughput.

The following implementation sketch demonstrates key aspects of a Multi-Paxos proposer:

```java
public class PaxosProposer {
    private final String nodeId;
    private final int majority;
    private final Map<Integer, Promise> promises;
    private long currentProposalNumber;
    private int currentBallot;
    private boolean isLeader;
    private volatile long lastLeaderHeartbeat;
    
    public ProposalResult propose(byte[] value) {
        if (!isLeader) {
            // In leaderless mode, must run full two-phase
            return proposeInLeaderlessMode(value);
        }
        
        // Leader can skip to accept phase
        currentProposalNumber = nextBallotNumber();
        AcceptRequest request = new AcceptRequest(
            currentBallot, 
            nextLogIndex(), 
            value
        );
        
        List<AcceptResponse> responses = sendAcceptRequests(request);
        
        if (countAccepted(responses) >= majority) {
            // Value chosen, notify learners
            notifyLearners(currentBallot, nextLogIndex(), value);
            return ProposalResult.success(nextLogIndex());
        }
        
        // Need to re-propose with higher ballot
        return proposeInLeaderlessMode(value);
    }
    
    private long nextBallotNumber() {
        return (currentBallot * NODE_COUNT) + nodeId.hashCode();
    }
    
    public void handlePromise(Promise promise) {
        promises.put(promise.ballot(), promise);
        
        // If we have majority promises, become leader
        if (!isLeader && promises.size() >= majority) {
            isLeader = true;
            // Start sending heartbeats to maintain leadership
            startLeaderHeartbeat();
        }
    }
}
```

## The Raft Consensus Algorithm

Raft was designed in 2013 by Diego Ongaro and John Ousterhout as a more understandable alternative to Paxos. The algorithm achieves the same safety guarantees as Paxos while being significantly easier to reason about and implement. Raft has been adopted by numerous production systems, including etcd, Consul, and CockroachDB.

### Core Raft Concepts

Raft decomposes the consensus problem into three clearly defined subproblems: leader election, log replication, and safety. This decomposition simplifies reasoning about the algorithm and makes implementation more straightforward.

The algorithm maintains several key state variables across all nodes: currentTerm (the latest term the node has seen), votedFor (the candidateId that received the node's vote in the current term), and log (the array of log entries). The leader maintains additional state: nextIndex (the index of the next log entry to send to each follower) and matchIndex (the highest log entry known to be replicated on each follower).

Terms in Raft serve a similar purpose to proposal numbers in Paxos. They provide a total ordering of events and help nodes identify stale information. When nodes communicate, they exchange term numbers; if a node's term is lower than another's, it updates its term and steps down to follower.

### Leader Election

Raft uses a leader election mechanism that ensures at most one leader per term. All nodes start as followers. If a follower does not receive a valid leader heartbeat within the election timeout, it becomes a candidate, increments its term, and initiates an election.

The candidate votes for itself and sends RequestVote requests to all other nodes. If a candidate receives votes from a majority of nodes, it becomes leader and begins sending heartbeat messages to maintain leadership. If another leader is discovered (through a valid RequestVote or AppendEntries response), the candidate steps down and becomes a follower.

The election timeout is randomized to reduce the probability of split votes. When multiple followers timeout simultaneously, they may each become candidates and split the vote. The randomization ensures that typically one candidate's timeout will expire first, giving it time to collect majority votes before others start their elections.

The following code demonstrates the leader election logic:

```java
public class RaftNode {
    private final NodeState state;
    private final int nodeId;
    private final int electionTimeoutMs;
    private final Random random;
    private long currentTerm;
    private int votedFor;
    private int currentLeader;
    private long lastHeartbeat;
    private Timer electionTimer;
    
    public void startElection() {
        currentTerm++;
        state.set(State.CANDIDATE);
        votedFor = nodeId;
        
        // Request votes from all other nodes
        List<RequestVoteResponse> votes = new ArrayList<>();
        votes.add(new RequestVoteResponse(nodeId, currentTerm, true)); // vote for self
        
        for (Node peer : peers) {
            RequestVoteResponse response = peer.requestVote(
                new RequestVoteRequest(currentTerm, nodeId, 
                    getLastLogIndex(), getLastLogTerm()));
            votes.add(response);
        }
        
        // Check if we won the election
        long voteCount = votes.stream().filter(RequestVoteResponse::voteGranted).count();
        if (voteCount >= majority()) {
            becomeLeader();
        }
    }
    
    private void becomeLeader() {
        state.set(State.LEADER);
        currentLeader = nodeId;
        
        // Initialize nextIndex for each follower
        for (Node peer : peers) {
            peer.setNextIndex(getLastLogIndex() + 1);
        }
        
        // Send initial empty AppendEntries as heartbeat
        startHeartbeat();
    }
    
    public void handleAppendEntries(AppendEntriesRequest request) {
        if (request.term() > currentTerm) {
            currentTerm = request.term();
            state.set(State.FOLLOWER);
            votedFor = -1;
        }
        
        // Reset election timer on valid leader communication
        if (isValidLeader(request)) {
            lastHeartbeat = System.currentTimeMillis();
            currentLeader = request.leaderId();
        }
    }
}
```

### Log Replication

Once a leader is elected, it accepts client commands and replicates them to followers through the AppendEntries RPC. When a client sends a command to the leader, the leader appends it to its log and sends AppendEntries requests to all followers in parallel.

Each AppendEntries request includes the leader's term, the previous log index and term, the entries to append, and the leader's commit index. When a follower receives the request, it verifies that the previous log entry matches (ensuring consistency with the leader's log), appends any new entries, and responds with its current log index.

The leader tracks the replication status of each follower through matchIndex. When an entry is replicated to a majority of followers, the leader commits that entry and applies it to its state machine. The leader then informs followers of the commit index through subsequent AppendEntries requests, allowing them to apply committed entries as well.

Log replication handles several failure scenarios. If a follower crashes and recovers, the leader will retry AppendEntries requests until the follower recovers and syncs its log. If the leader has a log entry that a follower does not have, the leader decrements nextIndex and retries with the previous entry. This process continues until the follower's log converges with the leader's.

### Safety and Log Compaction

Raft's safety property ensures that once a log entry is applied to the state machine, it will never be overwritten by a different entry with the same index. This property is maintained through several mechanisms: leaders never overwrite entries in their log, candidates can only win elections if their log is at least as up-to-date as the majority, and committed entries are never rolled back.

The "at least as up-to-date" comparison ensures that a candidate's log contains all committed entries. A candidate includes its last log index and term in RequestVote requests. Other nodes vote for the candidate only if the candidate's log is at least as up-to-date as their own—meaning either the terms match with higher index, or the terms match and the index is equal.

In production systems, the log grows unboundedly and must be compacted. Raft supports snapshotting, where the current state machine state is written to persistent storage, and the log is truncated up to the snapshot point. Nodes can then discard the truncated portion of the log while maintaining the ability to participate in consensus.

## Paxos versus Raft: Comparative Analysis

Both Paxos and Raft achieve the same safety guarantees in similar failure models, but they differ significantly in understandability, implementation complexity, and performance characteristics.

Paxos provides a more general solution to consensus that can be optimized for various use cases. The basic algorithm is elegant but understanding how to extend it to practical systems requires significant expertise. Multi-Paxos with leader election, log replication, and snapshotting adds considerable complexity beyond the basic algorithm.

Raft's primary advantage is its understandability. By decomposing the problem and imposing structure (leader first), Raft makes it easier to reason about the algorithm and implement it correctly. The clear leader semantics also simplify debugging and operational management.

From a performance perspective, both algorithms achieve similar throughput when properly implemented. Multi-Paxos and Raft both benefit from a stable leader and can process thousands of commands per second in production workloads. The choice between them often comes down to implementation maturity and team familiarity rather than raw performance.

## Production Considerations

Implementing consensus algorithms in production requires addressing concerns beyond the core algorithm. These include persistent state management, network partition handling, membership changes, and monitoring.

Persistent state including the current term, voted-for candidate, and log entries must survive node restarts. Most implementations use a combination of a write-ahead log for the consensus log and periodic snapshots for compaction. The storage subsystem must be reliable, as data loss or corruption can cause permanent inconsistency.

Network partitions present particular challenges for consensus algorithms. When a partition isolates the leader from a majority, the minority partition cannot elect a new leader (insufficient votes). The majority partition continues operating normally. When the partition heals, the minority must catch up with the majority's log, potentially discarding uncommitted entries.

Membership changes in Raft require careful handling to maintain safety. The joint consensus approach allows the cluster to transition between configurations atomically, but implementations must ensure that configuration changes are processed sequentially and that voting is calculated correctly during transitions.

The following monitoring metrics are essential for production consensus systems:

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| commit-latency | Time from proposal to commit | > 100ms p99 |
| leader-elections | Frequency of leadership changes | > 1 per hour |
| replication-lag | Follower distance from leader | > 1000 entries |
| term-changes | Frequency of term increments | > 10 per minute |
| dropped-proposals | Proposals rejected due to leadership changes | > 1% of total |

## Conclusion

Consensus algorithms provide the foundation for building reliable distributed systems. Paxos, despite its complexity, remains influential and is embodied in production systems through careful implementation and optimization. Raft offers a more accessible path to consensus while maintaining the same safety guarantees.

Understanding these algorithms enables architects and engineers to make informed decisions about distributed system design. Whether implementing a custom solution or configuring an existing system like etcd or CockroachDB, the principles of consensus underlie all fault-tolerant distributed data stores.