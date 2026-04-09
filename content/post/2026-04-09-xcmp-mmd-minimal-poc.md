---
author: Ron
catalog: true
date: 2026-04-09
tags:
- BlockChain
- Polkadot
- XCMP
title: Polkadot XCMP MMD — Minimal POC (merged)
aliases:
  - /post/2026-04-09-xcmp-mmd-1-pager/
  - /post/2026-04-09-xcmp-mmd-poc2-option1-spec/
  - /post/2026-04-09-xcmp-mmd-implementer-checklist/
  - /post/2026-04-09-xcmp-mmd-source-outbox-xcm-integration/
---

Consolidated from earlier split posts (**1‑pager**, **POC2 spec**, **implementer checklist**, **source outbox**). Master copy lives in Obsidian: **Polkadot XCMP MMD — Minimal POC** (kept in sync with this article).

Forum background: [XCMP Design Discussion (Polkadot)](https://forum.polkadot.network/t/xcmp-design-discussion/7328).

**POC design revamp (vs forum MMD):** the forum sketch uses **one `XcmpMessageMMR` per channel** and an **`XcmpChannelTree`** over those MMR roots. For this **minimal POC** we **drop that split**: a **single append-only global `XcmpOutboxMmr`** on the source commits all outbound messages; the header digest carries **`XcmpOutboxMmrRoot`** only. Each leaf still names **`dest`** (and nonce + `payload_hash`), so there is no loss of routing identity—only a shorter proof path and less on-chain bookkeeping. A future scale-out version can shard back into per-channel MMRs + channel tree.

**Committed structure:** the outbox is a **global MMR**—**one accumulator across all blocks**, leaves only appended, **monotonic `mmr_leaf_index`** over the lifetime of the chain (until reset / migration). We **do not** use a per-block-only binary Merkle snapshot as the primary commitment; **`XcmpOutboxMmrRoot`** in each header is the **current bagged root** after that block’s appends (unchanged if the block appended no leaves, per your empty-block rule).

---

## 1) Problem and motivation

**HRMP** stores message payloads on the relay chain, which is expensive (storage + execution).

**XCMP (MMD approach)** replaces that with:

- payloads kept off the relay chain
- messages proven by **nested Merkle proofs** anchored to relay commitments

---

## 2) How MMD XCMP replaces HRMP (conceptually)

HRMP:

- relay is a **payload mailbox** (`HrmpChannelContents`)
- receiver reads relay state proofs + prunes via watermarks

MMD XCMP:

- relay is a **commitment anchor** (no payload storage)
- receiver accepts **payload + proof bundle**, verifies it, then executes the XCM.

Minimal POC semantics:

- **unordered**: messages can arrive in any order
- **best-effort**: if nobody submits the proof bundle, nothing happens
- **no delivery guarantee**: protocol does not ensure eventual delivery
- **no pruning**: source/relayers may keep messages indefinitely (POC accepts this)
- **replay protection required**: prevent executing the same proven message repeatedly

---

## 3) “Matryoshka” proof stack (minimal POC variant, simplified)

Smallest → largest commitments:

1. **`XcmpOutboxMmr`** (single global, append-only): every drained outbound page becomes one leaf. Leaf body includes **`dest_para_id`**, **`nonce`**, **`payload_hash`** (and a fixed layout/version). **No separate per-channel MMR and no `XcmpChannelTree`.**
2. **Source parachain header**: digest item commits **`XcmpOutboxMmrRoot`** (bagged MMR root after the block’s appends).
3. **Para-heads merkle root** (`ParaHeadsRoot`): binary merkle root over `SCALE((para_id_u32, head_bytes))`, sorted by `para_id`.
4. **Relay MMR root**: from relay parent header digest; verify relay **MMR leaf proof** → `leaf_extra = ParaHeadsRoot`.

**Option 1 (POC):** accept relay’s **`MAX_PARA_HEADS = 1024`** truncation when reproducing `ParaHeadsRoot`.

Destination verifies nested proofs:

1. Get relay **MMR root** from relay parent header digest (Appendix A).
2. Verify **MMR leaf proof** → obtain leaf → read `leaf_extra = ParaHeadsRoot`.
3. Verify **para-heads merkle proof** against `ParaHeadsRoot` → obtain `head_bytes` for `source`.
4. Decode **`head_bytes`** as the source parachain **header**, then read the agreed digest item → **`XcmpOutboxMmrRoot`**.
5. Verify **outbox MMR leaf proof** for leaf **`(dest, nonce, payload_hash)`** against **`XcmpOutboxMmrRoot`**.
6. Check **`hash(payload) == payload_hash`** (relayer supplies bytes).
7. Replay protection: reject if already seen.
8. POC execution: emit event / queue payload / XCM execution

---

## 4) Current relay implementation we rely on (already in place)

Westend/Rococo configure `pallet_beefy_mmr::LeafExtra = H256` and set:

- `LeafExtra = ParaHeadsRoot`
- `ParaHeadsRootProvider` computes merkle root over `sorted_para_heads()`:
  - `(para_id_u32, head_bytes)` sorted by id
  - truncated to `MAX_PARA_HEADS = 1024`

**Important**: this defines the proof format and hashing. Our verifier must match it exactly.

---

## 5) Minimal POC submission model: permissionless extrinsic

Anyone can be a relayer. The destination chain exposes an extrinsic, e.g.:

- `submit_xcmp_mmd(messages: Vec<MessageWithProof>)`

No collator/inherent pipeline changes are required for the minimal POC.

### What the extrinsic must carry (per message)

- **Anchor (which source commitment):** enough context to pin one relay snapshot and one source header, e.g. **`source: u32`**, relay parent or BEEFY anchor the verifier accepts, and the **para-heads leaf index** for `source` (or equivalent unambiguous pointer). Without this, the destination cannot know which `head_bytes` / which `XcmpOutboxMmrRoot` to verify against.
- `dest: u32`, `payload: Vec<u8>` (bounded)
- **Relay MMR:** proof bundle that yields `ParaHeadsRoot` for that anchor (bounded; Appendix A)
- **`para_heads_merkle_proof`** + the **`head_bytes`** for `(source)` that the proof claims (bounded)
- **`outbox_mmr_proof`**: MMR membership of the committed leaf under **`XcmpOutboxMmrRoot`** extracted from that header + **`mmr_leaf_index`** (bounded)

### Definitions (identifiers / hashing)

- `SourceParaId`, `DestParaId`: `u32` (SCALE where needed).
- **Routing** is implicit in each outbox leaf **`(dest, nonce, payload_hash)`**; no separate channel-tree id.
- **Para-heads merkle** must match relay: `H = Keccak256`, leaf `SCALE((para_id_u32, head_bytes))`, relay sorts by `para_id`, odd-count promotion per `binary_merkle_tree` (`substrate/utils/binary-merkle-tree`).

### Destination verification algorithm (per message)

1. Obtain relay MMR root; verify MMR leaf proof → `ParaHeadsRoot`.
2. Verify `SCALE((source, head_bytes))` membership in `ParaHeadsRoot`.
3. Decode header from `head_bytes` → extract **`XcmpOutboxMmrRoot`** digest item.
4. Verify **`outbox_mmr_proof`** for **`(dest, nonce, payload_hash)`** at **`mmr_leaf_index`**.
5. Check **`hash(payload) == payload_hash`**.
6. Replay protection per your rules.
7. Execute (POC): emit event (full XCM execution later).

---

## 6) Non-goals (explicit for POC)

- **Ordering** guarantees (protocol-level)
- **Delivery** guarantees / forced inclusion
- **Receipts/acks**
- **Pruning** of message stores / MMRs
- Incentive mechanism for relayers/collators
- Full “execute XCM” integration (POC can emit events first)

---

## 7) Must-haves (even for minimal POC)

- **Replay protection** (at least `seen(message_hash)` or `seen((source, dest, mmr_leaf_index))` / `seen((source, dest, nonce))` per your leaf rules)
- **Hard bounds**:
  - max messages per call
  - max payload size
  - max proof nodes / bytes per proof layer
  - max total bytes per call
- **Deterministic source commitment (C1):**
  - During **source** block execution, the outbox must **`deposit_log`** the digest so that **`XcmpOutboxMmrRoot`** is part of the **final parachain header** for that block. The relay’s **`ParaHeadsRoot`** is computed over **`SCALE((para_id, head_bytes))`** where **`head_bytes`** is exactly that encoded header—so the commitment is binding once the source block is included on the relay. PVF / validators must agree on the same header bytes (same digest list, same root).

---

## 8) Implementation touchpoints (high level)

### Source parachain

- Outbox pallet to build:
  - **one global `XcmpOutboxMmr`** (append-only; `mmr_lib` / `merkle-mountain-range` pattern)
  - **`XcmpOutboxMmrRoot`** after each block’s appends
- Runtime: header digest item (**C1**) = **`XcmpOutboxMmrRoot`** (+ version tag).

### Destination parachain

- Verifier pallet with a permissionless extrinsic:
  - verifies relay MMR leaf proof → `ParaHeadsRoot`
  - verifies para-heads proof → `head_bytes`
  - extracts **`XcmpOutboxMmrRoot`** from header digest
  - verifies **outbox MMR leaf proof** (+ payload hash check)
  - replay protection + bounded execution

### Off-chain relayer tool

- Watches:
  - source collator / RPC: **MMR leaf data**, **`mmr_leaf_index`**, and header bytes (or archive) for blocks that emitted messages
  - relay: header(s) / BEEFY data needed for **relay MMR root** and **`ParaHeadsRoot`** proofs
- Builds proof bundle (anchor + para-heads + outbox MMR) and submits extrinsic to destination.

---

## 9) Source outbox ↔ `pallet-xcm` (Option A): drain `XcmpQueue`, commit hash + nonce

**Decision (POC):** integrate the outbox by **draining the existing outbound queue** (no parallel `SendXcm` sink). Commit **`payload_hash` + `nonce/index`** in the global MMR and header digest (**C1**). A **permissionless relayer** later submits the **full payload bytes** on the destination, together with proofs that bind to the committed hash.

### How XCM already reaches the bytes you hash

1. **`pallet-xcm`** routes sends through the runtime **`XcmRouter`**, which ends in **`XcmpQueue`’s `SendXcm`**: messages are encoded and stored as outbound pages (`OutboundXcmpMessages`).
2. **`ParachainSystem`** `on_finalize` calls **`OutboundXcmpMessageSource::take_outbound_messages`**, which (in typical runtimes) is **`XcmpQueue::take_outbound_messages`**, yielding **`Vec<(ParaId, Vec<u8>)>`**. Those **`Vec<u8>`** values are the HRMP page bytes today — they are the stable object to hash for the commitment.

### Integration pattern (no `pallet-xcm` changes)

- Add an **outbox / commitment pallet** that maintains:
  - **global `XcmpOutboxMmr`** and a **nonce** (global per block-stream, or per-`dest`; document which),
  - leaves **`SCALE(OutboxLeaf { dest, nonce, payload_hash, ... })`**,
  - **`on_finalize`** (or inline after last append) to deposit **`XcmpOutboxMmrRoot`** in the header digest (**C1**).
- In the runtime, replace `type OutboundXcmpMessageSource = XcmpQueue` with a **thin wrapper** that:
  1. Delegates to **`XcmpQueue::take_outbound_messages(maximum_channels)`**.
  2. For each **`(recipient, data)`**: compute **`payload_hash = H(data)`** with one fixed hash (e.g. Keccak256 or Blake2-256); bump **nonce**; **push leaf** on **`XcmpOutboxMmr`**.
  3. Returns the **same** message list unchanged so existing **`ParachainSystem`** / HRMP bandwidth behavior stays intact for a **dual-run** POC.

**Hashing note:** commit the hash of the **exact** page bytes returned by **`take_outbound_messages`**. Do not assume equality with the **`XcmpMessageSent.message_hash`** from **`deliver`** (that is a Blake2 hash over the **versioned XCM** encoding path and may differ from the final page bytes).

### Destination and relayer

- **On-chain commitment:** the outbox leaf binds **`(dest_para_id, nonce, payload_hash)`** at **`mmr_leaf_index`** under **`XcmpOutboxMmrRoot`** for a specific **source header** (via **`ParaHeadsRoot`** / relay anchor).
- **Relayer submission:** provide **`payload`**, **`outbox_mmr_proof`**, **`hash(payload) == payload_hash`**, plus the relay / para-head proof chain.

### Where the relayer gets the full `payload` (XCM bytes)

**On-chain you only commit `payload_hash`.** The **verifier** checks that submitted **`Vec<u8>`** matches that hash; it does **not** reconstruct the message from the chain.

The **relayer** obtains the **original page bytes** from **off-chain / side observability**, for example:

- **Dual-run HRMP POC:** the relay still stores the payload in **HRMP** for that window; archival nodes can read **`HrmpChannelContents`** and map context to bytes that hash to **`payload_hash`**.
- **Collator / full node:** can **publish** `(mmr_leaf_index, payload)` to an **indexer**, **DB**, or **directly** to whoever pays for relaying.
- **Block import / tracing:** same deterministic drain order as the outbox to attach bytes to each **MMR leaf index**.

**Cryptographic binding is on-chain; bytes are DA**—HRMP dual-run, off-chain stores, or an explicit DA path when HRMP is off.

### Dual-run vs HRMP-off (later)

- **Dual-run POC:** wrapper only adds commitments; full bytes can still ride HRMP as today.
- **HRMP-off:** keep the same **drain hook** for hashing; transport policy changes separately.

---

## 10) Outbox pallet: global `XcmpOutboxMmr`, `XcmpOutboxMmrRoot`, header digest

### 10.1 When state updates (hook ordering)

1. **During `ParachainSystem::on_finalize` → `take_outbound_messages`:** for each **`(recipient, data)`**, **`note_outbound`** pushes one leaf onto **`XcmpOutboxMmr`** (same order as HRMP drain).
2. **`XcmpMmdOutbox::on_finalize`:** bagged root → **`XcmpOutboxMmrRoot`**, **`deposit_log`**.

**Critical:** in **`construct_runtime!`**, place **`XcmpMmdOutbox` after `ParachainSystem`**.

### 10.2 Global `XcmpOutboxMmr` (single stream)

**Leaf (example):** **`{ dest: ParaId, nonce: u64, payload_hash: H256 }`** (+ optional **`leaf_version`**).

**Nonce:** global **`OutboundNonce`** or **`NextNonce: StorageMap<ParaId, u64>`**—pick one; destination replay rules must match.

**`payload_hash`:** hash exact **`Vec<u8>`** from **`take_outbound_messages`** with agreed **`H`**.

**MMR:** **`mmr_lib`** over **all leaves ever**; **`mmr_leaf_index`** is **global**. Digest **`XcmpOutboxMmrRoot`** = rolling snapshot after the block.

**Empty blocks:** define behavior when no leaves were pushed (carry forward root, `H256::default()`, or sentinel); source and verifier must match.

### 10.3 Depositing the digest (C1)

`frame_system::deposit_log(DigestItem::PreRuntime(engine_id, (digest_version, XcmpOutboxMmrRoot).encode()))` with a dedicated **4-byte `engine_id`** (e.g. `*b"xmmd"`), not colliding with **`CumulusDigestItem`**.

### 10.4 One-block dataflow

```text
ParachainSystem::on_finalize
  └─ take_outbound_messages (wrapper)
       ├─ XcmpQueue::take_outbound_messages
       └─ for each (dest, data): note_outbound → push leaf on XcmpOutboxMmr

XcmpMmdOutbox::on_finalize   // after ParachainSystem
  └─ XcmpOutboxMmrRoot = bag_peaks (current MMR root)
  └─ deposit_log(PreRuntime, (version, XcmpOutboxMmrRoot))
```

### 10.5 Destination prover (reminder)

Prove **`head_bytes`** in **`ParaHeadsRoot`** → decode source header → **`XcmpOutboxMmrRoot`** → **outbox MMR proof** + **`hash(payload) == payload_hash`**.

---

## Appendix A: relay MMR root (where it lives)

Relay runtimes set `pallet_mmr::Config::OnNewRoot = pallet_beefy_mmr::DepositBeefyDigest`, which deposits:

`DigestItem::Consensus(BEEFY_ENGINE_ID, ConsensusLog::MmrRoot(root).encode())`

Extract with:

`sp_consensus_beefy::mmr::find_mmr_root_digest(header) -> Option<MmrRootHash>`

Destination (via `set_validation_data` relay context): decode relay parent header → `find_mmr_root_digest` → verify supplied MMR leaf proof → `leaf_extra = ParaHeadsRoot`.

---

## Appendix B: Polkadot SDK touchpoints (implementer)

### Baseline — where HRMP flows today

- `cumulus/pallets/parachain-system/src/lib.rs` — `on_finalize` drains `take_outbound_messages`, stores `HrmpOutboundMessages`.
- `cumulus/pallets/parachain-system/src/validate_block/implementation.rs` — PVF reads `HrmpOutboundMessages` → `ValidationResult.horizontal_messages`.
- `polkadot/runtime/parachains/src/inclusion/mod.rs` — `hrmp::prune_hrmp`, `queue_outbound_hrmp`.

### POC changes (conceptual)

- **Types:** `OutboxLeaf { dest, nonce, payload_hash }`, `MessageWithProof { source, dest, payload, anchor, para_heads_proof, outbox_mmr_proof, mmr_leaf_index, ... }` with hard bounds.
- **Source:** global **`XcmpOutboxMmr`** + **`XcmpOutboxMmrRoot`** in digest; **`OutboundXcmpMessageSource` wrapper** around **`XcmpQueue`** (drain + note leaves, return same HRMP pages for dual-run).
- **C1:** root is in **source header** included in **`ParaHeadsRoot`**; no mandatory relay map `XcmpOutboxMmrRoots[ParaId]` (optional indexing only).
- **Destination:** permissionless extrinsic; verifies relay MMR → `ParaHeadsRoot` → header digest → outbox MMR + payload hash; replay protection.
- **PVF:** header must match validation; digest is part of agreed header bytes (see §7).
- **Tests / demo:** e.g. `cumulus/xcm/xcm-emulator` or integration tests.

### Stretch: BEEFY-first light clients

Code references for leaf-extra plumbing: `substrate/frame/beefy-mmr`, `substrate/primitives/consensus/beefy` (`MmrLeaf.leaf_extra`). The POC above still obtains **`ParaHeadsRoot`** via relay parent + MMR leaf proof as in Appendix A.

### Team review checklist

- Leaf = payload hash vs extra metadata
- Ordering / replay semantics
- Bounds + weights
- Pruning / incentives (post-POC)

---

*Older generic XCMP research (2021): see {{< relref "/post/2021-05-10-xcmp.md" >}} — not specific to this MMD minimal POC.*
