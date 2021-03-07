---
author: Ron
catalog: true
date: 2021-03-07
tags:
- BlockChain 
title: Darwinia Bridge
---

# Theory

[White Paper](https://darwinia.network/ChainRelay_Technical_Paper(Preview)_EN.pdf)

[Darwinia-Ethereum Bridge](https://docs.google.com/document/d/1NVDSk6KZXV5CjE20cNPA8Swmmd89IYeWyN0T9lRBOEM)


# Projects Navigation

## [Darwinia Bridge](https://github.com/darwinia-network/darwinia-common/tree/master/frame/bridge)

[cross-chain introduction](https://darwinianetwork.medium.com/darwinia-how-to-build-future-internet-of-tokens-ea99c2888eb1)

[cross-chain overview](https://miro.medium.com/max/700/0*W_Q1-GWv4JeCCQ7x)

### Background

[Patricia Merkle Trees](https://eth.wiki/concepts/light-client-protocol)

[Mining difficulty calculate](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-2.md)

[mmr](https://github.com/nervosnetwork/merkle-mountain-range)

[relay game](https://github.com/darwinia-network/relayer-game)


## [Bridger](https://github.com/darwinia-network/bridger)

Relayers (aka. Bridgers) in Darwinia Network are offchain worker clients which help relay the headers and messages between source chains and target chains

### Background
[actix](https://github.com/actix/actix)

deprecated [dj](https://github.com/darwinia-network/dj)

## [Shadow](https://github.com/darwinia-network/shadow)

Services for bridger which retrieve header data from public chains and generate mmr proof

### Background

[ffi](https://doc.rust-lang.org/book/ch19-01-unsafe-rust.html#using-extern-functions-to-call-external-code)


## [Wormhole](https://github.com/darwinia-network/wormhole)

### Background

[wiki](https://docs.darwinia.network/docs/en/wiki-tut-wormhole-general/)


# WorkFlow && Core Logic

## Ethereum To Darwinia

### wormhole

#### invoke token contract

```
function redeemTokenEth(account, params, callback) {
    let web3js = new Web3(window.ethereum || window.web3.currentProvider);
    const contract = new web3js.eth.Contract(TokenABI, config[`${params.tokenType.toUpperCase()}_ETH_ADDRESS`]);
    contract.methods.transferFrom(account, config['ETHEREUM_DARWINIA_ISSUING'], params.value, params.toHex).send({ from: account }).on('transactionHash', (hash) => {
        callback && callback(hash)
    })
}
```

[token](https://github.com/darwinia-network/darwinia-bridge-on-ethereum/blob/master/contracts/tokens/RING.sol)

[issuing-burn](https://github.com/darwinia-network/darwinia-bridge-on-ethereum/blob/master/issuing-burn/IssuingBurn.sol)

### contract

#### burn token and send BurnAndRedeem event

```
function tokenFallback(
    address _from,
    uint256 _amount,
    bytes _data
) public whenNotPaused {
    ...

    IBurnableERC20(msg.sender).burn(address(this), _amount);
    emit BurnAndRedeem(msg.sender, _from, _amount, _data);
}
```

### bridger

#### scan ethereum txs from token contracts

```
if l.topics.contains(&contracts.ring) || l.topics.contains(&contracts.kton)
{
    EthereumTransaction {
        tx_hash: EthereumTransactionHash::Token(
            l.transaction_hash.unwrap_or_default(),
        ),
        block_hash: l.block_hash.unwrap_or_default(),
        block,
        index,
    }
} 
...       
```

#### affirm

* will start the relay game in darwinia

```
/// Ethereum EthereumRelayHeaderParcel including ethereum block header and mmr root from shadow
#[derive(Encode, Decode, Debug, Default, PartialEq, Eq, Clone, Serialize, Deserialize)]
pub struct EthereumRelayHeaderParcel {
	/// Ethereum header
	pub header: EthereumHeader,
	/// MMR root
	pub mmr_root: [u8; 32],
}
...
let parcel = shadow.parcel(target as usize + 1).await.with_context(|| {
    format!(
        "Fail to get parcel from shadow when affirming ethereum block {}",
        target
    )
})?;
...
let ex = Extrinsic::Affirm(parcel);
let msg = MsgExtrinsic(ex);
extrinsics_service.send(msg).await?;
```

#### redeem 

* redeem after the end of relay game and block parcel confirmed

```
/// Ethereum ReceiptProofThing including Merkle Patricia Trie proof from ethereum and mmr proof from shadow
#[derive(Clone, Debug, Default, PartialEq, Eq, Encode)]
pub struct EthereumReceiptProofThing {
	/// Ethereum Header
	pub header: EthereumHeader,
	/// Ethereum Receipt Proof
	pub receipt_proof: EthereumReceiptProof,
	/// MMR Proof
	pub mmr_proof: MMRProof,
}
...
let proof = shadow
    .receipt(&format!("{:?}", tx.enclosed_hash()), last_confirmed)
    .await?;
let redeem_for = match tx.tx_hash {
    EthereumTransactionHash::Token(_) => RedeemFor::Token,
};
...
let ex = Extrinsic::Redeem(redeem_for, proof, tx);
let msg = MsgExtrinsic(ex);
extrinsics_service.send(msg).await?;
```

#### guard vote_pending_relay_header_parcel

* tech_comm member arbitrate as replacement for the relay game arbitrate

```
if pending_block_number > last_confirmed
    && !ethereum2darwinia.has_voted(&guard_account, voting_state)
{
    let parcel_from_shadow = shadow.parcel(pending_block_number as usize).await?;
    let ex = if pending_parcel.is_same_as(&parcel_from_shadow) {
        Extrinsic::GuardVote(pending_block_number, true)
    } else {
        Extrinsic::GuardVote(pending_block_number, false)
    };
    extrinsics_service.send(MsgExtrinsic(ex)).await?;
}
```

### shadow

#### mmr root

```
fn get_mmr_root(&self, leaf_index: u64) -> Result<Option<String>> {
    ...
    let mmr_size = cmmr::leaf_index_to_mmr_size(leaf_index);
    let mmr = MMR::<[u8; 32], MergeHash, _>::new(mmr_size, store);
    let root = mmr.get_root()?;
}
```

#### mmr proof

```
fn gen_proof(&self, member: u64, last_leaf: u64) -> Result<Vec<String>> {
    let mmr_size = cmmr::leaf_index_to_mmr_size(last_leaf);
    let mmr = MMR::<[u8; 32], MergeHash, _>::new(mmr_size, store);
    let proof = mmr.gen_proof(vec![cmmr::leaf_index_to_pos(member)])?;
}
```


### darwinia relay game 

[RelayerGame Rule](https://github.com/darwinia-network/darwinia-common/blob/master/frame/bridge/relayer-game/README.md)

[RelayerGame Protocol](https://github.com/darwinia-network/darwinia-common/blob/master/primitives/relay/src/relayer_game.rs)

#### start game

```
#[weight = 0]
pub fn affirm(
origin,
ethereum_relay_header_parcel: EthereumRelayHeaderParcel,
optional_ethereum_relay_proofs: Option<EthereumRelayProofs>
) {
  let game_id = T::RelayerGame::affirm(
  &relayer,
  ethereum_relay_header_parcel,
  optional_ethereum_relay_proofs
  )?;
  ...
}
```

#### challenge&extend game

```
pub fn dispute_and_affirm(
    origin,
    ethereum_relay_header_parcel: EthereumRelayHeaderParcel,
    optional_ethereum_relay_proofs: Option<EthereumRelayProofs>
) 

fn extend_affirmation(
    origin,
    extended_ethereum_relay_affirmation_id: RelayAffirmationId<EthereumBlockNumber>,
    game_sample_points: Vec<EthereumRelayHeaderParcel>,
    optional_ethereum_relay_proofs: Option<Vec<EthereumRelayProofs>>,
) 
```

#### update games

find the relayer win and confirm_relay_header_parcels

```
pub fn update_games(game_ids: Vec<RelayHeaderId<T, I>>) -> DispatchResult {
    let now = <frame_system::Module<T>>::block_number();
    let mut relay_header_parcels = vec![];

    for game_id in game_ids {
        trace!(
            target: "relayer-game",
            ">  Trying to Settle Game `{:?}`", game_id
        );

        let round_count = Self::round_count_of(&game_id);
        let last_round = if let Some(last_round) = round_count.checked_sub(1) {
            last_round
        } else {
            // Should never enter this condition
            error!(target: "relayer-game", "   >  Rounds - EMPTY");

            continue;
        };
        let mut relay_affirmations = Self::affirmations_of_game_at(&game_id, last_round);

        match (last_round, relay_affirmations.len()) {
            // Should never enter this condition
            (0, 0) => error!(target: "relayer-game", "   >  Affirmations - EMPTY"),
            // At first round and only one affirmation found
            (0, 1) => {
                trace!(target: "relayer-game", "   >  Challenge - NOT EXISTED");

                if let Some(relay_header_parcel) =
                    Self::settle_without_challenge(relay_affirmations.pop().unwrap())
                {
                    relay_header_parcels.push(relay_header_parcel);
                }
            }
            // No relayer response for the latest round
            (_, 0) => {
                trace!(target: "relayer-game", "   >  All Relayers Abstain, Settle Abandon");

                Self::settle_abandon(&game_id);
            }
            // No more challenge found at latest round, only one relayer win
            (_, 1) => {
                trace!(target: "relayer-game", "   >  No More Challenge, Settle With Challenge");

                if let Some(relay_header_parcel) =
                    Self::settle_with_challenge(&game_id, relay_affirmations.pop().unwrap())
                {
                    relay_header_parcels.push(relay_header_parcel);
                } else {
                    // Should never enter this condition

                    Self::settle_abandon(&game_id);
                }
            }
            (last_round, _) => {
                let distance = T::RelayableChain::distance_between(
                    &game_id,
                    Self::best_confirmed_header_id_of(&game_id),
                );

                if distance == round_count {
                    trace!(target: "relayer-game", "   >  A Full Chain Gave, On Chain Arbitrate");

                    // A whole chain gave, start continuous verification
                    if let Some(relay_header_parcel) = Self::on_chain_arbitrate(&game_id) {
                        relay_header_parcels.push(relay_header_parcel);
                    } else {
                        Self::settle_abandon(&game_id);
                    }
                } else {
                    trace!(target: "relayer-game", "   >  Still In Challenge, Update Games");

                    // Update game, start new round
                    Self::update_game_at(&game_id, last_round, now);

                    continue;
                }
            }
        }

        Self::game_over(game_id);
    }

    // TODO: handle error
    let _ = T::RelayableChain::try_confirm_relay_header_parcels(relay_header_parcels);

    trace!(target: "relayer-game", "---");

    Ok(())
}
```

#### verify proof in game

```
fn verify_relay_proofs(
		relay_header_id: &Self::RelayHeaderId,
		relay_header_parcel: &Self::RelayHeaderParcel,
		relay_proofs: &Self::RelayProofs,
		optional_best_confirmed_relay_header_id: Option<&Self::RelayHeaderId>,
	) -> DispatchResult {
		
    //verify ethash_proof
    ensure!(
        Self::verify_header(header, ethash_proof),
        <Error<T>>::HeaderInv
    );
    ...
    //verify mmr
    ensure!(
        Self::verify_mmr(
            last_leaf,
            mmr_root,
            mmr_proof
                .iter()
                .map(|h| array_unchecked!(h, 0, 32).into())
                .collect(),
            vec![(
                *best_confirmed_block_number,
                best_confirmed_block_header_hash
            )],
        ),
        <Error<T>>::MMRInv
    );
    ...
}
```

#### confirm relay parcel after game

```
pub fn update_confirmeds_with_reason(
    relay_header_parcel: EthereumRelayHeaderParcel,
    reason: Vec<u8>,
) {
    let relay_block_number = relay_header_parcel.header.number;

    ConfirmedBlockNumbers::mutate(|confirmed_block_numbers| {
        // TODO: remove old numbers according to `ConfirmedDepth`

        confirmed_block_numbers.push(relay_block_number);

        BestConfirmedBlockNumber::put(relay_block_number);
    });
    ConfirmedHeaderParcels::insert(relay_block_number, relay_header_parcel);

    Self::deposit_event(RawEvent::PendingRelayHeaderParcelConfirmed(
        relay_block_number,
        reason,
    ));
}
```

### [darwinia backing module](https://github.com/darwinia-network/darwinia-common/tree/master/frame/bridge/ethereum/backing)

redeem will happen only after game finished and block confirmed

#### redeem

```
/// Redeem balances
///
/// # <weight>
/// - `O(1)`
/// # </weight>
#[weight = 10_000_000]
pub fn redeem(origin, act: RedeemFor, proof: EthereumReceiptProofThing<T>) {
    let redeemer = ensure_signed(origin)?;

    if RedeemStatus::get() {
        match act {
            RedeemFor::Token => Self::redeem_token(&redeemer, &proof)?,
            RedeemFor::Deposit => Self::redeem_deposit(&redeemer, &proof)?,
        }
    } else {
        Err(<Error<T>>::RedeemDis)?;
    }
}
```

#### parse BurnAndRedeem event

```
fn parse_token_redeem_proof(
		proof_record: &EthereumReceiptProofThing<T>,
	) -> Result<(T::AccountId, (bool, Balance), RingBalance<T>), DispatchError> {
		let verified_receipt = T::EthereumRelay::verify_receipt(proof_record)
			.map_err(|_| <Error<T>>::ReceiptProofInv)?;
		let fee = T::EthereumRelay::receipt_verify_fee();
		let result = {
			let eth_event = EthEvent {
				name: "BurnAndRedeem".to_owned(),
				...
		debug::trace!(target: "ethereum-backing", "[ethereum-backing] Darwinia Account: {:?}", darwinia_account);

		Ok((darwinia_account, (is_ring, redeemed_amount), fee))
}
```

#### finish the transfer

```
C::transfer(
    &Self::account_id(),
    &darwinia_account,
    redeem_amount,
    KeepAlive,
)?;
// // Transfer the fee from redeemer.
// T::RingCurrency::transfer(redeemer, &T::EthereumRelay::account_id(), fee, KeepAlive)?;

VerifiedProof::insert(tx_index, true);
```


## Darwinia To Ethereum

### wormhole 

#### lock token

```
async function ethereumBackingLockDarwinia(account, params, callback, t) {
    try {
        console.log('ethereumBackingLock', { account, params, callback }, params.ring.toString(), params.kton.toString())
        if (window.darwiniaApi) {
            await window.darwiniaApi.isReady;
            const injector = await web3FromAddress(account);
            window.darwiniaApi.setSigner(injector.signer);
            const hash = await window.darwiniaApi.tx.ethereumBacking.lock(params.ring, params.kton, params.to)
            .signAndSend(account);
            callback && callback(hash);
        }
    } catch (error) {
        console.log(error);
    }
}
```

### darwinia backing module

#### lock balance and send ScheduleMMRRootEvent

```
// Lock some balances into the module account
/// which very similar to lock some assets into the contract on ethereum side
///
/// This might kill the account just like `balances::transfer`
#[weight = 10_000_000]
pub fn lock(
    origin,
    #[compact] ring_to_lock: RingBalance<T>,
    #[compact] kton_to_lock: KtonBalance<T>,
    ethereum_account: EthereumAddress,
) {
    ...
    T::RingCurrency::transfer(
        &user, &Self::account_id(),
        ring_to_lock,
        AllowDeath
    )?;
  
    let raw_event = RawEvent::LockRing(
        user.clone(),
        ethereum_account.clone(),
        RingTokenAddress::get(),
        ring_to_lock
    );
    let module_event: <T as Config>::Event = raw_event.clone().into();
    let system_event: <T as frame_system::Config>::Event = module_event.into();
  
    locked = true;
  
    <LockAssetEvents<T>>::append(system_event);
    Self::deposit_event(raw_event);
    if locked {
        //will send ScheduleMMRRootEvent 
        T::EcdsaAuthorities::schedule_mmr_root((
            <frame_system::Module<T>>::block_number().saturated_into::<u32>()
                / 10 * 10 + 10
        ).saturated_into());
    }
}
```

### bridger

#### handle ScheduleMMRRootEvent

```
// call ethereum_backing.lock will emit the event
  EventInfo::ScheduleMMRRootEvent(event) => {
      if self
          .darwinia2ethereum
          .is_authority(block, &self.account)
          .await?
      {
          info!("{}", event);
          let ex = Extrinsic::SignAndSendMmrRoot(event.block_number);
          self.delayed_extrinsics.insert(event.block_number, ex);
      }
  }
```
#### submit signed_mmr_root extrinsic

```
Extrinsic::SignAndSendMmrRoot(block_number) => {
    if let Some(darwinia2ethereum) = &darwinia2ethereum {
        trace!("Start sign and send mmr_root...");
        if let Some(relayer) = &darwinia2ethereum_relayer {
            let ex_hash = darwinia2ethereum
                .ecdsa_sign_and_submit_signed_mmr_root(
                    &relayer,
                    spec_name,
                    block_number,
                )
                .await?;
            info!(
                "Sign and send mmr root of block {} in extrinsic {:?}",
                block_number, ex_hash
            );
        }
    }
}
```

### [darwinia relay authorities](https://github.com/darwinia-network/darwinia-common/blob/master/frame/bridge/relay-authorities/src/lib.rs)

#### verify signature and send MMRRootSigned event

```
/// Verify
/// - the relay requirement is valid
/// - the signature is signed by the submitter
#[weight = 10_000_000]
pub fn submit_signed_mmr_root(
    origin,
    block_number: BlockNumber<T>,
    signature: RelayAuthoritySignature<T, I>
) {
    ...
    let mmr_root =
        T::DarwiniaMMR::get_root(block_number).ok_or(<Error<T, I>>::DarwiniaMMRRootNRY)?;

    ...

    ensure!(
        T::Sign::verify_signature(&signature, &message, &signer),
         <Error<T, I>>::SignatureInv
    );

    ...
    Self::mmr_root_signed(block_number);
    Self::deposit_event(RawEvent::MMRRootSigned(block_number, mmr_root, signatures));
}
```

### wormhole

#### invoke VerifyProof contract

* only after MMRRootSigned

```
export async function ClaimTokenFromD2E({ networkPrefix, mmrIndex, mmrRoot, mmrSignatures, blockNumber, blockHeaderStr, blockHash, historyMeta} , callback, t ) {
    connect('eth', async(_networkType, _account, subscribe) => {
    
    ...
    darwiniaToEthereumVerifyProof(_account, {
        root: '0x' + historyMeta.mmrRoot,
        MMRIndex: historyMeta.best,
        blockNumber: blockNumber,
        blockHeader: blockHeader.toHex(),
        peaks: mmrProof.peaks,
        siblings: mmrProof.siblings,
        eventsProofStr: eventsProof.toHex()
    }, (result) => {
        console.log('darwiniaToEthereumVerifyProof', result)
        callback && callback(result);
    }); 
}

export async function darwiniaToEthereumVerifyProof(account, {
    root,
    MMRIndex,
    blockNumber,
    blockHeader,
    peaks,
    siblings,
    eventsProofStr
}, callback) {
    let web3js = new Web3(window.ethereum || window.web3.currentProvider);
    const contract = new web3js.eth.Contract(DarwiniaToEthereumTokenIssuingABI, config.DARWINIA_ETHEREUM_TOKEN_ISSUING);

    // bytes32 root,
    // uint32 MMRIndex,
    // uint32 blockNumber,
    // bytes memory blockHeader,
    // bytes32[] memory peaks,
    // bytes32[] memory siblings,
    // bytes memory eventsProofStr
    contract.methods.verifyProof(
        root,
        MMRIndex,
        blockHeader,
        peaks,
        siblings,
        eventsProofStr).send({ from: account }, function(error, transactionHash) {
            if(error) {
               console.log(error);
               return;
            }
            callback && callback(transactionHash)
        })
}
```

### contract

#### issue mint

[Issuing-Mint](https://github.com/darwinia-network/darwinia-bridge-on-ethereum/blob/master/contracts/TokenIssuing.sol)

```
function verifyProof(
        bytes32 root,
        uint32 MMRIndex,
        bytes memory blockHeader,
        bytes32[] memory peaks,
        bytes32[] memory siblings,
        bytes memory eventsProofStr
    ) 
      public
      whenNotPaused
    {
        uint32 blockNumber = Scale.decodeBlockNumberFromBlockHeader(blockHeader);

        require(!history[blockNumber], "TokenIssuing:: verifyProof:  The block has been verified");

        Input.Data memory data = Input.from(relay.verifyRootAndDecodeReceipt(root, MMRIndex, blockNumber, blockHeader, peaks, siblings, eventsProofStr, storageKey));
        
        ScaleStruct.LockEvent[] memory events = Scale.decodeLockEvents(data);

        address ring = registry.addressOf(bytes32("CONTRACT_RING_ERC20_TOKEN"));
        address kton = registry.addressOf(bytes32("CONTRACT_KTON_ERC20_TOKEN"));

        uint256 len = events.length;

        for( uint i = 0; i < len; i++ ) {
          ScaleStruct.LockEvent memory item = events[i];
          uint256 value = decimalsConverter(item.value);
          if(item.token == ring) {
            expendDailyLimit(ring, value);
            IERC20(ring).mint(item.recipient, value);

            emit MintRingEvent(item.recipient, value, item.sender);
          }

          if (item.token == kton) {
            expendDailyLimit(kton, value);
            IERC20(kton).mint(item.recipient, value);

            emit MintKtonEvent(item.recipient, value, item.sender);
          }
        }

        history[blockNumber] = true;
        emit VerifyProof(blockNumber);
    }
```

#### verify mmr

[verify proof](https://github.com/darwinia-network/darwinia-bridge-on-ethereum/blob/master/contracts/Relay.sol)

```
function verifyRootAndDecodeReceipt(
    bytes32 root,
    uint32 MMRIndex,
    uint32 blockNumber,
    bytes memory blockHeader,
    bytes32[] memory peaks,
    bytes32[] memory siblings,
    bytes memory eventsProofStr,
    bytes memory key
) public view whenNotPaused returns (bytes memory){
    // verify block proof
    require(
        verifyBlockProof(root, MMRIndex, blockNumber, blockHeader, peaks, siblings),
        "Relay: Block header proof varification failed"
    );

    // get state root
    bytes32 stateRoot = Scale.decodeStateRootFromBlockHeader(blockHeader);

    return getLockTokenReceipt(stateRoot, eventsProofStr, key);
}
```






