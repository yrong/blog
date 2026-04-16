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
- **no Receipts/acks**
- **no Incentive mechanism for relayers**
- **replay protection required**: prevent executing the same proven message repeatedly


### “Matryoshka” proof stack (minimal POC variant, simplified)

Smallest → largest commitments:

1. **`XcmpOutboxMmr`** (source chain, single global, append-only): every drained outbound page becomes one leaf. Leaf body includes **`dest_para_id`**, **`nonce`**, **`payload_hash`** where `payload_hash = Keccak256(page_bytes)`. **No separate per-channel MMR and no `XcmpChannelTree`.**
2. **Source parachain header**: the header digest commits the rolling **`XcmpOutboxMmrRoot`** (bagged MMR root after the block’s appends; empty blocks carry-forward last root).
3. **`ParaHeadsRoot`** (relay chain snapshot): the chosen relay MMR leaf exposes `leaf_extra = ParaHeadsRoot`, a
   binary Merkle root committing to `SCALE((para_id_u32, head_bytes))` entries (sorted by `para_id`). The
   relevant entry includes the source `head_bytes` whose digest contains the `xmmd` commitment.
4. **Relay MMR root** (relay chain, implicit root anchor): read from the destination block’s **relay parent**
   header digest; it commits to the chosen relay MMR leaf. Since the relay MMR is append-only, a historical
   leaf still verifies under a later root.

Destination verifies nested proofs:

1. Get relay **MMR root** from the **current block’s relay parent** header digest (Appendix A). This is the **cumulative** MMR root after that relay parent (it includes **all** earlier relay leaves).
2. Verify the **relay MMR leaf proof** (exactly **one** leaf per message) at **`relay_mmr_leaf_index`**,
   i.e. the relay MMR leaf whose `leaf_extra` contains the required `ParaHeadsRoot` snapshot. Verify it
   against the implicit relay MMR root, then decode the leaf and read `leaf_extra = ParaHeadsRoot` for that
   leaf.
3. Verify **`binary_merkle_tree::MerkleProof`** for `SCALE((source, head_bytes))` against `ParaHeadsRoot`.
4. Decode **`head_bytes`** as the source parachain **header**, then read **`DigestItem::PreRuntime(*b"xmmd", …)`** → **`XcmpOutboxMmrRoot`**.
5. Verify **outbox MMR leaf proof** (single leaf) for leaf **`(dest, nonce, payload_hash)`** at **`mmr_leaf_index`** against **`XcmpOutboxMmrRoot`**.
6. Check **`Keccak256(payload) == payload_hash`** (relayer supplies bytes).
7. Replay protection: reject if **`seen((source, mmr_leaf_index))`**.
8. POC execution: emit event / queue payload / XCM execution

---

### Current Beefy-(MMR) implementation on the relay chain that we rely on

Relay chain runtimes configure `pallet_beefy_mmr::LeafExtra = H256` and set:

- `LeafExtra = ParaHeadsRoot`
- `ParaHeadsRootProvider` computes merkle root over `sorted_para_heads()`
  - `(para_id_u32, head_bytes)` sorted by id

**Important**: this defines the proof format and hashing. Our verifier must match it exactly.

---

## POC Spec (high level)

This is the minimal spec that the implementation follows.

**POC design revamp (vs forum MMD):** the forum sketch uses **one `XcmpMessageMMR` per channel** and an **`XcmpChannelTree`** over those MMR roots. For this **minimal POC** we **drop that split**: a **single append-only global `XcmpOutboxMmr`** on the source commits all outbound messages; the header digest carries **`XcmpOutboxMmrRoot`** only. Each leaf still names **`dest`** (and nonce + `payload_hash`), so there is no loss of routing identity—only a shorter proof path and less on-chain bookkeeping. A future scale-out version can shard back into per-channel MMRs + channel tree.

**Committed structure:** the outbox is a **global MMR**—**one accumulator across all blocks**, leaves only appended, **monotonic `mmr_leaf_index`** over the lifetime of the chain (until reset / migration). We **do not** use a per-block-only binary Merkle snapshot as the primary commitment; **`XcmpOutboxMmrRoot`** in each header is the **current bagged root** after that block’s appends. **Empty blocks (POC):** **carry-forward last root** — if no leaves are appended, the digest repeats the previous block’s `XcmpOutboxMmrRoot`.

### Commitments

- **Outbox accumulator:** one global append-only `XcmpOutboxMmr` (monotonic `mmr_leaf_index`)
- **Leaf:** `(dest: u32, nonce: u64, payload_hash: H256)` (SCALE-encoded)
- **`payload_hash`:** `Keccak256(payload_bytes)` where `payload_bytes` is exactly the `Vec<u8>` drained from `XcmpQueue::take_outbound_messages`
- **Nonce:** global monotonic `u64`
- **Header digest:** `DigestItem::PreRuntime(*b"xmmd", SCALE((version, XcmpOutboxMmrRoot)))`
- **Empty blocks:** carry-forward last root (repeat previous `XcmpOutboxMmrRoot` if no leaves appended)

### Relay anchoring

- **Anchor is implicit (root only):** the verifier takes the **relay MMR root** from the current block’s **relay parent** (`set_validation_data`). That fixes **which accumulator** you check; it does **not** force you to use the **tip** relay-MMR leaf.
- **Late relayers:** because relay MMR only **appends**, a membership proof for an **older** relay leaf index still verifies against the **current** MMR root from the (later) relay parent. The relayer supplies **`relay_mmr_leaf_index`** for the relay block whose `ParaHeadsRoot` snapshot actually contains the **`(source, head_bytes)`** you need—often the relay height where the source block was **included**, not necessarily the relay parent height itself. **Operational coupling** remains: you must pick the correct index and pay larger proofs if the relay has advanced far; **cryptographic** “old head vanished from tip snapshot” is not a dead end if you prove the **right historical leaf**.

### Proof types

- **Relay MMR proof (single leaf):** `sp_mmr_primitives::EncodableOpaqueLeaf` + `sp_mmr_primitives::LeafProof<H256>` with explicit **`relay_mmr_leaf_index`** (which relay leaf’s `leaf_extra` you claim).  
  Verified with `pallet_mmr::verify_leaves_proof::<Keccak256,_>(relay_root, ...)` against the **implicit** `relay_root` and decoded to obtain `leaf_extra = ParaHeadsRoot` **for that leaf**.
- **Para-heads proof:** `binary_merkle_tree::MerkleProof<H256, Vec<u8>>` where `leaf = SCALE((source_u32, head_bytes))`
- **Outbox MMR proof (single leaf):** `sp_mmr_primitives::EncodableOpaqueLeaf` + `sp_mmr_primitives::LeafProof<H256>`  
  Verified statelessly against `XcmpOutboxMmrRoot`.
- **OutboxLeaf:** `{ dest, nonce, payload_hash }`
- **MessageWithProof** `{ source, dest, nonce, mmr_leaf_index, relay_mmr_leaf_index, payload, relay_mmr_proof, para_heads_proof, outbox_mmr_proof }` with hard bounds and an implicit **relay-parent MMR root** anchor (`relay_mmr_leaf_index` is explicit in calldata).

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

---

## POC Implementation (low level)

### Source: XcmpMmdOutbox Pallet 

#### How to integrate with the current XcmpQueue

1. **`pallet-xcm`** routes sends through the runtime **`XcmRouter`**, which ends in **`XcmpQueue`’s `SendXcm`**: messages are encoded and stored as outbound pages (`OutboundXcmpMessages`).
2. **`ParachainSystem`** `on_finalize` calls **`OutboundXcmpMessageSource::take_outbound_messages`**, which (in typical runtimes) is **`XcmpQueue::take_outbound_messages`**, yielding **`Vec<(ParaId, Vec<u8>)>`**. Those **`Vec<u8>`** values are the HRMP page bytes today — they are the stable object to hash for the commitment.
3. In the runtime, replace `type OutboundXcmpMessageSource = XcmpQueue` with a **thin wrapper** like: **`type OutboundXcmpMessageSource = (XcmpQueue,XcmpMmdOutbox)`** so existing **`ParachainSystem`** / HRMP bandwidth behavior stays intact for a **dual-run** POC.
4. Add an **XcmpMmdOutbox pallet** that maintains:
  - For each **`(recipient, data)`**: compute **`payload_hash = Keccak256(data)`**; bump **global monotonic nonce**; **push one leaf** on **`XcmpOutboxMmr`**.
  - **Leaf content**: **`{ dest: ParaId, nonce: u64, payload_hash: H256 }`**. (A separate **`digest_version`** lives in the header digest wrapper; leaf layout stays fixed for the POC.)
  - **Nonce**: global monotonic **`OutboundNonce: u64`** incremented once per appended leaf.
  - **MMR:** **`mmr_lib`** over **all leaves ever**; **`mmr_leaf_index`** is **global**. Digest **`XcmpOutboxMmrRoot`** = rolling snapshot after the block. (append-only; `mmr_lib` / `merkle-mountain-range` pattern)
  - **`XcmpMmdOutbox::on_finalize`:** bagged root → **`XcmpOutboxMmrRoot`** and `frame_system::deposit_log(DigestItem::PreRuntime(engine_id, (digest_version, XcmpOutboxMmrRoot).encode()))` with a dedicated **4-byte `engine_id`** (e.g. `*b"xmmd"`), not colliding with **`CumulusDigestItem`** and include **`XcmpOutboxMmrRoot`** in the header digest.

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

**Decision**: integrate the outbox by **draining the existing outbound queue** (no parallel `SendXcm` sink). Commit **`payload_hash` + global `nonce`** in the global MMR and header digest. A **permissionless relayer** later submits the **full payload bytes** on the destination, together with proofs that bind to the committed hash.

**Hashing note**: commit the hash of the **exact** page bytes returned by **`take_outbound_messages`**. Do not assume equality with the **`XcmpMessageSent.message_hash`** from **`deliver`** (that is a Blake2 hash over the **versioned XCM** encoding path and may differ from the final page bytes).

**Empty blocks (fixed for POC):** **carry-forward last root** — if a block appends no leaves, the digest item repeats the previous block's `XcmpOutboxMmrRoot`.

**Critical:** in **`construct_runtime!`**, place **`XcmpMmdOutbox` after `ParachainSystem`**.

### Destination: XcmpMmdInbox Pallet 

#### Submission model: permissionless extrinsic

Anyone can be a relayer. The destination chain exposes an extrinsic, e.g.:

- `submit_xcmp_mmd(messages: Vec<MessageWithProof>)`

No collator/inherent pipeline changes are required for the minimal POC.

#### What the extrinsic must carry (per message)

- **Anchor (relay MMR root):** **implicit** — the verifier reads the **relay MMR root** from the **current block's relay parent** (`set_validation_data`). No relay block hash/number is required **for the root**.
- **Relay leaf pick (explicit):** `relay_mmr_leaf_index: u64` — which relay MMR leaf supplies `leaf_extra = ParaHeadsRoot` for this message (often a **historical** index if the relayer was slow).
- `source: u32`, `dest: u32`, `nonce: u64`, `mmr_leaf_index: u64` (outbox MMR leaf)
- `payload: Vec<u8>` (bounded)
- **Relay MMR (single leaf):** proof bundle for **`relay_mmr_leaf_index`** against the implicit `relay_root` (Appendix A).
  - Still **exactly one proven relay leaf per message** for the POC; that leaf may be **far behind** the relay parent on the relay chain.
- **Para-heads merkle proof:** a proof object whose leaf is exactly `SCALE((source_u32, head_bytes))` (bounded).
- **Outbox MMR (single leaf):** membership proof for committed outbox leaf `(dest, nonce, payload_hash)` at `mmr_leaf_index` under `XcmpOutboxMmrRoot` extracted from `head_bytes`.

#### Definitions (identifiers / hashing)

- `SourceParaId`, `DestParaId`: `u32` (SCALE where needed).
- **`relay_mmr_leaf_index`:** relay `pallet_mmr` **leaf index** for the relay block whose MMR leaf carries the `ParaHeadsRoot` you prove against (must match the sole leaf index in the relay `LeafProof`).
- **Routing** is implicit in each outbox leaf **`(dest, nonce, payload_hash)`**; no separate channel-tree id.
- **Hashing (fixed for POC):**
  - `payload_hash = Keccak256(payload_bytes)` where `payload_bytes` is the exact `Vec<u8>` drained from `XcmpQueue::take_outbound_messages`.
  - Para-heads merkle must match relay: `H = Keccak256`, leaf `SCALE((para_id_u32, head_bytes))`, relay sorts by `para_id`, odd-count promotion per `binary_merkle_tree` (`substrate/utils/binary-merkle-tree`).
- **Proof types (POC, concrete):**
  - Para-heads proof: `binary_merkle_tree::MerkleProof<H256, Vec<u8>>` where `leaf = SCALE((source_u32, head_bytes))`.
  - Relay MMR proof: `sp_mmr_primitives::EncodableOpaqueLeaf` + `sp_mmr_primitives::LeafProof<H256>` (exactly 1 leaf; indices must match **`relay_mmr_leaf_index`**).
  - Outbox MMR proof: `sp_mmr_primitives::EncodableOpaqueLeaf` + `sp_mmr_primitives::LeafProof<H256>` (exactly 1 leaf).

#### Off-chain relayer tool

- Watches:
  - source collator / RPC: **outbox MMR leaf data**, global **`mmr_leaf_index`**, and **encoded source header** (`head_bytes`) for the block that committed the message
  - relay: for the **relay leaf** where that `head_bytes` appears under **`ParaHeadsRoot`**, record **`relay_mmr_leaf_index`** and build the **relay MMR leaf proof** against the MMR root that the **destination** will use — i.e. the root from the **destination candidate’s relay parent** (append-only MMR: that root still proves old leaves)
- Builds proof bundle (**relay MMR + para-heads + outbox MMR**) and submits extrinsic to destination.

- **Relayer submission:** provide **`payload`**, **`relay_mmr_leaf_index`**, **outbox MMR proof** (single leaf), **`Keccak256(payload) == payload_hash`**, plus relay MMR leaf proof + para-heads proof. The **relay parent** is fixed by the destination block; the **relay leaf** is chosen so its `ParaHeadsRoot` contains your **`(source, head_bytes)`**.

#### Where the relayer gets the full `payload` (XCM bytes)

**On-chain we only commit `payload_hash`.** The **verifier** checks that submitted **`Vec<u8>`** matches that hash; it does **not** reconstruct the message from the chain.

The **relayer** obtains the **original page bytes** from **off-chain / side observability**, for example:

- **Dual-run HRMP POC:** the relay still stores the payload in **HRMP** for that window; archival nodes can read **`HrmpChannelContents`** and map context to bytes that hash to **`payload_hash`**.
- **Parachain:** can also store `(mmr_leaf_index, payload)` to an **off chain indexer**

**Cryptographic binding is on-chain; bytes are DA**—HRMP dual-run, off-chain stores, or an explicit DA path when HRMP is off.

#### How to verify the payload

- **On-chain commitment:** the outbox leaf binds **`(dest_para_id, nonce, payload_hash)`** at **`mmr_leaf_index`** under **`XcmpOutboxMmrRoot`** for a specific **source header**, linked through **`ParaHeadsRoot`** from the **chosen relay MMR leaf** and the **implicit relay-parent MMR root**.

- Verifier pallet with a permissionless extrinsic:
  - verifies relay MMR leaf proof at **`relay_mmr_leaf_index`** → `ParaHeadsRoot` for that leaf
  - verifies para-heads proof → `head_bytes`
  - extracts **`XcmpOutboxMmrRoot`** from header digest
  - verifies **outbox MMR leaf proof** (the payload hash)
  - verifies `Keccak256(payload) == payload_hash`
  - replay protection + bounded execution

##### Verification Implementation
1. Obtain relay parent header from validation data, extract relay MMR root from the BEEFY digest (Appendix A).
2. Verify the submitted **relay MMR leaf proof** (single leaf) **at `relay_mmr_leaf_index`** against that root; decode the proven leaf and read `leaf_extra = ParaHeadsRoot` (**snapshot for that relay leaf**, not “whatever the tip says today”).
3. Verify the submitted **para-heads Merkle proof** against that `ParaHeadsRoot` and decode its leaf as `SCALE((source_u32, head_bytes))`.
4. Decode `head_bytes` as the source parachain header → extract **`XcmpOutboxMmrRoot`** digest item (`engine_id = *b"xmmd"`).
5. Verify the submitted **outbox MMR proof** (single leaf) for outbox leaf `(dest, nonce, payload_hash)` at `mmr_leaf_index` against `XcmpOutboxMmrRoot`.
6. Check `Keccak256(payload) == payload_hash`.
7. Replay protection: `seen((source, mmr_leaf_index))` must be false; then mark it seen.
8. **Post-verify:** destination execution — feed those bytes into the destination runtime’s **normal inbound XCMP dispatch path** with the correct **sender origin** (`ParaId::from(source)` / `Sibling(ParaId)`), typically by invoking the configured **`XcmpMessageHandler`** (in Cumulus templates this is usually **`XcmpQueue`**) using whatever **internal hook / helper** your runtime exposes for “append sibling message bytes”.


#### Verifier guards (required)

- **`dest` must match this chain**: reject unless `dest == SelfParaId` (or the runtime’s canonical `u32` para id).
- **Bind extrinsic fields to commitments**: after proofs succeed, recompute / extract the committed outbox leaf and **`ensure!`** it matches the submitted **`(dest, nonce, payload_hash)`** (and that **`source`** matches the decoded para-heads leaf). Do not trust mismatched metadata once the leaf is known.
- **`relay_mmr_leaf_index` matches the relay `LeafProof`:** reject unless the proof’s leaf index (e.g. `leaf_indices[0]` for a single-leaf proof) equals the submitted **`relay_mmr_leaf_index`**.
- **Relay leaf vs relay parent:** `head_bytes` must be the **exact** `(source, …)` entry under the **`ParaHeadsRoot` carried by the relay MMR leaf at `relay_mmr_leaf_index`**. The **MMR root** still comes from the destination block’s **relay parent** (implicit). **Late relayers** choose a **historical** `relay_mmr_leaf_index` so that snapshot still contains the header you need; append-only relay MMR makes that valid under a **later** relay parent. **Practical limits:** wrong index → failed verify; very old indices → **larger** proofs and higher weight — tune **`MaxRelayMmrProofItems`** / fees for your devnet.

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


