---
author: Ron
date: 2026-06-15T00:13:00+08:00
tags:
- bitcoin
- dogecoin
- zk-rollup
- cryptography
- bitvm
- psy-protocol
title: "Investigation Report: Psy Protocol"
---

## Project Overview & Background

Psy Protocol (formerly known as QED Protocol) is a trustless, horizontally scalable Layer-1 blockchain and ZK-rollup network<sup>1, 2</sup>. Founded by Carter Jack Feldman, the project has secured substantial backing from prominent venture capital firms including Blockchain Capital, Arrington Capital, StarkWare, and Anagram<sup>1, 3</sup>. Its core mission is to enable internet-scale throughput for Web3 applications (such as high-frequency orderbook exchanges and agentic AI payments) while inheriting the base-layer security of Proof-of-Work networks like Bitcoin and Dogecoin<sup>2, 4, 5</sup>.

<!--more-->

## 1. psy_vm: A Domain-Specific zkVM

Unlike general-purpose zero-knowledge virtual machines (zkVMs) like RISC Zero or SP1, which emulate standard CPU architectures (like RISC-V) to run Rust or C++ code, psy_vm abandons general-purpose emulation entirely<sup>4, 6</sup>.

* **High-Level Language Support:** The psy-compiler natively supports JavaScript, TypeScript, Python, and a custom Psy Domain-Specific Language (DSL)<sup>4, 7</sup>.
* **Direct Constraint Generation:** Instead of compiling these languages into standard machine instructions (opcodes), the compiler translates them directly into highly optimized mathematical logic circuits and constraints<sup>7, 8</sup>.
* **The Goldilocks Field vs. Baby Bear:** While systems like RISC Zero utilize the Baby Bear field and rely heavily on server-side or cloud-based GPU/FPGA proof generation, psy_vm's cryptographic backend (Plonky2) operates strictly over the 64-bit Goldilocks prime field ($p = 2^{64} - 2^{32} + 1$)<sup>4, 8, 9</sup>. Because this field perfectly fits standard 64-bit CPU registers, it enables client-side local proving with minimal latency directly on consumer devices (like mobile phones or browsers)<sup>6, 9</sup>.

## 2. The PARTH State Model (Parallel Trading)

Psy Protocol circumvents the "sequential processing prison" of traditional blockchains (like Ethereum) via its PARTH (Parallel Arithmetic Recursive Turing-complete Hybrid) state model<sup>10, 11</sup>.

* **Elimination of Global State Contention:** Traditional chains force all transactions to wait in a single line to update a global ledger. In PARTH, every user maintains their own individualized local state tree (UCON)<sup>10</sup>.
* **Local Execution & Encrypted Deltas:** When Alice transacts with Bob, her transaction executes locally on her device via the psy-prover<sup>10</sup>. The client generates a zero-knowledge execution trace and an encrypted "state delta" proving the balance transfer<sup>10</sup>.
* **Asynchronous Global Aggregation:** These local state deltas are sent to network miners. The network uses "Proof of Useful Work" to recursively compress millions of these local zero-knowledge proofs in parallel into a single, succinct block proof<sup>7, 11</sup>. This updates a global Merkle Root, and Bob's personal tree is updated passively and asynchronously the next time he syncs with the network, completely avoiding execution bottlenecks.

## 3. Bitcoin L1 Verification & BitVM Architecture

While Psy operates locally at massive scale, it uses Bitcoin's Layer-1 for settlement security—specifically targeting withdrawal transactions that move assets from the L2 rollup back to Bitcoin<sup>2</sup>.

* **BitVM Principles:** Because Bitcoin Core lacks native opcodes to verify Plonky2 ZK proofs, Psy translates its verification logic into massive logic circuits built from primitive Bitcoin Script opcodes, inspired by BitVM<sup>12</sup>.
* **1,000 UTXO Sharding:** Since a complete ZK verifier script is too large (e.g., 20MB) to fit into a 4MB Bitcoin block, the protocol distributes the logic circuit across approximately 1,000 Unspent Transaction Outputs (UTXOs)<sup>12, 13</sup>. Using Taproot, these scripts are efficiently committed to the blockchain, allowing Psy to achieve direct cryptographic verification on Bitcoin L1 without requiring any network hard forks<sup>12</sup>.

## 4. Cross-Chain Expansions: Dogecoin & Solana

Psy Protocol is heavily involved in expanding its infrastructure beyond Bitcoin:

* **Dogecoin Scaling:** Psy partnered with Nexus to launch a zkVM on Dogecoin. This involves a proposed new operation code, `OP_CHECKGROTH16VERIFY`, which would allow Dogecoin to natively verify Groth16 proofs, paving the way for Dogecoin-native smart contracts, DEXs, and NFTs<sup>5, 14, 15</sup>.
* **Trustless Bridging:** The protocol has open-sourced infrastructures like `psy-doge-solana-bridge` and `doge-on-solana`, which run full Dogecoin consensus verification within the Solana execution environment. This enables trust-minimized, zero-knowledge bridges that do not rely on centralized multi-sig wallets<sup>16, 17</sup>.

## 5. Developer Ecosystem Status

* **Open Source Stack:** The core infrastructure, including `psy-compiler`, `psy-prover` (Rust), and `psy-sdk` (TypeScript), is completely open-source<sup>4, 7</sup>. The repositories reveal support for advanced concepts like Software Defined Circuits (SDC).
* **Tutorials & IDE:** Currently, official developer guides (such as "Smart Contract 0-to-1") and the planned Dapen Browser IDE (which will allow in-browser compiling and debugging) are listed as "Coming Soon" by the team. Web3 developers looking to build immediately must rely on exploring the raw GitHub repositories until the official SDK documentation goes live.
