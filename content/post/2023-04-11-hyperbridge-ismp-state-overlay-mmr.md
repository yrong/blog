---
author: Ron
catalog: true
date: 2023-04-11
tags:
- BlockChain
- Polkadot
- Hyperbridge
- ISMP
title: Hyperbridge ISMP — state_root, overlay_root, and mmr_root
---

Notes mirrored from **Hyperbridge - ISMP Storage Proofs & Substrate Child Trie** (Obsidian). Repo context: [`polytope-labs/hyperbridge`](https://github.com/polytope-labs/hyperbridge). Protocol docs: [docs.hyperbridge.network](https://docs.hyperbridge.network/).

When reading `pallet-ismp` and `SubstrateStateMachine`, three roots show up: the parachain **`state_root`**, the optional **`overlay_root` on `StateCommitment`**, and the **`mmr_root`** in the per-block **`ConsensusDigest`**. They are not interchangeable; each corresponds to a different data structure and proof type.

---

## What each root is

| Name | Role |
|------|------|
| **`state_root`** | Root of the chain’s **main** Substrate state trie (`Header::state_root`). It commits to **all** pallets. Child tries are still **included** under this trie. |
| **`mmr_root`** | Root of the **ISMP MMR** after the MMR pallet finalizes the block: an **append-only** tree over **message leaves** (full bodies stored off-chain). It appears in the header as part of **`ConsensusDigest`**, not as a separate top-level field on `StateCommitment` by itself. |
| **`overlay_root` on `StateCommitment`** | The **ISMP overlay** slot carried in consensus proofs. It is **not** a third independent trie type in the abstract—it is **whatever the chain puts in that slot** (see packing below). |

Each block, `on_finalize` builds:

- **`child_trie_root`** — `storage::child::root` for the ISMP child trie (`b"ISMP"`), where commitment metadata and related keys live.
- **`mmr_root`** — `OffchainDB::finalize()` from the MMR accumulator.

Both go into **`ConsensusDigest { mmr_root, child_trie_root }`** in the header digest.

---

## How `StateCommitment` packs those digest fields

`StateCommitment` has `timestamp`, `state_root`, and optional `overlay_root`. The parachain consensus client maps header digest + header `state_root` into that struct. There are two regimes (`modules/ismp/clients/parachain/client/src/consensus.rs`):

**Ordinary parachain (not the coprocessor)**

- `state_root` = header state root (main trie).
- `overlay_root` = **`child_trie_root`** from `ConsensusDigest`.

**Hyperbridge as coprocessor**

- `state_root` = **`child_trie_root`** (ISMP child trie only).
- `overlay_root` = **`mmr_root`**.

So on Hyperbridge, the **MMR root** is stored in **`overlay_root`**, and the **child trie root** is stored in **`state_root`**. The naming in `StateCommitment` is easy to misread; the packing is explicit in code.

---

## Which root a proof uses

**1. POST request/response membership via Patricia trie** (`verify_membership`, `OverlayProof` in `modules/ismp/state-machines/substrate/src/lib.rs`)

- Verifies that commitment keys exist under the **child trie** layout.
- Root selection: if the proof targets the **coprocessor** state machine, use **`state.state_root`** (which, for that commitment, **is** the child trie root); otherwise use **`state.overlay_root`** (child trie root on other chains).
- This path does **not** verify the MMR.

**2. GET / arbitrary storage reads** (`verify_state_proof`)

- **`StateProof`** → verify against **`state_root`** (full chain trie).
- **`OverlayProof`** → same root choice as membership when reading keys under the overlay trie.

**3. EVM batch delivery**

- Solidity checks **MMR multiproofs** against **`overlayRoot`** on the stored commitment. For Hyperbridge, that value **is** the **`mmr_root`**.

---

## Scenario summary

| Scenario | What you prove | Root |
|----------|----------------|------|
| Substrate membership of ISMP commitments | Child trie (overlay proof) | `overlay_root` on normal chains; **`state_root`** when the target is Hyperbridge coprocessor (still the child trie). |
| Arbitrary storage read | Main trie | **`state_root`** with `StateProof`. |
| POST batch to EVM | MMR | **`overlayRoot`** = **`mmr_root`** for Hyperbridge; MMR multiproof. |
| “What commits the whole chain?” | — | **`state_root`**. |

**Mnemonic:** **`state_root`** = entire chain state; **child trie** = compact ISMP commitment/receipt trie; **`mmr_root`** = ordered message log for succinct proofs—on Hyperbridge exposed to MMR-speaking clients as **`overlay_root`**.

Related (Polkadot transport vs commitments): [Polkadot XCMP MMD — Minimal POC (merged)](/post/2026-04-09-xcmp-mmd-minimal-poc/).

---

## Why a child trie for request/response data

ISMP stores commitment metadata under `ChildInfo::new_default("ISMP")` because **child tries yield cheaper Patricia proofs** than proving through the global state trie (`child_trie.rs` module comment).

- **Smaller proofs** — only the ISMP subtree, not paths under the full **`state_root`**.
- **Separation** — `OverlayProof` vs `StateProof`; one **`child_trie_root`** in the digest.
- **Cross-chain verifiers** — `read_child_proof` targets the child trie; less data than full-state proofs.

---

## Coprocessor vs non-coprocessor

`Coprocessor: Get<Option<StateMachine>>` names an optional **ISMP proxy** (usually Hyperbridge). See [ISMP proxies](https://docs.hyperbridge.network/protocol/ismp/proxies).

| | Non-coprocessor | Coprocessor |
|--|-----------------|-------------|
| Config | `None` | `Some(Hyperbridge)` |
| `StateCommitment` | `overlay_root` = child trie; `state_root` = header | swapped: `overlay_root` = MMR, `state_root` = child trie |
| Overlay proof root | `state.overlay_root` | For proofs about Hyperbridge id, `state.state_root` (= child trie in that encoding) |

Non-coprocessor: no single proxy. Coprocessor: heavy verification aggregated on Hyperbridge; downstream uses cheaper proofs / proxy routing (`allowed_proxy()` = coprocessor).

---

## Why two paths — child trie vs MMR

Not two redundant proofs of the same fact.

| Path | Proves | Typical use |
|------|--------|---------------|
| Child trie (`OverlayProof`) | Commitment **stored** in pallet state (metadata, fees, index). | Substrate `verify_membership` |
| MMR | Commitment as **leaf in the message log** for relay / batch delivery. | EVM handler vs `overlayRoot` (MMR root on Hyperbridge) |

Trie = **state** registration; MMR = **ordered relay log**. Destinations usually require **one** style, not both. Same commitment hash, two structures for different verifiers and costs.

---

## Verifying a `LayoutV0` storage proof

**`LayoutV0<H>`** (`sp_trie`) is the Substrate Patricia trie layout; **`H`** is the node hasher (must match the source chain). Ethereum storage uses a different layout (e.g. **`EIP1186Layout`** in `modules/trees/ethereum` — RLP / EIP-1186), not `LayoutV0`.

Verification pattern in `SubstrateStateMachine` (`modules/ismp/state-machines/substrate/src/lib.rs`):

1. `StorageProof::new(nodes).into_memory_db::<H>()`
2. `TrieDBBuilder::<LayoutV0<H>>::new(&db, &root).build()`
3. `trie.get(&key)` — check value

Used by `verify_membership` and `verify_state_proof`. Helpers: `read_proof_check`, `read_proof_check_for_parachain` in the same file. Test: `modules/pallets/testsuite/src/tests/child_trie_proof_check.rs`.

---

## EVM: `OptimismHost` has no verification

**`OptimismHost`** (`evm/src/hosts/Optimism.sol`) only sets **`CHAIN_ID`** and inherits **`EvmHost`**.

**`EvmHost`** holds ISMP state and delegates **all** proof logic to **`HostParams.handler`** (usually **`HandlerV1`**).

**`HandlerV1`**: `handleConsensus` → **`IConsensus.verifyConsensus`** (deployed **`consensusClient`**, e.g. BEEFY under `evm/src/consensus/`); `handlePostRequests` → **MMR** verify vs **`overlayRoot`**, then `dispatchIncoming`.

Incoming messages from Substrate (e.g. Bifrost via Hyperbridge) are proved on L2 with **Hyperbridge MMR + consensus updates**, not with custom code in `OptimismHost`.

---

## `IConsensus` on EVM (BEEFY stack)

**Interface:** `sdk/packages/core/contracts/interfaces/IConsensus.sol` — `verifyConsensus(trustedState, proof) → (newState, IntermediateState[])`.

Implementations under `evm/src/consensus/`: **`ConsensusRouter`** (first proof byte → **BeefyV1** naive, **SP1Beefy** ZK, **BeefyV1FiatShamir**); **`BeefyV1`** verifies relay **BEEFY/MMR** update + **parachain header** proofs and returns **`IntermediateState`**. Deployed address is **`HostParams.consensusClient`**; **`HandlerV1.handleConsensus`** calls it.

---

## Two MMRs (relay vs message)

**Relay BEEFY MMR** — checked in **`BeefyV1.verifyMmrUpdateProof`** (`RelayChainProof`): Polkadot relay finality / authority / relay MMR. **Not** “this ISMP message exists.”

**Hyperbridge message MMR** — checked in **`HandlerV1.handlePostRequests`** against **`overlayRoot`**: ISMP request leaves on Hyperbridge. **Not** the same tree as the relay MMR.

Order: **`handleConsensus`** (trust roots) → **`handlePostRequests`** (message MMR membership).
