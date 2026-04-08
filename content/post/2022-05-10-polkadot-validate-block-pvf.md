---
author: Ron
catalog: true
date: 2022-05-10
tags:
- BlockChain
- Polkadot
title: Polkadot validate_block, PVF, and relay validators
---

Companion to [Polkadot HRMP protocol (implementation guide)]({{< relref "2022-05-09-polkadot-hrmp-protocol.md" >}}).

## What `implementation.rs` is

**`cumulus/pallets/parachain-system/src/validate_block/implementation.rs`** implements **`validate_block`**: take the PoV’s **storage proof**, build a sparse in-memory trie, **override** `sp_io::storage` (and related) host functions so validation runs **inside the Wasm** instead of calling the node’s DB, **execute the parachain block**, then return **`ValidationResult`** — head data, `horizontal_messages`, `hrmp_watermark`, upward messages, processed downward message count, optional new validation code.

The helper **`run_with_externalities_and_recorder`** wraps Substrate **`Externalities`** (`Ext` over proof + **`OverlayedChanges`**) so pallet storage reads/writes during `execute_verified_block` and the follow-up reads for the result see consistent state. That is **production PVF** behavior, not limited to tests.

## PVF entry point

Parachain runtimes register validation with **`cumulus_pallet_parachain_system::register_validate_block!`**. In **`no_std`** builds, the proc-macro in **`cumulus/pallets/parachain-system/proc-macro/src/lib.rs`** emits a **`#[no_mangle] unsafe fn validate_block(...)`** that forwards into this pallet’s validate-block implementation. That symbol is part of the **parachain validation Wasm** registered on the relay chain — the **PVF**.

So **`implementation.rs` is compiled into the parachain PVF**, not into the Polkadot relay runtime (`frame_executive`).

## Relay validators vs relay on-chain runtime

| Accurate | Misleading |
|----------|--------------|
| **Relay validators** load the parachain’s PVF and run it in a **sandboxed VM** (Wasm / PolkaVM) as part of **candidate validation**. | This code **runs on-chain** as a relay-chain pallet in a relay block. |

PVF execution is **validator node work**, **off-chain** with respect to relay state transitions — but it is **mandatory** for security and is what backs **committed** parachain progress.

## One-liner

**`validate_block` in `implementation.rs` is the core logic inside the parachain PVF; relay validators execute that Wasm when validating candidates; it is not relay-chain runtime logic, but it is how the relay chain checks parachain blocks.**
