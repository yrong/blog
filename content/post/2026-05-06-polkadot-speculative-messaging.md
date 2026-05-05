---
author: Ron
date: 2026-05-06T15:00:00Z
tags:
- polkadot
- xcm
- cross-chain
- merkle-tree
title: Polkadot Speculative Messaging — Design Deep Dive
---

Speculative Messaging is the companion design to Low-Latency Parachains v2. Its goal: replace HRMP (Horizontal Relay Message Passing) with a faster, more scalable cross-chain communication mechanism built on MMR accumulators, on-chain commitments, and off-chain message delivery.

<!--more-->

## Why Replace HRMP?

Three pain points with current HRMP:

1. **High latency**: messages must flow through relay chain storage and routing, taking 12–18 seconds under ideal conditions
2. **Poor scalability**: all messages pass through relay chain state; every validator processes message routing
3. **Incompatible with Low-Latency v2**: LLv2 recommends building on older finalized relay parents (for fork immunity). Using HRMP with old relay parents would worsen latency dramatically

## Core Idea

**Messages don't live on the relay chain. They flow off-chain. The relay chain does exactly one thing: verify that hash commitments match.**

### Step 1: Message Accumulators (MMR)

Each chain maintains a hierarchical Merkle Mountain Range accumulating all outgoing messages:

```
Top-Level Root (Merkle tree over per-destination MMR roots)
├── Chain B: MMR_B Root → [hash(msg1), hash(msg2), ...]
├── Chain C: MMR_C Root → [hash(msg1), ...]
└── Chain D: MMR_D Root → [hash(msg1), ...]
```

The hierarchical structure means a receiver only proves their subtree — proof size is `O(log D + log m)` where D = destinations and m = messages to that receiver.

### Step 2: On-Chain Commitments

- Sender emits a **provides commitment** in each block: the top-level MMR root hash
- Receiver emits a **requires commitment**: `{source: ChainId, expected_root: the provides root it was built against}`

### Step 3: Off-Chain Message Delivery

Collators exchange messages directly over the existing libp2p network layer, via `MessageBatch`:

```
MessageBatch {
    source: Chain A,
    provides_root: 0xabc...            ← top-level Merkle root
    subtree_root: 0xdef...             ← Chain A→B subtree MMR root
    subtree_inclusion_proof: [...]      ← proves subtree_root is in provides_root
    messages: [msg1, msg2, msg3]
}
```

The receiving collator verifies in two layers:

1. **Top-level proof**: `subtree_root` is indeed within `provides_root` (standard Merkle proof, O(log D) hashes)
2. **Subtree internal verification**: extend the local subtree MMR (only stores hashes of messages sent to this chain) with new messages, compute the new root, and compare with `subtree_root`

Chain B only maintains a lightweight `SourceState` for Chain A — the `last_processed` position and a subtree MMR containing only Chain A→B messages. No full MMR tree needed.

### Step 4: Relay Chain Enforcement

At inclusion time, the relay chain performs two-phase commitment matching in `enact_candidate`.

---

## The Core Flow: Execute First, Verify Later

This is the "speculative" part — XCM messages execute during block building, not after relay chain verification:

```
t=0: Chain A collator produces block → emits provides commitment → sends messages off-chain to Chain B
t=1: Chain B collator receives messages → executes XCM during block building → emits requires commitment
t=2+: Both blocks submitted to relay chain → relay chain does commitment matching
```

The collator bears the speculative risk: if Chain A's block never makes it on-chain, or its provides root changes, Chain B's block cannot be included — it becomes an orphan whose state changes never happened. This is what makes Low-Latency v2's acknowledgement rules essential: the collator made an economic commitment when acknowledging the block, and gets slashed if the speculation fails.

## HRMP vs Speculative Messaging

| | HRMP | Speculative Messaging |
|---|---|---|
| When messages execute | After relay chain confirms message exists | During block building |
| Latency | 12–18s | Parachain block time |
| Who bears risk | User (must wait) | Collator (slashed on failure) |
| Relay chain's role | Store + route messages | Hash matching only |

---

## Relay Chain Verification (Code-Level Walkthrough)

### When: enact_candidate

In the current codebase, `inclusion/mod.rs` `enact_candidate` runs when a backed candidate is included in a relay chain block. The existing order:

```rust
fn enact_candidate(...) {
    // 1. Reward backing validators
    T::RewardValidators::reward_backing(...);
    // 2. Handle code upgrades
    // 3. Process upward messages (UMP)
    Self::receive_upward_messages(...);
    // 4. HRMP: prune incoming
    hrmp::prune_hrmp(para_id, hrmp_watermark);
    // 5. HRMP: queue outgoing
    hrmp::queue_outbound_hrmp(para_id, horizontal_messages);
    // 6. Emit CandidateIncluded event
}
```

Speculative messaging adds a commitment-matching step alongside the existing HRMP processing.

### Storage: Minimal

The relay chain only needs one lightweight storage map:

```rust
/// Latest provides root per parachain
#[pallet::storage]
pub type ProvidesRoots<T: Config> = StorageMap<_, Twox64Concat, ParaId, Hash>;
```

Compare this to HRMP's full message queues (`HrmpChannels`, `HrmpChannelDigests`, etc.) — orders of magnitude less state.

### Two-Phase Matching

Candidates within a single relay chain block are processed in `ParaId` order. Chain B (ParaId=1000) might be processed before Chain A (ParaId=2000) even though B depends on A. The fix: **Phase 0 pre-collects all provides** before any processing begins.

```rust
pub(crate) fn process_candidates<GV>(...) {
    // ═══════ Phase 0: collect all provides in this block ═══════
    let mut provides_this_block: BTreeMap<ParaId, Hash> = BTreeMap::new();
    for (para_id, backed_list) in candidates.iter() {
        for (candidate, _) in backed_list {
            if let Some(provides) = &candidate.commitments.provides {
                provides_this_block.insert(*para_id, provides.root);
            }
        }
    }

    // ═══ Phase 1: verify requires per candidate, then enact ═══
    for (para_id, backed_list) in candidates.iter() {
        for (candidate, core_index) in backed_list {
            // ──── Speculative messaging commitment matching ────
            for req in &candidate.commitments.requires {
                // Path 1: provides from another candidate in THIS block
                let ok1 = provides_this_block
                    .get(&req.source)
                    .map_or(false, |r| r == &req.expected_root);
                // Path 2: provides from a PREVIOUS block (persisted state)
                let ok2 = ProvidesRoots::<T>::get(&req.source)
                    .map_or(false, |r| r == req.expected_root);
                ensure!(ok1 || ok2, "requires not satisfied");
            }

            enact_candidate(...);

            // After successful inclusion, persist provides for future blocks
            if let Some(provides) = &candidate.commitments.provides {
                ProvidesRoots::<T>::insert(*para_id, provides.root);
            }
        }
    }
}
```

The lookup logic:

```
Chain B's requires (expected_root = 0xabc, source = ChainA)

┌─────────────────────────────┐
│ Path 1: provides_this_block │   ← in-memory map (Phase 0 pre-collected)
│ { ChainA => 0xabc }         │     handles intra-block dependencies
│ ✅ Match!                   │     regardless of processing order
└─────────────────────────────┘
         ↓ if Path 1 fails
┌─────────────────────────────┐
│ Path 2: ProvidesRoots       │   ← relay chain persisted state
│ ChainA => 0xabc             │     written when ChainA was included
│ ✅ Match!                   │     in a previous block
└─────────────────────────────┘
         ↓ if Path 2 also fails
┌─────────────────────────────┐
│ ❌ Candidate invalid        │
│ requires unsatisfied → dropped │
└─────────────────────────────┘
```

### Mismatch: Only the Failing Candidate Is Dropped

```
Relay chain block N processes two candidates:

Candidate A (provides = 0xabc)    Candidate B (requires ChainA = 0xdef)
  ↓                                  ↓
  No requires                     requires lookup fails
  ✅ Included                     ❌ Dropped

Result: Chain A lands on-chain. Chain B's block becomes an orphan.
```

Chain A is unaffected — its provides commitment is self-contained and valid regardless of whether anyone references it.

---

## Late Block Proofs

When a receiving block's required root is older than the current provides root (the sender has advanced several blocks), the POV carries an MMR extension proof demonstrating the old requires is still valid under the new provides. Proof size: typically ~770 bytes, worst case ~1.6 KB.

---

## Super Chains

When one collator set operates multiple chains, they can form a super chain — producing all member-chain blocks atomically in one slot. Intra-block bidirectional messaging becomes possible because the collator has simultaneous access to all chains' state.

---

## Trust Domains

| Message source | Confirmed by | Latency | Use case |
|---------------|-------------|---------|----------|
| Same super chain | Co-authored block | <1 block | Tightly coupled shards |
| Same trust domain | Source chain collator ACK | ~1–2 blocks | Fast cross-chain DeFi |
| Cross-domain | Source chain relay inclusion | ~2–3 relay blocks | Untrusted / cross-domain |
| HRMP (legacy) | Relay chain only | ~3+ relay blocks | Deprecated |

---

## Summary

Speculative Messaging, combined with Low-Latency v2, reduces cross-chain messaging latency from ~18 seconds to parachain block times (~100ms–6s), while preserving decentralization and horizontal scaling. The core insight: demote the relay chain from a message store-and-forward layer to a lightweight hash-commitment verifier.
