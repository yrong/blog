# Investigation Report: Psy Protocol (With References)

**Project Overview & Background**
[Psy Protocol](https://psy.xyz/) (formerly known as [QED Protocol](https://qedprotocol.com/)) is a trustless, horizontally scalable Layer-1 blockchain and ZK-rollup network. Founded by Carter Jack Feldman, the project has secured substantial backing from prominent venture capital firms including Blockchain Capital, Arrington Capital, StarkWare, and Anagram. Its core mission is to enable internet-scale throughput for Web3 applications (such as high-frequency orderbook exchanges and agentic AI payments) while inheriting the base-layer security of Proof-of-Work networks like Bitcoin and Dogecoin. 

---

### 1. `psy_vm`: A Domain-Specific zkVM
Unlike general-purpose zero-knowledge virtual machines (zkVMs) like RISC Zero or SP1, which emulate standard CPU architectures (like RISC-V) to run Rust or C++ code, `psy_vm` abandons general-purpose emulation entirely. 
* **High-Level Language Support:** The `psy-compiler` natively supports JavaScript, TypeScript, Python, and a custom Psy Domain-Specific Language (DSL).
* **Direct Constraint Generation:** Instead of compiling these languages into standard machine instructions (opcodes), the compiler translates them directly into highly optimized mathematical logic circuits and constraints.
* **The Goldilocks Field vs. Baby Bear:** `psy_vm`'s cryptographic backend operates strictly over the 64-bit Goldilocks prime field. Because this field perfectly fits standard 64-bit CPU registers, it enables **client-side local proving** with minimal latency directly on consumer devices (like mobile phones or browsers).

### 2. The PARTH State Model (Parallel Trading)
Psy Protocol circumvents the "sequential processing prison" of traditional blockchains via its PARTH (Parallel Arithmetic Recursive Turing-complete Hybrid) state model.
* **Elimination of Global State Contention:** Traditional chains force all transactions to wait in a single line to update a global ledger. In PARTH, every user maintains their own individualized local state tree (UCON). 
* **Local Execution & Encrypted Deltas:** When a user transacts, the transaction executes locally on their device via the `psy-prover` ([GitHub Link](https://github.com/PsyProtocol/psy-prover)). The client generates a zero-knowledge execution trace and an encrypted "state delta". 
* **Asynchronous Global Aggregation:** The network uses "Proof of Useful Work" to recursively compress millions of these local zero-knowledge proofs in parallel into a single, succinct block proof. This passively updates the global state, completely avoiding execution bottlenecks.

### 3. Bitcoin L1 Verification & BitVM Architecture
While Psy operates locally at massive scale, it uses Bitcoin's Layer-1 for settlement security—specifically targeting **withdrawal transactions** that move assets from the L2 rollup back to Bitcoin.
* **BitVM Principles:** Because Bitcoin Core lacks native opcodes to verify ZK proofs, Psy translates its verification logic into massive logic circuits built from primitive Bitcoin Script opcodes, inspired by BitVM.
* **1,000 UTXO Sharding:** Since a complete ZK verifier script is too large to fit into a Bitcoin block, the protocol distributes the logic circuit across approximately 1,000 Unspent Transaction Outputs (UTXOs). Using Taproot, these scripts are efficiently committed to the blockchain, allowing Psy to achieve direct cryptographic verification on Bitcoin L1 without requiring any network hard forks.

### 4. Cross-Chain Expansions: Dogecoin & Solana
Psy Protocol is heavily involved in expanding its infrastructure beyond Bitcoin:
* **Dogecoin Scaling:** Psy partnered with Nexus to launch a zkVM on Dogecoin. This involves a proposed new operation code, `OP_CHECKGROTH16VERIFY`, which would allow Dogecoin to natively verify Groth16 proofs, paving the way for Dogecoin-native smart contracts, DEXs, and NFTs.
* **Trustless Bridging:** The protocol has open-sourced infrastructures like `psy-doge-solana-bridge` ([GitHub Link](https://github.com/PsyProtocol/psy-doge-solana-bridge)) and `doge-on-solana` ([GitHub Link](https://github.com/PsyProtocol/doge-on-solana)), which run full Dogecoin consensus verification within the Solana execution environment. This enables trust-minimized, zero-knowledge bridges.

### 5. Developer Ecosystem Status
* **Open Source Stack:** The core infrastructure, including `psy-compiler` ([GitHub Link](https://github.com/PsyProtocol/psy-compiler)), `psy-prover` ([GitHub Link](https://github.com/PsyProtocol/psy-prover)), and `psy-sdk` ([GitHub Link](https://github.com/PsyProtocol/psy-sdk)), is completely open-source under the [Psy Protocol GitHub Organization](https://github.com/psyprotocol). 
* **Tutorials & IDE:** Official developer guides (such as the "Smart Contract 0-to-1" tutorial) and the planned Dapen Browser IDE are currently listed as "Coming Soon". Web3 developers looking to build immediately must rely on exploring the raw GitHub repositories until the official SDK documentation goes live.

---

### Reference Links
Here is a consolidated list of the official references and news reports covering the protocol:

**Official Resources & Codebases**
* **Official Website:** [psy.xyz](https://psy.xyz/) | [qedprotocol.com](https://qedprotocol.com/)
* **GitHub Organization:** [github.com/psyprotocol](https://github.com/psyprotocol)
* **Psy Wallet (Chrome Web Store):** [Psy Wallet Extension](https://chromewebstore.google.com/detail/psy-wallet/gkjbpipdcdijofkbpoefkpgoaameonal)
* **RootData Profile:** [Psy Protocol Project Data](https://www.rootdata.com/projects/detail/Psy%20Protocol?k=OTE3MQ%3D%3D)

**News & Press Releases**
* **CryptoBriefing:** [Psy Protocol testnet combines internet scale and speed with Bitcoin-level security](https://cryptobriefing.com/psy-protocol-testnet-combines-internet-scale-and-speed-with-bitcoin-level-security/)
* **Business Wire:** [QED Protocol Raises $6 Million for Scaling with Bitcoin-powered Tech](https://www.businesswire.com/news/home/20240703164257/en/QED-Protocol-Raises-%246-Million-for-Scaling-with-Bitcoin-powered-Tech)
* **Business Wire:** [QED Protocol Partners with Nexus to Scale Dogecoin](https://www.businesswire.com/news/home/20240926951226/en/QED-Protocol-Partners-with-Nexus-to-Scale-Dogecoin)
* **Business Wire:** [QED Releases First ZK Rollup on Dogecoin](https://www.businesswire.com/news/home/20240729606338/en/QED-Releases-First-ZK-Rollup-on-Dogecoin)
* **Nexus Blog:** [Nexus Partners with QED Protocol to Scale Dogecoin](https://blog.nexus.xyz/qed/)
