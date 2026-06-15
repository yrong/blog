---
author: Ron
date: 2023-08-15T11:12:00+08:00
tags:
- zcash
- privacy
- zk-snark
- cryptography
- proof-of-work
title: "Investigation Report: Zcash"
---

## Project Overview & Background

Zcash is a decentralized protocol and privacy-protecting digital currency designed to function as encrypted electronic cash. It holds the distinction of being the first cryptocurrency to pioneer and implement zero-knowledge encryption specifically for private peer-to-peer payments. Its core mission is to protect users' right to privacy through end-to-end encryption, ensuring that individuals retain full control over their funds without relying on traditional banks.

<!--more-->

## 1. Core Technology: Zero-Knowledge Proofs

While many modern networks use Zero-Knowledge Proofs (ZKPs) to scale execution, Zcash utilizes ZKPs (specifically zk-SNARKs) strictly for **financial privacy**. 

* **Shielded Transactions:** When a user sends Zcash (ZEC), the cryptographic proof guarantees that the transaction is valid while completely shielding the sender, receiver, and transaction amount from the public network. 
* **Encrypted Memos:** The protocol allows users to attach secret, encrypted messages alongside their financial transactions.

### Comparison: Transparent vs. Shielded Addresses

Zcash supports both transparent addresses (like Bitcoin) and fully shielded addresses:

| Feature | Transparent Addresses (`t-address`) | Shielded Addresses (`z-address`) |
| :--- | :--- | :--- |
| **Sender Visibility** | Publicly visible on blockchain | Hidden / Shielded |
| **Recipient Visibility** | Publicly visible on blockchain | Hidden / Shielded |
| **Transaction Value** | Publicly visible on blockchain | Hidden / Shielded |
| **Encrypted Memo** | Not supported | Supported |
| **Cryptography** | Standard ECDSA | zk-SNARK (Halo 2 / Orchard) |

---

## 2. Network Architecture & Consensus

Unlike newer Layer-1 networks that rely on localized state trees or sharding, Zcash maintains a more orthodox infrastructure:

* **Global Ledger:** Zcash relies on a traditional blockchain architecture with a single global ledger. All transactions, even though they are shielded, must be sequentially ordered and processed by the network to prevent double-spending.
* **Proof-of-Work (PoW):** The network is secured by a standard Proof-of-Work consensus mechanism, similar to Bitcoin, where miners dedicate computational power to solving cryptographic puzzles.

---

## 3. Practical Tutorial: Shielded Transactions via the CLI

Below is a step-by-step tutorial for interacting with Zcash's shielding mechanics using `zcash-cli`:

### Step 1: Generate Addresses
Generate a standard transparent address and a private shielded address:
```bash
# Generate a transparent address (t-address)
zcash-cli getnewaddress

# Generate a shielded address (z-address)
zcash-cli z_getnewaddress
```

### Step 2: Send a Shielded Transaction
To move ZEC from a transparent address to a shielded address (shielding the funds), use `z_sendmany`:
```bash
zcash-cli z_sendmany \
  "t1TransparentAddressExample..." \
  '[{"address": "zs1ShieldedAddressExample...", "amount": 0.1, "memo": "54686973206973206120736563726574"}]'
```
*(Note: The memo field is a hex-encoded string. The string above represents `"This is a secret"`).*

### Step 3: Check Transaction Status
Since shielded transactions are asynchronous, `z_sendmany` returns an operation ID. Query the status like so:
```bash
zcash-cli z_getoperationstatus '["opid-12345678-abcd-1234-abcd-1234567890ab"]'
```

---

## 4. Proving Systems: Halo 2 & The Elimination of the Trusted Setup

The evolution of Zcash's cryptographic proving systems is one of the most significant achievements in applied cryptography:

```
[Sprout Upgrade (2016)]
  └── Proving System: BCTV14
  └── Trusted Setup Required: Multi-Party Ceremony
       │
[Sapling Upgrade (2018)]
  └── Proving System: Groth16
  └── Trusted Setup Required: Smaller Ceremony, Massive Performance Boost
       │
[Orchard Upgrade / NU5 (2022)]
  └── Proving System: Halo 2
  └── Trusted Setup: ELIMINATED (Trustless)
```

### Why Eliminating the Trusted Setup Matters
Older zk-SNARK proving systems required a one-time "trusted setup" to generate the structured reference string (SRS) parameters. If the setup participants colluded or the secrets were exposed, bad actors could generate false proofs to inflate the currency supply undetected.

With the **Halo 2** proving system, Zcash eliminated the trusted setup entirely. It achieves this by using:
1. **PLONKish Arithmetization:** Allowing customizable constraints and lookup arguments for high-speed circuit design.
2. **Inner Product Argument (IPA):** A polynomial commitment scheme based on discrete log assumptions (similar to Bulletproofs) that does not require a trusted setup.
3. **Recursive Proof Composition:** Accumulator-based recursive verification that compresses a chain of proofs into a single proof without requiring a pairing-friendly elliptic curve.

---

## 5. Use Case & Programmability 

Compared to general-purpose networks (like Ethereum, Polkadot, or Psy Protocol) which compile highly complex smart contracts into massive logic circuits, **Zcash intentionally has limited programmability**. It does not attempt to serve as a hyper-scalable global computer; rather, it remains hyper-focused on its primary utility: serving as the ultimate secure and private medium of exchange.
