---
author: Ron
catalog: true
date: 2026-04-09
tags:
- BlockChain
- Polkadot
title: XCMP MMD POC implementer checklist (Polkadot SDK)
---

Companion note to [XCMP Merkle Matryoshka Dolls (1‑pager)]({{< relref "2026-04-09-xcmp-mmd-1-pager.md" >}}).

## Baseline: where HRMP flows today

### Parachain (Cumulus) outbound → commitments

- `cumulus/pallets/parachain-system/src/lib.rs`
  - `on_finalize` drains `T::OutboundXcmpMessageSource::take_outbound_messages(...)`
  - stores `HrmpOutboundMessages` (later becomes `ValidationResult.horizontal_messages`)

### PVF / validate_block

- `cumulus/pallets/parachain-system/src/validate_block/implementation.rs`
  - Executes the block under externalities and then **reads**:
    - `HrmpOutboundMessages` → `ValidationResult.horizontal_messages`
    - `HrmpWatermark` → `ValidationResult.hrmp_watermark`
  - This code is compiled into the parachain **PVF** and executed by relay validators.

### Relay inclusion

- `polkadot/runtime/parachains/src/inclusion/mod.rs`
  - checks acceptance criteria (`check_validation_outputs`)
  - enacts candidate messaging:
    - `hrmp::Pallet::prune_hrmp(para, hrmp_watermark)`
    - `hrmp::Pallet::queue_outbound_hrmp(para, horizontal_messages)`

## POC target (what changes)

Goal: stop storing payloads in relay HRMP queues. Instead:
- Source commits outbound messages into a compact root.
- Relay stores/anchors that root (or it’s anchored via BEEFY/MMR later).
- Destination verifies message payloads against the root using membership proofs.
- Collator includes payload+proof in destination’s authored block (collator-as-relayer).

## POC1 (recommended): relay storage proof anchor (fastest “real proof” path)

### 1) Define new commitment + proof types (primitives)

Define SCALE-encoded types and bounds:
- `ChannelId { sender: ParaId, recipient: ParaId }`
- `MessageLeaf { index/nonce, payload_hash, maybe_sent_at }`
- `MessageWithProof { source, dest, payload, proofs... }`

Hard bounds:
- max messages per block
- max proof nodes per message
- max payload size

### 2) Source para: outbox pallet to build commitments

Implement a pallet that:
- maintains per-channel append-only structure (MMR or hash-chain for POC)
- produces a `channel_tree_root` that commits to all channel MMR roots

Wire into outbound path:
- `cumulus/pallets/parachain-system/src/lib.rs` `on_finalize`
  - feature-gate replacing `HrmpOutboundMessages::put(...)`
  - drain `T::OutboundXcmpMessageSource::take_outbound_messages(...)`
  - append to outbox commitment structure instead

### 3) PVF output: make the root visible to relay inclusion

You need the root to be part of what validators agree the block produced.

Options:
- Preferred: extend the validation result/commitments plumbing to carry `xcmp_channel_root`.
- POC fallback: encode `xcmp_channel_root` into an agreed `head_data` format (format invasive).

Touchpoint:
- `cumulus/pallets/parachain-system/src/validate_block/implementation.rs`
  - after `execute_verified_block`, read the outbox root and include it in the returned result

### 4) Relay runtime: store anchor root per para

Add relay storage:
- `XcmpChannelRoots[ParaId] -> Hash`
- optional: small history window for replay/out-of-order demos

Touchpoints:
- new relay module/pallet under `polkadot/runtime/parachains/`
- `polkadot/runtime/parachains/src/inclusion/mod.rs`
  - acceptance checks for the new root field
  - enactment writes `XcmpChannelRoots[para_id] = root`

### 5) Destination para: verifier + execution

Implement a pallet that:
- accepts `MessageWithProof` via inherent or call
- verifies:
  - message ∈ per-channel commitment (MMR proof)
  - commitment ∈ channel tree (channel tree proof)
  - channel tree root matches relay anchor for source para (relay state proof)
- tracks replay protection (e.g., last seen index per `(source, channel)`)
- dispatches verified payloads into XCM execution path

Touchpoints:
- destination runtime pallet
- parachain inherent types (`cumulus_primitives_parachain_inherent`)

### 6) Collator-as-relayer: build proofs and include in inherent

Implement collator-side logic that:
- watches relay anchor roots and source commitments
- retrieves message payloads (source message store)
- builds `MessageWithProof`
- injects into destination block inherent data

Touchpoints:
- collator inherent construction code under `cumulus/client/*` (depends on stack)
- `cumulus_primitives_parachain_inherent` data format

### 7) Demo / tests

Add an end-to-end demo:
- `cumulus/xcm/xcm-emulator` or integration tests
- verify: source commits → relay anchors → dest verifies+executes

## POC2 (optional): anchor via BEEFY/MMR (closer to forum MMD)

Once POC1 works, move anchoring to BEEFY/MMR:
- `substrate/frame/beefy-mmr/src/lib.rs` (leaf extra plumbing)
- `substrate/primitives/consensus/beefy/src/mmr.rs` (`MmrLeaf.leaf_extra`)

## Team review checklist

- Commitment format (leaf = payload hash vs payload+metadata)
- Protocol ordering requirements
- Replay protection semantics
- Block bounds (messages, proofs) + weight model
- Delivery receipts/acks for pruning & incentives

