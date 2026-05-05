---
author: Ron
date: 2026-05-06T15:00:00Z
tags:
- polkadot
- xcm
- implementation
- design
title: Speculative Messaging — POC Implementation Design
---

# Speculative Messaging — Minimal POC Implementation Design

Based on [speculative-messaging-design.md](speculative-messaging-design.md).

This covers the "happy path" without Late Block Proofs. Assumes: sender and receiver
blocks are both included in the same or adjacent relay chain blocks, so provides
roots are available at matching time.

---

## 1. Data Flow Overview

```
 Chain A (Sender)                         Chain B (Receiver)
 ════════════════                         ══════════════════
 
 1. Build block                           4. Receive MessageBatch off-chain
    - Execute txs → produce XCM msgs          - Verify subtree inclusion proof
    - Append hashes to per-dest MMR           - Verify message continuity via local subtree MMR
    - Compute top-level Merkle root           
                                             5. Build block
 2. Emit ProvidesCommitment { root }            - Execute received XCM messages
    in CandidateCommitments                     - Emit RequiresCommitment { source, expected_root }
                                                 in CandidateCommitments
 3. Send MessageBatch off-chain
    to Chain B's collators                 ═══════════════════════════════════════
                                           
                                           Relay Chain
                                           ═══════════════════════════════════════
                                           6. Inclusion: enact_candidate
                                              - For each candidate, verify all requires
                                                can be matched to a provides
                                              - Looking in: this block's candidates + persisted state
                                              - Update ProvidesRoots storage
```

---

## 2. Primitives (polkadot-primitives)

### 2.1 New types in `v9/mod.rs` (or new `v10` module if breaking)

```rust
/// A commitment that a parachain provides a set of outbound messages.
/// The root is the top-level Merkle root over all per-destination MMR roots.
#[derive(Clone, Encode, Decode, PartialEq, RuntimeDebug, TypeInfo)]
pub struct ProvidesCommitment {
    /// Top-level Merkle root over all per-destination MMR roots.
    /// This commits to ALL outbound messages from this block.
    pub root: Hash,
}

/// A commitment that a parachain requires messages from a source parachain.
#[derive(Clone, Encode, Decode, PartialEq, RuntimeDebug, TypeInfo)]
pub struct RequiresCommitment {
    /// The source parachain whose provides root we expect.
    pub source: ParaId,
    /// The provides root we built against (from the source chain's block).
    pub expected_root: Hash,
}

/// A message batch sent off-chain between collators.
#[derive(Clone, Encode, Decode, Debug)]
pub struct MessageBatch {
    /// Source parachain
    pub source: ParaId,
    /// Source block hash that produced these messages
    pub source_block: Hash,
    /// The top-level provides root for this block
    pub provides_root: Hash,
    /// The per-destination MMR root for the receiver
    pub subtree_root: Hash,
    /// Merkle proof that subtree_root is in provides_root
    pub subtree_inclusion_proof: Vec<Hash>,
    /// The actual messages with their positions in the sender's subtree MMR
    pub messages: Vec<OutgoingMessage>,
}

#[derive(Clone, Encode, Decode, Debug)]
pub struct OutgoingMessage {
    pub position: u64,
    pub payload: Vec<u8>,
}
```

### 2.2 Extend `CandidateCommitments`

```rust
pub struct CandidateCommitments<N = BlockNumber> {
    pub upward_messages: UpwardMessages,
    pub horizontal_messages: HorizontalMessages,  // HRMP (legacy, eventually removed)
    pub new_validation_code: Option<ValidationCode>,
    pub head_data: HeadData,
    pub processed_downward_messages: u32,
    pub hrmp_watermark: N,

    // ── New speculative messaging fields ──
    /// Provides commitment: the top-level Merkle root of all outbound messages.
    /// `None` if this block sends no messages.
    pub provides: Option<ProvidesCommitment>,
    /// Requires commitments: the provides roots this block's received messages
    /// were built against. Empty if this block receives no messages.
    pub requires: Vec<RequiresCommitment>,
}
```

---

## 3. Relay Chain Runtime Changes

### 3.1 New Storage

In `polkadot/runtime/parachains/src/speculative_messaging.rs` (new module):

```rust
use frame_support::pallet_prelude::*;
use polkadot_primitives::{Hash, Id as ParaId};

/// Latest provides root per parachain.
/// Updated each time a candidate with a provides commitment is included.
#[pallet::storage]
pub type ProvidesRoots<T: Config> = StorageMap<_, Twox64Concat, ParaId, Hash>;
```

### 3.2 Validation in `inclusion/mod.rs`

Add to `process_candidates()` — before the main processing loop:

```rust
pub(crate) fn process_candidates<GV>(
    allowed_relay_parents: &AllowedRelayParentsTracker<T::Hash, BlockNumberFor<T>>,
    candidates: &BTreeMap<ParaId, Vec<(BackedCandidate<T::Hash>, CoreIndex)>>,
    group_validators: GV,
    ...
) -> Result<..., Error> {
    // ══════════════════════════════════════════════════
    // Step 0: Pre-collect all provides from this block.
    // Needed because candidates are processed in ParaId
    // order, but a receiver (lower ParaId) may depend
    // on a sender (higher ParaId).
    // ══════════════════════════════════════════════════
    let mut provides_in_block: BTreeMap<ParaId, Hash> = BTreeMap::new();
    for (para_id, backed_list) in candidates.iter() {
        for (candidate, _) in backed_list {
            if let Some(ref p) = candidate.commitments.provides {
                provides_in_block.insert(*para_id, p.root);
            }
        }
    }

    // ... existing sanction checks, etc. ...

    for (para_id, backed_list) in candidates.iter() {
        for (candidate, core_index) in backed_list {
            // ════════════════════════════════════════
            // NEW: Verify speculative messaging requires
            // ════════════════════════════════════════
            for req in &candidate.commitments.requires {
                // Path 1: provides from another candidate in THIS block
                let path1 = provides_in_block
                    .get(&req.source)
                    .map_or(false, |root| root == &req.expected_root);

                // Path 2: provides from a PREVIOUS block (persisted)
                let path2 = SpeculativeMessaging::<T>::provides_root(&req.source)
                    .map_or(false, |root| root == req.expected_root);

                ensure!(path1 || path2, Error::<T>::UnsatisfiedRequires);
            }

            // Existing per-candidate processing
            Self::enact_candidate(
                relay_parent_number,
                candidate.candidate.receipt.clone(),
                candidate.candidate.backers.clone(),
                ...
            );

            // ════════════════════════════════════════
            // NEW: Update persisted provides root
            // ════════════════════════════════════════
            if let Some(ref p) = candidate.commitments.provides {
                SpeculativeMessaging::<T>::update_provides_root(
                    *para_id,
                    p.root,
                );
            }

            // ... existing per-candidate event emission ...
        }
    }
}
```

### 3.3 SpeculativeMessaging pallet fragment

```rust
// In speculative_messaging.rs — a new module registered in lib.rs

impl<T: Config> Pallet<T> {
    /// Read the latest provides root for a parachain.
    pub fn provides_root(para_id: &ParaId) -> Option<Hash> {
        ProvidesRoots::<T>::get(para_id)
    }

    /// Update the provides root after a candidate is included.
    /// Always overwrites — only the latest root matters for matching.
    pub fn update_provides_root(para_id: ParaId, root: Hash) {
        ProvidesRoots::<T>::insert(para_id, root);
    }
}
```

### 3.4 New Error variant

In the inclusion or paras module error enum:

```rust
/// A requires commitment could not be matched to any provides.
UnsatisfiedRequires,
```

---

## 4. Parachain Runtime Changes

Each parachain needs an MMR module. This is per-runtime, not per-relay-chain.

### 4.1 Outgoing Message MMR (Sender Side)

```rust
// In the parachain runtime — a new pallet or utility module

use sp_mmr_primitives::MerkleMountainRange;
use sp_core::H256;

/// Per-destination MMRs for outgoing messages.
/// Key: destination ParaId → Value: MMR instance
#[pallet::storage]
pub type OutgoingMMRs<T: Config> = StorageMap<
    _,
    Twox64Concat,
    ParaId,
    MMRState,
>;

#[derive(Clone, Encode, Decode, TypeInfo)]
pub struct MMRState {
    /// Number of leaves appended so far
    pub leaf_count: u64,
    /// Latest MMR root
    pub root: H256,
    /// Stored nodes (for proof generation)
    pub nodes: BTreeMap<u64, H256>,
}

impl Pallet<T: Config> {
    /// Append a message to the per-destination MMR.
    /// Called during block execution when an XCM message is produced.
    pub fn append_outgoing_message(
        dest: ParaId,
        payload: &[u8],
    ) -> u64 {
        let hash = sp_io::hashing::keccak_256(payload);
        let mut state = OutgoingMMRs::<T>::get(&dest).unwrap_or_default();
        let position = state.leaf_count;

        // MMR append: insert new leaf, update peaks, compute new root
        state.insert_leaf(hash);
        state.leaf_count = position + 1;

        OutgoingMMRs::<T>::insert(&dest, state);

        // Emit event for off-chain relaying
        Self::deposit_event(Event::MessageAppended {
            dest,
            position,
            payload_hash: H256::from(hash),
        });

        position
    }

    /// Compute the top-level Merkle root over all per-destination MMR roots.
    /// Called at the end of block building to produce the provides commitment.
    pub fn compute_provides_root() -> H256 {
        let mut roots: Vec<(ParaId, H256)> = OutgoingMMRs::<T>::iter()
            .map(|(dest, state)| (dest, state.root))
            .collect();
        roots.sort_by_key(|(id, _)| *id);

        let leaves: Vec<H256> = roots.into_iter().map(|(_, root)| root).collect();
        compute_merkle_root(&leaves)
    }
}
```

### 4.2 Incoming Message Verification (Receiver Side)

```rust
/// Per-source tracking for incoming messages.
#[pallet::storage]
pub type IncomingState<T: Config> = StorageMap<
    _,
    Twox64Concat,
    ParaId,  // source chain
    SourceState,
>;

#[derive(Clone, Encode, Decode, TypeInfo, Default)]
pub struct SourceState {
    /// Last processed message position in the source's subtree MMR
    pub last_processed: u64,
    /// The source's subtree root we last synced to
    pub last_seen_subtree_root: H256,
    /// Local copy of the subtree MMR (only nodes affecting OUR messages)
    pub local_subtree: MMRState,
}

/// Message batch verification — called by the collator before block building.
/// NOT part of the runtime state transition; runs in the collator's off-chain logic.
pub fn verify_message_batch(batch: &MessageBatch) -> Result<Vec<OutgoingMessage>, Error> {
    // 1. Verify subtree_inclusion_proof
    let leaf = (batch.source, batch.subtree_root).encode();
    let leaf_hash = sp_io::hashing::keccak_256(&leaf);
    let computed_top_root = verify_merkle_proof(
        batch.provides_root,
        &batch.subtree_inclusion_proof,
        leaf_hash,
    )?;

    // 2. Verify message continuity against local state
    let mut local_state = IncomingState::<T>::get(&batch.source)
        .unwrap_or_default();

    for msg in &batch.messages {
        ensure!(
            msg.position == local_state.last_processed + 1,
            "Non-consecutive message"
        );
        let msg_hash = sp_io::hashing::keccak_256(&msg.payload);
        local_state.local_subtree.insert_leaf(msg_hash);
        local_state.last_processed = msg.position;
    }

    // 3. Verify computed subtree root matches batch
    ensure!(
        local_state.local_subtree.root == batch.subtree_root,
        "Subtree root mismatch"
    );

    // 4. Persist updated state
    local_state.last_seen_subtree_root = batch.subtree_root;
    IncomingState::<T>::insert(&batch.source, local_state);

    Ok(batch.messages.clone())
}
```

### 4.3 Producing Commitments (end of block)

After block execution, the parachain runtime emits commitments:

```rust
fn on_finalize(n: BlockNumber) {
    // Compute provides commitment (top-level Merkle root)
    if OutgoingMMRs::<T>::iter().count() > 0 {
        let provides_root = Self::compute_provides_root();
        ProvidesCommitment::put(ProvidesCommitment { root: provides_root });
    }

    // Compute requires commitments (one per source we received from)
    let requires: Vec<RequiresCommitment> = IncomingState::<T>::iter()
        .map(|(source, state)| RequiresCommitment {
            source,
            expected_root: state.last_seen_subtree_root,  // or top-level root
        })
        .collect();
    RequiresCommitments::put(requires);
}
```

These get read by the collator and placed into the `CandidateCommitments` for the candidate.

---

## 5. Candidate Commitments Plumbing

### 5.1 PVF / Validation

The PVF validation function (`validate_block`) needs to verify that the provides/requires in `CandidateCommitments` match the block's actual execution results. This means:

1. Execute the block
2. Read the provides/requires storage values that the block produced
3. Assert they match what's in the `CandidateCommitments`

This is similar to how `head_data` is currently validated — the block produces it, and the candidate commitments must carry the same value.

### 5.2 Collator-Side

The collator:

1. Executes the block → gets provides/requires from storage
2. Constructs `CandidateCommitments` with these values
3. Submits the candidate to backers

```rust
impl Collator {
    async fn build_candidate(&self, block: Block) -> CandidateCommitments {
        let commitments = CandidateCommitments {
            upward_messages: block.upward_messages(),
            horizontal_messages: block.horizontal_messages(),
            new_validation_code: block.new_code(),
            head_data: block.head_data(),
            processed_downward_messages: block.processed_dmp(),
            hrmp_watermark: block.hrmp_watermark(),
            // ── New fields ──
            provides: block.provides_commitment(),
            requires: block.requires_commitments(),
        };
        commitments
    }
}
```

---

## 6. Off-Chain Networking (Collator Protocol)

### 6.1 New Request/Response Protocol

```rust
/// Collator protocol extension for speculative messaging
pub struct SpeculativeMessagingProtocol;

impl RequestResponseProtocol for SpeculativeMessagingProtocol {
    type Request = MessageBatchRequest;
    type Response = MessageBatchResponse;
}

#[derive(Encode, Decode, Debug)]
pub struct MessageBatchRequest {
    /// Request messages from this source parachain
    pub source: ParaId,
    /// Starting from this block
    pub from_block: Hash,
    /// Up to this block (inclusive)
    pub to_block: Option<Hash>,
}

#[derive(Encode, Decode, Debug)]
pub struct MessageBatchResponse {
    pub batches: Vec<MessageBatch>,
}
```

### 6.2 Collator Integration

```rust
impl Collator {
    /// Before building a block: fetch pending messages from trusted peers.
    async fn fetch_pending_messages(&self) -> Vec<(ParaId, MessageBatch)> {
        let mut messages = Vec::new();

        // For each registered source chain in the trust domain:
        for source in self.trust_domain_sources() {
            // 1. Determine the last seen block from this source
            let last_known = self.incoming_state.last_known_block(source);

            // 2. Request new messages since that block
            let response = self.network.request(
                SpeculativeMessagingProtocol,
                MessageBatchRequest {
                    source,
                    from_block: last_known,
                    to_block: None, // all available
                },
            ).await?;

            // 3. Verify each batch
            for batch in response.batches {
                verify_message_batch(&batch)?;
                messages.push((source, batch));
            }
        }

        messages
    }

    /// During block building: execute verified XCM messages.
    async fn build_block(&self) -> Block {
        let pending = self.fetch_pending_messages().await;

        let mut block = Block::new();
        for (source, batch) in pending {
            for msg in batch.messages {
                block.execute_xcm(source, msg.payload);
            }
        }

        block.finalize();  // produces provides/requires commitments
        block
    }
}
```

---

## 7. Summary of File Changes

| File | Change |
|------|--------|
| `polkadot/primitives/src/v9/mod.rs` | Add `ProvidesCommitment`, `RequiresCommitment`, `MessageBatch`, extend `CandidateCommitments` |
| `polkadot/runtime/parachains/src/speculative_messaging.rs` | **New file**: `ProvidesRoots` storage + read/update helpers |
| `polkadot/runtime/parachains/src/inclusion/mod.rs` | Phase 0 pre-collect provides, requires validation before enact, update provides after enact |
| `polkadot/runtime/parachains/src/lib.rs` | Register speculative_messaging module |
| `polkadot/runtime/parachains/src/paras/mod.rs` | Add `UnsatisfiedRequires` error variant |
| Parachain runtime: new MMR pallet (e.g., `pallet-outgoing-mmr`) | Per-destination MMR append + top-level Merkle root computation |
| Parachain runtime: `pallet-incoming-queue` | Per-source state tracking, message batch verification |
| Collator: new request/response protocol | `MessageBatchRequest` / `MessageBatchResponse` |
| Collator: block building pipeline | Fetch pending messages before block build, execute XCM in block |
| PVF validation | Assert provides/requires in commitments match block execution output |

## 8. What's NOT In This POC

- **Late Block Proofs**: requires MMR extension proofs, PVF transformation of commitments
- **Trust domains beyond "all collators trust each other"**: no cross-domain fallback
- **Super chains**: no intra-block bidirectional messaging
- **Acknowledgement rules for message dependencies**: low-latency v2 ACK extension rules
- **Cycle prevention**: handled by the simple rule "don't process messages from blocks that don't exist yet"
