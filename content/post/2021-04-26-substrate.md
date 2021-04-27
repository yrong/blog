---
author: Ron
catalog: true
date: 2021-04-26
tags:
- BlockChain 
title: substrate tips
---

# upgrade to substrate 3.0

[guidelines](https://crates.parity.io/frame_support/attr.pallet.html#upgrade-guidelines)

[check](https://crates.parity.io/frame_support/attr.pallet.html#checking-upgrade-guidelines)

[example](https://github.com/paritytech/substrate/pull/7984/)

[macros](https://github.com/paritytech/substrate/blob/master/frame/support/src/lib.rs)


# runtime migration

> [kb](https://substrate.dev/docs/en/knowledgebase/runtime/upgrades#storage-migrations)

## examples

> [examples](https://github.com/apopiak/substrate-migrations)

### tips

> [custom order](https://github.com/hicommonwealth/edgeware-node/blob/7b66f4f0a9ec184fdebcccd41533acc728ebe9dc/node/runtime/src/lib.rs#L845-L866)

> [include deprecated types](https://github.com/hicommonwealth/substrate/blob/5f3933f5735a75d2d438341ec6842f269b886aaa/frame/indices/src/migration.rs#L5-L22)

> [check storage version](https://github.com/paritytech/substrate/blob/c79b522a11bbc7b3cf2f4a9c0a6627797993cb79/frame/elections-phragmen/src/lib.rs#L119-L157)

### weights

> [doc](https://crates.parity.io/frame_support/weights/index.html)


