---
author: Ron
catalog: true
date: 2022-02-01
tags:
- BlockChain
- Ethereum
- Solidity
title: Solidity patterns: Assembly Tricks (1)
---

## Solidity 设计模式汇总笔记

本笔记总结了用于优化 Gas 消耗、增强安全性以及改善开发体验的核心 Solidity 编程模式。

### 1. 重入保护模式 (Reentrancy Protection)

问题：当合约发起外部调用时，执行控制权会转移给另一方。攻击者可以利用此机会在原始操作完成前再次调用合约函数，从而导致资产被超额提取。

检查-效果-交互 (CEI) 模式：
- Checks：验证输入参数和初始状态。
- Effects：在进行任何外部调用之前，更新所有的状态变量。
- Interactions：最后再执行外部调用或资产转移。

重入卫兵 (Reentrancy Guards/Mutex)：使用一个布尔标志（如 `nonReentrant` 修饰符）在函数进入时加锁，结束后解锁。如果函数在锁定状态下再次被调用，则交易回滚。

### 2. 存储打包模式 (Packing Storage)

问题：读写 EVM 存储插槽（32 字节）是极其昂贵的操作。

- 自动插槽打包：将多个小于 32 字节的原始类型（如 `uint8`, `bool`, `bytes16`）相邻声明，编译器会将它们压缩进同一个存储插槽以减少 Gas。
- 共定位建议：将经常同时读写的变量定义在一起，以利用 EIP-2929 的“热访问”折扣。
- 类型选择：根据需求选择更小的类型（例如用 `uint40` 表示时间戳，而不是 `uint256`）。

### 3. Permit2 模式

问题：传统 `approve` UX 差（每个协议都要一次授权交易）且存在风险（用户倾向无限授权）。

- 离线签名授权：用户向 Permit2 规范合约授予一次性授权。
- 跨协议共享：之后用户只需签署符合 EIP-712 的离线消息即可授权，集成 Permit2 的协议可共享授权。
- 安全优势：签名包含过期时间，Permit2 合约更简单，通常更易审计。

### 4. 委托调用访问控制 (onlyDelegateCall / noDelegateCall)

问题：代理架构中逻辑合约是独立合约，敏感函数若未限制，可能被直接调用导致严重后果。

- onlyDelegateCall：用 immutable 记录部署地址，通过 `address(this) != DEPLOYED_ADDRESS` 限制只能通过代理的 `delegatecall` 执行。
- noDelegateCall：确保函数不能被 `delegatecall` 调用（常见于防止被代理/克隆复用逻辑，例如 Uniswap V3 风格）。

### 5. 独立授权目标 (Separate Allowance Targets)

问题：协议升级频繁，若用户授权给易变逻辑合约，升级需重授权且逻辑漏洞可能危及已授权资产。

- 职责分离：部署一个极简、稳定的授权目标合约（Allowance Target），用户仅授权给它。
- 动态控制：业务合约向授权合约请求扣款，治理可随时开关业务合约的访问权限。

### 6. 只读委托调用 (Read-only Delegatecall)

问题：`delegatecall` 可能修改状态，且不能直接在 `view` 中使用。

思路：
- 包装在 `staticcall` 中：对自身辅助函数发起 `staticcall`，底层强制只读，即便内部使用 `delegatecall` 也无法修改状态。
- 执行后回滚：执行完 `delegatecall` 后主动 `revert`，撤销状态更改，并通过回滚 payload 捕获返回值。

### 7. “栈过深”解决方法 (Stack Too Deep Workarounds)

问题：EVM 栈只能直接访问顶部 32 个槽位，局部变量/参数过多会导致编译错误。

- IR 编译（`--via-ir`）：让编译器把部分栈变量移入内存。
- 块级作用域：用 `{ ... }` 缩短变量生命周期。
- 内存结构体：把多个变量封装进 `struct memory`，栈上只保留一个指针。
- 离线计算：把复杂计算放链下，链上做验证。

---

## Assembly Tricks (Part 1)（新增）

## 来源

本篇整理自 Dragonfly 的 patterns（`assembly-tricks-1`）：`https://github.com/dragonfly-xyz/useful-solidity-patterns/tree/main/patterns/assembly-tricks-1`。

目标：总结这些 “short & sweet” assembly 技巧的**模式本质**（为什么省 gas/解决什么限制）、**适用边界**与**踩坑点**，方便在生产代码里安全复用。

---

## Pattern 1: Bubble up reverts（原样冒泡 revert data）

### 问题

当你用低级 `call/delegatecall/staticcall` 或 `try/catch` 捕获失败时，会拿到 `bytes memory revertBytes`。常见错误做法：

```solidity
revert(string(revertBytes));
```

这会把“原始 revert data”重新编码成 `Error(string)`，导致错误类型/selector 丢失（也可能破坏自定义 error 的 data）。

### 模式

在 assembly 里直接 `revert(ptr, len)` 抛出**原始 revert data**：

```solidity
assembly { revert(add(revertBytes, 0x20), mload(revertBytes)) }
```

### 使用场景

- 你只想对某些错误做特殊处理，其它错误要“向上透传”；
- 你希望保留自定义 error / Panic / Error(string) 的原始格式，便于上层解码。

### 风险/边界

- 仅对 `memory` 的 `bytes` 直接适用（catch 里的 bytes 通常在 memory）。
- 注意不要在你已经构造了新的错误信息后又混用原始 bytes，避免泄漏或误报。

---

## Pattern 2: Hash two words（两个 word 的 keccak 更便宜写法）

### 问题

`keccak256(abi.encode(x, y))` 会触发 `abi.encode` 分配新内存缓冲区，开销更大。

### 模式

用 scratch space `0x00..0x3f` 直接拼两个 32 字节再 keccak：

```solidity
bytes32 hash;
assembly {
    mstore(0x00, word1)
    mstore(0x20, word2)
    hash := keccak256(0x00, 0x40)
}
```

### 使用场景

- Merkle traversal / pair hashing / 两个 32 字节值组合哈希；
- 你明确知道两段数据在 64 字节内（或严格两个 words）。

### 风险/边界

- 只适用于“固定宽度、固定拼接形态”。如果你原来使用 `abi.encodePacked` 或拼接规则不同，结果会不同。
- scratch space 通常可用，但若你在同一段 assembly 中依赖了 `0x00..0x3f` 的其它值，要小心覆盖。

---

## Pattern 3: Cast between compatible `memory` array types（数组类型零拷贝转型）

### 问题

Solidity 不允许在类型系统层面直接把 `address[]` 当作 `IERC20[]` 之类（即便它们在内存里都是 32-byte slots 的兼容表示）。朴素做法是逐元素复制，浪费 gas。

### 模式

对 `memory` 动态数组：变量本质是指针，直接把指针赋给另一种数组类型。

```solidity
address[] memory a = ...;
IERC20[] memory b;
assembly { b := a }
```

### 使用场景

- 你**确信 bit-level 兼容**（例如 `address` 与 `contract/interface` 视为 20 字节地址存储在 word 里）；
- 需要把某个库函数输入类型“对齐”到你已有数据结构。

### 风险/边界（很重要）

- 只适用于 `memory` 数组；`calldata` 的指针语义不同，不能这样搞。
- 兼容性必须严格成立：例如 `uint256[]` 与 `bytes32[]` 的 slot 是兼容的，但若元素类型有不同编码/对齐规则就会出错。
- 这种“类型欺骗”会让审计/读者更难理解：建议封装成内部函数并在命名里强调 `unsafe`。

---

## Pattern 4: Cast between compatible `memory` structs（struct 零拷贝转型）

与数组同理，对兼容字段布局的 `memory` struct 可以用相同技巧：

```solidity
Foo memory foo = ...;
Bar memory bar;
assembly { bar := foo }
```

### 风险/边界

- 只有当两个 struct 的字段**数量、顺序、slot 布局**完全兼容时才安全。
- 这种技巧对可维护性影响更大：建议仅用于非常局部的性能热点，并写清楚兼容性前提。

---

## Pattern 5: Shortening dynamic `memory` arrays（原地缩短动态数组）

### 背景

动态 `memory` 数组的首 word 存长度 `mload(arr)`，后面紧跟元素。

### 模式

直接改写长度（通常只安全缩短，不要变长）：

```solidity
uint256[] memory arr = new uint256[](100);
assembly { mstore(arr, 99) }
```

### 使用场景

- 你预分配了一个较长数组，后来确定实际有效元素更少；
- 想避免再分配/复制一份新数组。

### 风险/边界

- 只能安全缩短；变长可能读到/写到其它变量占用的内存区域。
- 这会影响同一引用的其它使用者：确认没有其它代码依赖原长度。

---

## Pattern 6: “Shorten” static arrays / slicing（静态数组截断与切片）

静态数组没有 length 前缀，不能用 `mstore` 改长度。可用“指针复用”创建子视图：

```solidity
uint256[10] memory arr;
uint256[9] memory shortArr;
assembly { shortArr := arr }
```

甚至可以把指针偏移 0x20，从而创建共享 slice：

```solidity
uint256[10] memory arr;
uint256[8] memory slice;
assembly { slice := add(arr, 0x20) } // 跳过第一个元素
```

### 风险/边界

- 对静态数组声明本身会分配内存（没有动态数组那么省），但仍避免逐元素复制。
- 指针偏移 slice 的可读性较差，且容易和真实所有权/边界搞混；尽量限定在 internal 纯函数内。

---

## 总结：什么时候值得用这些 assembly tricks

- **值得用**：性能热点（循环内）、Merkle/哈希密集、需要保持 revert data 原样、与第三方库类型不一致但 bit 兼容。
- **不值得/慎用**：边界复杂、团队维护成本高、需要在 `calldata` 上玩指针、struct 布局不稳定（未来升级）。

