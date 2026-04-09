---
author: Ron
catalog: true
date: 2026-04-09
tags:
- BlockChain
- Polkadot
title: XCMP MMD POC2 (Option 1) spec
---

POC goal: implement XCMP “Merkle Matryoshka Dolls” (MMD) anchored by the relay’s **MMR root**, obtained directly via the parachain’s **relay-chain state proof** (from `set_validation_data`), and then using an **MMR leaf proof** to obtain `leaf_extra` that commits to a **binary Merkle root of parachain heads**.

Scope choices:
- **A1**: relay MMR leaf extra anchors a “ParaHeaderTree-like” root (here: *para heads merkle root*).
- **C1**: source commits `XcmpChannelTree_root` in the **real parachain header digest**.
- **Option 1**: accept relay’s `MAX_PARA_HEADS = 1024` truncation for POC.

---

## Definitions

### Identifiers

- `SourceParaId`: `u32` (SCALE encoded)
- `DestParaId`: `u32`
- `ChannelId`: `(SourceParaId, DestParaId)` (unidirectional)

### Hashing (para-heads merkle root)

Must match relay runtime exactly:

- `H = Keccak256`
- Leaf bytes: `leaf = SCALE.encode((para_id_u32, head_bytes: Vec<u8>))`
- Leaf hash: `h_leaf = H(leaf)`
- Inner node hash: `h_parent = H(h_left || h_right)`
- No sorting at tree build time (ordering is decided by input list; the relay sorts by `para_id`).
- If odd number of nodes in a layer, the last node is **promoted**.

Reference: `binary_merkle_tree` (`substrate/utils/binary-merkle-tree`).

### Relay anchor commitment

Relay provides the MMR root in a header digest item; the destination obtains it via the **relay-chain state proof** included in parachain block production.

Then, given the MMR root, an **MMR leaf proof** yields an MMR leaf whose `leaf_extra` is:

- `ParaHeadsRoot: H256` computed as:
  - `para_heads = parachains_paras::Pallet::<Runtime>::sorted_para_heads()`
  - `ParaHeadsRoot = binary_merkle_tree::merkle_root::<Keccak256,_>(para_heads.map(|pair| SCALE(pair)))`

Notes:
- `sorted_para_heads()` is sorted by `para_id` ascending and truncated to 1024.

### Source header commitment (C1)

Source parachain header must include a digest log item that encodes:
- a fixed “XCMP_MMD” identifier/version tag
- `XcmpChannelTreeRoot: H256`

This digest item must be produced deterministically in block execution so PVF validation yields identical header bytes on all validators.

---

## Proof bundle format (permissionless extrinsic)

For the minimal POC, any account can submit a batch of inbound messages via an extrinsic; each message must carry:

### `InboundXcmpMmdMessage` (conceptual)

- `source: u32`
- `dest: u32`
- `payload: Vec<u8>`

**Relay MMR anchor + leaf proof**
- `relay_mmr_root_proof` (read MMR root digest item from relay via relay-state-proof / inherent machinery)
- `mmr_leaf_proof` (yields `MmrLeaf.leaf_extra = ParaHeadsRoot`)

**Para heads merkle proof**
- `para_heads_merkle_proof`: merkle proof for leaf index `i` against `ParaHeadsRoot`
- `head_bytes: Vec<u8>` for `(source)`

**Header commitment**
- Extract `XcmpChannelTreeRoot` from `head_bytes` digest

**Channel-tree + message-MMR proofs**
- `channel_tree_proof`
- `message_mmr_proof`
- `mmr_leaf_index` / `nonce` (for replay protection), depending on MMR format

---

## Destination verification algorithm (per message)

1. Obtain relay MMR root via relay-state proof; verify MMR leaf proof → obtain `ParaHeadsRoot`.
2. Verify `SCALE((source, head_bytes))` membership in `ParaHeadsRoot`.
3. Decode `head_bytes`, extract `XcmpChannelTreeRoot` digest item.
4. Verify `channel_tree_proof` against `XcmpChannelTreeRoot` → get `message_mmr_root`.
5. Verify `message_mmr_proof` for `payload_hash` under `message_mmr_root`.
6. Replay protection: monotonic `mmr_leaf_index` per channel.
7. Execute (POC): emit an event (XCM execution later).

---

## Bounds (must-have)

- max inbound messages per block
- max payload bytes per message
- max proof nodes per layer
- total proof bytes per block

---

## Appendix: where the relay MMR root lives (and how to read it)

### Relay header digest item

Relay runtimes configure `pallet_mmr::Config::OnNewRoot = pallet_beefy_mmr::DepositBeefyDigest<Runtime>`.
That implementation deposits a **consensus digest item**:

- `DigestItem::Consensus(BEEFY_ENGINE_ID, ConsensusLog::MmrRoot(root).encode())`

### Extracting the root from a relay header

`sp_consensus_beefy` provides:

- `sp_consensus_beefy::mmr::find_mmr_root_digest(header) -> Option<MmrRootHash>`

It scans the header digest for the `BEEFY_ENGINE_ID` consensus item and returns the `MmrRoot(root)` value.

### How the destination gets it in this POC

Even though message submission is permissionless via extrinsic, destination still uses the standard parachain `set_validation_data` inherent relay context:

1) decode relay parent header from inherent-provided relay data\n+2) call `find_mmr_root_digest` to obtain `MmrRootHash`\n+3) verify supplied MMR leaf proof against `MmrRootHash` to obtain `leaf_extra = ParaHeadsRoot`

