# Uniswap V4 Position Subscriber - Complete Technical Guide

## Introduction

This document provides a comprehensive technical explanation of the **Subscriber** pattern in Uniswap V4, which allows external contracts to receive real-time notifications about liquidity position changes. This is one of the most powerful extensibility features of V4's Position Manager.

### What You'll Learn

- Understanding the Subscriber pattern and its use cases
- Implementing the ISubscriber interface
- Handling position lifecycle notifications (subscribe, unsubscribe, burn)
- Tracking liquidity changes in real-time
- Building non-transferable token systems
- Managing state synchronization with Position Manager
- Gas optimization for notification callbacks
- Security considerations for subscriber contracts

### Key Concepts

**Subscriber**: A contract that implements the `ISubscriber` interface to receive notifications when subscribed positions are modified.

**Subscribe**: The act of linking a position (NFT) to a subscriber contract. After subscribing, the subscriber receives notifications for all position changes.

**Non-Transferable Tokens**: Tokens that represent ownership or participation but cannot be transferred between addresses. Used for reputation, voting rights, or tracking.

**Notification Callback**: A function call from Position Manager to the subscriber when a position event occurs.

**Gas Limit**: Subscribers have gas limits to prevent DoS attacks. `unsubscribe` has a configurable limit set at deployment.

**Position Lifecycle**: The sequence of events from creation → subscription → modifications → unsubscription/burn.

---

## 🔔 Understanding the "Notification" System

### ⚠️ Important Clarification

The term "notifications" might be misleading if you're familiar with traditional off-chain notification systems. Let's clarify:

**❌ What This Is NOT:**
- NOT an external notification service (like webhooks, email, SMS)
- NOT a centralized backend monitoring events
- NOT an off-chain push notification system
- NOT asynchronous - everything happens in the same transaction

**✅ What This Actually IS:**
- **On-chain callback pattern** - direct function calls between contracts
- **Synchronous execution** - happens within the same transaction
- **Built into Uniswap V4** - Position Manager calls your contract directly
- **Atomic** - all or nothing, no separate notification delivery

### How It Works

```solidity
// User Transaction
User calls: posm.increaseLiquidity(tokenId, ...)
    ↓
// Position Manager (Uniswap V4 code)
function _modifyLiquidity(...) internal {
    // 1. Modify the liquidity in the pool
    liquidityDelta = poolManager.modifyLiquidity(...);
    
    // 2. Check if position has subscriber
    address subscriber = positionInfo.subscriber();
    
    // 3. If yes, CALL the subscriber directly
    if (subscriber != address(0)) {
        ISubscriber(subscriber).notifyModifyLiquidity(
            tokenId,
            liquidityChange,
            liquidityDelta
        );
        // ↑ This is a direct contract call, not an event emission!
    }
    
    // 4. Continue execution
    // All of this happens in ONE transaction
}
```

### Real Flow Visualization

```
┌──────────────────────────────────────────────────────────────┐
│                   SINGLE TRANSACTION                         │
│                                                              │
│  User                                                        │
│   │ increaseLiquidity(tokenId, 1000)                       │
│   ↓                                                          │
│  Position Manager                                            │
│   │ 1. Modify pool liquidity                               │
│   │ 2. Get subscriber address                              │
│   │ 3. subscriber.notifyModifyLiquidity(...) ← DIRECT CALL│
│   │    │                                                    │
│   │    ↓                                                    │
│   │  Your Subscriber Contract                              │
│   │    │ Update balances                                   │
│   │    │ Mint tokens                                       │
│   │    │ return                                            │
│   │    ↓                                                    │
│   │ 4. Continue execution                                  │
│   ↓                                                          │
│  ✅ Transaction complete                                    │
└──────────────────────────────────────────────────────────────┘
```

### Comparison: On-chain Callbacks vs Traditional Notifications

| Aspect | Subscriber (On-chain) | Traditional Notifications (Off-chain) |
|--------|----------------------|---------------------------------------|
| **Execution** | Same transaction | Separate process |
| **Trigger** | Direct function call | Event emission → Backend detects |
| **Latency** | Immediate (atomic) | Seconds to minutes |
| **Reliability** | Guaranteed (or tx reverts) | Depends on infrastructure |
| **Cost** | Gas cost | Free (but need infrastructure) |
| **State Changes** | Yes, immediately | Only after notification processed |
| **Example** | `ISubscriber(addr).notify()` | `emit Event() → Bot → Webhook` |

### Why Use This Pattern?

**Advantages:**
- ✅ **Atomic Updates**: Your state updates in the same transaction as the position change
- ✅ **Guaranteed Delivery**: If position changes, your contract is called (unless out of gas)
- ✅ **No Infrastructure**: No off-chain bots, databases, or APIs needed
- ✅ **Composability**: Your contract can react and modify state immediately
- ✅ **Trustless**: No reliance on external services

**Trade-offs:**
- ⚠️ **Gas Cost**: User pays gas for your callback execution
- ⚠️ **Gas Limits**: Your code must be efficient (limited gas per callback)
- ⚠️ **Complexity**: Must handle all edge cases on-chain
- ⚠️ **Opt-in**: Users must explicitly subscribe (not automatic)

### Analogy: JavaScript Events vs Solidity Callbacks

```javascript
// JavaScript (off-chain event pattern)
button.addEventListener('click', handleClick);
// Event fires → handler executes LATER

// Solidity (on-chain callback pattern)
ISubscriber(subscriber).notifyModifyLiquidity(...);
// Direct call → handler executes IMMEDIATELY in same transaction
```

### Key Takeaway

> **"Subscriber notifications" are not push notifications!**
> 
> They are **synchronous contract calls** made by Position Manager when certain actions occur on subscribed positions. Everything happens on-chain, atomically, within the user's transaction.

Think of it as:
- **Hooks**: For protocol-wide events (all swaps, all liquidity changes)
- **Subscribers**: For position-specific events (only positions you're subscribed to)

Both are on-chain callbacks, not external notification systems!

---

## 🔍 How Position Manager Knows Your Subscriber

### The Subscription Mechanism

Position Manager stores a **mapping** that links each position (tokenId) to its subscriber contract:

```solidity
// Inside PositionManager.sol (Uniswap V4)
contract PositionManager {
    // tokenId => subscriber address
    mapping(uint256 => address) private subscribers;
    
    // User calls this to register their subscriber
    function subscribe(
        uint256 tokenId,
        address newSubscriber,
        bytes calldata data
    ) external {
        // 1. Verify caller owns the position
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        
        // 2. Verify not already subscribed
        require(subscribers[tokenId] == address(0), "Already subscribed");
        
        // 3. STORE the subscriber address
        subscribers[tokenId] = newSubscriber;
        
        // 4. Notify the subscriber about the subscription
        ISubscriber(newSubscriber).notifySubscribe(tokenId, data);
        
        emit Subscribed(tokenId, newSubscriber);
    }
}
```

### Complete Subscription Flow

```
┌─────────────────────────────────────────────────────────────┐
│ STEP 1: User Subscribes Position to Your Contract          │
└─────────────────────────────────────────────────────────────┘

User (Position Owner)
  │
  │ posm.subscribe(tokenId: 123, subscriber: 0xYourContract, data: "")
  ↓
Position Manager
  │
  ├─ Check: Is caller the owner of tokenId 123? ✅
  ├─ Check: Is tokenId 123 already subscribed? ❌ No
  │
  ├─ STORE: subscribers[123] = 0xYourContract
  │          ↑ This is how PM "remembers" your contract!
  │
  ├─ CALL: ISubscriber(0xYourContract).notifySubscribe(123, "")
  │
  └─ Emit: Subscribed(123, 0xYourContract)

┌─────────────────────────────────────────────────────────────┐
│ STEP 2: Later, When Position is Modified                   │
└─────────────────────────────────────────────────────────────┘

User (Position Owner)
  │
  │ posm.increaseLiquidity(tokenId: 123, liquidity: 1000)
  ↓
Position Manager
  │
  ├─ Modify pool liquidity (add 1000)
  │
  ├─ LOOKUP: subscriber = subscribers[123]
  │          subscriber = 0xYourContract ✅ Found!
  │
  ├─ CHECK: if (subscriber != address(0)) {
  │
  ├─── CALL: ISubscriber(0xYourContract).notifyModifyLiquidity(
  │            tokenId: 123,
  │            liquidityChange: +1000,
  │            feesAccrued: 0
  │          )
  │
  └─ Continue execution
```

### Storage Structure in Position Manager

```solidity
contract PositionManager {
    // Core NFT data
    mapping(uint256 => PositionInfo) private positions;
    
    // Subscriber tracking (THIS IS THE KEY!)
    mapping(uint256 => address) private subscribers;
    //      tokenId  =>  your subscriber contract address
    
    // Example state after subscription:
    // subscribers[123] = 0xABC...  (your contract)
    // subscribers[456] = 0xDEF...  (another contract)
    // subscribers[789] = 0x000...  (not subscribed)
}
```

### Real Code Example

Let's see the complete process with actual code:

```solidity
// 1. USER DEPLOYS SUBSCRIBER CONTRACT
contract MySubscriber is ISubscriber {
    IPositionManager public immutable posm;
    
    constructor(address _posm) {
        posm = IPositionManager(_posm);
    }
    
    function notifySubscribe(uint256 tokenId, bytes memory data) 
        external 
        onlyPositionManager 
    {
        // Your logic here
    }
    
    // ... other notify functions ...
}

// 2. USER MINTS A POSITION
uint256 tokenId = posm.mint(...);
// tokenId = 123
// subscribers[123] = address(0)  ← Not subscribed yet

// 3. USER SUBSCRIBES THE POSITION
MySubscriber mySubscriber = new MySubscriber(address(posm));
posm.subscribe(
    123,                        // tokenId
    address(mySubscriber),      // subscriber address
    ""                          // optional data
);
// NOW: subscribers[123] = address(mySubscriber) ✅

// 4. USER MODIFIES POSITION
posm.increaseLiquidity(123, 1000, ...);

// Position Manager executes:
//   1. Modify liquidity
//   2. address sub = subscribers[123];  ← Reads from storage
//   3. if (sub != address(0)) {
//        ISubscriber(sub).notifyModifyLiquidity(...);
//      }
```

### Unsubscribe Process

```solidity
// Position Manager
function unsubscribe(uint256 tokenId) external {
    // 1. Verify ownership
    require(ownerOf(tokenId) == msg.sender, "Not owner");
    
    // 2. Get the subscriber
    address subscriber = subscribers[tokenId];
    require(subscriber != address(0), "Not subscribed");
    
    // 3. Notify subscriber (with gas limit!)
    ISubscriber(subscriber).notifyUnsubscribe{
        gas: unsubscribeGasLimit
    }(tokenId);
    
    // 4. DELETE the subscription
    delete subscribers[tokenId];
    //     ↑ Now subscribers[tokenId] = address(0)
    
    emit Unsubscribed(tokenId);
}
```

### State Transitions

```
Initial State:
  tokenId: 123
  owner: 0xUser...
  subscribers[123] = address(0)  ← No subscriber

After posm.subscribe(123, 0xMyContract, ""):
  tokenId: 123
  owner: 0xUser...
  subscribers[123] = 0xMyContract  ← Subscribed! ✅

After posm.unsubscribe(123):
  tokenId: 123
  owner: 0xUser...
  subscribers[123] = address(0)  ← Unsubscribed

After posm.burn(123):
  tokenId: 123 doesn't exist anymore
  subscribers[123] is deleted
```

### Multiple Positions, Same Subscriber

```solidity
// One subscriber can track many positions
MySubscriber sub = new MySubscriber(address(posm));

// Subscribe multiple positions to the same contract
posm.subscribe(123, address(sub), "");
posm.subscribe(456, address(sub), "");
posm.subscribe(789, address(sub), "");

// Position Manager storage:
subscribers[123] = address(sub)
subscribers[456] = address(sub)
subscribers[789] = address(sub)

// When any of these positions change:
// PM looks up subscribers[tokenId] → finds address(sub) → calls it
```

### Important Limitations

```solidity
// ❌ One position can only have ONE subscriber
posm.subscribe(123, subscriberA, "");  // OK
posm.subscribe(123, subscriberB, "");  // ❌ REVERTS: "Already subscribed"

// To change subscriber, must unsubscribe first:
posm.unsubscribe(123);                 // Clear subscriberA
posm.subscribe(123, subscriberB, "");  // Now OK

// ✅ One subscriber can handle many positions
posm.subscribe(123, mySubscriber, ""); // OK
posm.subscribe(456, mySubscriber, ""); // OK
posm.subscribe(789, mySubscriber, ""); // OK
```

### Access Control

```solidity
function subscribe(uint256 tokenId, address newSubscriber, bytes calldata data) 
    external 
{
    // CRITICAL: Only position owner can subscribe
    require(ownerOf(tokenId) == msg.sender, "Not owner");
    
    // This prevents:
    // - Random users subscribing your positions
    // - Malicious subscribers intercepting notifications
    // - Unauthorized tracking
}

function unsubscribe(uint256 tokenId) external {
    // CRITICAL: Only position owner can unsubscribe
    require(ownerOf(tokenId) == msg.sender, "Not owner");
    
    // Owner has full control over subscription
}
```

### Visual Summary

```
Position Manager Storage:

┌──────────┬─────────────────────┐
│ tokenId  │  subscriber address │
├──────────┼─────────────────────┤
│   123    │  0xABC... (yours)   │ ← PM calls this when 123 changes
│   456    │  0xABC... (yours)   │ ← PM calls this when 456 changes
│   789    │  0xDEF... (other)   │ ← PM calls this when 789 changes
│   999    │  0x000... (none)    │ ← PM doesn't call anyone
└──────────┴─────────────────────┘

When posm.increaseLiquidity(123, ...) is called:
  1. address sub = subscribers[123];     // sub = 0xABC...
  2. if (sub != address(0)) {
  3.   ISubscriber(sub).notifyModifyLiquidity(...);
  4. }
```

### Key Takeaways

✅ **Position Manager stores a mapping**: `tokenId → subscriber address`

✅ **User explicitly subscribes**: `posm.subscribe(tokenId, yourContract, data)`

✅ **PM reads from storage**: When position changes, looks up subscriber

✅ **Direct contract call**: PM calls the stored address directly

✅ **One-to-one**: Each position can have max 1 subscriber

✅ **Owner control**: Only position owner can subscribe/unsubscribe

✅ **Persistent**: Subscription persists until unsubscribe or burn

This is how Position Manager "knows" which subscriber to call - it simply stores and looks up the address you provided during subscription! 🎯

## Contract Overview

The `Subscriber.sol` exercise demonstrates how to build a subscriber contract that:

1. Mints non-transferable tokens proportional to liquidity added
2. Burns tokens when liquidity is removed
3. Tracks position ownership and pool association
4. Handles all four notification types from Position Manager
5. Manages state for positions that may be burned

### Core Features

| Feature | Description |
|---------|-------------|
| **Subscribe Notifications** | Receive callback when position subscribes |
| **Unsubscribe Notifications** | Cleanup when position unsubscribes |
| **Burn Notifications** | Handle position destruction |
| **Modify Liquidity Notifications** | Track liquidity increases/decreases |
| **Non-Transferable Tokens** | Mint tokens that can't be transferred |
| **State Tracking** | Store poolId and owner per position |
| **Balance Management** | Per-pool, per-user balances |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Interface**: ISubscriber
- **Pattern**: Callback-based notifications
- **Token Type**: Non-transferable (no transfer functions)
- **Storage**: tokenId → (poolId, owner) mappings
- **Balance Tracking**: poolId → owner → amount
- **Access Control**: onlyPositionManager modifier

## 🏗️ Architecture Overview

### The Subscriber Pattern

```
┌──────────────────────────────────────────────────────────────────┐
│                           USER                                   │
│                    (Position Owner)                              │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             │ 1. posm.subscribe(tokenId, subscriber, data)
                             ↓
┌──────────────────────────────────────────────────────────────────┐
│                     POSITION MANAGER                             │
│                       (ERC721 NFT)                               │
│                                                                  │
│  • Manages liquidity positions as NFTs                           │
│  • Tracks subscriber per tokenId                                 │
│  • Triggers notifications on position changes                    │
│  • Enforces gas limits on callbacks                              │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             │ 2. Callbacks (when position changes)
                             ↓
┌──────────────────────────────────────────────────────────────────┐
│                    SUBSCRIBER CONTRACT                           │
│                  (Your Implementation)                           │
│                                                                  │
│  Notification Handlers:                                          │
│  • notifySubscribe(tokenId, data)                                │
│  • notifyUnsubscribe(tokenId)                                    │
│  • notifyBurn(tokenId, owner, info, liq, fees)                   │
│  • notifyModifyLiquidity(tokenId, liquidityChange, fees)         │
│                                                                  │
│  Your Custom Logic:                                              │
│  • Mint/burn non-transferable tokens                             │
│  • Track reputation points                                       │
│  • Collect analytics                                             │
│  • Enforce rules or fees                                         │
└──────────────────────────────────────────────────────────────────┘
```

### Token Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Token Contract                           │
│            (Base for non-transferable tokens)               │
│                                                             │
│  Storage:                                                   │
│  mapping(poolId => mapping(owner => balance))              │
│                                                             │
│  Functions:                                                 │
│  • _mint(poolId, owner, amount)                            │
│  • _burn(poolId, owner, amount)                            │
│  • balanceOf(poolId, owner) → uint256                      │
│                                                             │
│  Note: No transfer() function!                             │
└─────────────────────────────────────────────────────────────┘
                          ↑
                          │ inherits
                          │
┌─────────────────────────────────────────────────────────────┐
│                  Subscriber Contract                        │
│              (Implements ISubscriber)                       │
│                                                             │
│  Additional Storage:                                        │
│  • mapping(tokenId => poolId)   - Track pool               │
│  • mapping(tokenId => owner)    - Track owner              │
│                                                             │
│  Notification Handlers:                                     │
│  • notifySubscribe     → _mint tokens                      │
│  • notifyUnsubscribe   → _burn tokens                      │
│  • notifyBurn          → _burn tokens                      │
│  • notifyModifyLiquidity → _mint or _burn                  │
└─────────────────────────────────────────────────────────────┘
```

### State Lifecycle

```
Position Created (NFT minted)
         │
         │ User calls: posm.subscribe(tokenId, subscriber, "")
         ↓
┌────────────────────────┐
│   SUBSCRIBED STATE     │  ← notifySubscribe() called
│                        │    • Mint tokens = liquidity
│  • poolIds[tokenId]    │    • Store poolId
│  • ownerOf[tokenId]    │    • Store owner
│  • balanceOf[poolId]   │
│    [owner] = liquidity │
└────────────────────────┘
         │
         │ Position modifications
         ↓
┌────────────────────────┐
│  MODIFY LIQUIDITY      │  ← notifyModifyLiquidity() called
│                        │    • liquidityChange > 0: mint more
│  Balance increases     │    • liquidityChange < 0: burn some
│  or decreases          │    • Track in balanceOf
└────────────────────────┘
         │
         │ User unsubscribes OR burns position
         ↓
    ┌────────┴────────┐
    │                 │
    ↓                 ↓
┌──────────┐   ┌────────────┐
│UNSUBSCRIBE│   │    BURN    │  ← notifyBurn() called
│           │   │            │    • Burn remaining tokens
│ Cleanup   │   │  Cleanup   │    • Delete poolIds[tokenId]
│ state     │   │  state     │    • Delete ownerOf[tokenId]
└──────────┘   └────────────┘
    │                 │
    └────────┬────────┘
             ↓
      ┌─────────────┐
      │   CLEANED   │
      │             │
      │  All state  │
      │  deleted    │
      └─────────────┘
```

## 🔄 Execution Flow Diagrams

### Flow 1: Subscribing to a Position

```
USER                POSITION MANAGER           SUBSCRIBER CONTRACT
 │                        │                            │
 │  subscribe(tokenId,    │                            │
 │   subscriber, data)    │                            │
 │───────────────────────>│                            │
 │                        │                            │
 │                        │ [1. Validate]              │
 │                        │ • tokenId exists?          │
 │                        │ • Not already subscribed?  │
 │                        │ • Caller is owner?         │
 │                        │ ✅                         │
 │                        │                            │
 │                        │ [2. Store subscription]    │
 │                        │ subscribers[tokenId] =     │
 │                        │   subscriber address       │
 │                        │                            │
 │                        │  notifySubscribe(          │
 │                        │    tokenId, data)          │
 │                        │───────────────────────────>│
 │                        │                            │
 │                        │                            │ [3. Get position info]
 │                        │  getPoolAndPositionInfo()  │
 │                        │<───────────────────────────│
 │                        │                            │
 │                        │  PoolKey, liquidity        │
 │                        │───────────────────────────>│
 │                        │                            │
 │                        │                            │ [4. Mint tokens]
 │                        │                            │ poolId = key.toId()
 │                        │                            │ owner = posm.ownerOf(tokenId)
 │                        │                            │ _mint(poolId, owner, liquidity)
 │                        │                            │
 │                        │                            │ [5. Store state]
 │                        │                            │ poolIds[tokenId] = poolId
 │                        │                            │ ownerOf[tokenId] = owner
 │                        │                            │
 │                        │  ✅ Success                 │
 │                        │<───────────────────────────│
 │                        │                            │
 │  ✅ Subscribed          │                            │
 │<───────────────────────│                            │
 │                        │                            │
```

**Key Steps**:
1. User calls `subscribe()` on Position Manager
2. Position Manager validates ownership and state
3. Position Manager calls `notifySubscribe()` on subscriber
4. Subscriber mints tokens equal to current liquidity
5. Subscriber stores poolId and owner for future reference

### Flow 2: Modifying Liquidity (Increase)

```
USER                POSITION MANAGER           SUBSCRIBER CONTRACT
 │                        │                            │
 │  increaseLiquidity(    │                            │
 │    tokenId, +1000)     │                            │
 │───────────────────────>│                            │
 │                        │                            │
 │                        │ [1. Add liquidity to pool] │
 │                        │ Execute INCREASE_LIQUIDITY │
 │                        │ action                     │
 │                        │                            │
 │                        │ [2. Check subscription]    │
 │                        │ subscriber = subscribers   │
 │                        │   [tokenId]                │
 │                        │ if (subscriber != 0) {     │
 │                        │                            │
 │                        │  notifyModifyLiquidity(    │
 │                        │    tokenId,                │
 │                        │    +1000, feesAccrued)     │
 │                        │───────────────────────────>│
 │                        │                            │
 │                        │                            │ [3. Get stored data]
 │                        │                            │ poolId = poolIds[tokenId]
 │                        │                            │ owner = ownerOf[tokenId]
 │                        │                            │
 │                        │                            │ [4. Check delta]
 │                        │                            │ liquidityChange = +1000
 │                        │                            │ if (liquidityChange > 0) {
 │                        │                            │
 │                        │                            │ [5. Mint additional tokens]
 │                        │                            │ _mint(poolId, owner, 1000)
 │                        │                            │ }
 │                        │                            │
 │                        │  ✅ Success                 │
 │                        │<───────────────────────────│
 │                        │ }                          │
 │                        │                            │
 │  ✅ Liquidity increased │                            │
 │<───────────────────────│                            │
 │                        │                            │
```

**Key Points**:
- Position Manager automatically notifies subscriber after liquidity change
- Positive `liquidityChange` → mint tokens
- Subscriber uses stored poolId and owner (more efficient)

### Flow 3: Modifying Liquidity (Decrease)

```
USER                POSITION MANAGER           SUBSCRIBER CONTRACT
 │                        │                            │
 │  decreaseLiquidity(    │                            │
 │    tokenId, -500)      │                            │
 │───────────────────────>│                            │
 │                        │                            │
 │                        │ [1. Remove liquidity]      │
 │                        │ Execute DECREASE_LIQUIDITY │
 │                        │ action                     │
 │                        │                            │
 │                        │ [2. Notify subscriber]     │
 │                        │  notifyModifyLiquidity(    │
 │                        │    tokenId,                │
 │                        │    -500, feesAccrued)      │
 │                        │───────────────────────────>│
 │                        │                            │
 │                        │                            │ [3. Get stored data]
 │                        │                            │ poolId = poolIds[tokenId]
 │                        │                            │ owner = ownerOf[tokenId]
 │                        │                            │
 │                        │                            │ [4. Check delta]
 │                        │                            │ liquidityChange = -500
 │                        │                            │ if (liquidityChange < 0) {
 │                        │                            │
 │                        │                            │ [5. Burn tokens]
 │                        │                            │ amount = min(
 │                        │                            │   uint(-liquidityChange),
 │                        │                            │   balanceOf[poolId][owner]
 │                        │                            │ )
 │                        │                            │ _burn(poolId, owner, amount)
 │                        │                            │ }
 │                        │                            │
 │                        │  ✅ Success                 │
 │                        │<───────────────────────────│
 │                        │                            │
 │  ✅ Liquidity decreased │                            │
 │<───────────────────────│                            │
 │                        │                            │
```

**Key Points**:
- Negative `liquidityChange` → burn tokens
- Use `min()` to handle edge cases (fees may increase liquidity)
- State persists (not deleted) unless position burned

### Flow 4: Unsubscribing

```
USER                POSITION MANAGER           SUBSCRIBER CONTRACT
 │                        │                            │
 │  unsubscribe(tokenId)  │                            │
 │───────────────────────>│                            │
 │                        │                            │
 │                        │ [1. Validate]              │
 │                        │ • Caller is owner?         │
 │                        │ • Is subscribed?           │
 │                        │ ✅                         │
 │                        │                            │
 │                        │ [2. Call with gas limit]   │
 │                        │  notifyUnsubscribe{        │
 │                        │    gas: unsubscribeGasLimit│
 │                        │  }(tokenId)                │
 │                        │───────────────────────────>│
 │                        │                            │
 │                        │                            │ [3. Get stored data]
 │                        │                            │ poolId = poolIds[tokenId]
 │                        │                            │ owner = ownerOf[tokenId]
 │                        │                            │ balance = balanceOf
 │                        │                            │   [poolId][owner]
 │                        │                            │
 │                        │                            │ [4. Burn all tokens]
 │                        │                            │ _burn(poolId, owner,
 │                        │                            │       balance)
 │                        │                            │
 │                        │                            │ [5. Delete state]
 │                        │                            │ delete poolIds[tokenId]
 │                        │                            │ delete ownerOf[tokenId]
 │                        │                            │
 │                        │  ✅ Success                 │
 │                        │<───────────────────────────│
 │                        │                            │
 │                        │ [6. Clear subscription]    │
 │                        │ delete subscribers[tokenId]│
 │                        │                            │
 │  ✅ Unsubscribed        │                            │
 │<───────────────────────│                            │
 │                        │                            │
```

**Important**: 
- `notifyUnsubscribe` has a **gas limit** to prevent DoS
- Must clean up ALL state for the tokenId
- Use stored data (can't rely on position existing)

### Flow 5: Burning Position

```
USER                POSITION MANAGER           SUBSCRIBER CONTRACT
 │                        │                            │
 │  burn(tokenId)         │                            │
 │───────────────────────>│                            │
 │                        │                            │
 │                        │ [1. Check subscription]    │
 │                        │ subscriber = subscribers   │
 │                        │   [tokenId]                │
 │                        │ if (subscriber != 0) {     │
 │                        │                            │
 │                        │ [2. Notify BEFORE burn]    │
 │                        │  notifyBurn(tokenId,       │
 │                        │    owner, info, liq, fees) │
 │                        │───────────────────────────>│
 │                        │                            │
 │                        │                            │ [3. Use stored data]
 │                        │                            │ ⚠️ CANNOT call getInfo()!
 │                        │                            │ (NFT will be burned)
 │                        │                            │
 │                        │                            │ poolId = poolIds[tokenId]
 │                        │                            │ // owner from param
 │                        │                            │ balance = balanceOf
 │                        │                            │   [poolId][owner]
 │                        │                            │
 │                        │                            │ [4. Burn all tokens]
 │                        │                            │ _burn(poolId, owner,
 │                        │                            │       balance)
 │                        │                            │
 │                        │                            │ [5. Delete state]
 │                        │                            │ delete poolIds[tokenId]
 │                        │                            │ delete ownerOf[tokenId]
 │                        │                            │
 │                        │  ✅ Success                 │
 │                        │<───────────────────────────│
 │                        │ }                          │
 │                        │                            │
 │                        │ [6. Burn NFT]              │
 │                        │ _burn(tokenId)             │
 │                        │ Remove all position data   │
 │                        │                            │
 │  ✅ Position burned     │                            │
 │<───────────────────────│                            │
 │                        │                            │
```

**Critical Differences from Unsubscribe**:
- `notifyBurn()` called BEFORE NFT is destroyed
- Receives owner and liquidity as parameters
- CANNOT call `posm.getPoolAndPositionInfo()` or `posm.ownerOf()`
- Must use stored state (poolIds, ownerOf mappings)

## 📚 ISubscriber Interface Reference

### Complete Interface

```solidity
interface ISubscriber {
    /// @notice Called when a position subscribes to this subscriber contract
    function notifySubscribe(uint256 tokenId, bytes memory data) external;

    /// @notice Called when a position unsubscribes from the subscriber
    /// @dev Gas is capped at `unsubscribeGasLimit`
    function notifyUnsubscribe(uint256 tokenId) external;

    /// @notice Called when a position is burned
    function notifyBurn(
        uint256 tokenId,
        address owner,
        uint256 info,
        uint256 liquidity,
        int256 feesAccrued
    ) external;

    /// @notice Called when a position modifies its liquidity or collects fees
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityChange,
        int256 feesAccrued
    ) external;
}
```

### Notification Types

| Notification | When Called | Parameters | Purpose |
|--------------|-------------|------------|---------|
| **notifySubscribe** | User calls `posm.subscribe()` | tokenId, data | Initialize tracking for new subscription |
| **notifyUnsubscribe** | User calls `posm.unsubscribe()` | tokenId | Clean up tracking when unsubscribing |
| **notifyBurn** | User calls `posm.burn()` (if subscribed) | tokenId, owner, info, liquidity, feesAccrued | Handle position destruction |
| **notifyModifyLiquidity** | After `increaseLiquidity()` or `decreaseLiquidity()` | tokenId, liquidityChange, feesAccrued | Track liquidity changes |

### Gas Considerations

| Notification | Gas Limit | Behavior on Out-of-Gas |
|--------------|-----------|------------------------|
| **notifySubscribe** | Unlimited | Transaction reverts |
| **notifyUnsubscribe** | Limited (unsubscribeGasLimit) | Silently fails, continues |
| **notifyBurn** | Unlimited | Transaction reverts |
| **notifyModifyLiquidity** | Unlimited | Transaction reverts |

**Why Different Gas Limits?**
- `notifyUnsubscribe` is limited to prevent malicious subscribers from DOS-ing position operations
- Other notifications are user-initiated and expected to complete

### Access Control

All notification functions MUST be protected:

```solidity
modifier onlyPositionManager() {
    require(msg.sender == address(posm), "not PositionManager");
    _;
}

function notifySubscribe(...) external onlyPositionManager { ... }
function notifyUnsubscribe(...) external onlyPositionManager { ... }
function notifyBurn(...) external onlyPositionManager { ... }
function notifyModifyLiquidity(...) external onlyPositionManager { ... }
```

**Why Critical?**
- Prevents unauthorized token minting/burning
- Ensures state consistency
- Protects against manipulation

## 📝 Function-by-Function Implementation Guide

### Helper Function: `getInfo()`

**Purpose**: Retrieve current position information from Position Manager

**Signature**:
```solidity
function getInfo(uint256 tokenId)
    public
    view
    returns (bytes32 poolId, address owner, uint128 liquidity)
```

**Implementation**:
```solidity
function getInfo(uint256 tokenId)
    public
    view
    returns (bytes32 poolId, address owner, uint128 liquidity)
{
    // Get pool key and position info
    (PoolKey memory key,) = posm.getPoolAndPositionInfo(tokenId);
    
    // Convert pool key to pool ID
    poolId = PoolId.unwrap(key.toId());
    
    // Get NFT owner (reverts if doesn't exist)
    owner = posm.ownerOf(tokenId);
    
    // Get current liquidity amount
    liquidity = posm.getPositionLiquidity(tokenId);
}
```

**When to Use**:
- ✅ In `notifySubscribe()` - position exists
- ✅ In `notifyModifyLiquidity()` - position exists
- ❌ In `notifyUnsubscribe()` - use stored data (gas optimization)
- ❌ In `notifyBurn()` - NFT will be burned, can't query!

**Important Notes**:
- `posm.ownerOf()` reverts if tokenId doesn't exist
- This is a helper, not part of ISubscriber interface
- Provides convenient access to commonly needed data

---

### Function 1: `notifySubscribe()`

**Purpose**: Initialize tracking when a position subscribes

**Signature**:
```solidity
function notifySubscribe(uint256 tokenId, bytes memory data)
    external
    onlyPositionManager
```

**Parameters**:
- `tokenId`: The NFT token ID of the subscribing position
- `data`: Optional data passed by the user (can be empty)

**Returns**: Nothing (void)

#### Implementation Steps

**Step 1: Get Position Information**
```solidity
(bytes32 poolId, address owner, uint128 liquidity) = getInfo(tokenId);
```

**Why?** We need to know:
- Which pool this position belongs to
- Who owns the position
- How much liquidity they have

**Step 2: Mint Non-Transferable Tokens**
```solidity
_mint(poolId, owner, liquidity);
```

**Token Amount = Liquidity Amount**: The user receives tokens equal to their initial liquidity. This creates a 1:1 relationship.

**Step 3: Store Pool Association**
```solidity
poolIds[tokenId] = poolId;
```

**Why Store?** Future notifications may not be able to query the NFT (e.g., `notifyBurn`).

**Step 4: Store Owner**
```solidity
ownerOf[tokenId] = owner;
```

**Why Store?** Same reason - we need this data when the NFT might be destroyed.

#### Complete Function

```solidity
function notifySubscribe(uint256 tokenId, bytes memory data)
    external
    onlyPositionManager
{
    // Get current position data
    (bytes32 poolId, address owner, uint128 liquidity) = getInfo(tokenId);
    
    // Mint tokens equal to initial liquidity
    _mint(poolId, owner, liquidity);
    
    // Store for future reference
    poolIds[tokenId] = poolId;
    ownerOf[tokenId] = owner;
}
```

#### State After Subscribe

```
Before:
  poolIds[tokenId] = 0
  ownerOf[tokenId] = address(0)
  balanceOf[poolId][owner] = 0

After:
  poolIds[tokenId] = poolId (e.g., 0xabc123...)
  ownerOf[tokenId] = owner (e.g., 0xUser...)
  balanceOf[poolId][owner] = liquidity (e.g., 1e18)
```

#### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "not PositionManager" | Called by non-PM address | Only PM can call |
| Revert in getInfo() | tokenId doesn't exist | Validate before subscribing |
| Out of gas | Too much logic | Keep subscribe simple |

---

### Function 2: `notifyUnsubscribe()`

**Purpose**: Clean up state when user unsubscribes

**Signature**:
```solidity
function notifyUnsubscribe(uint256 tokenId) 
    external 
    onlyPositionManager
```

**Parameters**:
- `tokenId`: The position being unsubscribed

**Returns**: Nothing (void)

#### Implementation Steps

**Step 1: Retrieve Stored Data**
```solidity
bytes32 poolId = poolIds[tokenId];
address owner = ownerOf[tokenId];
```

**Why Not Use getInfo()?**
- Gas optimization - stored data is cheaper
- More efficient than querying Position Manager
- Still works if position has issues

**Step 2: Get Current Balance**
```solidity
uint256 balance = balanceOf[poolId][owner];
```

**Why?** User's balance may differ from original liquidity due to:
- Multiple increases/decreases
- Fees accrued
- Partial burns

**Step 3: Burn All Tokens**
```solidity
_burn(poolId, owner, balance);
```

**Burn ALL tokens** for this position, regardless of amount.

**Step 4: Delete Stored Data**
```solidity
delete poolIds[tokenId];
delete ownerOf[tokenId];
```

**Critical**: Always clean up! Storage refund = gas savings.

#### Complete Function

```solidity
function notifyUnsubscribe(uint256 tokenId) 
    external 
    onlyPositionManager 
{
    // Get stored data (can't rely on getInfo)
    bytes32 poolId = poolIds[tokenId];
    address owner = ownerOf[tokenId];
    
    // Burn all tokens for this position
    _burn(poolId, owner, balanceOf[poolId][owner]);
    
    // Clean up state
    delete poolIds[tokenId];
    delete ownerOf[tokenId];
}
```

#### Alternative Implementation (From Exercise)

The exercise starter uses `getInfo()`:

```solidity
function notifyUnsubscribe(uint256 tokenId) 
    external 
    onlyPositionManager 
{
    (bytes32 poolId, address owner, uint128 liquidity) = getInfo(tokenId);
    _burn(poolId, owner, liquidity);
    delete poolIds[tokenId];
    delete ownerOf[tokenId];
}
```

**Problem**: Burns `liquidity` (current position) instead of `balanceOf` (user's tokens).

**Why It Matters**:
```
User subscribes with 1000 liquidity
User increases by 500 (now 1500 total)
User unsubscribes
  - getInfo() returns liquidity = 1500
  - But balanceOf might be different due to fees
  - Should burn actual token balance, not position liquidity
```

**Solution Version** (More Robust):
```solidity
_burn(poolId, owner, balanceOf[poolId][owner]);
```

#### State After Unsubscribe

```
Before:
  poolIds[tokenId] = poolId
  ownerOf[tokenId] = owner
  balanceOf[poolId][owner] = 1500

After:
  poolIds[tokenId] = 0 (deleted)
  ownerOf[tokenId] = address(0) (deleted)
  balanceOf[poolId][owner] = 0
```

#### Gas Limit Warning

⚠️ **Critical**: This function has a **gas limit**!

```solidity
// In Position Manager:
function unsubscribe(uint256 tokenId) external {
    // ... validation ...
    
    ISubscriber(subscriber).notifyUnsubscribe{
        gas: unsubscribeGasLimit  // Limited!
    }(tokenId);
    
    // If out of gas, continues anyway
}
```

**Implications**:
- Keep logic simple and efficient
- Avoid unbounded loops
- Minimize storage operations
- Test gas usage thoroughly

---

### Function 3: `notifyBurn()`

**Purpose**: Handle position destruction (NFT burn)

**Signature**:
```solidity
function notifyBurn(
    uint256 tokenId,
    address owner,
    uint256 info,
    uint256 liquidity,
    int256 feesAccrued
) external onlyPositionManager
```

**Parameters**:
- `tokenId`: Position being burned
- `owner`: Owner of the position (provided by PM)
- `info`: Position info packed as uint256
- `liquidity`: Liquidity amount in position
- `feesAccrued`: Fees collected during burn

**Returns**: Nothing (void)

#### Implementation Steps

**Step 1: Retrieve Stored Pool ID**
```solidity
bytes32 poolId = poolIds[tokenId];
```

**Critical**: CANNOT use `getInfo(tokenId)` here!

**Why?** The NFT will be burned AFTER this callback returns. Calling `posm.ownerOf(tokenId)` would revert.

**Step 2: Burn All User's Tokens**
```solidity
_burn(poolId, owner, balanceOf[poolId][owner]);
```

**Why `balanceOf[poolId][owner]` not `liquidity`?**
- Position liquidity may be > token balance
- Positions accumulate fees over time
- Fee growth can inflate liquidity
- User tokens should match their deposits, not final liquidity

**Example**:
```
User subscribes with 1000 liquidity
  → mints 1000 tokens
  
Position earns 100 in fees
  → position liquidity becomes 1100
  → but user still has 1000 tokens
  
On burn:
  - liquidity parameter = 1100
  - balanceOf[poolId][owner] = 1000
  - Should burn 1000 tokens (what user has)
```

**Step 3: Clean Up State**
```solidity
delete poolIds[tokenId];
delete ownerOf[tokenId];
```

Same cleanup as unsubscribe.

#### Complete Function

```solidity
function notifyBurn(
    uint256 tokenId,
    address owner,
    uint256 info,
    uint256 liquidity,
    int256 feesAccrued
) external onlyPositionManager {
    // MUST use stored data - NFT will be destroyed!
    bytes32 poolId = poolIds[tokenId];
    
    // Burn user's token balance (not position liquidity)
    _burn(poolId, owner, balanceOf[poolId][owner]);
    
    // Clean up state
    delete poolIds[tokenId];
    delete ownerOf[tokenId];
}
```

#### Comparison: Unsubscribe vs Burn

| Aspect | notifyUnsubscribe | notifyBurn |
|--------|-------------------|------------|
| **NFT State** | Still exists | About to be destroyed |
| **Can use getInfo()** | ✅ Yes | ❌ No - will revert |
| **Owner param** | ❌ Not provided | ✅ Provided |
| **Liquidity param** | ❌ Not provided | ✅ Provided |
| **Gas Limit** | ✅ Limited | ❌ Unlimited |
| **When Called** | User chooses | User burns position |

#### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| Revert in getInfo() | Trying to query burned NFT | Use stored poolIds[tokenId] |
| Underflow in _burn | Burning more than balance | Use balanceOf, not liquidity |
| "not PositionManager" | Wrong caller | Only PM can call |

---

### Function 4: `notifyModifyLiquidity()`

**Purpose**: Track liquidity increases and decreases

**Signature**:
```solidity
function notifyModifyLiquidity(
    uint256 tokenId,
    int256 liquidityChange,
    int256 feesAccrued
) external onlyPositionManager
```

**Parameters**:
- `tokenId`: Position being modified
- `liquidityChange`: Change in liquidity (positive = increase, negative = decrease)
- `feesAccrued`: Fees collected during the modification

**Returns**: Nothing (void)

#### Implementation Steps

**Step 1: Retrieve Stored Data**
```solidity
bytes32 poolId = poolIds[tokenId];
address owner = ownerOf[tokenId];
```

**Why Stored?** More efficient than querying, and guaranteed to exist.

**Step 2: Check Direction of Change**
```solidity
if (liquidityChange > 0) {
    // Increase - mint tokens
} else {
    // Decrease - burn tokens
}
```

**Step 3a: Handle Increase**
```solidity
if (liquidityChange > 0) {
    _mint(poolId, owner, uint256(liquidityChange));
}
```

**Simple**: Just mint the additional amount.

**Step 3b: Handle Decrease**
```solidity
else {
    uint256 burnAmount = min(
        uint256(-liquidityChange),
        balanceOf[poolId][owner]
    );
    _burn(poolId, owner, burnAmount);
}
```

**Why `min()`?**
- Protects against underflow
- Handles fee-inflated positions
- User can't burn more tokens than they have

**Example Scenario**:
```
User has 1000 tokens
Position has 1100 liquidity (due to fees)
User decreases by 1100
  - liquidityChange = -1100
  - But user only has 1000 tokens
  - min(-(-1100), 1000) = min(1100, 1000) = 1000
  - Burns 1000 (all user tokens)
```

#### Complete Function (Solution)

```solidity
function notifyModifyLiquidity(
    uint256 tokenId,
    int256 liquidityChange,
    int256 feesAccrued
) external onlyPositionManager {
    bytes32 poolId = poolIds[tokenId];
    address owner = ownerOf[tokenId];
    
    if (liquidityChange > 0) {
        // Increase: mint additional tokens
        _mint(poolId, owner, uint256(liquidityChange));
    } else {
        // Decrease: burn tokens safely
        _burn(
            poolId,
            owner,
            min(uint256(-liquidityChange), balanceOf[poolId][owner])
        );
    }
}
```

#### Alternative Implementation (Simpler but Less Safe)

```solidity
function notifyModifyLiquidity(
    uint256 tokenId,
    int256 liquidityChange,
    int256 feesAccrued
) external onlyPositionManager {
    (bytes32 poolId, address owner, uint128 liquidity) = getInfo(tokenId);
    
    if (liquidityChange > 0) {
        _mint(poolId, owner, uint256(liquidityChange));
    } else {
        _burn(poolId, owner, uint256(-liquidityChange));
    }
}
```

**Risks**:
- No `min()` protection → could underflow
- Uses `getInfo()` → less gas efficient
- Assumes balance always >= liquidityChange

#### State Changes

**Increase Example**:
```
Before:
  balanceOf[poolId][owner] = 1000
  
notifyModifyLiquidity(tokenId, +500, 0)
  
After:
  balanceOf[poolId][owner] = 1500
```

**Decrease Example**:
```
Before:
  balanceOf[poolId][owner] = 1500
  
notifyModifyLiquidity(tokenId, -300, 0)
  
After:
  balanceOf[poolId][owner] = 1200
```

#### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| Underflow in _burn | Burning more than balance | Use min() protection |
| "not PositionManager" | Wrong caller | Only PM calls this |
| Using deleted state | Called after unsubscribe | Check if subscribed first |

---

## 🧪 Testing Guide

### Test Setup

```solidity
contract SubscriberTest is Test {
    Subscriber sub;
    IPositionManager posm;
    uint256 tokenId;
    uint256 liquidity = 1e12;
    bytes32 poolId;
    
    function setUp() public {
        // Deploy subscriber
        sub = new Subscriber(address(posm));
        
        // Fund test account
        deal(USDC, address(this), 1_000_000e6);
        deal(address(this), 100 ether);
        
        // Mint a position
        tokenId = mint({
            tickLower: -100,
            tickUpper: 100,
            liquidity: liquidity
        });
        
        // Get pool ID for assertions
        (PoolKey memory key,) = posm.getPoolAndPositionInfo(tokenId);
        poolId = PoolId.unwrap(key.toId());
    }
}
```

### Test 1: Subscribe Notification

```solidity
function test_notifySubscribe() public {
    // Subscribe to the subscriber contract
    posm.subscribe(tokenId, address(sub), "");
    
    // Verify tokens minted
    assertEq(
        sub.balanceOf(poolId, address(this)),
        liquidity,
        "Should mint tokens = liquidity"
    );
    
    // Verify state stored
    (bytes32 storedPoolId, address storedOwner,) = 
        sub.getStoredInfo(tokenId);
    assertEq(storedPoolId, poolId, "Pool ID stored");
    assertEq(storedOwner, address(this), "Owner stored");
}
```

### Test 2: Unsubscribe Notification

```solidity
function test_notifyUnsubscribe() public {
    // First subscribe
    posm.subscribe(tokenId, address(sub), "");
    uint256 initialBalance = sub.balanceOf(poolId, address(this));
    assertGt(initialBalance, 0, "Should have tokens");
    
    // Then unsubscribe
    posm.unsubscribe(tokenId);
    
    // Verify tokens burned
    assertEq(
        sub.balanceOf(poolId, address(this)),
        0,
        "All tokens should be burned"
    );
    
    // Verify state cleaned up
    (bytes32 storedPoolId, address storedOwner,) = 
        sub.getStoredInfo(tokenId);
    assertEq(storedPoolId, bytes32(0), "Pool ID deleted");
    assertEq(storedOwner, address(0), "Owner deleted");
}
```

### Test 3: Modify Liquidity (Increase)

```solidity
function test_notifyModifyLiquidity_increase() public {
    // Subscribe first
    posm.subscribe(tokenId, address(sub), "");
    uint256 initialBalance = sub.balanceOf(poolId, address(this));
    
    // Increase liquidity
    increaseLiquidity({
        tokenId: tokenId,
        liquidity: liquidity,  // Double it
        amount0Max: uint128(address(this).balance),
        amount1Max: uint128(usdc.balanceOf(address(this)))
    });
    
    // Verify additional tokens minted
    assertEq(
        sub.balanceOf(poolId, address(this)),
        2 * liquidity,
        "Should double token balance"
    );
    
    // Verify delta
    assertEq(
        sub.balanceOf(poolId, address(this)) - initialBalance,
        liquidity,
        "Delta should equal increase"
    );
}
```

### Test 4: Modify Liquidity (Decrease)

```solidity
function test_notifyModifyLiquidity_decrease() public {
    // Subscribe and increase first
    posm.subscribe(tokenId, address(sub), "");
    increaseLiquidity(tokenId, liquidity, type(uint128).max, type(uint128).max);
    
    uint256 balanceBefore = sub.balanceOf(poolId, address(this));
    assertEq(balanceBefore, 2 * liquidity);
    
    // Decrease liquidity
    decreaseLiquidity({
        tokenId: tokenId,
        liquidity: liquidity,  // Remove half
        amount0Min: 1,
        amount1Min: 1
    });
    
    // Verify tokens burned
    assertEq(
        sub.balanceOf(poolId, address(this)),
        liquidity,
        "Should have half tokens left"
    );
}
```

### Test 5: Burn Notification

```solidity
function test_notifyBurn() public {
    // Subscribe first
    posm.subscribe(tokenId, address(sub), "");
    uint256 balanceBefore = sub.balanceOf(poolId, address(this));
    assertGt(balanceBefore, 0);
    
    // Burn the position
    burn(tokenId, 1, 1);
    
    // Verify all tokens burned
    assertEq(
        sub.balanceOf(poolId, address(this)),
        0,
        "All tokens should be burned"
    );
    
    // Verify state cleaned
    (bytes32 storedPoolId, address storedOwner,) = 
        sub.getStoredInfo(tokenId);
    assertEq(storedPoolId, bytes32(0), "Pool ID deleted");
    assertEq(storedOwner, address(0), "Owner deleted");
}
```

### Test 6: Multiple Positions Same Pool

```solidity
function test_multiplePositions() public {
    // Mint second position
    uint256 tokenId2 = mint({
        tickLower: -200,
        tickUpper: 200,
        liquidity: liquidity * 2
    });
    
    // Subscribe both
    posm.subscribe(tokenId, address(sub), "");
    posm.subscribe(tokenId2, address(sub), "");
    
    // Verify separate tracking but same pool
    assertEq(
        sub.balanceOf(poolId, address(this)),
        liquidity + (liquidity * 2),
        "Should sum both positions"
    );
    
    // Unsubscribe first
    posm.unsubscribe(tokenId);
    
    // Verify only first burned
    assertEq(
        sub.balanceOf(poolId, address(this)),
        liquidity * 2,
        "Should only burn first position tokens"
    );
}
```

### Running Tests

```bash
# Run all subscriber tests
forge test --fork-url $FORK_URL --match-path test/Subscriber.test.sol -vvv

# Run specific test
forge test --fork-url $FORK_URL --match-test test_notifySubscribe -vvvv

# With gas report
forge test --fork-url $FORK_URL --match-path test/Subscriber.test.sol --gas-report
```

### Expected Output

```
Running 4 tests for test/Subscriber.test.sol:SubscriberTest

[PASS] test_notifySubscribe() (gas: 245128)
Logs:
  Initial balance: 0
  After subscribe: 1000000000000

[PASS] test_notifyUnsubscribe() (gas: 267943)
Logs:
  After subscribe: 1000000000000
  After unsubscribe: 0

[PASS] test_notifyModifyLiquidity() (gas: 456821)
Logs:
  Initial: 1000000000000
  After increase: 2000000000000
  After decrease: 1000000000000

[PASS] test_notifyBurn() (gas: 298562)
Logs:
  Before burn: 1000000000000
  After burn: 0

Test result: ok. 4 passed; 0 failed; finished in 2.14s
```

---

## 🐛 Debugging Guide

### Problem 1: "not PositionManager" Error

**Symptom**:
```
Error: not PositionManager
```

**Root Cause**: Function called by unauthorized address

**Debug Steps**:

1. **Check msg.sender**:
```solidity
console.log("msg.sender:", msg.sender);
console.log("posm address:", address(posm));
```

2. **Verify Test Setup**:
```solidity
// ❌ WRONG: Calling directly
sub.notifySubscribe(tokenId, "");

// ✅ CORRECT: Let Position Manager call
posm.subscribe(tokenId, address(sub), "");
```

**Solution**: Always use Position Manager functions, not subscriber functions directly.

---

### Problem 2: Underflow in _burn

**Symptom**:
```
Error: Arithmetic underflow
```

**Root Cause**: Trying to burn more tokens than user has

**Debug Steps**:

1. **Check Balances**:
```solidity
console.log("User balance:", sub.balanceOf(poolId, owner));
console.log("Trying to burn:", amount);
```

2. **Check liquidityChange**:
```solidity
console.log("Liquidity change:", liquidityChange);
console.log("Position liquidity:", posm.getPositionLiquidity(tokenId));
```

**Solution**: Use `min()` function in notifyModifyLiquidity:

```solidity
// ❌ WRONG: Direct burn
_burn(poolId, owner, uint256(-liquidityChange));

// ✅ CORRECT: Safe burn
_burn(poolId, owner, min(uint256(-liquidityChange), balanceOf[poolId][owner]));
```

---

### Problem 3: State Not Deleted

**Symptom**: Gas not refunded, or stale data causes issues

**Debug Steps**:

1. **Check After Unsubscribe**:
```solidity
function test_stateDeleted() public {
    posm.subscribe(tokenId, address(sub), "");
    posm.unsubscribe(tokenId);
    
    // Should be deleted
    assertEq(sub.poolIds(tokenId), bytes32(0));
    assertEq(sub.ownerOf(tokenId), address(0));
}
```

**Solution**: Always delete state in cleanup functions:

```solidity
function notifyUnsubscribe(uint256 tokenId) external {
    // ... burn logic ...
    
    // ✅ CRITICAL: Delete state
    delete poolIds[tokenId];
    delete ownerOf[tokenId];
}
```

---

### Problem 4: Using getInfo() in notifyBurn

**Symptom**:
```
Error: ERC721: owner query for nonexistent token
```

**Root Cause**: NFT is burned after callback, can't query it

**Debug Steps**:

```solidity
function notifyBurn(...) external {
    // ❌ WRONG: This will revert
    (bytes32 poolId, address owner,) = getInfo(tokenId);
    
    // getInfo() calls:
    //   posm.ownerOf(tokenId) ← REVERTS! Token being burned
}
```

**Solution**: Use stored data and function parameters:

```solidity
function notifyBurn(
    uint256 tokenId,
    address owner,  // ✅ Use this parameter
    ...
) external {
    // ✅ CORRECT: Use stored data
    bytes32 poolId = poolIds[tokenId];
    
    // Use 'owner' parameter, not posm.ownerOf()
    _burn(poolId, owner, balanceOf[poolId][owner]);
}
```

---

### Problem 5: Out of Gas in Unsubscribe

**Symptom**: Unsubscribe succeeds but tokens not burned

**Root Cause**: Gas limit exceeded in notifyUnsubscribe

**Debug Steps**:

1. **Check Gas Usage**:
```bash
forge test --match-test test_notifyUnsubscribe --gas-report
```

2. **Compare Against Limit**:
```solidity
// Position Manager sets limit at deployment
uint256 unsubscribeGasLimit = 100_000; // Example

// Your function uses:
// SLOAD (poolId) = 2100
// SLOAD (owner) = 2100
// SLOAD (balanceOf) = 2100
// SSTORE (burn) = 2900
// DELETE (poolIds) = -15000 (refund)
// DELETE (ownerOf) = -15000 (refund)
// Total: ~60,000 (safe)
```

**Solution**: Keep notifyUnsubscribe simple:

```solidity
// ✅ GOOD: Minimal operations
function notifyUnsubscribe(uint256 tokenId) external {
    bytes32 poolId = poolIds[tokenId];
    address owner = ownerOf[tokenId];
    _burn(poolId, owner, balanceOf[poolId][owner]);
    delete poolIds[tokenId];
    delete ownerOf[tokenId];
}

// ❌ BAD: Too complex
function notifyUnsubscribe(uint256 tokenId) external {
    // Multiple external calls
    // Unbounded loops
    // Complex calculations
    // Will exceed gas limit!
}
```

---

## 💼 Real-World Applications

### Use Case 1: Reputation System

```solidity
contract LPReputationSubscriber is ISubscriber {
    // Track reputation based on liquidity provision duration
    mapping(address => uint256) public reputationPoints;
    mapping(uint256 => uint256) public subscribeTimestamp;
    
    function notifySubscribe(uint256 tokenId, bytes memory) external {
        (bytes32 poolId, address owner, uint128 liquidity) = getInfo(tokenId);
        subscribeTimestamp[tokenId] = block.timestamp;
        // Initialize tracking
    }
    
    function notifyUnsubscribe(uint256 tokenId) external {
        uint256 duration = block.timestamp - subscribeTimestamp[tokenId];
        address owner = ownerOf[tokenId];
        
        // Award reputation based on duration and amount
        reputationPoints[owner] += duration * liquidity / 1e18;
        
        // Cleanup
        delete subscribeTimestamp[tokenId];
    }
    
    // Reputation can be used for:
    // - Governance voting weight
    // - Fee discounts
    // - Access to exclusive pools
    // - Loyalty rewards
}
```

### Use Case 2: Auto-Compounding Vault

```solidity
contract AutoCompoundSubscriber is ISubscriber {
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityChange,
        int256 feesAccrued
    ) external {
        if (feesAccrued > 0) {
            // Fees were collected
            // Automatically reinvest them
            
            // Swap fees to balanced ratio
            (uint256 amount0, uint256 amount1) = 
                balanceFeesForPool(feesAccrued);
            
            // Add back to position
            posm.increaseLiquidity(
                tokenId,
                calculateLiquidity(amount0, amount1),
                uint128(amount0),
                uint128(amount1)
            );
        }
    }
}
```

### Use Case 3: Analytics Dashboard

```solidity
contract AnalyticsSubscriber is ISubscriber {
    struct PositionMetrics {
        uint256 totalLiquidityAdded;
        uint256 totalLiquidityRemoved;
        uint256 numberOfModifications;
        uint256 totalFeesEarned;
        uint256 subscribeTime;
        uint256 unsubscribeTime;
    }
    
    mapping(uint256 => PositionMetrics) public metrics;
    mapping(address => uint256[]) public userPositions;
    
    function notifySubscribe(uint256 tokenId, bytes memory) external {
        metrics[tokenId].subscribeTime = block.timestamp;
        userPositions[owner].push(tokenId);
    }
    
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityChange,
        int256 feesAccrued
    ) external {
        PositionMetrics storage m = metrics[tokenId];
        m.numberOfModifications++;
        
        if (liquidityChange > 0) {
            m.totalLiquidityAdded += uint256(liquidityChange);
        } else {
            m.totalLiquidityRemoved += uint256(-liquidityChange);
        }
        
        m.totalFeesEarned += uint256(feesAccrued);
    }
    
    function notifyUnsubscribe(uint256 tokenId) external {
        metrics[tokenId].unsubscribeTime = block.timestamp;
    }
    
    // Query functions for dashboard
    function getPositionROI(uint256 tokenId) external view returns (uint256) {
        PositionMetrics memory m = metrics[tokenId];
        return (m.totalFeesEarned * 10000) / m.totalLiquidityAdded;
    }
    
    function getUserMetrics(address user) external view returns (
        uint256 totalPositions,
        uint256 totalLiquidity,
        uint256 totalFees
    ) {
        uint256[] memory positions = userPositions[user];
        for (uint i = 0; i < positions.length; i++) {
            PositionMetrics memory m = metrics[positions[i]];
            totalPositions++;
            totalLiquidity += m.totalLiquidityAdded;
            totalFees += m.totalFeesEarned;
        }
    }
}
```

### Use Case 4: Fee Sharing Pool

```solidity
contract FeeShareSubscriber is ISubscriber {
    // Share fees proportionally among all LPs
    mapping(bytes32 => uint256) public totalShares; // poolId => total
    mapping(bytes32 => mapping(address => uint256)) public shares; // poolId => user => amount
    mapping(bytes32 => uint256) public feePool; // Accumulated fees
    
    function notifySubscribe(uint256 tokenId, bytes memory) external {
        (bytes32 poolId, address owner, uint128 liquidity) = getInfo(tokenId);
        shares[poolId][owner] += liquidity;
        totalShares[poolId] += liquidity;
    }
    
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityChange,
        int256 feesAccrued
    ) external {
        bytes32 poolId = poolIds[tokenId];
        address owner = ownerOf[tokenId];
        
        // Add fees to pool
        if (feesAccrued > 0) {
            feePool[poolId] += uint256(feesAccrued);
        }
        
        // Update shares
        if (liquidityChange > 0) {
            shares[poolId][owner] += uint256(liquidityChange);
            totalShares[poolId] += uint256(liquidityChange);
        } else {
            uint256 decrease = uint256(-liquidityChange);
            shares[poolId][owner] -= decrease;
            totalShares[poolId] -= decrease;
        }
    }
    
    function claimFees(bytes32 poolId) external {
        uint256 userShares = shares[poolId][msg.sender];
        uint256 total = totalShares[poolId];
        uint256 fees = feePool[poolId];
        
        // Calculate proportional share
        uint256 userFees = (fees * userShares) / total;
        
        // Transfer fees
        // ... transfer logic ...
        
        feePool[poolId] -= userFees;
    }
}
```

### Use Case 5: Risk Management

```solidity
contract RiskMonitorSubscriber is ISubscriber {
    uint256 constant MAX_POSITION_SIZE = 1000 ether;
    uint256 constant MIN_LIQUIDITY_THRESHOLD = 0.1 ether;
    
    mapping(uint256 => bool) public flaggedPositions;
    
    event PositionFlagged(uint256 indexed tokenId, string reason);
    event PositionUnflagged(uint256 indexed tokenId);
    
    function notifySubscribe(uint256 tokenId, bytes memory) external {
        (, , uint128 liquidity) = getInfo(tokenId);
        
        if (liquidity > MAX_POSITION_SIZE) {
            flaggedPositions[tokenId] = true;
            emit PositionFlagged(tokenId, "Position too large");
        }
    }
    
    function notifyModifyLiquidity(
        uint256 tokenId,
        int256 liquidityChange,
        int256
    ) external {
        (, , uint128 currentLiquidity) = getInfo(tokenId);
        
        // Check for suspicious activity
        if (liquidityChange < 0) {
            uint256 decrease = uint256(-liquidityChange);
            uint256 percentChange = (decrease * 100) / currentLiquidity;
            
            if (percentChange > 90) {
                emit PositionFlagged(tokenId, "Large withdrawal detected");
            }
        }
        
        // Check if position falls below threshold
        if (currentLiquidity < MIN_LIQUIDITY_THRESHOLD) {
            emit PositionFlagged(tokenId, "Below minimum liquidity");
        }
    }
    
    function notifyUnsubscribe(uint256 tokenId) external {
        if (flaggedPositions[tokenId]) {
            delete flaggedPositions[tokenId];
            emit PositionUnflagged(tokenId);
        }
    }
}
```

---

## 🎓 Advanced Concepts

### Non-Transferable Token Pattern

**Why Non-Transferable?**

Traditional ERC20 tokens have `transfer()` and `transferFrom()`. Our Token contract intentionally omits these:

```solidity
contract Token {
    mapping(bytes32 => mapping(address => uint256)) public balanceOf;
    
    function _mint(bytes32 poolId, address dst, uint256 amount) internal {
        balanceOf[poolId][dst] += amount;
    }
    
    function _burn(bytes32 poolId, address src, uint256 amount) internal {
        balanceOf[poolId][src] -= amount;
    }
    
    // ❌ NO transfer() function!
    // ❌ NO transferFrom() function!
    // ❌ NO approve() function!
}
```

**Use Cases**:
- **Reputation/Points**: Can't buy reputation, must earn it
- **Voting Rights**: Tied to actual LP participation
- **Credentials**: Proof of providing liquidity
- **Time-Locked Rewards**: Can't trade before unlock

**Alternative**: Soulbound Tokens (SBTs) - permanently bound to an address

### Multi-Pool Balance Tracking

Our implementation uses `poolId` as a dimension:

```solidity
mapping(bytes32 => mapping(address => uint256)) public balanceOf;
```

This enables:

**1. Per-Pool Isolation**
```solidity
// User provides liquidity to two different pools
balanceOf[poolId1][user] = 1000;
balanceOf[poolId2][user] = 2000;
// Separate tracking, no cross-contamination
```

**2. Pool-Specific Features**
```solidity
function getPoolTokens(bytes32 poolId, address user) 
    external 
    view 
    returns (uint256) 
{
    return balanceOf[poolId][user];
}

function getUserPools(address user) 
    external 
    view 
    returns (bytes32[] memory) 
{
    // Return all pools user participates in
}
```

**3. Pool Governance**
```solidity
function voteOnPoolProposal(bytes32 poolId, uint256 proposalId) external {
    uint256 votes = balanceOf[poolId][msg.sender];
    require(votes > 0, "No voting power in this pool");
    // Cast votes proportional to liquidity in specific pool
}
```

### Gas Optimization Strategies

#### Strategy 1: Use Stored Data

```solidity
// ❌ EXPENSIVE: Query every time
function notifyModifyLiquidity(...) external {
    (PoolKey memory key,) = posm.getPoolAndPositionInfo(tokenId);
    bytes32 poolId = key.toId();
    address owner = posm.ownerOf(tokenId);
    // 2 external calls + computation
}

// ✅ CHEAP: Use stored data
function notifyModifyLiquidity(...) external {
    bytes32 poolId = poolIds[tokenId];  // 1 SLOAD = 2100 gas
    address owner = ownerOf[tokenId];   // 1 SLOAD = 2100 gas
    // Total: 4200 gas vs ~10,000+ gas
}
```

#### Strategy 2: Batch Operations

```solidity
// For managing multiple positions
function batchSubscribe(uint256[] calldata tokenIds) external {
    for (uint i = 0; i < tokenIds.length; i++) {
        posm.subscribe(tokenIds[i], address(this), "");
    }
}
```

#### Strategy 3: Minimal State

```solidity
// ❌ EXCESSIVE: Store too much
struct PositionData {
    bytes32 poolId;
    address owner;
    uint128 liquidity;
    int24 tickLower;
    int24 tickUpper;
    uint256 subscribeTime;
    uint256 feesEarned;
}

// ✅ MINIMAL: Only what you can't query
mapping(uint256 => bytes32) poolIds;
mapping(uint256 => address) ownerOf;
// Everything else queryable from Position Manager
```

#### Strategy 4: Delete When Done

```solidity
// ✅ GOOD: Get refund
delete poolIds[tokenId];      // Refund: 15,000 gas
delete ownerOf[tokenId];      // Refund: 15,000 gas
// Total refund: 30,000 gas

// ❌ BAD: No refund
poolIds[tokenId] = 0;         // Still uses storage slot
ownerOf[tokenId] = address(0); // Still uses storage slot
```

### Security Considerations

#### 1. Access Control is Critical

```solidity
// ❌ DANGEROUS: No protection
function notifySubscribe(uint256 tokenId, bytes memory data) external {
    // Anyone can mint tokens!
}

// ✅ SAFE: Only Position Manager
function notifySubscribe(uint256 tokenId, bytes memory data) 
    external 
    onlyPositionManager 
{
    // Controlled minting
}
```

**Attack Scenario Without Protection**:
```
Attacker calls notifySubscribe(fakeTokenId, "")
  → Mints tokens they don't deserve
  → Can use for governance voting
  → Can claim rewards
  → Can manipulate protocols trusting the token
```

#### 2. Reentrancy Protection

```solidity
// Position Manager protects us, but be careful with:
function notifyModifyLiquidity(...) external onlyPositionManager {
    // ❌ DANGEROUS: External call before state update
    externalContract.doSomething();
    _mint(...);
    
    // ✅ SAFE: State update before external call
    _mint(...);
    externalContract.doSomething();
}
```

#### 3. Integer Overflow/Underflow

```solidity
// ❌ DANGEROUS: Can underflow
function notifyModifyLiquidity(...) external {
    if (liquidityChange < 0) {
        _burn(poolId, owner, uint256(-liquidityChange));
        // What if balance < liquidityChange?
    }
}

// ✅ SAFE: Protected
function notifyModifyLiquidity(...) external {
    if (liquidityChange < 0) {
        uint256 burnAmount = min(
            uint256(-liquidityChange),
            balanceOf[poolId][owner]
        );
        _burn(poolId, owner, burnAmount);
    }
}
```

#### 4. Stale Data Risks

```solidity
// ❌ RISK: Using old data
function getRewards(uint256 tokenId) external {
    address owner = ownerOf[tokenId]; // Stale if owner transferred NFT!
    // Send rewards to wrong person
}

// ✅ BETTER: Always fresh
function getRewards(uint256 tokenId) external {
    address owner = posm.ownerOf(tokenId); // Current owner
    // Send to correct person
}
```

#### 5. Gas Limit DOS

```solidity
// ❌ VULNERABLE: Unbounded operations
function notifyUnsubscribe(uint256 tokenId) external {
    for (uint i = 0; i < largeArray.length; i++) {
        // Complex operations
    }
    // Exceeds gas limit → DOS
}

// ✅ PROTECTED: Simple operations
function notifyUnsubscribe(uint256 tokenId) external {
    // O(1) operations only
    _burn(...);
    delete poolIds[tokenId];
    delete ownerOf[tokenId];
}
```

---

## 📊 Comparison: Subscriber vs Direct Integration

| Aspect | With Subscriber | Direct Integration |
|--------|----------------|-------------------|
| **Coupling** | Loose - separate contract | Tight - Position Manager aware |
| **Upgradability** | Easy - deploy new subscriber | Hard - requires PM upgrade |
| **Gas Cost** | +callback overhead | Cheaper |
| **Flexibility** | High - any logic | Limited to PM features |
| **Setup** | Requires subscription | Automatic |
| **Multiple Trackers** | ✅ Can have many subscribers | ❌ One implementation |
| **User Control** | ✅ Can unsubscribe | ❌ Always tracked |
| **Async Updates** | ✅ Notifications | ❌ Must poll |

### When to Use Subscriber Pattern

✅ **Use Subscribers When**:
- Tracking external metrics (reputation, analytics)
- Building composable features (vaults, governance)
- Need multiple independent trackers
- Users should opt-in to tracking
- Logic may change/upgrade

❌ **Don't Use Subscribers When**:
- Core functionality (use Position Manager directly)
- Gas is critical concern
- Simple queries (use view functions)
- Need 100% coverage (subscribers are opt-in)

---

## 📚 Additional Resources

### Official Documentation
- [Uniswap V4 Docs - Subscribers](https://docs.uniswap.org/contracts/v4/overview)
- [Position Manager Source](https://github.com/Uniswap/v4-periphery/blob/main/src/PositionManager.sol)
- [ISubscriber Interface](https://github.com/Uniswap/v4-periphery/blob/main/src/interfaces/ISubscriber.sol)

### Related Patterns
- [ERC721 Hooks](https://eips.ethereum.org/EIPS/eip-721)
- [Observer Pattern](https://en.wikipedia.org/wiki/Observer_pattern)
- [Soulbound Tokens](https://vitalik.ca/general/2022/01/26/soulbound.html)
- [Non-Transferable NFTs](https://eips.ethereum.org/EIPS/eip-4973)

### Code Examples
- [Subscriber Tests](https://github.com/Uniswap/v4-periphery/tree/main/test/position-managers)
- [Real Subscriber Implementations](https://github.com/Uniswap/v4-periphery/tree/main/src/base)

---

## 🎯 Exercise Checklist

Before moving on, ensure you can:

- [ ] Explain what a subscriber is and why it's useful
- [ ] Implement all four ISubscriber notification functions
- [ ] Understand when to use stored data vs querying Position Manager
- [ ] Protect against underflow in _burn operations
- [ ] Handle the special case of notifyBurn (NFT destroyed)
- [ ] Manage multi-pool token balances correctly
- [ ] Implement gas-efficient notifyUnsubscribe
- [ ] Write comprehensive tests for all notifications
- [ ] Debug common subscriber issues
- [ ] Design real-world subscriber applications

### Self-Assessment Questions

1. **Why can't you call `getInfo()` in `notifyBurn()`?**
   <details>
   <summary>Answer</summary>
   The NFT is being destroyed after the callback. Calling `posm.ownerOf(tokenId)` will revert with "nonexistent token". Use stored `poolIds[tokenId]` and the `owner` parameter instead.
   </details>

2. **Why use `min()` when burning in `notifyModifyLiquidity()`?**
   <details>
   <summary>Answer</summary>
   Position liquidity can be inflated by fees. User might have 1000 tokens but position has 1100 liquidity. Without `min()`, trying to burn 1100 would underflow. `min(1100, 1000) = 1000` protects against this.
   </details>

3. **What happens if `notifyUnsubscribe()` exceeds its gas limit?**
   <details>
   <summary>Answer</summary>
   The call silently fails but the unsubscribe continues. The subscription is cleared in Position Manager, but your state might not be cleaned up. Keep this function simple to avoid this.
   </details>

4. **Why are the tokens non-transferable?**
   <details>
   <summary>Answer</summary>
   They represent actual liquidity provision, which is tied to a specific position and owner. Transferring tokens without transferring the underlying position would break the 1:1 relationship. Also useful for reputation systems.
   </details>

5. **Can one position be subscribed to multiple subscribers?**
   <details>
   <summary>Answer</summary>
   No, Position Manager only tracks one subscriber per tokenId. However, you could create a "meta-subscriber" that forwards notifications to multiple downstream subscribers.
   </details>

---

## 🚀 Next Steps

Now that you've mastered the Subscriber pattern:

1. **Build Real Applications**:
   - Reputation/points system for LPs
   - Auto-compounding vault
   - Analytics dashboard
   - Risk monitoring system

2. **Explore Advanced Patterns**:
   - Meta-subscribers (forwarding to multiple)
   - Conditional subscriptions
   - Fee optimization strategies
   - Cross-protocol integrations

3. **Study Security**:
   - Review subscriber implementations
   - Learn gas optimization techniques
   - Understand edge cases
   - Practice safe coding patterns

4. **Contribute**:
   - Build open-source subscribers
   - Share patterns with community
   - Write tutorials
   - Report issues

---

## 📝 Summary

The **Subscriber** pattern is a powerful extensibility mechanism in Uniswap V4 that enables:

### Core Concepts
- **Callback-Based**: Position Manager notifies your contract
- **Opt-In**: Users choose to subscribe their positions
- **Four Notifications**: Subscribe, Unsubscribe, Burn, ModifyLiquidity
- **Non-Transferable Tokens**: Track participation without transferability
- **Multi-Pool**: Separate balances per pool and user

### Critical Implementation Details
- Use `onlyPositionManager` modifier on all notifications
- Store `poolId` and `owner` for positions that might be burned
- Use stored data in `notifyUnsubscribe` and `notifyBurn`
- Protect burns with `min()` to prevent underflow
- Delete state to get gas refunds
- Keep `notifyUnsubscribe` simple (gas limit!)

### Common Patterns
- **Reputation Systems**: Award points for LP duration
- **Auto-Compounding**: Reinvest fees automatically
- **Analytics**: Track metrics across positions
- **Governance**: Voting rights based on liquidity
- **Risk Management**: Monitor suspicious activity

### Security Checklist
- ✅ Access control on all notifications
- ✅ Underflow protection in burns
- ✅ State cleanup for gas refunds
- ✅ Gas efficiency in unsubscribe
- ✅ Proper use of stored vs queried data

**Congratulations!** You now understand how to build powerful extensions for Uniswap V4 using the Subscriber pattern. This opens up endless possibilities for DeFi innovation! 🎓

Continue to the next exercise to explore more advanced V4 features! 🚀

