---
author: Ron
catalog: true
date: 2026-04-09
tags:
- BlockChain
- Polkadot
title: XCMP Merkle Matryoshka Dolls (1‑pager)
---

Source context: [XCMP Design Discussion (Polkadot forum)](https://forum.polkadot.network/t/xcmp-design-discussion/7328)

## Problem

**HRMP** stores **message payloads on the relay chain**, which is expensive in relay-chain storage and execution.

**XCMP (MMD approach)** aims to replace HRMP by moving payload storage and most computation off-chain, keeping only **compact commitments** anchored by relay consensus.

## Core idea (MMD)

Instead of proving “message exists in the source state trie”, prove “message was committed by source chain” via **nested Merkle commitments** (“Matryoshka dolls”).

### Commitments (small → large)

1. **`XcmpMessageMMR` (per channel)**: append-only Merkle Mountain Range over messages for one `(source → dest)` channel.
2. **`XcmpChannelTree` (on source)**: binary merkle tree whose leaves are `XcmpMessageMMR_root(channel_id)` for all open channels.
3. **Source para header**: contains the `XcmpChannelTree_root`.
4. **`ParaHeaderTree` (relay)**: binary merkle tree over parachain headers.
5. **`BEEFYMMR` (relay)**: finality MMR whose leaf provides (directly or indirectly) the `ParaHeaderTree` root.

### Verification (destination)

Given a trusted **BEEFY root**, verify nested proofs in order:

1. BEEFY MMR proof → extract `ParaHeaderTree` root.
2. ParaHeaderTree proof → extract source parachain header.
3. XcmpChannelTree proof → extract the per-channel `XcmpMessageMMR` root.
4. XcmpMessageMMR proof → verify the message leaf (payload hash / payload).

If all checks pass, the destination has a **verified message** and can execute XCM.

## Who provides payload + proofs?

The design uses **relayers** (permissionless off-chain actors) to submit:
- the **message payload**
- the **nested proof bundle**

Collators can play the relayer role (collator-as-relayer), which can simplify a first implementation and pruning.

## Open issues (for full HRMP replacement)

- **Delivery guarantees**: MMD (as described) doesn’t automatically guarantee delivery; incentives or enshrined relaying may be needed.
- **Pruning**: without delivery receipts/acks, pruning can be hard; receipts make both pruning and incentives easier.
- **Ordered vs unordered delivery**: both possible; unordered is more resilient for liveness, ordering can be layered at app level.
- **DoS bounds**: proofs + payload sizes must be bounded per block.

## Practical POC staging (recommended)

POC1: implement the “MMD shape” but anchor commitments using **relay storage proofs** (via the existing `set_validation_data` relay-state-proof path) rather than going straight to a full `BEEFYMMR → ParaHeaderTree` pipeline.

POC2: move the anchor into BEEFY/MMR leaf extra and prove from BEEFY roots (closer to the forum design).

