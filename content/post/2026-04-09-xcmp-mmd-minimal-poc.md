---
author: Ron
catalog: true
date: 2026-04-09
tags:
- BlockChain
- Polkadot
- XCMP
title: Polkadot XCMP MMD — Minimal POC
---

Forum background: [XCMP Design Discussion (Polkadot)](https://forum.polkadot.network/t/xcmp-design-discussion/7328).

---

## Problem and motivation

**HRMP** stores message payloads on the relay chain, which is expensive (storage + execution).

**XCMP (MMD approach)** replaces that with:

- payloads kept off the relay chain
- messages proven by **nested Merkle proofs** anchored to relay commitments

---

## How MMD XCMP replaces HRMP (conceptually)

HRMP:

- relay is a **payload mailbox** (`HrmpChannelContents`)
- receiver reads relay state proofs + prunes via watermarks

MMD XCMP:

- relay is a **commitment anchor** (no payload storage)
- receiver accepts **payload + proof bundle**, verifies it, then executes the XCM.

Minimal POC semantics:

- **unordered**: messages can arrive in any order
- **best-effort**: if nobody submits the proof bundle, nothing happens
- **no pruning**: of message stores / MMRs
- **no receipts/acks**
- **no Incentive mechanism for relayers**
- **replay protection required**: prevent executing the same proven message repeatedly

---

## POC Spec (high level)

This is the minimal spec that the implementation follows.

### POC design revamp (vs forum MMD)

- The forum sketch uses **one `XcmpMessageMMR` per channel** plus an **`XcmpChannelTree`** over those roots.
  This POC drops that split: a **single global append-only `XcmpOutboxMmr`** commits all outbound pages, and
  the parachain header digest carries only **`XcmpOutboxMmrRoot`**.
- The outbox is **one accumulator across all blocks**: leaves only append, and `mmr_leaf_index` is globally
  monotonic. We do **not** use a per-block Merkle snapshot as the primary commitment.

### Must-haves (even for minimal POC)

- **Replay protection:** `seen((source, mmr_leaf_index))`.
- **Hard bounds**:
  - max messages per call: `MaxMessagesPerCall = 4`
  - max payload size: `MaxPayloadBytes = 256 * 1024` (256 KiB)
  - relay MMR proof: exactly 1 leaf, max proof items `MaxRelayMmrProofItems = 128` (raise for devnets if you expect **deep** historical leaves; proof width grows with relay progress)
  - para-heads Merkle proof: max proof items `MaxParaHeadsProofItems = 32`
  - outbox MMR proof: exactly 1 leaf, max proof items `MaxOutboxMmrProofItems = 64`
  - implied max total bytes per call: `MaxTotalCallBytes ≈ 768 * 1024` (768 KiB) via the above bounds
- **Deterministic source commitment**
  - During **source** block execution, the outbox must **`deposit_log`** the digest so that **`XcmpOutboxMmrRoot`** is part of the **final parachain header** for that block. The relay’s **`ParaHeadsRoot`** is computed over **`SCALE((para_id, head_bytes))`** where **`head_bytes`** is exactly that encoded header—so the commitment is binding once the source block is included on the relay. PVF / validators must agree on the same header bytes (same digest list, same root).

### Current Beefy-(MMR) implementation on the relay chain that we rely on

Relay chain runtimes configure `pallet_beefy_mmr::LeafExtra = H256` and set:

- `LeafExtra = ParaHeadsRoot`
- `ParaHeadsRootProvider` computes Merkle root over `sorted_para_heads()`
  - `(para_id_u32, head_bytes)` sorted by id

**Important**: this defines the proof format and hashing. Our verifier must match it exactly.

### “Matryoshka” proof stack (minimal POC variant, simplified)

#### Smallest → largest commitments

1. **`XcmpOutboxMmr`** (source chain, global, append-only): each drained outbound page becomes one leaf
   containing `(dest_para_id, payload_hash)`, where `payload_hash = Keccak256(page_bytes)`. The global
   `mmr_leaf_index` is the only monotonic identifier (“nonce”).
2. **Source parachain header**: the header digest commits the rolling **`XcmpOutboxMmrRoot`** (bagged MMR root after the block’s appends; empty blocks carry-forward the last root).
3. **`ParaHeadsRoot`** (relay snapshot): a chosen relay MMR leaf exposes `leaf_extra = ParaHeadsRoot`, a
   binary Merkle root over `SCALE((para_id_u32, head_bytes))` entries (sorted by `para_id`). The relevant
   entry includes the source `head_bytes` whose digest contains the `xmmd` item carrying `XcmpOutboxMmrRoot`.
4. **Relay MMR root** (implicit root anchor): read from the destination block’s **relay parent** header
   digest. It commits to the chosen relay MMR leaf; because the relay MMR appends, historical leaves still
   verify under later roots.

#### Destination verifies nested proofs

1. From the destination block’s relay parent (Appendix A), extract the relay **MMR root**. This root is
   cumulative (includes all earlier relay leaves).
2. Verify a single relay MMR leaf proof at **`relay_mmr_leaf_index`** against that root, then decode the
   leaf to obtain `leaf_extra = ParaHeadsRoot`.
3. Verify **`binary_merkle_tree::MerkleProof`** for `SCALE((source, head_bytes))` against `ParaHeadsRoot`.
4. Decode **`head_bytes`** as the source parachain **header**, then read **`DigestItem::PreRuntime(*b"xmmd", …)`** → **`XcmpOutboxMmrRoot`**.
5. Verify **outbox MMR leaf proof** (single leaf) for leaf **`(dest, payload_hash)`** at **`mmr_leaf_index`** against **`XcmpOutboxMmrRoot`**.
6. Check **`Keccak256(payload) == payload_hash`** (relayer supplies bytes).
7. Replay protection: reject if **`seen((source, mmr_leaf_index))`**.
8. POC execution: emit event / enqueue bytes / XCM execution

---

## POC Implementation (low level)

#### Commitments, identifiers, and proof types (concrete)

- **Outbox accumulator**: one global append-only `XcmpOutboxMmr`
- **OutboxLeaf**: `(dest: u32, payload_hash: H256)` (SCALE-encoded)
- **Outbox leaf index / “nonce”**: `mmr_leaf_index: u64` (global monotonic; not stored in the leaf)
- **Header digest (source header)**: `DigestItem::PreRuntime(*b"xmmd", SCALE((version, XcmpOutboxMmrRoot)))`
- **Empty blocks**: carry-forward last root (repeat previous `XcmpOutboxMmrRoot`)

- `SourceParaId`, `DestParaId`: `u32` (SCALE where needed)
- **`relay_mmr_leaf_index`**: relay `pallet_mmr` leaf index whose relay MMR leaf carries the `ParaHeadsRoot`
  you prove against (must match the sole leaf index in the relay `LeafProof`)
- **Routing**: implicit in `(dest, payload_hash)`; no channel tree

- **Hashing**:
  - `payload_hash = Keccak256(payload_bytes)` where `payload_bytes` is the exact `Vec<u8>` drained from `XcmpQueue::take_outbound_messages`
  - Para-heads Merkle must match relay: `H = Keccak256`, leaf `SCALE((para_id_u32, head_bytes))`, relay sorts by `para_id`, per `binary_merkle_tree` (`substrate/utils/binary-merkle-tree`)

- **Proof types**:
  - **Para-heads proof**: `binary_merkle_tree::MerkleProof<H256, Vec<u8>>` where `leaf = SCALE((source_u32, head_bytes))`
  - **Relay MMR proof (single leaf)**: `sp_mmr_primitives::EncodableOpaqueLeaf` + `sp_mmr_primitives::LeafProof<H256>` (exactly 1 leaf; proof’s sole `leaf_indices[0]` must equal `relay_mmr_leaf_index`)
  - **Outbox MMR proof (single leaf)**: `sp_mmr_primitives::EncodableOpaqueLeaf` + `sp_mmr_primitives::LeafProof<H256>` (exactly 1 leaf; proof’s sole `leaf_indices[0]` must equal `mmr_leaf_index`), verified statelessly against `XcmpOutboxMmrRoot`

- **`MessageWithProof`**: `{ source, dest, mmr_leaf_index, relay_mmr_leaf_index, payload, relay_mmr_proof, para_heads_proof, outbox_mmr_proof }`

### Source: XcmpMmdOutbox Pallet 

#### How to integrate with the current XcmpQueue

- Hook point: `ParachainSystem::on_finalize` drains `OutboundXcmpMessageSource::take_outbound_messages`
  (typically `XcmpQueue`), yielding `Vec<(ParaId, Vec<u8>)>`.
- Runtime wiring: set `type OutboundXcmpMessageSource = XcmpMmdOutbox` so the wrapper can observe the drained
  bytes.
- Wrapper behavior (per `(dest, data)`):
  - `payload_hash = Keccak256(data)`
  - append one outbox leaf `(dest, payload_hash)` to the global MMR (this defines `mmr_leaf_index`)
- Finalize: compute bagged `XcmpOutboxMmrRoot` and `deposit_log(DigestItem::PreRuntime(*b"xmmd", ...))`.

#### One-block dataflow

```text
ParachainSystem::on_finalize
  └─ take_outbound_messages (wrapper)
       ├─ XcmpQueue::take_outbound_messages
       └─ for each (dest, data): note_outbound → push leaf on XcmpOutboxMmr

XcmpMmdOutbox::on_finalize   // after ParachainSystem
  └─ XcmpOutboxMmrRoot = bag_peaks (current MMR root)
  └─ deposit_log(PreRuntime, (version, XcmpOutboxMmrRoot))
```

**Critical:** in **`construct_runtime!`**, place **`XcmpMmdOutbox` after `ParachainSystem`**.

### Destination: XcmpMmdInbox Pallet 

#### Submission model: permissionless extrinsic

Anyone can be a relayer. The destination chain exposes an extrinsic, e.g.:

- `submit_xcmp_mmd(messages: Vec<MessageWithProof>)`

No collator/inherent pipeline changes are required for the minimal POC.

#### What the extrinsic must carry (per message)

- `source: u32`, `dest: u32`
- `mmr_leaf_index: u64` (outbox MMR leaf index / nonce)
- `relay_mmr_leaf_index: u64` (relay MMR leaf index that supplies `leaf_extra = ParaHeadsRoot`)
- `payload: Vec<u8>` (bounded)
- `relay_mmr_proof` (single leaf at `relay_mmr_leaf_index`, verified against the implicit relay-root; Appendix A)
- `para_heads_proof` (leaf `SCALE((source_u32, head_bytes))`)
- `outbox_mmr_proof` (single leaf at `mmr_leaf_index`, under `XcmpOutboxMmrRoot` from `head_bytes`)

#### Off-chain relayer tool

- For each source message:
  - fetch `payload` bytes (see below) and compute `payload_hash`
  - choose `relay_mmr_leaf_index` whose `ParaHeadsRoot` contains the exact `(source, head_bytes)`
  - generate proofs: `relay_mmr_proof`, `para_heads_proof`, `outbox_mmr_proof`
  - submit `MessageWithProof` to destination

#### Where the relayer gets the full `payload` (XCM bytes)

**On-chain we only commit `payload_hash`.** The **verifier** checks that submitted **`Vec<u8>`** matches that hash; it does **not** reconstruct the message from the chain.

The **relayer** obtains the **original page bytes** from a **data-availability path**, for example:

- **Source parachain archival state (recommended for POC):** fetch the drained outbound bytes from the
  **source parachain’s state at the committed block** (archive node / historical state RPC). In today’s
  Cumulus flow, `ParachainSystem::on_finalize` drains `take_outbound_messages` and stores outbound HRMP
  messages for PVF; an archive node can read that storage (e.g. `HrmpOutboundMessages` in
  `cumulus/pallets/parachain-system`) at the source block hash and recover the exact `Vec<u8>` page bytes
  that were hashed into `payload_hash`.
**Cryptographic binding is on-chain; bytes are a data-availability problem.** This POC assumes some off-chain publication/custody path exists for the committed bytes.

#### How the relayer generates the outbox MMR proof

To submit `outbox_mmr_proof` for a historical `mmr_leaf_index`, the relayer needs a way to obtain a
single-leaf `sp_mmr_primitives::LeafProof<H256>` against the `XcmpOutboxMmrRoot` committed in the source
header.

**Preferred (POC-friendly):** expose a **runtime API** that returns the outbox leaf + proof at a given block:

- Input: `{ at: source_block_hash, mmr_leaf_index }`
- Output: `{ outbox_leaf: (dest, payload_hash), outbox_leaf_proof: LeafProof<H256> }`

The relayer calls this against a full/archive source node (historical state), then submits that proof
bundle to the destination.

**Storage implication:** the source chain must retain enough MMR node/peak data to build proofs for the
desired history range. For a minimal POC this can be **no pruning**; a production design can use a bounded
window (older proofs become unavailable unless material is retained elsewhere).

#### Verification (canonical algorithm)
1. Obtain relay parent header from validation data, extract relay MMR root from the BEEFY digest (Appendix A).
2. Verify the submitted **relay MMR leaf proof** (single leaf) **at `relay_mmr_leaf_index`** against that root; decode the proven leaf and read `leaf_extra = ParaHeadsRoot` (**snapshot for that relay leaf**, not “whatever the tip says today”).
3. Verify the submitted **para-heads Merkle proof** against that `ParaHeadsRoot` and decode its leaf as `SCALE((source_u32, head_bytes))`.
4. Decode `head_bytes` as the source parachain header → extract **`XcmpOutboxMmrRoot`** digest item (`engine_id = *b"xmmd"`).
5. Verify the submitted **outbox MMR proof** (single leaf) for outbox leaf `(dest, payload_hash)` at `mmr_leaf_index` against `XcmpOutboxMmrRoot`.
6. Check `Keccak256(payload) == payload_hash`.
7. Replay protection: `seen((source, mmr_leaf_index))` must be false; then mark it seen.
8. **Post-verify:** destination execution — feed those bytes into the destination runtime’s **normal inbound XCMP dispatch path** with the correct **sender origin** (`ParaId::from(source)` / `Sibling(ParaId)`), typically by invoking the configured **`XcmpMessageHandler`** (in Cumulus templates this is usually **`XcmpQueue`**) using whatever **internal hook / helper** your runtime exposes for “append sibling message bytes”.


#### Minimal verifier guards

- Reject unless `dest == SelfParaId`.
- Reject unless `relay_leaf_proof.leaf_indices[0] == relay_mmr_leaf_index` and
  `outbox_leaf_proof.leaf_indices[0] == mmr_leaf_index` (single-leaf POC).
- After decoding the proven outbox leaf, `ensure!(leaf.dest == dest && leaf.payload_hash == Keccak256(payload))`.

## Appendix A: Relay MMR root (where it lives)

Relay runtimes set `pallet_mmr::Config::OnNewRoot = pallet_beefy_mmr::DepositBeefyDigest`, which deposits:

`DigestItem::Consensus(BEEFY_ENGINE_ID, ConsensusLog::MmrRoot(root).encode())`

Extract with:

`sp_consensus_beefy::mmr::find_mmr_root_digest(header) -> Option<MmrRootHash>`

Destination (via `set_validation_data` relay context): decode **relay parent** header (**implicit MMR-root anchor**) → `find_mmr_root_digest` → verify supplied **relay MMR leaf proof** (POC: exactly **one** leaf) **at `relay_mmr_leaf_index`** → decode that leaf’s `leaf_extra = ParaHeadsRoot` for **that** relay height.

**Historical leaves:** the digest’s `root` is the MMR **after** the relay parent block’s execution; it includes **all** prior relay leaves. Proving an **earlier** leaf under that root is the normal MMR membership story — no extra relay hash in calldata, and **no** requirement that the relayer land “immediately after” source inclusion. You still need an **archive-quality** relay view (or pruned-but-deep-enough state) to **build** wide proofs for very old leaves.

---

## Appendix B: Where HRMP flows today

- `cumulus/pallets/parachain-system/src/lib.rs` — `on_finalize` drains `take_outbound_messages`, stores `HrmpOutboundMessages`.
- `cumulus/pallets/parachain-system/src/validate_block/implementation.rs` — PVF reads `HrmpOutboundMessages` → `ValidationResult.horizontal_messages`.
- `polkadot/runtime/parachains/src/inclusion/mod.rs` — `hrmp::prune_hrmp`, `queue_outbound_hrmp`.


