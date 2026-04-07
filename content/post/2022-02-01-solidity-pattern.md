---
author: Ron
catalog: true
date: 2022-02-01
tags:
- BlockChain
- Ethereum
- Solidity
title: solidity patterns
---

## Solidity 设计模式汇总笔记
本笔记总结了用于优化 Gas 消耗、增强安全性以及改善开发体验的核心 Solidity 编程模式。

1. 重入保护模式 (Reentrancy Protection)
问题： 当合约发起外部调用时，执行控制权会转移给另一方。攻击者可以利用此机会在原始操作完成前再次调用合约函数，从而导致资产被超额提取。
检查-效果-交互 (CEI) 模式：
Checks：验证输入参数和初始状态。
Effects：在进行任何外部调用之前，更新所有的状态变量。
Interactions：最后再执行外部调用或资产转移。
重入卫兵 (Reentrancy Guards/Mutex)： 使用一个布尔标志（如 nonReentrant 修饰符）在函数进入时加锁，结束后解锁。如果函数在锁定状态下再次被调用，则交易回滚。

2. 存储打包模式 (Packing Storage)
问题： 读写 EVM 存储插槽（32 字节）是极其昂贵的操作。
自动插槽打包： 将多个小于 32 字节的原始类型（如 uint8, bool, bytes16）相邻声明。Solidity 编译器会将它们压缩进同一个存储插槽，从而大幅减少 Gas 开销。
共定位建议： 将经常同时读写的变量定义在一起，以利用 EIP-2929 的“热访问” Gas 折扣。
类型选择： 根据实际需求选择最小的变量类型（例如用 uint40 表示时间戳，而不是 uint256）。

3. Permit2 模式
问题： 传统的 approve 模式 UX 极差（每个新协议都要发一笔独立交易）且存在安全风险（用户倾向于无限授权）。
离线签名授权： 用户向 Permit2 规范合约授予一次性无限授权。
跨协议共享： 之后，用户只需签署符合 EIP-712 的离线消息即可完成授权。所有集成 Permit2 的协议都可以共享这一授权，无需用户再次发送 approve 交易。
安全优势： 签名包含过期时间，且 Permit2 合约结构简单，比复杂的业务合约更易于审计。

4. 委托调用访问控制 (onlyDelegateCall / noDelegateCall)
问题： 在代理架构中，逻辑合约本身是一个独立合约。如果其敏感函数（如初始化或自毁）未加限制，可能被攻击者直接调用导致严重后果。
onlyDelegateCall： 使用 immutable 记录部署地址，通过 address(this) != DEPLOYED_ADDRESS 确保函数只能通过代理合约的 delegatecall 执行。
noDelegateCall： 与上述相反，确保函数绝不能被通过 delegatecall 调用。这常用于防止他人通过代理方式套用或克隆你的合约逻辑（如 Uniswap V3）。

5. 独立授权目标 (Separate Allowance Targets)
问题： 复杂协议逻辑经常需要升级，如果用户直接授权给逻辑合约，每次升级都要重新授权，且逻辑合约的漏洞可能威胁到已授权的所有资产。
职责分离： 部署一个功能极简、几乎不更改的 授权目标合约 (Allowance Target)。用户只授权给它。
动态控制： 主业务合约（逻辑合约）向授权合约发起扣款请求。治理方可以随时开启或关闭业务合约对授权合约的访问权限。

6. 只读委托调用 (Read-only Delegatecall)
问题： delegatecall 允许在当前上下文中执行外部代码，但它具有潜在的状态修改风险，且不能直接在 view 函数中使用。
模拟“静态”版本：
包装在 staticcall 中：通过对合约自身的辅助函数发起外部 staticcall，由于底层强制只读，即便内部执行 delegatecall 逻辑也无法修改状态。
执行后回滚：在执行完 delegatecall 后主动调用 revert。这会撤销所有状态更改，但执行结果可以通过回滚消息负载捕获并解码。

7. “栈过深”解决方法 (Stack Too Deep Workarounds)
问题： EVM 栈只能直接访问顶部 32 个槽位，局部变量或参数过多会导致编译错误。
IR 编译 (--via-ir)： 启用较新的编译器标志，自动将栈变量移入内存。
块级作用域： 使用 { ... } 包裹变量，使编译器能尽早丢弃不再使用的中间变量。
内存结构体： 将多个变量封装进一个 struct memory，这样在栈上只需要存储一个 32 字节的内存指针。
离线计算： 将复杂计算逻辑移至链下，合约仅负责对结果进行简单的逻辑验证。
