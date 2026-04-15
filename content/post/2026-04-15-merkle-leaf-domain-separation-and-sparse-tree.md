---
title: "Merkle 叶子哈希、域分离与稀疏树证明（MerkleDropHelper）"
date: 2026-04-15
draft: false
tags: ["cryptography", "ethereum", "merkle", "security"]
---

## 结论速记

- **关键不是“多 hash 一次更强”**：`keccak256(keccak256(...))` 的主要价值在于**域分离（domain separation）**，让“叶子哈希”和“内部节点哈希”的构造形状不同，避免 Merkle 结构里的“角色混淆”讨论。
- **更标准**：显式前缀（leaf/internal）通常比 `~hash` 或双 keccak 更容易被审计/跨语言实现接受。
- **验证端必须逐字对齐**：叶子公式、内部节点哈希顺序（是否排序）、稀疏缺失节点默认值（0）必须完全一致。

## `keccak256(keccak256(abi.encode(member, amount)))` 是否足以避免 second preimage？

在 Merkle 语境里，大家常担心的不是去破 Keccak 的 preimage，而是：

- 叶子与内部节点若缺少明确区分，理论上会讨论“能否拿某个内部节点值来冒充叶子值”造成**叶子/内部节点角色混淆**。

若内部节点固定为：

```solidity
parent = keccak256(abi.encode(min(left, right), max(left, right)));
```

那么把叶子定义成：

```solidity
leaf = keccak256(keccak256(abi.encode(member, amount)));
```

通常可视为足够的**域分离**：叶子是“对 32 字节 digest 再 hash”，内部节点是“对两个 digest（排序后）再 hash”，两者在构造形态上可区分。

更常见、更直观的域分离写法是显式前缀：

```solidity
leaf   = keccak256(abi.encodePacked(uint8(0x00), member, amount));
parent = keccak256(abi.encodePacked(uint8(0x01), min(left,right), max(left,right)));
```

## `MerkleDropHelper` 代码解读（稀疏 + 排序哈希）

### `constructTree(members, claimAmounts)`

- **树高**：不断把 \(n\) 变成 \(\lceil n/2 \rceil\) 直到 0，得到层数 `height`。
- **叶子层**：每个叶子为：

```solidity
nodes[i] = ~keccak256(abi.encode(members[i], claimAmounts[i]));
```

`~`（按位取反）是一个“与内部节点区分开”的技巧（非标准，但能达到域分离目标的一种实现）。

- **内部节点**：缺失的右孩子视为 `bytes32(0)`（稀疏），并且兄弟始终按排序顺序哈希：

```solidity
hashes[i / 2] = keccak256(a > b ? abi.encode(b, a) : abi.encode(a, b));
```

### `createProof(memberIndex, tree)`

- `memberIndex` 是叶子数组中的下标。
- 每层取兄弟下标：偶数取 `+1`，奇数取 `-1`；越界则该层 sibling 为 `0`（稀疏默认值）。
- `leafIndex /= 2` 上移继续。

### 验证端必须满足的三条

要写 `verify(member, amount, index, proof, root)`，必须与建树逻辑一致：

- 叶子：同一公式（这里是 `~keccak256(abi.encode(...))`；若你换成双 keccak/前缀，两端一起换）。
- 父节点：同样的 sibling 排序规则。
- 缺失 sibling：按 `0` 参与计算。

## `MerkleDropHelper` 源码

```solidity
contract MerkleDropHelper {
    // Construct a sparse merkle tree from a list of members and respective claim
    // amounts. This tree will be sparse in the sense that rather than padding
    // tree levels to the next power of 2, missing nodes will default to a value of
    // 0.
    function constructTree(
        address[] memory members,
        uint256[] memory claimAmounts
    )
        external
        pure
        returns (bytes32 root, bytes32[][] memory tree)
    {
        require(members.length != 0 && members.length == claimAmounts.length);
        // Determine tree height.
        uint256 height = 0;
        {
            uint256 n = members.length;
            while (n != 0) {
                n = n == 1 ? 0 : (n + 1) / 2;
                ++height;
            }
        }
        tree = new bytes32[][](height);
        // The first layer of the tree contains the leaf nodes, which are
        // hashes of each member and claim amount.
        bytes32[] memory nodes = tree[0] = new bytes32[](members.length);
        for (uint256 i = 0; i < members.length; ++i) {
            // Leaf hashes are inverted to prevent second preimage attacks.
            nodes[i] = ~keccak256(abi.encode(members[i], claimAmounts[i]));
        }
        // Build up subsequent layers until we arrive at the root hash.
        // Each parent node is the hash of the two children below it.
        // E.g.,
        //              H0         <-- root (layer 2)
        //           /     \
        //        H1        H2
        //      /   \      /  \
        //    L1     L2  L3    L4  <--- leaves (layer 0)
        for (uint256 h = 1; h < height; ++h) {
            uint256 nHashes = (nodes.length + 1) / 2;
            bytes32[] memory hashes = new bytes32[](nHashes);
            for (uint256 i = 0; i < nodes.length; i += 2) {
                bytes32 a = nodes[i];
                // Tree is sparse. Missing nodes will have a value of 0.
                bytes32 b = i + 1 < nodes.length ? nodes[i + 1] : bytes32(0);
                // Siblings are always hashed in sorted order.
                hashes[i / 2] = keccak256(a > b ? abi.encode(b, a) : abi.encode(a, b));
            }
            tree[h] = nodes = hashes;
        }
        // Note the tree root is at the bottom.
        root = tree[height - 1][0];
    }

    // Given a merkle tree and a member index (leaf node index), generate a proof.
    // The proof is simply the list of sibling nodes/hashes leading up to the root.
    function createProof(uint256 memberIndex, bytes32[][] memory tree)
        external
        pure
        returns (bytes32[] memory proof)
    {
        uint256 leafIndex = memberIndex;
        uint256 height = tree.length;
        proof = new bytes32[](height - 1);
        for (uint256 h = 0; h < proof.length; ++h) {
            uint256 siblingIndex = leafIndex % 2 == 0 ? leafIndex + 1 : leafIndex - 1;
            if (siblingIndex < tree[h].length) {
                proof[h] = tree[h][siblingIndex];
            }
            leafIndex /= 2;
        }
    }
}
```

