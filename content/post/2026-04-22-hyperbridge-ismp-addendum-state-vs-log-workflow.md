---
author: Ron
catalog: true
date: 2026-04-22
tags:
- BlockChain
- Polkadot
- Hyperbridge
- ISMP
title: Hyperbridge ISMP — state vs log, coprocessor GET flow, and relayer queue
---

This post **supplements** [Hyperbridge ISMP — state_root, overlay_root, and mmr_root](/post/2023-04-11-hyperbridge-ismp-state-overlay-mmr/) with a consolidated “root map + workflow” view, **new framing** (trie vs MMR as **state vs log**, not a Substrate-vs-EVM split), and notes from reading `pallet_state_coprocessor` and Tesseract EVM messaging.

Repo context: [`polytope-labs/hyperbridge`](https://github.com/polytope-labs/hyperbridge).

---

## TL;DR (one paragraph)

Hyperbridge keeps **two “views” of the same ISMP object**, keyed by the same **commitment hash**:

- a compact **ISMP child trie** (Patricia / Substrate `LayoutV0`) for **pallet state**: commitment metadata, receipt bookkeeping, claim/fee data, and pointers into the offchain log
- an append-only **message MMR** (ordered log) for **history + succinct inclusion** proofs (and relayer/EVM batch verification)

The commitment hash of a request/response is **not** stored twice as separate unrelated facts: it is used as a **key** in the trie and as a **member** of the MMR log, but the **stored payloads differ** (trie = operational metadata; MMR = message log membership).

**Role split (keep this mental model):** trie proofs answer **“does this key exist in state, and with what app metadata?”**; MMR proofs answer **“is this message in the ordered log at this place?”** — that is **state vs log**, not a clean “Substrate uses trie, Ethereum uses MMR” rule.

On the EVM side, Solidity verifies message inclusion against `StateCommitment.overlayRoot`, which—**for Hyperbridge as coprocessor**—is the **message MMR root** (not the relay-chain BEEFY MMR).

---

## ISMP child trie vs message MMR (is this duplication?)

**Short answer: yes, intentionally redundant indexing — not “two copies of the same bytes in two merkle trees for no reason.”**

- **Child trie (overlay child trie)**
  - “Database index” in Substrate state for ISMP: did we record a commitment, who delivered it, is it claimed, what fee metadata exists, where is the offchain leaf, etc.
  - Proofs are **trie / Patricia proofs** to keys derived from the commitment.
- **Message MMR**
  - “Append-only message history” (requests/responses) where inclusion is proven with **MMR multiproofs** (what EVM `HandlerV1` typically checks for batch delivery to Solidity).

**What the MMR leaf “contains” (conceptual):** it corresponds to a full `Request` / `Response` object (or its hash commitment), which already embeds `source/dest/nonce/...` as part of the message encoding. The proof path is “this hash is a leaf in the MMR at this index/position,” not a separate second preimage.

---

## Trie vs MMR: it’s **state vs log**, not “Substrate vs Ethereum”

The useful split is:

- **Trie proofs (main trie + ISMP child trie)**: prove **key existence / absence** in Substrate state — membership of commitment records, receipts, fee metadata, “not yet handled” timeout checks, etc.
- **MMR proofs**: prove **inclusion in an append-only message log** — the canonical ordered history of requests/responses for succinct batching and cheap on-chain verification.

**Not a hard platform rule:**

- Substrate integrators still frequently fetch **MMR proofs** (e.g. `mmr_queryProof`) when the *verifier on the other side* is an EVM host that checks `overlayRoot` via MMR multiproofs.
- EVM integrators still care about **receipt/commitment state** on the host contract, but for *message delivery* the handler’s common path is **MMR inclusion** against `overlayRoot` (for Hyperbridge coprocessor: the message MMR root).

So: **trie = state/index layer; MMR = log/history layer** — both can appear in both worlds, depending on what you’re proving *to*.

---

## The three roots you will see (and what they actually mean)

| Root name you see | What it commits to | Where it lives |
|---|---|---|
| **Substrate `Header::state_root`** | full chain state (all pallets) | block header |
| **ISMP child trie root** (`child_trie_root`) | ISMP child trie subtree (commitments/receipts metadata) | header digest (`ConsensusDigest`) |
| **ISMP message MMR root** (`mmr_root`) | append-only message log of request/response leaves | header digest (`ConsensusDigest`) |

### How they are packed into `StateCommitment`

`StateCommitment` only has `state_root` + optional `overlay_root`, so the parachain client packs digest fields into those slots. There are two regimes:

**Ordinary parachain (not coprocessor):**

- `state_root` = header `state_root` (full trie)
- `overlay_root` = `child_trie_root`

**Hyperbridge as coprocessor:**

- `state_root` = `child_trie_root`
- `overlay_root` = `mmr_root`

So on Hyperbridge, **`overlay_root` is the message MMR root**.

---

## What `overlayRoot` means on EVM (the exact question)

In `HandlerV1.handleGetResponses`:

```solidity
bytes32 root = host.stateMachineCommitment(message.proof.height).overlayRoot;
bool valid = MerkleMountainRange.VerifyProof(root, message.proof.multiproof, leaves, message.proof.leafCount);
```

`overlayRoot` here is **the Hyperbridge ISMP message overlay MMR root** for the referenced Hyperbridge height.

It is **not** the Polkadot relay-chain/BEEFY MMR root.

Relationship:

1) relay-chain finality proof ⇒ EVM consensus client accepts a Hyperbridge `StateCommitment`  
2) that `StateCommitment.overlayRoot` ⇒ used by the handler to verify message leaves (requests/responses) via MMR

---

## Hyperbridge coprocessor GET workflow (end-to-end)

This is the flow we confirmed while reading `pallet_state_coprocessor`:

### 1) Source chain initiates a `GetRequest`

The request exists on the source chain and is committed into the source’s ISMP state (so it can be proven later).

### 2) Relayer (Tesseract) observes GETs and assembles proofs

Tesseract groups GETs and fetches:

- a **source proof** that the GET request(s) were committed on the source chain at a finalized height
- a **destination storage proof** for the requested keys at `GetRequest.height`

Then it submits **one unsigned message** to Hyperbridge:

- `GetRequestsWithProof { requests, source, response, address }`

### 3) Hyperbridge verifies and certifies the response locally

`pallet_state_coprocessor::handle_unsigned(GetRequestsWithProof)` verifies both proofs, constructs `GetResponse { get, values }`, then calls:

- `dispatch_get_response(get_response, address)`

**What `dispatch_get_response` does (important):**

- inserts the `GetResponse` as a **response leaf** into the coprocessor’s **MMR** (offchain overlay tree)
- writes `ResponseCommitments[response_commitment] -> (leaf index + position + metadata)`
- marks `Responded[request_commitment] = true`
- emits:
  - `pallet_ismp::Event::Response { commitment, req_commitment, ... }`
  - `pallet_ismp::Event::GetRequestHandled { commitment: req_commitment, relayer: address }`

It does **not** “send a response to the source chain” by itself. It certifies/records on Hyperbridge; consumers can then prove or read it.

---

## Consuming Hyperbridge-certified GET responses

You usually consume the certification via either:

1) **Substrate runtime API + node RPC** (fetch full response + proof material), or  
2) **EVM Host/Handler delivery** (MMR proof checked on-chain, then app callback invoked).

### A) Substrate consumption (runtime API + node RPC)

From a Substrate client you can:

- **Read events**:
  - runtime API: `IsmpRuntimeApi::block_events()` / `block_events_with_metadata()`
  - node RPC wrapper: `ismp_queryEvents*`

- **Fetch full response objects**:
  - runtime API: `IsmpRuntimeApi::responses([commitment])`
  - node RPC wrapper: `ismp_queryResponses`

The runtime loads the response by using `ResponseCommitments` → offchain leaf position → fetch leaf (`Leaf::Response(...)`).

- **Fetch proofs (what you fetch depends on what the *verifier* checks):** see the section *Trie vs MMR: it’s state vs log, not “Substrate vs Ethereum”* above.
  - to satisfy an **MMR / log inclusion** check (typical for `HandlerV1` on EVM), fetch an **MMR proof**:
    - RPC: `mmr_queryProof(at, ProofKeys::Responses([commitment]))`
  - to satisfy a **state / child-trie key** check (trie proof), fetch a **child-trie proof**:
    - RPC: `ismp_queryChildTrieProof(at, [ResponseCommitments::storage_key(commitment)])`

### B) EVM consumption (EvmHost + Handler)

On EVM, the verifier is typically `HandlerV1` (set as `HostParams.handler`). Delivery looks like:

1. relayer submits a `GetResponseMessage` to `HandlerV1.handleGetResponses(host, message)`
2. handler checks challenge period, request existence, replay protection
3. handler verifies MMR multiproof against:
   - `host.stateMachineCommitment(message.proof.height).overlayRoot`
   - which for Hyperbridge coprocessor is **the Hyperbridge message MMR root**
4. if valid, handler calls `host.dispatchIncoming(GetResponse, relayer)`
5. `EvmHost.dispatchIncoming(GetResponse, relayer)` calls the app’s:
   - `IApp.onGetResponse(IncomingGetResponse(response, relayer))`

---

## Tesseract relayer: what `submit()` and the queue pipeline really do (EVM)

In `tesseract/messaging/evm`, `submit(messages)` is just:

- “put `Vec<Message>` into a pipeline queue and wait”

The queue is created with `start_pipeline`, and the handler is:

- `handle_message_submission(&client, messages)` (`tesseract/messaging/evm/src/tx.rs`)

That handler:

1) converts messages into EVM contract calls (calldata) for the **Handler** contract  
2) signs/sends transactions  
3) extracts `*Handled` events from receipts and returns `TxResult`

Crucially: **proof bytes are already inside the `Message` objects** by the time `submit()` is called; the queue just turns those messages into actual on-chain submissions.
