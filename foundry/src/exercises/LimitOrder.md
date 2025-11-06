# Uniswap V4 LimitOrder Hook - Complete Technical Guide

## Introduction

This document provides an in-depth technical explanation of the `LimitOrder.sol` hook contract, one of the most sophisticated and practical applications of Uniswap V4's hook system. This hook enables traders to place limit orders directly on Uniswap V4 pools, bringing traditional order book functionality to automated market makers (AMMs).

### What You'll Learn

- How to implement a production-grade limit order system using hooks
- Understanding concentrated liquidity as a mechanism for limit orders
- Managing order buckets, slots, and user positions
- Handling order lifecycle: place, fill, cancel, and claim
- Advanced hook patterns: afterInitialize, afterSwap interactions
- Multi-user coordination and fair order execution
- Fee accrual and distribution in limit orders

### Key Concepts

**Limit Order**: An order to buy or sell at a specific price or better. Unlike market orders that execute immediately, limit orders wait until the market price reaches the specified level.

**Concentrated Liquidity as Limit Order**: In Uniswap V3/V4, providing liquidity in a single tick range acts like a limit order. When price crosses the range, the liquidity is "spent" and converted to the output token.

**Bucket**: A collection of limit orders at the same tick and direction, managed together for gas efficiency.

**Slot**: A sequential identifier for buckets at the same tick/direction. When a bucket fills, a new slot is created for future orders.

**Zero-for-One**: Direction of swap. `true` = selling token0 for token1 (price going down), `false` = selling token1 for token0 (price going up).

**Tick**: A discrete price point in Uniswap. Price = 1.0001^tick. Each tick represents a ~0.01% price change.

## Contract Overview

The `LimitOrder.sol` hook implements a fully-featured limit order system by:

1. Storing limit orders as concentrated liquidity positions
2. Automatically filling orders when price crosses through them
3. Managing multiple users' orders in shared "buckets" for efficiency
4. Tracking filled orders so users can claim their tokens
5. Allowing users to cancel unfilled orders

### Core Features

| Feature | Description |
|---------|-------------|
| **Place Orders** | Add liquidity at specific tick with single-sided token deposit |
| **Automatic Fill** | Orders execute automatically when price crosses the tick |
| **Bucket System** | Multiple orders at same tick share gas costs |
| **Slot Management** | Incremental slots prevent conflicts between fills |
| **Cancel Orders** | Remove unfilled orders and reclaim tokens |
| **Claim Filled Orders** | Withdraw tokens from executed orders |
| **Fee Accrual** | Capture trading fees while order waits |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Architecture Pattern**: Hook + TStore (transient storage for actions)
- **Hook Permissions**: afterInitialize, afterSwap
- **Storage Pattern**: Nested mappings (PoolId → Bucket → Slot → Order data)
- **Order Execution**: Automatic via afterSwap hook
- **Gas Optimization**: Shared buckets, slot-based segregation

## Understanding Limit Orders in AMMs

### Traditional Limit Orders vs AMM Limit Orders

#### Traditional Order Book

```
Buy Orders (Bids)          Sell Orders (Asks)
Price    Amount           Price    Amount
$2950    10 ETH           $3050    5 ETH
$2940    15 ETH           $3060    8 ETH
$2930    20 ETH           $3070    12 ETH
```

- **Pros**: Exact price execution, partial fills, price-time priority
- **Cons**: Requires active order management, centralized infrastructure

#### AMM Limit Orders (This Contract)

```
Tick-Based Liquidity Positions:

Tick 85180 ($2950): 10 ETH liquidity (sells at $2950)
Tick 85200 ($2970): 15 ETH liquidity (sells at $2970)
Tick 85220 ($2990): 20 ETH liquidity (sells at $2990)
```

- **Pros**: Passive execution, decentralized, earn fees while waiting
- **Cons**: Tick-level precision (not exact price), full execution only, no priority

### How Concentrated Liquidity Acts as a Limit Order

**Key Insight**: Single-tick liquidity positions convert entirely to the output token when price crosses.

#### Example: Sell 1 ETH at $3000

**Setup**:
```solidity
// Current price: $2950
// Want to sell 1 ETH when price reaches $3000
// Tick for $3000: 85184

// Place liquidity in range [85184, 85194] (one tick spacing)
place({
    tickLower: 85184,
    tickUpper: 85194,  // tickLower + tickSpacing
    zeroForOne: true,  // Selling token0 (ETH) for token1 (USDC)
    liquidity: calculateLiquidity(1 ETH, 85184, 85194)
});
```

**Before Price Crosses**:
```
Price: $2950 (tick 85100)
Position: 1 ETH in range [85184, 85194]
Status: Waiting (below the range)
```

**Price Crosses to $3000**:
```
Price: $3000 (tick 85184) ← Enters our range!
Position: Liquidity starts converting
Result: ETH → USDC swap happens automatically
```

**After Price Crosses**:
```
Price: $3010 (tick 85194) ← Exits our range
Position: 0 ETH, ~3000 USDC
Status: Filled! Ready to claim
```

### Why Single-Tick Ranges?

**Single-Tick Range** (this contract):
```solidity
tickLower: 85184
tickUpper: 85194  // tickLower + tickSpacing
```

**Behavior**:
- ✅ All liquidity converts when price crosses once
- ✅ Acts like a true limit order (one execution)
- ✅ Predictable output amount

**Multi-Tick Range** (not used here):
```solidity
tickLower: 85184
tickUpper: 85384  // Wide range
```

**Behavior**:
- ❌ Liquidity converts gradually as price moves through range
- ❌ Acts like providing liquidity (multiple trades)
- ❌ Variable output depending on price path

## Contract Architecture

### Dependencies and Imports

#### Core Imports

```solidity
import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CurrencyLib} from "../libraries/CurrencyLib.sol";
import {StateLibrary} from "../libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "../types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {TStore} from "../TStore.sol";
```

| Interface/Library | Purpose | Key Usage |
|-------------------|---------|-----------|
| `IERC20` | ERC20 token operations | Transfer tokens for orders |
| `IPoolManager` | Pool coordinator | Add/remove liquidity, get pool state |
| `Hooks` | Hook utilities | Permission validation |
| `SafeCast` | Safe type conversions | int128 ↔ uint128 conversions |
| `CurrencyLib` | Currency helpers | `transferIn()`, `transferOut()` |
| `StateLibrary` | Pool state queries | `getSlot0()` - get current tick |
| `PoolIdLibrary` | Pool identification | `toId()` - compute PoolId |
| `BalanceDelta` | Balance tracking | Extract amounts from operations |
| `TStore` | Transient storage | Track action types (ADD/REMOVE_LIQUIDITY) |

### State Variables

```solidity
IPoolManager public immutable poolManager;
mapping(bytes32 => uint256) public slots;
mapping(bytes32 => mapping(uint256 => Bucket)) public buckets;
mapping(PoolId => int24) public ticks;
```

| Variable | Type | Purpose |
|----------|------|---------|
| `poolManager` | `IPoolManager` | Reference to Uniswap V4's pool coordinator |
| `slots` | `mapping(bytes32 => uint256)` | Current slot number for each bucket ID |
| `buckets` | `mapping(bytes32 => mapping(uint256 => Bucket))` | Actual order data |
| `ticks` | `mapping(PoolId => int24)` | Last known tick for each pool |

### Storage Pattern: Buckets and Slots

**Bucket ID Calculation**:
```solidity
bytes32 bucketId = keccak256(abi.encode(poolId, tickLower, zeroForOne));
```

A bucket ID uniquely identifies:
- Which pool
- Which tick level
- Which direction (buy or sell)

**Slot System**:
```solidity
// First orders at tick 85184, zeroForOne=true
bucketId = keccak256(poolId, 85184, true);
uint256 slot = slots[bucketId];  // = 0 (initial slot)

Bucket storage bucket = buckets[bucketId][0];
// Orders accumulate in this bucket...

// Price crosses, bucket fills
bucket.filled = true;

// New orders at same tick/direction go to next slot
slots[bucketId] = 1;  // Increment!
bucket = buckets[bucketId][1];  // New empty bucket
```

**Why Slots?**
- Separate filled and unfilled orders
- Multiple "generations" of orders at same tick
- Gas efficient (don't need to iterate/search)

---

## 🔍 DEEP DIVE: Bucket vs Slot - The Complete Relationship

This is **the most important part** to understand the LimitOrder system. Let's explain it from scratch with maximum clarity.

### Fundamental Concepts

#### What is a Bucket?

A **Bucket** is a **logical container** that groups all limit orders that share:
1. **Same pool** (e.g., ETH-USDC)
2. **Same tick** (e.g., 85200 = $3050)
3. **Same direction** (e.g., zeroForOne = true = sell ETH)

**Real-world analogy**:
```
Imagine a restaurant with a reservation system:

Bucket = "Table for 8:00 PM on Friday"
  ↳ All people who book for that time are "grouped"
  ↳ They share the same "condition" (time, day)
  ↳ When 8:00 PM arrives, ALL reservations in that bucket "execute"
```

#### What is a Slot?

A **Slot** is a **sequential number** that separates different "generations" of buckets at the same tick.

**Analogy**:
```
Continuing with the restaurant:

Slot 0 = "First batch of reservations for 8:00 PM"
  ↳ The first 10 people who book go here
  ↳ When 8:00 PM arrives, everyone eats → Slot filled

Slot 1 = "Second batch of reservations for 8:00 PM" 
  ↳ The next people who book AFTER go here
  ↳ Since Slot 0 is already full (eating), these wait for the next round
```

### Technical Relationship: Bucket ID + Slot

```solidity
// STEP 1: Calculate Bucket ID (identifies the "category" of orders)
bytes32 bucketId = keccak256(abi.encode(
    poolId,      // Which pool? (e.g., ETH-USDC)
    tickLower,   // At what price? (e.g., 85200 = $3050)
    zeroForOne   // Which direction? (e.g., true = sell ETH)
));

// STEP 2: Get current Slot (identifies the "generation")
uint256 slot = slots[bucketId];  // Starts at 0, increments when filled

// STEP 3: Access the specific Bucket
Bucket storage bucket = buckets[bucketId][slot];
//                               ↑          ↑
//                        which category   which generation
```

### Visualization: Complete Storage System

```
┌─────────────────────────────────────────────────────────────────┐
│                    STORAGE MAPPINGS                             │
└─────────────────────────────────────────────────────────────────┘

1. slots mapping (uint256):
   bucketId (bytes32) → current slot number

   ┌─────────────┬──────┐
   │ bucketId_A  │  2   │  ← At slot 2 (generation 3)
   │ bucketId_B  │  0   │  ← At slot 0 (generation 1)
   │ bucketId_C  │  1   │  ← At slot 1 (generation 2)
   └─────────────┴──────┘

2. buckets mapping (nested):
   bucketId (bytes32) → slot (uint256) → Bucket struct

   bucketId_A:
      slot 0 → Bucket {filled: true, ...}   ← First gen (filled)
      slot 1 → Bucket {filled: true, ...}   ← Second gen (filled)
      slot 2 → Bucket {filled: false, ...}  ← Third gen (active) ← slots[bucketId_A] points here
   
   bucketId_B:
      slot 0 → Bucket {filled: false, ...}  ← First gen (active) ← slots[bucketId_B] points here
```

### Complete Step-by-Step Example

#### Scenario
- Pool: ETH-USDC
- Target tick: 85200 ($3050)
- Action: Sell ETH (zeroForOne = true)

#### Complete Timeline

```solidity
// ═══════════════════════════════════════════════════════════════
// TIME T0: First order at this tick
// ═══════════════════════════════════════════════════════════════

// User A places 1 ETH
bytes32 bucketId = keccak256(abi.encode(poolId, 85200, true));
// bucketId = 0xabc123...

uint256 slot = slots[bucketId];  // = 0 (first time, default value)

buckets[bucketId][0] = Bucket {
    filled: false,
    amount0: 0,
    amount1: 0,
    liquidity: 1e18,
    sizes: {UserA: 1e18}
}

// System state:
// slots[0xabc123...] = 0  ← Points to active slot
// buckets[0xabc123...][0] = {filled: false, liq: 1e18, ...}


// ═══════════════════════════════════════════════════════════════
// TIME T1: More users join the SAME slot
// ═══════════════════════════════════════════════════════════════

// User B places 2 ETH
uint256 slot = slots[bucketId];  // = 0 (same slot because not filled yet)

buckets[bucketId][0].liquidity += 2e18;  // Accumulates
buckets[bucketId][0].sizes[UserB] = 2e18;

// User C places 0.5 ETH
buckets[bucketId][0].liquidity += 0.5e18;  // Accumulates
buckets[bucketId][0].sizes[UserC] = 0.5e18;

// System state:
// slots[0xabc123...] = 0  ← Still at slot 0
// buckets[0xabc123...][0] = {
//     filled: false,
//     liquidity: 3.5e18,  ← Total accumulated
//     sizes: {UserA: 1e18, UserB: 2e18, UserC: 0.5e18}
// }


// ═══════════════════════════════════════════════════════════════
// TIME T2: Price crosses tick 85200! (afterSwap executes)
// ═══════════════════════════════════════════════════════════════

// afterSwap() detects crossing and fills the bucket
uint256 slot = slots[bucketId];  // = 0

Bucket storage bucket = buckets[bucketId][0];

// Step 1: Convert all liquidity (3.5 ETH → 10,675 USDC)
// (assuming $3050 price)
bucket.amount0 = 0;        // ETH is gone
bucket.amount1 = 10675e6;  // USDC received
bucket.filled = true;      // MARKED AS FILLED!

// Step 2: Increment slot for future orders
slots[bucketId] = 1;  // ← CRITICAL CHANGE

// System state:
// slots[0xabc123...] = 1  ← NOW points to slot 1 (next generation)
// 
// buckets[0xabc123...][0] = {  ← Slot 0 = FILLED (historical)
//     filled: true,
//     amount0: 0,
//     amount1: 10675e6,
//     liquidity: 3.5e18,
//     sizes: {UserA: 1e18, UserB: 2e18, UserC: 0.5e18}
// }
// 
// buckets[0xabc123...][1] = {  ← Slot 1 = EMPTY (ready for new orders)
//     filled: false,
//     amount0: 0,
//     amount1: 0,
//     liquidity: 0,
//     sizes: {}
// }


// ═══════════════════════════════════════════════════════════════
// TIME T3: User D tries to place new order at same tick
// ═══════════════════════════════════════════════════════════════

// User D places 1 ETH at tick 85200, zeroForOne=true
bytes32 bucketId = keccak256(abi.encode(poolId, 85200, true));
// bucketId = 0xabc123... (SAME bucketId!)

uint256 slot = slots[bucketId];  // = 1 ← BUT NOW AT SLOT 1

// Their order goes to slot 1 (new generation)
buckets[bucketId][1].liquidity = 1e18;
buckets[bucketId][1].sizes[UserD] = 1e18;

// System state:
// slots[0xabc123...] = 1  ← Still at slot 1
// 
// buckets[0xabc123...][0] = {  ← Slot 0 = FILLED (UserA, B, C waiting to claim)
//     filled: true,
//     amount1: 10675e6,
//     liquidity: 3.5e18,
//     ...
// }
// 
// buckets[0xabc123...][1] = {  ← Slot 1 = ACTIVO (UserD esperando fill)
//     filled: false,
//     liquidity: 1e18,
//     sizes: {UserD: 1e18}
// }


// ═══════════════════════════════════════════════════════════════
// TIME T4: Users A, B, C claim their proceeds
// ═══════════════════════════════════════════════════════════════

// UserA calls take(poolKey, 85200, true)
bytes32 bucketId = keccak256(abi.encode(poolId, 85200, true));
uint256 slot = slots[bucketId];  // = 1 ← CURRENT slot (for new orders)

// BUT UserA is in slot 0, we need to access THAT slot
// System looks at slot 0 (where UserA's order is)
Bucket storage bucket = buckets[bucketId][0];  // ← Explicitly slot 0

require(bucket.filled, "Not filled");  // ✅ true

uint128 userShare = bucket.sizes[UserA];  // = 1e18
uint256 amount1 = (bucket.amount1 * userShare) / bucket.liquidity;
// amount1 = (10675e6 * 1e18) / 3.5e18 = 3050e6 (3,050 USDC)

// Transfer to UserA
USDC.transfer(UserA, 3050e6);

// Update bucket
bucket.liquidity -= 1e18;  // = 2.5e18
bucket.amount1 -= 3050e6;  // = 7625e6
bucket.sizes[UserA] = 0;

// State after UserA's take:
// buckets[0xabc123...][0] = {
//     filled: true,
//     amount1: 7625e6,    ← Reduced
//     liquidity: 2.5e18,  ← Reduced
//     sizes: {UserA: 0, UserB: 2e18, UserC: 0.5e18}
// }

// UserB and UserC can do the same...
```

### Why Do We Need Slots? - The Problem They Solve

#### ❌ Without Slots (Problem)

```solidity
// Imagine there are NO slots, only buckets:

// T0: UserA places order at tick 85200
buckets[bucketId] = {filled: false, liq: 1e18, sizes: {A: 1e18}}

// T1: Price crosses, order fills
buckets[bucketId].filled = true;
buckets[bucketId].amount1 = 3050e6;

// T2: UserB tries to place order at SAME tick 85200
// What happens?
// 
// Option 1: Revert because bucket is filled
//   ❌ Problem: You can't place new orders at that price
//
// Option 2: Add to filled bucket
//   ❌ Problem: You'd mix executed orders with unexecuted ones
//   ❌ Problem: UserB would enter already-filled bucket (makes no sense)
//
// Option 3: Reset the bucket
//   ❌ Problem: You'd lose UserA's data who hasn't claimed yet!

// 🚨 WITHOUT SLOTS, THERE'S NO CLEAN WAY TO HANDLE THIS 🚨
```

#### ✅ With Slots (Solution)

```solidity
// WITH slots:

// T0: UserA places order at tick 85200
slots[bucketId] = 0;
buckets[bucketId][0] = {filled: false, liq: 1e18, ...}

// T1: Price crosses, order fills
buckets[bucketId][0].filled = true;
slots[bucketId] = 1;  ← INCREMENT SLOT

// T2: UserB tries to place order at SAME tick 85200
uint256 slot = slots[bucketId];  // = 1
buckets[bucketId][1] = {filled: false, liq: 1e18, ...}
//                  ↑
//               DIFFERENT BUCKET, DIFFERENT GENERATION

// ✅ UserA can claim from buckets[bucketId][0]
// ✅ UserB waits in buckets[bucketId][1]
// ✅ No conflicts, data perfectly separated
```

### Visualization: Buckets in Multiple Slots

```
Pool: ETH-USDC
Tick: 85200 ($3050)
Direction: Sell ETH (zeroForOne = true)

bucketId = keccak256(poolId, 85200, true) = 0xABCD...


┌───────────────────────────────────────────────────────────┐
│                       SLOT 0                              │
│  (First generation - ALREADY EXECUTED)                    │
├───────────────────────────────────────────────────────────┤
│  Bucket {                                                 │
│    filled: ✅ true                                        │
│    amount0: 0 ETH                                         │
│    amount1: 10,500 USDC                                   │
│    liquidity: 3.5 ETH                                     │
│    sizes: {                                               │
│      Alice: 1 ETH    → can claim 3,000 USDC               │
│      Bob: 2 ETH      → can claim 6,000 USDC               │
│      Carol: 0.5 ETH  → can claim 1,500 USDC               │
│    }                                                      │
│  }                                                        │
└───────────────────────────────────────────────────────────┘
                            ↓
                (Price crossed 85200, slot incremented)
                            ↓
┌───────────────────────────────────────────────────────────┐
│                       SLOT 1                              │
│  (Second generation - WAITING)                            │
├───────────────────────────────────────────────────────────┤
│  Bucket {                                                 │
│    filled: ❌ false                                       │
│    amount0: 0                                             │
│    amount1: 0                                             │
│    liquidity: 2 ETH                                       │
│    sizes: {                                               │
│      Dave: 1.5 ETH   → waiting for price to cross again   │
│      Eve: 0.5 ETH    → waiting for price to cross again   │
│    }                                                      │
│  }                                                        │
└───────────────────────────────────────────────────────────┘
                            ↓
                (If price crosses 85200 again)
                            ↓
┌───────────────────────────────────────────────────────────┐
│                       SLOT 2                              │
│  (Third generation - EMPTY, READY)                        │
├───────────────────────────────────────────────────────────┤
│  Bucket {                                                 │
│    filled: false                                          │
│    amount0: 0                                             │
│    amount1: 0                                             │
│    liquidity: 0                                           │
│    sizes: {}                                              │
│  }                                                        │
└───────────────────────────────────────────────────────────┘

slots[0xABCD...] = 1  ← Points to current active slot
```

### Bucket Access: How Does the Contract Know Which Slot to Use?

```solidity
// ══════════════════════════════════════════════════════════
// CASE 1: place() - Place new order
// ══════════════════════════════════════════════════════════
function place(PoolKey calldata key, int24 tickLower, bool zeroForOne, uint128 liq) {
    bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);
    
    // Use CURRENT slot (where new orders go)
    uint256 slot = slots[bucketId];  // ← Active slot
    
    Bucket storage bucket = buckets[bucketId][slot];
    bucket.liquidity += liq;
    bucket.sizes[msg.sender] += liq;
    
    // New order goes to current active bucket
}


// ══════════════════════════════════════════════════════════
// CASE 2: cancel() - Cancel unexecuted order
// ══════════════════════════════════════════════════════════
function cancel(PoolKey calldata key, int24 tickLower, bool zeroForOne) {
    bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);
    
    // Also uses CURRENT slot (because you can only cancel active orders)
    uint256 slot = slots[bucketId];  // ← Active slot
    
    Bucket storage bucket = buckets[bucketId][slot];
    require(!bucket.filled, "Already filled");  // Only cancel unexecuted ones
    
    uint128 userLiq = bucket.sizes[msg.sender];
    bucket.liquidity -= userLiq;
    bucket.sizes[msg.sender] = 0;
}


// ══════════════════════════════════════════════════════════
// CASE 3: take() - Claim executed order
// ══════════════════════════════════════════════════════════
function take(PoolKey calldata key, int24 tickLower, bool zeroForOne) {
    bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);
    
    // ⚠️ HERE IT'S DIFFERENT: need to find which slot has your order
    // Current implementation simplifies by assuming you know your slot,
    // or searches current slot first
    
    uint256 slot = slots[bucketId];  // Current slot
    
    // BUT: Your order may be in a previous slot (already filled)
    // That's why take() must find the correct slot where user has sizes > 0
    
    // Option 1: User passes slot as parameter
    // Option 2: Iterate slots backwards looking for where sizes[user] > 0
    // Option 3: Maintain additional mapping: user → slots where they have orders
    
    // In this simplified implementation:
    Bucket storage bucket = buckets[bucketId][slot];
    require(bucket.filled, "Not filled");
    
    uint128 userSize = bucket.sizes[msg.sender];
    uint256 share = (bucket.amount1 * userSize) / bucket.liquidity;
    
    // Transfer share to user...
}


// ══════════════════════════════════════════════════════════
// CASE 4: afterSwap() - Fill orders when price crosses
// ══════════════════════════════════════════════════════════
function afterSwap(...) {
    // Iterate crossed ticks
    for (int24 tick = tickLower; tick <= tickUpper; tick += tickSpacing) {
        bytes32 bucketId = getBucketId(poolId, tick, !zeroForOne);
        
        // Access CURRENT slot (active orders waiting)
        uint256 slot = slots[bucketId];  // ← Active slot
        
        Bucket storage bucket = buckets[bucketId][slot];
        
        if (bucket.liquidity > 0) {
            // Fill bucket
            bucket.filled = true;
            bucket.amount0 = ...;
            bucket.amount1 = ...;
            
            // Increment slot for future orders
            slots[bucketId]++;  // ← CREATE NEW GENERATION
        }
    }
}
```

### Final Analogy: Generation System

Think of slots as **order generations**:

```
🏔️ Mount Everest (Tick 85200 = $3050)

Generation 1 (Slot 0):
  👥 Group 1 waiting to reach the summit
  ⏰ They wait... and wait...
  ✅ They reach the summit! (price crosses)
  🎉 Mission completed, they get their reward
  🔒 Their slot "closes" (filled = true)

Generation 2 (Slot 1):
  👥 Group 2 starts climbing (new orders)
  📍 They're on the SAME mountain (same tick)
  📍 They have the SAME goal (same price)
  ❗ BUT they're a DIFFERENT group (different slot)
  ⏰ They wait their turn...
  
Generation 3 (Slot 2):
  👥 Group 3 prepares (future orders)
  🔓 Empty slot, ready to receive orders

The slots[] system always points to the "current active group"
Previous slots are "groups that already completed their mission"
```

### Summary: Bucket vs Slot

| Concept | Bucket ID | Slot |
|----------|-----------|------|
| **What is it** | Unique category identifier | Sequential generation number |
| **Calculates** | `keccak256(pool, tick, direction)` | Counter: `0, 1, 2, 3...` |
| **Identifies** | Pool + Price + Direction | Which "batch" of orders |
| **When changes** | Never (deterministic) | Each time a bucket fills |
| **Purpose** | Group similar orders | Separate executed from unexecuted |
| **Analogy** | "Reservations for 8:00 PM" | "First batch, second batch..." |

**Complete relationship**:
```
buckets[bucketId][slot] = Specific Bucket instance
          ↑        ↑
       category  generation
```

---

### Bucket Structure

```solidity
struct Bucket {
    bool filled;              // Has this bucket been executed?
    uint256 amount0;          // Token0 accumulated after fill
    uint256 amount1;          // Token1 accumulated after fill
    uint128 liquidity;        // Total liquidity in bucket
    mapping(address => uint128) sizes;  // Each user's share
}
```

**Field Breakdown**:

| Field | Type | Purpose |
|-------|------|---------|
| `filled` | `bool` | `false` = waiting for price, `true` = executed |
| `amount0` | `uint256` | Token0 balance after fill (for claiming) |
| `amount1` | `uint256` | Token1 balance after fill (for claiming) |
| `liquidity` | `uint128` | Total liquidity from all users in this bucket |
| `sizes` | `mapping(address => uint128)` | Track each user's contribution |

**Example Bucket Evolution**:

```solidity
// Initial state (empty)
Bucket {
    filled: false,
    amount0: 0,
    amount1: 0,
    liquidity: 0,
    sizes: {}
}

// User1 places 1 ETH order
Bucket {
    filled: false,
    amount0: 0,
    amount1: 0,
    liquidity: 1e18,
    sizes: {User1: 1e18}
}

// User2 places 0.5 ETH order (accumulates in same bucket)
Bucket {
    filled: false,
    amount0: 0,
    amount1: 0,
    liquidity: 1.5e18,
    sizes: {User1: 1e18, User2: 0.5e18}
}

// Price crosses, bucket fills (receives 4500 USDC for 1.5 ETH)
Bucket {
    filled: true,        // ← Now filled!
    amount0: 0,
    amount1: 4500e6,     // ← USDC received
    liquidity: 1.5e18,
    sizes: {User1: 1e18, User2: 0.5e18}
}

// User1 claims (gets 3000 USDC = 4500 * 1.0 / 1.5)
// User2 claims (gets 1500 USDC = 4500 * 0.5 / 1.5)
```

### Action Constants

```solidity
uint256 constant ADD_LIQUIDITY = 1;
uint256 constant REMOVE_LIQUIDITY = 2;
```

Used with `TStore` to track which operation is happening in `unlockCallback`.

### Custom Errors

```solidity
error NotPoolManager();
error WrongTickSpacing();
error NotAllowedAtCurrentTick();
error BucketFilled();
error BucketNotFilled();
```

| Error | When Thrown | Meaning |
|-------|-------------|---------|
| `NotPoolManager()` | Callback from non-PoolManager | Security check failed |
| `WrongTickSpacing()` | Tick not multiple of tickSpacing | Invalid tick for this pool |
| `NotAllowedAtCurrentTick()` | Placing order at current tick | Would execute immediately |
| `BucketFilled()` | Canceling filled order | Can't cancel executed orders |
| `BucketNotFilled()` | Claiming unfilled order | Order hasn't executed yet |

### Events

```solidity
event Place(bytes32 indexed poolId, uint256 indexed slot, address indexed user, 
            int24 tickLower, bool zeroForOne, uint128 liquidity);
event Cancel(bytes32 indexed poolId, uint256 indexed slot, address indexed user,
             int24 tickLower, bool zeroForOne, uint128 liquidity);
event Take(bytes32 indexed poolId, uint256 indexed slot, address indexed user,
           int24 tickLower, bool zeroForOne, uint256 amount0, uint256 amount1);
event Fill(bytes32 indexed poolId, uint256 indexed slot, int24 tickLower,
           bool zeroForOne, uint256 amount0, uint256 amount1);
```

**Event Usage**:
- `Place`: Track new order placement
- `Cancel`: Track order cancellation
- `Take`: Track user claiming filled order
- `Fill`: Track bucket execution (no user address, bucket-level event)

## Constructor and Hook Permissions

### Constructor

```solidity
constructor(address _poolManager) {
    poolManager = IPoolManager(_poolManager);
    Hooks.validateHookPermissions(address(this), getHookPermissions());
}
```

Standard hook constructor pattern:
1. Store PoolManager reference
2. Validate hook address matches permissions

### Hook Permissions

```solidity
function getHookPermissions()
    public
    pure
    returns (Hooks.Permissions memory)
{
    return Hooks.Permissions({
        beforeInitialize: false,
        afterInitialize: true,      // ← Store initial tick
        beforeAddLiquidity: false,
        afterAddLiquidity: false,
        beforeRemoveLiquidity: false,
        afterRemoveLiquidity: false,
        beforeSwap: false,
        afterSwap: true,            // ← Check for filled orders
        beforeDonate: false,
        afterDonate: false,
        beforeSwapReturnDelta: false,
        afterSwapReturnDelta: false,
        afterAddLiquidityReturnDelta: false,
        afterRemoveLiquidityReturnDelta: false
    });
}
```

**Enabled Hooks** (set to `true`):

1. ✅ **afterInitialize**: Store the initial tick when pool is created
2. ✅ **afterSwap**: Check if price crossed any order ticks and fill them

**Why Only These Two?**

- **afterInitialize**: Need starting point to track tick changes
- **afterSwap**: Only time price changes, so only time orders can fill
- All other hooks unnecessary for limit order functionality

### Hook Address Mining

For this hook, the required address pattern is:

```solidity
// Enabled permissions:
// afterInitialize (bit 1) = 1
// afterSwap (bit 7) = 1

// Bit pattern: 0b10000010 = 0x82
// Address must end with: 0x...XX82
```

**Mining Process**:
```bash
# 1. Run salt finder
forge test --match-path test/FindHookSalt.test.sol -vvv

# 2. Export found salt
export SALT=0x...

# 3. Deploy with CREATE2
hook = new LimitOrder{salt: salt}(POOL_MANAGER);
```

## Hook Implementation: afterInitialize

### Function Signature

```solidity
function afterInitialize(
    address sender,
    PoolKey calldata key,
    uint160 sqrtPriceX96,
    int24 tick
) external onlyPoolManager returns (bytes4)
```

**When Called**: Immediately after a new pool is initialized.

**Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `sender` | `address` | Who initialized the pool |
| `key` | `PoolKey` | Pool identifier |
| `sqrtPriceX96` | `uint160` | Initial price (sqrt format) |
| `tick` | `int24` | Initial tick corresponding to the price |

**Return**: Function selector for validation

### Implementation

```solidity
function afterInitialize(
    address sender,
    PoolKey calldata key,
    uint160 sqrtPriceX96,
    int24 tick
) external onlyPoolManager returns (bytes4) {
    ticks[key.toId()] = tick;
    return this.afterInitialize.selector;
}
```

**Purpose**: Store the initial tick for this pool.

**Why Needed?**

```solidity
// Later in afterSwap, we need to know:
// - Previous tick (before swap)
// - Current tick (after swap)
// - Range between them (which orders to fill)

int24 previousTick = ticks[poolId];  // ← Stored here!
int24 currentTick = _getTick(poolId);

// Fill orders in range [previousTick, currentTick]
```

**Example**:

```solidity
// Pool initialization
poolManager.initialize(
    ETH_USDC_KEY,
    sqrtPriceX96: 1234567890,  // ≈ $2950
    tick: 85100
);

// Hook is called:
afterInitialize(..., tick: 85100) {
    ticks[ETH_USDC_PoolId] = 85100;  // ← Store!
    return selector;
}

// Now we can track tick changes from this baseline
```

## Hook Implementation: afterSwap - The Heart of Order Filling

### Function Signature

```solidity
function afterSwap(
    address sender,
    PoolKey calldata key,
    SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
) external onlyPoolManager setAction(REMOVE_LIQUIDITY) returns (bytes4, int128)
```

**When Called**: Immediately after a swap completes in the pool.

**Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `sender` | `address` | Who initiated the swap |
| `key` | `PoolKey` | Pool identifier |
| `params` | `SwapParams` | Swap details (zeroForOne, amountSpecified) |
| `delta` | `BalanceDelta` | Actual balance changes from the swap |
| `hookData` | `bytes` | Custom data (unused here) |

**Modifier**: `setAction(REMOVE_LIQUIDITY)` - Sets transient storage for unlockCallback

**Return**: Function selector + unspecified delta (0 = no adjustment)

### Core Logic Overview

```
afterSwap is called
       ↓
Get tick range [previous, current]
       ↓
Loop through each tick in range
       ↓
For each tick with orders:
  → Find opposite-direction bucket
  → If bucket has liquidity:
    → Increment slot (segregate filled orders)
    → Remove liquidity from pool
    → Take tokens to hook contract
    → Mark bucket as filled
    → Store amounts for claiming
       ↓
Update stored tick to current
```

### Step-by-Step Breakdown

#### Step 1: Get Tick Range

```solidity
(int24 tickLower, int24 tickUpper) = _getTickRange(
    ticks[key.toId()],     // Previous tick (before swap)
    _getTick(key.toId()),  // Current tick (after swap)
    key.tickSpacing        // Tick spacing for this pool
);
```

**Purpose**: Determine which ticks the price crossed during the swap.

**Helper Function**: `_getTickRange()`

```solidity
function _getTickRange(int24 tick0, int24 tick1, int24 tickSpacing)
    private
    pure
    returns (int24 lower, int24 upper)
{
    // Get tick lower (rounded down to tick spacing)
    int24 l0 = _getTickLower(tick0, tickSpacing);
    int24 l1 = _getTickLower(tick1, tickSpacing);

    if (tick0 <= tick1) {
        // Price increased (ticks went up)
        lower = l0;
        upper = l1 - tickSpacing;
    } else {
        // Price decreased (ticks went down)
        lower = l1 + tickSpacing;
        upper = l0;
    }
}
```

**Example**:

```solidity
// Before swap: tick = 85100
// After swap: tick = 85250
// Tick spacing: 10

// Calculate:
l0 = _getTickLower(85100, 10) = 85100
l1 = _getTickLower(85250, 10) = 85250

// tick0 < tick1, so:
lower = 85100
upper = 85250 - 10 = 85240

// Range to check: [85100, 85240] with step 10
// Ticks checked: 85100, 85110, 85120, ..., 85240
```

**Why `upper = l1 - tickSpacing`?**

```solidity
// The current tick's range hasn't been fully crossed yet!
// Example: If current tick is 85250 (range 85250-85260)
// We're just entering this range, not exiting it
// So don't fill orders at 85250 yet

// Only fill orders we fully crossed:
// 85100 ✅ (fully crossed)
// 85110 ✅ (fully crossed)
// ...
// 85240 ✅ (fully crossed)
// 85250 ❌ (just entering, not fully crossed)
```

#### Step 2: Loop Through Crossed Ticks

```solidity
PoolId poolId = key.toId();
for (int24 tick = tickLower; tick <= tickUpper; tick += key.tickSpacing) {
    // Process each tick...
}
```

**Example Iteration**:

```solidity
// Range: [85100, 85240], spacing: 10

// Iteration 1: tick = 85100
// Iteration 2: tick = 85110
// Iteration 3: tick = 85120
// ...
// Iteration 15: tick = 85240
```

#### Step 3: Determine Order Direction

```solidity
bool zeroForOne = !params.zeroForOne;
```

**Critical Logic**: Orders filled are in the **opposite direction** of the swap!

**Why?**

```solidity
// Swap direction: zeroForOne = true (selling ETH for USDC)
// This means price is DECREASING (moving down ticks)
// Orders that get filled: USDC → ETH (zeroForOne = false)
// Because those orders wanted to buy ETH at higher prices!

// Example:
// Order at tick 85150: "Buy ETH at $3000" (zeroForOne = false)
// Swap selling ETH pushes price from $3050 → $2950
// When price crosses 85150 ($3000), order executes!
// Order gets filled: receives ETH, pays USDC
```

**Visual Example**:

```
Price moves DOWN (swap: ETH → USDC, zeroForOne = true)
$3100 ───────────────────────────────────────────
       ↓
$3050  ← Order at tick 85200: "Buy ETH at $3050" (zeroForOne=false)
       ↓   This order FILLS when price crosses down!
$3000  ← Order at tick 85150: "Buy ETH at $3000" (zeroForOne=false)
       ↓   This order FILLS too!
$2950 ←───── Final price after swap

Price moves UP (swap: USDC → ETH, zeroForOne = false)
$2950 ───────────────────────────────────────────
       ↑
$3000  ← Order at tick 85150: "Sell ETH at $3000" (zeroForOne=true)
       ↑   This order FILLS when price crosses up!
$3050  ← Order at tick 85200: "Sell ETH at $3050" (zeroForOne=true)
       ↑   This order FILLS too!
$3100 ←───── Final price after swap
```

#### Step 4: Find Bucket

```solidity
bytes32 bucketId = getBucketId(poolId, tick, zeroForOne);
uint256 slot = slots[bucketId];
Bucket storage bucket = buckets[bucketId][slot];

if (bucket.liquidity == 0) continue;  // No orders at this tick
```

**Bucket ID Components**:
- `poolId`: Which pool (ETH/USDC, DAI/USDC, etc.)
- `tick`: Which price level (85150, 85160, etc.)
- `zeroForOne`: Which direction (buy or sell)

**Example**:

```solidity
// Pool: ETH/USDC (poolId = 0xabc...)
// Tick: 85150 ($3000)
// Direction: false (buy ETH)

bucketId = keccak256(0xabc..., 85150, false)
         = 0x123...

slot = slots[bucketId]  // = 0 (first slot)
bucket = buckets[bucketId][0]

if (bucket.liquidity > 0) {
    // There are orders here! Fill them
}
```

#### Step 5: Increment Slot

```solidity
slots[bucketId] = slot + 1;
```

**Purpose**: Segregate filled orders from future orders.

**Why Important?**

```solidity
// Before this swap:
slots[bucketId] = 0
buckets[bucketId][0] = {filled: false, liquidity: 1.5 ETH, ...}

// After filling:
slots[bucketId] = 1  // ← Increment!
buckets[bucketId][0] = {filled: true, liquidity: 1.5 ETH, ...}

// New orders after this point go to slot 1:
buckets[bucketId][1] = {filled: false, liquidity: 0, ...}

// This prevents:
// ❌ New orders mixing with filled orders
// ❌ Users claiming unfilled portions
// ❌ Confusion about order status
```

#### Step 6: Remove Liquidity from Pool

```solidity
(int256 d,) = poolManager.modifyLiquidity({
    key: key,
    params: ModifyLiquidityParams({
        tickLower: tick,
        tickUpper: tick + key.tickSpacing,
        liquidityDelta: -int128(bucket.liquidity),  // NEGATIVE = remove
        salt: bytes32(0)
    }),
    hookData: ""
});
```

**What This Does**:

1. **Removes liquidity** from the pool at this tick range
2. **Returns BalanceDelta** showing how much of each token we get back
3. **Pool state updates** - liquidity no longer available for swaps

**Example**:

```solidity
// Bucket has 1.5 ETH worth of liquidity at tick 85150
// Price crossed, so position converted to USDC

modifyLiquidity({
    tickLower: 85150,
    tickUpper: 85160,
    liquidityDelta: -1500000000000000000  // -1.5 ETH liquidity
});

// Pool returns:
// delta.amount0() = 0      (no ETH back, it was sold)
// delta.amount1() = +4500e6 (received 4500 USDC)
```

#### Step 7: Extract Amounts

```solidity
BalanceDelta fillDelta = BalanceDelta.wrap(d);
uint256 amount0 = uint128(fillDelta.amount0());
uint256 amount1 = uint128(fillDelta.amount1());
```

**Important**: Amounts are POSITIVE when receiving from pool.

**Sign Convention**:

```solidity
// When removing liquidity:
// Positive = receiving tokens back
// Negative = shouldn't happen (we're taking, not providing)

// Example:
fillDelta.amount0() = +0        // No ETH (it was converted)
fillDelta.amount1() = +4500e6   // 4500 USDC received
```

#### Step 8: Take Tokens from Pool

```solidity
if (amount0 > 0) {
    poolManager.take(key.currency0, address(this), amount0);
}
if (amount1 > 0) {
    poolManager.take(key.currency1, address(this), amount1);
}
```

**Purpose**: Transfer tokens from PoolManager to the hook contract.

**Why Needed?**

```solidity
// After modifyLiquidity:
// - Tokens are available in PoolManager's accounting
// - But not physically transferred yet
// - Need to explicitly "take" them

// take() does:
// 1. Updates PoolManager's internal balances
// 2. Transfers tokens to hook contract
// 3. Hook now holds tokens for users to claim
```

**Example**:

```solidity
// Before take:
// PoolManager: 4500 USDC (accounting credit for hook)
// Hook: 0 USDC (physical balance)

poolManager.take(USDC, address(hook), 4500e6);

// After take:
// PoolManager: 0 USDC (debt cleared)
// Hook: 4500 USDC (physical balance)
// Users can now claim their share from hook
```

#### Step 9: Update Bucket State

```solidity
bucket.filled = true;
bucket.amount0 += amount0;
bucket.amount1 += amount1;
```

**State Changes**:

| Field | Before | After |
|-------|--------|-------|
| `filled` | `false` | `true` |
| `amount0` | `0` | `amount0` (if any) |
| `amount1` | `0` | `amount1` (if any) |
| `liquidity` | `1.5e18` | `1.5e18` (unchanged, for shares) |

**Why Keep `liquidity`?**

```solidity
// Used to calculate each user's share:
uint256 userShare = bucket.amount1 * userSize / bucket.liquidity;

// Example:
// Total liquidity: 1.5 ETH
// Total received: 4500 USDC
// User1 size: 1.0 ETH
// User1 share: 4500 * 1.0 / 1.5 = 3000 USDC
```

#### Step 10: Emit Fill Event

```solidity
emit Fill(
    PoolId.unwrap(poolId),
    slot,
    tick,
    zeroForOne,
    bucket.amount0,
    bucket.amount1
);
```

**Event Data**:
- `poolId`: Which pool
- `slot`: Which bucket slot was filled
- `tick`: Which price level
- `zeroForOne`: Which direction
- `amount0`, `amount1`: Total amounts available for claiming

### Complete afterSwap Example

**Scenario**: ETH/USDC pool, price moves from $2950 → $3050

```solidity
// Initial state
ticks[poolId] = 85100  // $2950

// Orders waiting:
// Tick 85150 ($3000): Sell 1.5 ETH (zeroForOne=true)
// Tick 85200 ($3050): Sell 0.5 ETH (zeroForOne=true)

// Large buy swap happens: buy 10 ETH with USDC
// Swap: zeroForOne = false (USDC → ETH)
// Price moves: 85100 → 85220

// afterSwap is called
int24 previousTick = ticks[poolId];     // = 85100
int24 currentTick = _getTick(poolId);   // = 85220

(int24 lower, int24 upper) = _getTickRange(85100, 85220, 10);
// lower = 85100
// upper = 85210

// Loop: tick = 85100, 85110, 85120, ..., 85210
for (int24 tick = 85100; tick <= 85210; tick += 10) {
    bool orderDirection = !false;  // = true
    // Looking for zeroForOne=true orders (sell ETH)
    
    // Iteration at tick = 85150:
    bucketId = getBucketId(poolId, 85150, true);
    slot = slots[bucketId];  // = 0
    bucket = buckets[bucketId][0];
    // bucket.liquidity = 1.5 ETH worth
    
    // Increment slot for future orders
    slots[bucketId] = 1;
    
    // Remove liquidity
    (int256 d,) = modifyLiquidity({
        tickLower: 85150,
        tickUpper: 85160,
        liquidityDelta: -1.5e18
    });
    // Returns: amount0=0, amount1=+4500e6 USDC
    
    // Take tokens
    poolManager.take(USDC, hook, 4500e6);
    
    // Update bucket
    bucket.filled = true;
    bucket.amount0 = 0;
    bucket.amount1 = 4500e6;
    
    emit Fill(poolId, 0, 85150, true, 0, 4500e6);
    
    // Continue to tick 85160, 85170, ..., 85200, 85210
    // Tick 85200 order also fills similarly
}

// Update stored tick
ticks[poolId] = 85220;

return (this.afterSwap.selector, 0);
```

### Edge Cases Handled

#### Case 1: No Orders at Tick

```solidity
if (bucket.liquidity == 0) continue;
```

Most ticks won't have orders. Skip them efficiently.

#### Case 2: Price Moves Backwards

```solidity
// Range calculation handles both directions:
if (tick0 <= tick1) {
    // Price increased (normal)
    lower = l0;
    upper = l1 - tickSpacing;
} else {
    // Price decreased (also works!)
    lower = l1 + tickSpacing;
    upper = l0;
}
```

#### Case 3: Multiple Orders Same Tick

All accumulated in same bucket, filled together. Each user gets proportional share.

#### Case 4: Order Direction Mismatch

```solidity
bool zeroForOne = !params.zeroForOne;
// Only checks opposite direction, won't accidentally fill same-direction orders
```

## User Functions: Order Lifecycle

### Function 1: `place()` - Create a Limit Order

#### Function Signature

```solidity
function place(
    PoolKey calldata key,
    int24 tickLower,
    bool zeroForOne,
    uint128 liquidity
) external payable setAction(ADD_LIQUIDITY)
```

**Purpose**: Place a new limit order at a specific price.

**Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `key` | `PoolKey` | Which pool to place order in |
| `tickLower` | `int24` | Price level (must be multiple of tickSpacing) |
| `zeroForOne` | `bool` | `true` = sell token0, `false` = sell token1 |
| `liquidity` | `uint128` | Amount of liquidity to provide |

**Payable**: Can send ETH if token0 is native currency

**Modifier**: `setAction(ADD_LIQUIDITY)` - Sets action for unlockCallback

#### Execution Flow

```
User calls place()
       ↓
Validate tick spacing
       ↓
poolManager.unlock()
       ↓
unlockCallback(ADD_LIQUIDITY)
  → Add liquidity to pool
  → Transfer tokens from user
  → Settle with PoolManager
       ↓
Update bucket state
       ↓
Emit Place event
```

#### Implementation Breakdown

**Step 1: Validate Tick Spacing**

```solidity
if (tickLower % key.tickSpacing != 0) revert WrongTickSpacing();
```

**Why?**

```solidity
// Valid ticks for tickSpacing = 10:
85100 ✅  (85100 % 10 = 0)
85110 ✅  (85110 % 10 = 0)
85115 ❌  (85115 % 10 = 5)  // Not aligned!

// Pool only has liquidity at valid ticks
// Invalid ticks would cause failures in modifyLiquidity
```

**Step 2: Call unlock with Data**

```solidity
bytes memory data = abi.encode(
    msg.sender,
    msg.value,
    key,
    tickLower,
    zeroForOne,
    liquidity
);
poolManager.unlock(data);
```

**Data Encoding**:
- `msg.sender`: Who is placing the order (for payment)
- `msg.value`: ETH sent (if token0 is native)
- `key`: Pool details
- `tickLower`: Where to place order
- `zeroForOne`: Direction
- `liquidity`: Amount

**Step 3: Update Bucket (After Unlock Returns)**

```solidity
PoolId poolId = key.toId();
bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);
uint256 slot = slots[bucketId];
Bucket storage bucket = buckets[bucketId][slot];

bucket.liquidity += liquidity;
bucket.sizes[msg.sender] += liquidity;
```

**State Changes**:

```solidity
// Before (empty bucket):
bucket = {
    filled: false,
    amount0: 0,
    amount1: 0,
    liquidity: 0,
    sizes: {}
}

// After place(user1, 1e18):
bucket = {
    filled: false,
    amount0: 0,
    amount1: 0,
    liquidity: 1e18,
    sizes: {user1: 1e18}
}

// After place(user2, 0.5e18):
bucket = {
    filled: false,
    amount0: 0,
    amount1: 0,
    liquidity: 1.5e18,
    sizes: {user1: 1e18, user2: 0.5e18}
}
```

**Step 4: Emit Event**

```solidity
emit Place(
    PoolId.unwrap(poolId),
    slot,
    msg.sender,
    tickLower,
    zeroForOne,
    liquidity
);
```

### unlockCallback: ADD_LIQUIDITY Branch

**Called by**: `poolManager.unlock()` during `place()`

```solidity
if (action == ADD_LIQUIDITY) {
    (address sender, uint256 ethValue, PoolKey memory key,
     int24 tickLower, bool zeroForOne, uint128 liquidity
    ) = abi.decode(data, (...));
    
    // Step 1: Validate not at current tick
    if (tickLower == ticks[key.toId()]) revert NotAllowedAtCurrentTick();
    
    // Step 2: Add liquidity to pool
    (int256 d,) = poolManager.modifyLiquidity({
        key: key,
        params: ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickLower + key.tickSpacing,
            liquidityDelta: int256(uint256(liquidity)),  // POSITIVE = add
            salt: bytes32(0)
        }),
        hookData: ""
    });
    
    // Step 3: Extract amounts needed
    BalanceDelta delta = BalanceDelta.wrap(d);
    int128 amount0 = delta.amount0();
    int128 amount1 = delta.amount1();
    
    // Step 4: Determine which token to pay
    address currency;
    uint256 amountToPay;
    if (zeroForOne) {
        require(amount0 < 0 && amount1 == 0, "Tick crossed");
        currency = key.currency0;
        amountToPay = (-amount0).toUint256();
    } else {
        require(amount0 == 0 && amount1 < 0, "Tick crossed");
        currency = key.currency1;
        amountToPay = (-amount1).toUint256();
    }
    
    // Step 5: Sync and settle
    poolManager.sync(currency);
    
    if (currency == address(0)) {
        // Native ETH
        require(ethValue >= amountToPay, "Insufficient ETH sent");
        poolManager.settle{value: amountToPay}();
        if (ethValue > amountToPay) {
            _sendEth(sender, ethValue - amountToPay);  // Refund excess
        }
    } else {
        // ERC20
        require(ethValue == 0, "ETH sent for ERC20");
        IERC20(currency).transferFrom(sender, address(poolManager), amountToPay);
        poolManager.settle();
    }
    
    return "";
}
```

#### Detailed Callback Breakdown

**Validation: Not at Current Tick**

```solidity
if (tickLower == ticks[key.toId()]) revert NotAllowedAtCurrentTick();
```

**Why?**

```solidity
// Current tick: 85150
// Placing order at 85150:

// Problem: If we add liquidity at current tick,
// it would execute IMMEDIATELY in the same transaction!
// This defeats the purpose of a limit order (wait for price)

// Solutions:
// ✅ Place at 85140 (below current, will execute if price drops)
// ✅ Place at 85160 (above current, will execute if price rises)
// ❌ Place at 85150 (current, would execute now) ← REVERT
```

**Add Liquidity: Understanding liquidityDelta Sign**

```solidity
liquidityDelta: int256(uint256(liquidity))  // POSITIVE = add
```

**Direction Logic**:

```solidity
// zeroForOne = true (selling token0):
// Want to provide token0 liquidity
// When price crosses UP through this tick,
// token0 converts to token1

// zeroForOne = false (selling token1):
// Want to provide token1 liquidity
// When price crosses DOWN through this tick,
// token1 converts to token0
```

**Extract Payment Amounts**:

```solidity
if (zeroForOne) {
    // Selling token0
    require(amount0 < 0 && amount1 == 0, "Tick crossed");
    // amount0 < 0: Need to pay token0
    // amount1 == 0: Don't need token1 (range is one-sided)
    currency = key.currency0;
    amountToPay = (-amount0).toUint256();
} else {
    // Selling token1
    require(amount0 == 0 && amount1 < 0, "Tick crossed");
    // amount0 == 0: Don't need token0
    // amount1 < 0: Need to pay token1
    currency = key.currency1;
    amountToPay = (-amount1).toUint256();
}
```

**Why "Tick crossed" Error?**

```solidity
// If both amounts are needed, the range spans the current price
// This means the order would partially execute immediately
// We want EITHER amount0 OR amount1, not both

// Example:
// Current tick: 85150
// Place at tick 85140, zeroForOne=true
// Range: [85140, 85150)
// If current price is IN this range:
//   → Would need both tokens (providing liquidity at current price)
//   → REVERT "Tick crossed"
// If current price is ABOVE this range:
//   → Only need token0 (will convert when price drops)
//   → OK ✅
```

**Payment Handling: Native ETH**

```solidity
if (currency == address(0)) {
    require(ethValue >= amountToPay, "Insufficient ETH sent");
    poolManager.settle{value: amountToPay}();
    if (ethValue > amountToPay) {
        _sendEth(sender, ethValue - amountToPay);
    }
}
```

**Process**:
1. Check user sent enough ETH
2. Send exact amount to PoolManager
3. Refund any excess

**Example**:

```solidity
// Need to pay: 0.1 ETH
// User sent: 0.15 ETH

require(0.15 >= 0.1, ...)  // ✅ Pass
poolManager.settle{value: 0.1 ether}();
_sendEth(user, 0.05 ether);  // Refund 0.05 ETH
```

**Payment Handling: ERC20**

```solidity
else {
    require(ethValue == 0, "ETH sent for ERC20");
    IERC20(currency).transferFrom(sender, address(poolManager), amountToPay);
    poolManager.settle();
}
```

**Process**:
1. Verify no ETH was sent (common mistake)
2. Transfer ERC20 from user directly to PoolManager
3. Call settle() to finalize

**Example**:

```solidity
// Need to pay: 300 USDC
// User approved: 1000 USDC

require(msg.value == 0, ...)  // ✅ No ETH sent
USDC.transferFrom(user, poolManager, 300e6);
poolManager.settle();  // Finalizes the debt
```

### Complete place() Example

**Scenario**: Sell 1 ETH when price reaches $3050

```solidity
// Current price: $3000 (tick 85150)
// Want to sell at: $3050 (tick 85200)

// Calculate liquidity for 1 ETH at this range
uint128 liq = calculateLiquidity(1 ether, 85200, 85210);

// Call place
hook.place{value: 1 ether}(
    key: ETH_USDC_KEY,
    tickLower: 85200,
    zeroForOne: true,  // Selling ETH (token0)
    liquidity: liq
);

// Execution:
// 1. Validate: 85200 % 10 = 0 ✅
// 2. unlock() → unlockCallback(ADD_LIQUIDITY)
//    a. Validate: 85200 != 85150 ✅ (not at current tick)
//    b. modifyLiquidity(85200, 85210, +liq)
//       Returns: amount0 = -1 ETH, amount1 = 0
//    c. currency = ETH, amountToPay = 1 ETH
//    d. poolManager.settle{value: 1 ether}()
// 3. Update bucket:
//    buckets[bucketId][0].liquidity = 1e18
//    buckets[bucketId][0].sizes[user] = 1e18
// 4. Emit Place(...)

// Result: Order placed! Waiting for price to reach $3050
```

### Function 2: `cancel()` - Cancel an Unfilled Order

#### Function Signature

```solidity
function cancel(
    PoolKey calldata key,
    int24 tickLower,
    bool zeroForOne
) external setAction(REMOVE_LIQUIDITY)
```

**Purpose**: Cancel a limit order that hasn't filled yet and reclaim tokens.

**Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `key` | `PoolKey` | Which pool |
| `tickLower` | `int24` | Which tick the order is at |
| `zeroForOne` | `bool` | Which direction |

**Modifier**: `setAction(REMOVE_LIQUIDITY)` - Sets action for unlockCallback

#### Execution Flow

```
User calls cancel()
       ↓
Find user's bucket/slot
       ↓
Verify bucket not filled
       ↓
Update bucket (remove user's liquidity)
       ↓
poolManager.unlock()
       ↓
unlockCallback(REMOVE_LIQUIDITY)
  → Remove liquidity from pool
  → Take tokens back
  → Calculate fees
       ↓
Handle fees (last canceler gets all)
       ↓
Transfer tokens to user
       ↓
Emit Cancel event
```

#### Implementation Breakdown

**Step 1: Find Bucket**

```solidity
PoolId poolId = key.toId();
bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);
uint256 slot = slots[bucketId];
Bucket storage bucket = buckets[bucketId][slot];
```

**Step 2: Verify Not Filled**

```solidity
if (bucket.filled) revert BucketFilled();
```

**Why?**

```solidity
// Filled orders can't be canceled
// They've already executed!
// Use take() instead to claim proceeds
```

**Step 3: Remove User's Liquidity from Bucket**

```solidity
uint128 userLiquidity = bucket.sizes[msg.sender];
require(userLiquidity > 0, "limit order size = 0");
bucket.liquidity -= userLiquidity;
bucket.sizes[msg.sender] = 0;
```

**State Changes**:

```solidity
// Before cancel (bucket with 2 users):
bucket = {
    filled: false,
    liquidity: 1.5e18,
    sizes: {user1: 1.0e18, user2: 0.5e18}
}

// user1 cancels:
bucket = {
    filled: false,
    liquidity: 0.5e18,        // ← Reduced
    sizes: {user1: 0, user2: 0.5e18}  // ← user1 removed
}
```

**Step 4: Call Unlock to Remove Liquidity**

```solidity
bytes memory res = poolManager.unlock(
    abi.encode(key, tickLower, userLiquidity)
);

(uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1) = 
    abi.decode(res, (uint256, uint256, uint256, uint256));
```

**Returns**:
- `amount0`, `amount1`: Tokens removed from position
- `fee0`, `fee1`: Fees accrued while liquidity was in pool

**Step 5: Fee Distribution Logic**

```solidity
if (bucket.liquidity > 0) {
    // Other users still have orders in this bucket
    // Keep fees in bucket for last canceler
    bucket.amount0 += fee0;
    bucket.amount1 += fee1;
    
    // Send principal minus fees to user
    if (amount0 > fee0) {
        key.currency0.transferOut(msg.sender, amount0 - fee0);
    }
    if (amount1 > fee1) {
        key.currency1.transferOut(msg.sender, amount1 - fee1);
    }
} else {
    // Last user to cancel (bucket now empty)
    // Gets their principal + all accumulated fees
    amount0 += bucket.amount0;
    bucket.amount0 = 0;
    if (amount0 > 0) key.currency0.transferOut(msg.sender, amount0);
    
    amount1 += bucket.amount1;
    bucket.amount1 = 0;
    if (amount1 > 0) key.currency1.transferOut(msg.sender, amount1);
}
```

**Fee Distribution Example**:

```solidity
// Initial: 3 users, 10 USDC fees accumulated
// bucket.amount0 = 10e6
// bucket.liquidity = 3e18
// sizes = {user1: 1e18, user2: 1e18, user3: 1e18}

// User1 cancels:
// Gets: principal only (no fees)
// bucket.amount0 = 10e6 (fees stay)
// bucket.liquidity = 2e18

// User2 cancels:
// Gets: principal only (no fees)
// bucket.amount0 = 10e6 (fees still stay)
// bucket.liquidity = 1e18

// User3 cancels (LAST):
// Gets: principal + ALL 10 USDC fees!
// bucket.amount0 = 0
// bucket.liquidity = 0
```

**Why This Design?**

```solidity
// Problem: How to fairly distribute fees when canceling?
// 
// Solution 1: Split fees proportionally on each cancel
// ❌ Complex math
// ❌ Rounding errors
// ❌ Gas intensive
//
// Solution 2: Last canceler gets all fees
// ✅ Simple
// ✅ No rounding errors
// ✅ Gas efficient
// ✅ Incentivizes last person to clean up
```

### unlockCallback: REMOVE_LIQUIDITY Branch

**Called by**: `poolManager.unlock()` during `cancel()`

```solidity
else if (action == REMOVE_LIQUIDITY) {
    (PoolKey memory key, int24 tickLower, uint128 size) = 
        abi.decode(data, (PoolKey, int24, uint128));
    
    // Remove liquidity from pool
    (int256 d, int256 f) = poolManager.modifyLiquidity({
        key: key,
        params: ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickLower + key.tickSpacing,
            liquidityDelta: -int256(uint256(size)),  // NEGATIVE = remove
            salt: bytes32(0)
        }),
        hookData: ""
    });
    
    // Extract amounts (principal)
    BalanceDelta delta = BalanceDelta.wrap(d);
    uint256 amount0 = 0;
    uint256 amount1 = 0;
    if (delta.amount0() > 0) {
        amount0 = uint256(uint128(delta.amount0()));
        poolManager.take(key.currency0, address(this), amount0);
    }
    if (delta.amount1() > 0) {
        amount1 = uint256(uint128(delta.amount1()));
        poolManager.take(key.currency1, address(this), amount1);
    }
    
    // Extract fees (separate return value!)
    BalanceDelta feesAccrued = BalanceDelta.wrap(f);
    uint256 fee0 = 0;
    uint256 fee1 = 0;
    if (feesAccrued.amount0() > 0) {
        fee0 = uint256(uint128(feesAccrued.amount0()));
    }
    if (feesAccrued.amount1() > 0) {
        fee1 = uint256(uint128(feesAccrued.amount1()));
    }
    
    return abi.encode(amount0, amount1, fee0, fee1);
}
```

**Key Details**:

1. **Two Return Values from modifyLiquidity**:
   - `d` = BalanceDelta (principal amounts)
   - `f` = BalanceDelta (fees accrued)

2. **Take Both Principal and Fees**:
   - `amount0 + fee0` total taken
   - But returned separately for fee logic

3. **Return Encoded Data**:
   - `cancel()` needs these values to distribute properly

### Complete cancel() Example

**Scenario**: Cancel a sell order before it fills

```solidity
// User placed: Sell 1 ETH at tick 85200
// Current price: Still at tick 85150 (order not filled)
// Time passed: 1 hour, earned 0.1 USDC in fees

// Call cancel
hook.cancel(
    key: ETH_USDC_KEY,
    tickLower: 85200,
    zeroForOne: true
);

// Execution:
// 1. Find bucket:
//    bucketId = hash(poolId, 85200, true)
//    slot = 0
//    bucket.filled = false ✅
//
// 2. Get user's size:
//    userLiquidity = 1e18
//    bucket.liquidity = 1e18 (only user)
//
// 3. Update bucket:
//    bucket.liquidity = 0
//    bucket.sizes[user] = 0
//
// 4. unlock() → unlockCallback(REMOVE_LIQUIDITY)
//    a. modifyLiquidity(85200, 85210, -1e18)
//       Returns: 
//         delta = (amount0: 1 ETH, amount1: 0)
//         fees = (fee0: 0, fee1: 0.1 USDC)
//    b. take(ETH, 1 ether)
//    c. take(USDC, 0.1e6)
//    d. return (1 ether, 0, 0, 0.1e6)
//
// 5. Fee distribution:
//    bucket.liquidity = 0 (last canceler!)
//    amount0 += bucket.amount0 (none accumulated)
//    Transfer 1 ETH to user
//    Transfer 0.1 USDC to user (fees!)
//
// 6. Emit Cancel(...)

// Result: User got back 1 ETH + 0.1 USDC fees
```

### Function 3: `take()` - Claim Filled Order Proceeds

#### Function Signature

```solidity
function take(
    PoolKey calldata key,
    int24 tickLower,
    bool zeroForOne
) external
```

**Purpose**: Claim your share of the output tokens after an order has filled.

**Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `key` | `PoolKey` | Which pool |
| `tickLower` | `int24` | Which tick the order was at |
| `zeroForOne` | `bool` | Which direction the order was |

**No Modifier**: Doesn't need unlock, just transfers tokens

#### Execution Flow

```
User calls take()
       ↓
Find bucket and verify filled
       ↓
Calculate user's share
       ↓
Update bucket state
       ↓
Transfer tokens to user
       ↓
Emit Take event
```

#### Implementation Breakdown

**Step 1: Find Bucket**

```solidity
PoolId poolId = key.toId();
bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);
uint256 slot = slots[bucketId];
Bucket storage bucket = buckets[bucketId][slot];
```

**Step 2: Verify Bucket is Filled**

```solidity
if (!bucket.filled) revert BucketNotFilled();
```

**Why?**

```solidity
// Can only claim proceeds from filled orders
// Unfilled orders: use cancel() instead
```

**Step 3: Calculate User's Proportional Share**

```solidity
uint128 size = bucket.sizes[msg.sender];
require(size > 0, "limit order size = 0");

// Calculate user's percentage of total liquidity
uint256 amount0 = (bucket.amount0 * size) / bucket.liquidity;
uint256 amount1 = (bucket.amount1 * size) / bucket.liquidity;
```

**Proportional Math**:

```solidity
// Bucket state after fill:
// bucket.liquidity = 10e18 (total from all users)
// bucket.amount0 = 0 (all converted)
// bucket.amount1 = 3050 USDC (received from swap)

// User's position:
// size = 2e18 (user contributed 2 ETH of the 10 ETH)

// User's share:
// amount0 = (0 * 2e18) / 10e18 = 0
// amount1 = (3050e6 * 2e18) / 10e18 = 610 USDC

// User gets 610 USDC (20% of 3050 USDC)
```

**Step 4: Update Bucket State**

```solidity
bucket.liquidity -= size;
bucket.amount0 -= amount0;
bucket.amount1 -= amount1;
bucket.sizes[msg.sender] = 0;
```

**State Evolution**:

```solidity
// After fill (3 users):
bucket = {
    filled: true,
    amount0: 0,
    amount1: 3050e6,  // Total USDC received
    liquidity: 10e18,  // Total ETH that was sold
    sizes: {
        user1: 5e18,   // 50%
        user2: 3e18,   // 30%
        user3: 2e18    // 20%
    }
}

// user1 takes (5 ETH = 50%):
bucket = {
    filled: true,
    amount0: 0,
    amount1: 1525e6,  // 3050 - 1525 = 1525
    liquidity: 5e18,   // 10 - 5 = 5
    sizes: {
        user1: 0,       // Claimed!
        user2: 3e18,
        user3: 2e18
    }
}

// user2 takes (3 ETH = 30% of original):
bucket = {
    filled: true,
    amount0: 0,
    amount1: 610e6,    // 1525 - 915 = 610
    liquidity: 2e18,    // 5 - 3 = 2
    sizes: {
        user1: 0,
        user2: 0,       // Claimed!
        user3: 2e18
    }
}

// user3 takes (2 ETH = 20% of original):
bucket = {
    filled: true,
    amount0: 0,
    amount1: 0,         // All distributed
    liquidity: 0,        // All claimed
    sizes: {
        user1: 0,
        user2: 0,
        user3: 0        // Claimed!
    }
}
```

**Step 5: Transfer Tokens**

```solidity
if (amount0 > 0) {
    key.currency0.transferOut(msg.sender, amount0);
}
if (amount1 > 0) {
    key.currency1.transferOut(msg.sender, amount1);
}
```

**Step 6: Emit Event**

```solidity
emit Take(
    PoolId.unwrap(poolId),
    slot,
    msg.sender,
    tickLower,
    zeroForOne,
    amount0,
    amount1
);
```

### Complete take() Example

**Scenario**: Claim proceeds from filled sell order

```solidity
// Initial order:
// - User sold 2 ETH at $3050
// - Part of larger bucket with 10 ETH total
// - Order filled! 10 ETH → 30,500 USDC
// - User owns 20% (2 ETH of 10 ETH)

// Call take
hook.take(
    key: ETH_USDC_KEY,
    tickLower: 85200,
    zeroForOne: true
);

// Execution:
// 1. Find bucket:
//    bucketId = hash(poolId, 85200, true)
//    slot = 1 (filled bucket)
//    bucket.filled = true ✅
//
// 2. Get user's size:
//    size = 2e18
//
// 3. Calculate shares:
//    amount0 = (0 * 2e18) / 10e18 = 0
//    amount1 = (30500e6 * 2e18) / 10e18 = 6100e6 (6,100 USDC)
//
// 4. Update bucket:
//    bucket.liquidity = 10e18 - 2e18 = 8e18
//    bucket.amount1 = 30500e6 - 6100e6 = 24400e6
//    bucket.sizes[user] = 0
//
// 5. Transfer:
//    USDC.transfer(user, 6100e6)
//
// 6. Emit Take(...)

// Result: User received 6,100 USDC for their 2 ETH
// Execution price: $3,050 per ETH (exactly as specified!)
```

### Take vs Cancel: When to Use

| Situation | Function | Result |
|-----------|----------|--------|
| Order not filled yet | `cancel()` | Get back original tokens + any fees |
| Order filled | `take()` | Get output tokens (swap proceeds) |
| Filled but haven't claimed | `take()` | Claim anytime, no rush |
| Want to exit unfilled order | `cancel()` | Immediate exit |

**Important Notes**:

```solidity
// 1. take() can be called anytime after fill (no expiry)
// 2. Must call take() for each filled order separately
// 3. Proportional share is fixed at time of fill
// 4. Last person to take() gets rounding benefits/dust
```

## Helper Functions

### Function: `getBucketId()`

**Purpose**: Generate unique identifier for a bucket

```solidity
function getBucketId(
    PoolId poolId,
    int24 tickLower,
    bool zeroForOne
) private pure returns (bytes32)
```

**Implementation**:

```solidity
return keccak256(abi.encode(poolId, tickLower, zeroForOne));
```

**Example**:

```solidity
// ETH-USDC pool, tick 85200, sell ETH
bytes32 id = keccak256(abi.encode(
    0x742d...,  // poolId
    85200,      // tickLower
    true        // zeroForOne
));

// Different direction = different bucket!
bytes32 id2 = keccak256(abi.encode(
    0x742d...,  // same pool
    85200,      // same tick
    false       // DIFFERENT direction
));
// id != id2 (separate buckets for buy vs sell)
```

### Function: `_getTick()`

**Purpose**: Get current tick of a pool

```solidity
function _getTick(PoolKey calldata key) private view returns (int24 tick)
```

**Implementation**:

```solidity
(, tick,,) = poolManager.getSlot0(key.toId());
```

**What is Slot0?**

```solidity
// Slot0 contains:
struct Slot0 {
    uint160 sqrtPriceX96;  // Current price (sqrt format)
    int24 tick;            // Current tick ← We want this
    uint24 protocolFee;    // Protocol fee settings
    uint24 lpFee;          // LP fee settings
}

// We only care about tick, so we use:
// (, tick,,) = ... 
//    ↑  ↑ ↑↑
//    |  | ||__ lpFee (ignored)
//    |  | |___ protocolFee (ignored)
//    |  |_____ tick (extracted!)
//    |________ sqrtPriceX96 (ignored)
```

### Function: `_getTickLower()`

**Purpose**: Calculate the lower tick of a range given direction

```solidity
function _getTickLower(
    int24 tick,
    int24 tickSpacing,
    bool zeroForOne
) private pure returns (int24)
```

**Logic**:

```solidity
// zeroForOne = true (swapping token0 for token1):
//   Price is RISING
//   Fill orders ABOVE current tick
//   tickLower = tick (aligned to tickSpacing)

// zeroForOne = false (swapping token1 for token0):
//   Price is FALLING
//   Fill orders BELOW current tick
//   tickLower = tick - tickSpacing (aligned)

int24 tickLower;
if (zeroForOne) {
    // Price rising, fill sell orders at or above current tick
    tickLower = tick;
} else {
    // Price falling, fill buy orders at or below current tick
    tickLower = tick - tickSpacing;
}

// Align to valid tick spacing
if (tickLower % tickSpacing != 0) {
    // Round down to nearest multiple
    tickLower = (tickLower / tickSpacing) * tickSpacing;
}

return tickLower;
```

**Visual Example**:

```
tickSpacing = 10

Current tick: 85155

zeroForOne = true (price rising):
  tickLower = 85155
  Aligned: 85150 (round down to nearest 10)
  Range to check: [85150, ∞)

zeroForOne = false (price falling):
  tickLower = 85155 - 10 = 85145
  Aligned: 85140 (round down to nearest 10)
  Range to check: (-∞, 85140]
```

### Function: `_getTickRange()`

**Purpose**: Determine the range of ticks to check for filled orders

```solidity
function _getTickRange(
    int24 tickPrev,
    int24 tick,
    int24 tickSpacing,
    bool zeroForOne
) private pure returns (int24 tickLower, int24 tickUpper)
```

**Implementation**:

```solidity
tickLower = _getTickLower(
    tickPrev < tick ? tickPrev : tick,
    tickSpacing,
    zeroForOne
);

tickUpper = _getTickLower(
    tick < tickPrev ? tickPrev : tick,
    tickSpacing,
    zeroForOne
);
```

**Logic Breakdown**:

```solidity
// Find min and max of (tickPrev, tick)
int24 min = tickPrev < tick ? tickPrev : tick;
int24 max = tick < tickPrev ? tickPrev : tick;

// Get lower bound of range
tickLower = _getTickLower(min, tickSpacing, zeroForOne);

// Get upper bound of range
tickUpper = _getTickLower(max, tickSpacing, zeroForOne);

// Returns: [tickLower, tickUpper]
// This is the range where orders may have filled
```

**Example 1: Price Rising**

```solidity
// tickSpacing = 10
// tickPrev = 85140
// tick = 85170 (price moved UP)
// zeroForOne = true (swap going UP)

min = 85140
max = 85170

tickLower = _getTickLower(85140, 10, true) = 85140
tickUpper = _getTickLower(85170, 10, true) = 85170

// Range: [85140, 85170]
// Check ticks: 85140, 85150, 85160, 85170
```

**Example 2: Price Falling**

```solidity
// tickSpacing = 10
// tickPrev = 85170
// tick = 85140 (price moved DOWN)
// zeroForOne = false (swap going DOWN)

min = 85140
max = 85170

tickLower = _getTickLower(85140, 10, false) = 85130
tickUpper = _getTickLower(85170, 10, false) = 85160

// Range: [85130, 85160]
// Check ticks: 85130, 85140, 85150, 85160
```

### Why This Range Logic?

```solidity
// Problem: Swap moved from tick A to tick B
// Which limit orders got filled?

// Answer: Orders between A and B (exclusive of endpoints!)

// Example:
// Before swap: tick = 85140
// After swap: tick = 85170
// Orders at: 85150, 85160

// These orders are IN THE RANGE [85140, 85170]
// They were crossed during the swap → FILLED!

// The range calculation ensures we:
// 1. Find the min and max of (prev, current)
// 2. Align them properly for the swap direction
// 3. Return an inclusive range to iterate
```

## Complete Order Lifecycle Examples

### Example 1: Place → Fill → Take

**Setup**:
- Pool: ETH-USDC
- Current price: $3000 (tick 85150)
- User wants: Sell 1 ETH at $3050

**Step 1: Place Order**

```solidity
// Calculate liquidity for 1 ETH in range [85200, 85210)
uint128 liq = 1e18; // Simplified

hook.place{value: 1 ether}(
    key: ETH_USDC_KEY,
    tickLower: 85200,  // Price $3050
    zeroForOne: true,  // Sell ETH
    liquidity: liq
);

// State after place:
// buckets[bucketId][0] = {
//     filled: false,
//     amount0: 0,
//     amount1: 0,
//     liquidity: 1e18,
//     sizes: {user: 1e18}
// }
// Pool has 1 ETH liquidity at tick 85200
```

**Step 2: Wait for Price Movement** (Someone Swaps)

```solidity
// Another user swaps 10,000 USDC for ETH
// This pushes price up from $3000 → $3100
// Price crosses through tick 85200!

// afterSwap() triggers:
// - Detects tick crossed 85200
// - Finds bucket for tick 85200, zeroForOne=true
// - Converts 1 ETH → 3050 USDC
// - Marks bucket as filled

// State after fill:
// slots[bucketId] = 1 (new slot for next orders)
// buckets[bucketId][0] = {
//     filled: true,     ← Changed!
//     amount0: 0,
//     amount1: 3050e6,  ← Proceeds!
//     liquidity: 1e18,
//     sizes: {user: 1e18}
// }
```

**Step 3: User Claims Proceeds**

```solidity
hook.take(
    key: ETH_USDC_KEY,
    tickLower: 85200,
    zeroForOne: true
);

// Calculation:
// amount1 = (3050e6 * 1e18) / 1e18 = 3050e6

// User receives: 3050 USDC
// Exactly $3050 per ETH as specified!
```

### Example 2: Place → Cancel (Before Fill)

**Setup**:
- Pool: ETH-USDC  
- Current price: $3000
- User wants: Sell at $3050
- But: Changes mind before it fills

**Step 1: Place Order**

```solidity
hook.place{value: 1 ether}(
    key: ETH_USDC_KEY,
    tickLower: 85200,
    zeroForOne: true,
    liquidity: 1e18
);

// User's 1 ETH now in pool at tick 85200
```

**Step 2: Wait... Price Stays at $3000**

```solidity
// Hours pass, price doesn't reach $3050
// User decides to cancel

hook.cancel(
    key: ETH_USDC_KEY,
    tickLower: 85200,
    zeroForOne: true
);

// Execution:
// 1. Check bucket.filled = false ✅
// 2. Remove 1e18 liquidity from pool
// 3. Transfer 1 ETH back to user
// 4. If fees accrued, user gets those too

// User receives: 1 ETH + any fees
```

### Example 3: Multiple Users, Partial Takes

**Setup**:
- 3 users place orders at same tick
- All get filled together
- Each claims their share separately

**Step 1: Users Place Orders**

```solidity
// User1: 5 ETH
hook.place{value: 5 ether}(...);

// User2: 3 ETH
hook.place{value: 3 ether}(...);

// User3: 2 ETH
hook.place{value: 2 ether}(...);

// Bucket state:
// liquidity = 10e18
// sizes = {user1: 5e18, user2: 3e18, user3: 2e18}
```

**Step 2: Order Fills**

```solidity
// afterSwap converts 10 ETH → 30,500 USDC

// Bucket state:
// filled = true
// amount1 = 30500e6
// liquidity = 10e18
// sizes = {user1: 5e18, user2: 3e18, user3: 2e18}
```

**Step 3: Users Claim (Any Order)**

```solidity
// User2 claims first:
hook.take(...);
// Receives: (30500e6 * 3e18) / 10e18 = 9150e6 (9,150 USDC)

// User1 claims second:
hook.take(...);
// Receives: (21350e6 * 5e18) / 7e18 = 15250e6 (15,250 USDC)

// User3 claims last:
hook.take(...);
// Receives: (6100e6 * 2e18) / 2e18 = 6100e6 (6,100 USDC)

// Total distributed: 9150 + 15250 + 6100 = 30,500 USDC ✅
```

## Testing Guide

### Running Tests

```bash
# Run all limit order tests
forge test --match-contract LimitOrder

# Run specific test
forge test --match-test testPlace -vvv

# Run with gas report
forge test --match-contract LimitOrder --gas-report

# Run with detailed traces
forge test --match-test testAfterSwap -vvvv
```

### Test Structure (from `LimitOrder.test.sol`)

The test file demonstrates all key scenarios:

#### 1. Setup Tests

```solidity
function setUp() public {
    // Deploy fresh contracts
    // Create test pool
    // Initialize pool state
    // Fund test accounts
}
```

**Key Setup**:
- Deploys PoolManager and LimitOrder hook
- Creates ETH-USDC test pool
- Provides liquidity for swaps
- Mints test tokens

#### 2. Place Tests

```solidity
function testPlace() public {
    // Place order above current price
    // Verify bucket state
    // Verify liquidity added to pool
}

function testPlaceMultipleUsers() public {
    // Multiple users place at same tick
    // Verify shared bucket
    // Check individual sizes
}

function testPlaceBelowCurrentTick() public {
    // Place sell order below price (should work)
    // Place buy order above price (should work)
}

function testPlaceAtCurrentTick() public {
    // Should revert: NotAllowedAtCurrentTick
}
```

#### 3. Cancel Tests

```solidity
function testCancel() public {
    // Place order
    // Cancel before fill
    // Verify tokens returned
}

function testCancelWithFees() public {
    // Place order
    // Wait for fees to accrue
    // Cancel as last user
    // Verify got principal + fees
}

function testCancelFilled() public {
    // Place order
    // Let it fill
    // Try to cancel
    // Should revert: BucketFilled
}
```

#### 4. Take Tests

```solidity
function testTake() public {
    // Place order
    // Execute swap to fill it
    // Take proceeds
    // Verify correct amounts
}

function testTakeMultipleUsers() public {
    // Multiple users place orders
    // Orders fill
    // Each user takes their share
    // Verify proportional distribution
}

function testTakeNotFilled() public {
    // Place order
    // Try to take before fill
    // Should revert: BucketNotFilled
}
```

#### 5. Integration Tests

```solidity
function testAfterSwapFillsOrders() public {
    // Place orders at multiple ticks
    // Execute large swap
    // Verify all orders in range filled
    // Verify orders outside range untouched
}

function testCompleteLifecycle() public {
    // User1: place → fill → take
    // User2: place → cancel
    // User3: place → fill → take
    // Verify all state transitions
}
```

### Writing Your Own Tests

#### Template: Test Place Order

```solidity
function testMyPlace() public {
    // 1. Define test parameters
    int24 tickLower = 85200;
    bool zeroForOne = true;
    uint128 liquidity = 1e18;
    
    // 2. Get initial state
    (,int24 tickBefore,,) = poolManager.getSlot0(poolId);
    uint256 balanceBefore = address(this).balance;
    
    // 3. Execute place
    hook.place{value: 1 ether}(
        key,
        tickLower,
        zeroForOne,
        liquidity
    );
    
    // 4. Verify state changes
    bytes32 bucketId = hook.getBucketId(poolId, tickLower, zeroForOne);
    (bool filled,, uint256 amount1, uint128 liq,) = 
        hook.getBucket(bucketId, 0);
    
    assertEq(filled, false);
    assertEq(liq, liquidity);
    assertEq(amount1, 0);
    
    // 5. Verify balance change
    assertEq(balanceBefore - address(this).balance, 1 ether);
}
```

#### Template: Test Order Fill

```solidity
function testMyOrderFill() public {
    // 1. Place order
    int24 tickLower = 85200;
    hook.place{value: 1 ether}(
        key,
        tickLower,
        true,  // zeroForOne
        1e18
    );
    
    // 2. Check order not filled yet
    bytes32 bucketId = hook.getBucketId(poolId, tickLower, true);
    (bool filledBefore,,,,) = hook.getBucket(bucketId, 0);
    assertEq(filledBefore, false);
    
    // 3. Execute swap to cross price
    // Need to swap enough to move from current tick to tickLower
    int256 amountIn = 10000e6;  // 10k USDC
    
    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
        zeroForOne: false,  // Buy ETH with USDC
        amountSpecified: amountIn,
        sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(tickLower + 1)
    });
    
    poolManager.swap(key, params, "");
    
    // 4. Verify order filled
    (bool filledAfter,, uint256 amount1,,) = hook.getBucket(bucketId, 0);
    assertEq(filledAfter, true);
    assertGt(amount1, 0);  // Has USDC proceeds
    
    // 5. Verify slot incremented (new orders go to slot 1)
    uint256 currentSlot = hook.getSlot(bucketId);
    assertEq(currentSlot, 1);
}
```

### Common Test Patterns

#### Pattern 1: Asserting Reverts

```solidity
// Test invalid tick spacing
vm.expectRevert(WrongTickSpacing.selector);
hook.place(key, 85205, true, 1e18);  // 85205 % 10 != 0

// Test cancel filled order
hook.place{value: 1 ether}(key, 85200, true, 1e18);
_swapToCross(85200);  // Fill it
vm.expectRevert(BucketFilled.selector);
hook.cancel(key, 85200, true);
```

#### Pattern 2: Testing Multiple Users

```solidity
function testMultipleUsers() public {
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    
    // Fund users
    vm.deal(user1, 10 ether);
    vm.deal(user2, 10 ether);
    
    // User1 places order
    vm.prank(user1);
    hook.place{value: 5 ether}(key, 85200, true, 5e18);
    
    // User2 places order at same tick
    vm.prank(user2);
    hook.place{value: 3 ether}(key, 85200, true, 3e18);
    
    // Verify shared bucket
    bytes32 bucketId = hook.getBucketId(poolId, 85200, true);
    (,,, uint128 totalLiq,) = hook.getBucket(bucketId, 0);
    assertEq(totalLiq, 8e18);
    
    // Verify individual sizes
    uint128 size1 = hook.getSize(bucketId, 0, user1);
    uint128 size2 = hook.getSize(bucketId, 0, user2);
    assertEq(size1, 5e18);
    assertEq(size2, 3e18);
}
```

#### Pattern 3: Testing Edge Cases

```solidity
function testEdgeCases() public {
    // Edge Case 1: Tiny liquidity amount
    hook.place{value: 1 wei}(key, 85200, true, 1);
    
    // Edge Case 2: Huge liquidity amount
    hook.place{value: 1000 ether}(key, 85200, true, 1000e18);
    
    // Edge Case 3: Price exactly at tick
    (,int24 currentTick,,) = poolManager.getSlot0(poolId);
    vm.expectRevert(NotAllowedAtCurrentTick.selector);
    hook.place{value: 1 ether}(key, currentTick, true, 1e18);
    
    // Edge Case 4: Same user places twice at same tick
    hook.place{value: 1 ether}(key, 85200, true, 1e18);
    hook.place{value: 2 ether}(key, 85200, true, 2e18);
    
    bytes32 bucketId = hook.getBucketId(poolId, 85200, true);
    uint128 size = hook.getSize(bucketId, 0, address(this));
    assertEq(size, 3e18);  // Accumulated
}
```

## Common Pitfalls and Solutions

### Pitfall 1: Wrong Tick Spacing

**Problem**:

```solidity
// Pool has tickSpacing = 10
hook.place(key, 85205, true, 1e18);  // ❌ REVERTS

// Error: WrongTickSpacing
// 85205 % 10 = 5 (not aligned!)
```

**Solution**:

```solidity
// Always align to tickSpacing
int24 tickSpacing = key.tickSpacing;
int24 desiredTick = 85205;

// Round down to nearest multiple
int24 validTick = (desiredTick / tickSpacing) * tickSpacing;
// validTick = 85200 ✅

hook.place(key, validTick, true, 1e18);
```

### Pitfall 2: Placing Order at Current Tick

**Problem**:

```solidity
(,int24 currentTick,,) = poolManager.getSlot0(poolId);
hook.place(key, currentTick, true, 1e18);  // ❌ REVERTS

// Error: NotAllowedAtCurrentTick
```

**Why?**

```solidity
// If you place at current tick, the liquidity would execute immediately
// This defeats the purpose of a limit order!
```

**Solution**:

```solidity
(,int24 currentTick,,) = poolManager.getSlot0(poolId);

// For sell orders (zeroForOne=true), place ABOVE current price
int24 sellTick = currentTick + key.tickSpacing;
hook.place(key, sellTick, true, 1e18);  // ✅

// For buy orders (zeroForOne=false), place BELOW current price
int24 buyTick = currentTick - key.tickSpacing;
hook.place(key, buyTick, false, 1e18);  // ✅
```

### Pitfall 3: Calling take() Before Order Fills

**Problem**:

```solidity
hook.place{value: 1 ether}(key, 85200, true, 1e18);
hook.take(key, 85200, true);  // ❌ REVERTS

// Error: BucketNotFilled
```

**Solution**:

```solidity
// Check if filled before taking
bytes32 bucketId = hook.getBucketId(poolId, 85200, true);
uint256 slot = hook.getSlot(bucketId);
(bool filled,,,,) = hook.getBucket(bucketId, slot);

if (filled) {
    hook.take(key, 85200, true);  // ✅
} else {
    // Order not filled yet, wait or cancel
    hook.cancel(key, 85200, true);  // ✅
}
```

### Pitfall 4: Calling cancel() After Order Fills

**Problem**:

```solidity
hook.place{value: 1 ether}(key, 85200, true, 1e18);
// ... price crosses 85200, order fills ...
hook.cancel(key, 85200, true);  // ❌ REVERTS

// Error: BucketFilled
```

**Solution**:

```solidity
// Check bucket status first
bytes32 bucketId = hook.getBucketId(poolId, 85200, true);
uint256 slot = hook.getSlot(bucketId);
(bool filled,,,,) = hook.getBucket(bucketId, slot);

if (!filled) {
    hook.cancel(key, 85200, true);  // ✅ Can cancel
} else {
    hook.take(key, 85200, true);  // ✅ Must take instead
}
```

### Pitfall 5: Insufficient ETH Sent

**Problem**:

```solidity
// Need to provide 1 ETH of liquidity
hook.place{value: 0.5 ether}(key, 85200, true, 1e18);  // ❌ REVERTS

// Error: Insufficient ETH sent
```

**Solution**:

```solidity
// Send enough ETH (or slightly more, excess is refunded)
hook.place{value: 1.1 ether}(key, 85200, true, 1e18);  // ✅
// Contract will refund 0.1 ETH automatically
```

### Pitfall 6: Wrong zeroForOne Direction

**Problem**:

```solidity
// Want to sell ETH (token0) at high price
// But set zeroForOne = false (wrong!)
hook.place(key, 85200, false, 1e18);

// This creates a BUY order, not a SELL order!
// Will execute when price falls to 85200, not rises
```

**Understanding**:

```
zeroForOne = true:
  "I'm swapping token0 FOR token1"
  Selling token0, buying token1
  Order executes when price RISES (more token1 per token0)

zeroForOne = false:
  "I'm swapping token1 FOR token0"
  Selling token1, buying token0
  Order executes when price FALLS (more token0 per token1)
```

**Solution**:

```solidity
// To sell ETH at $3050 (high price):
hook.place(key, 85200, true, 1e18);  // ✅ zeroForOne = true

// To buy ETH at $2950 (low price):
hook.place(key, 84800, false, 1e18);  // ✅ zeroForOne = false
```

### Pitfall 7: Not Accounting for Fees

**Problem**:

```solidity
// Place 1 ETH order
hook.place{value: 1 ether}(key, 85200, true, 1e18);

// Time passes, fees accrue
// Cancel and expect exactly 1 ETH back
hook.cancel(key, 85200, true);

// But actual ETH < 1 if other users still in bucket
// Or actual ETH > 1 if you're last canceler!
```

**Solution**:

```solidity
// Record balance before cancel
uint256 balanceBefore = address(this).balance;

hook.cancel(key, 85200, true);

uint256 balanceAfter = address(this).balance;
uint256 received = balanceAfter - balanceBefore;

// received might be:
// - Less than 1 ETH (fees kept in bucket for last canceler)
// - More than 1 ETH (you're last, got all accumulated fees!)
// - Exactly 1 ETH (no fees accrued yet)
```

### Pitfall 8: Rounding in Proportional Distribution

**Problem**:

```solidity
// 3 users contribute to bucket:
// User1: 1e18
// User2: 1e18  
// User3: 1e18
// Total: 3e18

// Order fills, receives 10 USDC
// 10 USDC / 3 users = 3.333... each

// User1 takes: (10e6 * 1e18) / 3e18 = 3333333 (3.33 USDC)
// User2 takes: (6666667 * 1e18) / 2e18 = 3333333 (3.33 USDC)
// User3 takes: (3333334 * 1e18) / 1e18 = 3333334 (3.33 USDC)

// Total: 3333333 + 3333333 + 3333334 = 10000000 ✅
// Last user gets rounding dust (1 extra wei)
```

**Solution**:

```solidity
// This is by design!
// Rounding errors accumulate to last user
// Always <= 1 wei per token
// Completely acceptable for limit orders
```

## Real-World Use Cases

### Use Case 1: Take-Profit Order

**Scenario**: You bought ETH at $2800, want to sell at $3200

```solidity
// Current price: $3000
// Target price: $3200

// Calculate tick for $3200
int24 targetTick = 85600;  // Approximate

// Place sell order
hook.place{value: 10 ether}(
    key: ETH_USDC_KEY,
    tickLower: targetTick,
    zeroForOne: true,  // Sell ETH
    liquidity: 10e18
);

// Wait for price to reach $3200
// Order automatically executes
// Call take() to claim USDC proceeds
```

### Use Case 2: Buy-the-Dip Order

**Scenario**: Wait for ETH to drop to $2600, then buy

```solidity
// Current price: $3000
// Target price: $2600

// Calculate tick for $2600
int24 targetTick = 84200;

// Place buy order with USDC
USDC.approve(address(hook), 26000e6);

hook.place(
    key: ETH_USDC_KEY,
    tickLower: targetTick,
    zeroForOne: false,  // Buy ETH (sell USDC)
    liquidity: calculateLiquidity(26000e6, targetTick, key.tickSpacing)
);

// If price drops to $2600, order executes
// Call take() to claim ETH
```

### Use Case 3: DCA (Dollar-Cost Averaging)

**Scenario**: Place multiple buy orders at different price levels

```solidity
// Place orders every $100 below current price
int24[] memory ticks = [
    84900,  // $2900
    84800,  // $2800
    84700,  // $2700
    84600,  // $2600
    84500   // $2500
];

for (uint i = 0; i < ticks.length; i++) {
    hook.place(
        key: ETH_USDC_KEY,
        tickLower: ticks[i],
        zeroForOne: false,  // Buy ETH
        liquidity: 1e18  // Same amount each
    );
}

// As price falls, orders execute one by one
// Automatic DCA into ETH!
```

### Use Case 4: Arbitrage Protection

**Scenario**: DEX price differs from CEX, place profitable orders

```solidity
// CEX price: $3000
// DEX price: $2980 (undervalued)

// If someone arbitrages, price will rise to $3000
// Place sell orders just above $3000 to capture the move

hook.place{value: 5 ether}(
    key: ETH_USDC_KEY,
    tickLower: 85180,  // $3010
    zeroForOne: true,
    liquidity: 5e18
);

// When arb bots push price up, your order fills at premium
```

## Best Practices

### 1. Always Check Bucket Status Before Actions

```solidity
function safeCancel(PoolKey calldata key, int24 tick, bool zeroForOne) 
    external 
{
    bytes32 bucketId = hook.getBucketId(key.toId(), tick, zeroForOne);
    uint256 slot = hook.getSlot(bucketId);
    (bool filled,,,,) = hook.getBucket(bucketId, slot);
    
    require(!filled, "Use take() instead");
    hook.cancel(key, tick, zeroForOne);
}
```

### 2. Store Order Parameters for Later Retrieval

```solidity
struct UserOrder {
    PoolKey key;
    int24 tickLower;
    bool zeroForOne;
    uint128 liquidity;
    uint256 timestamp;
}

mapping(address => UserOrder[]) public userOrders;

function placeAndTrack(...) external {
    hook.place{value: msg.value}(key, tickLower, zeroForOne, liquidity);
    
    userOrders[msg.sender].push(UserOrder({
        key: key,
        tickLower: tickLower,
        zeroForOne: zeroForOne,
        liquidity: liquidity,
        timestamp: block.timestamp
    }));
}
```

### 3. Implement Order Expiration

```solidity
function placeWithExpiry(
    PoolKey calldata key,
    int24 tickLower,
    bool zeroForOne,
    uint128 liquidity,
    uint256 expiryTime
) external payable {
    hook.place{value: msg.value}(key, tickLower, zeroForOne, liquidity);
    
    // Store expiry
    orderExpiries[msg.sender][getBucketId(...)] = expiryTime;
}

function cancelIfExpired(...) external {
    require(
        block.timestamp >= orderExpiries[msg.sender][bucketId],
        "Not expired yet"
    );
    hook.cancel(key, tickLower, zeroForOne);
}
```

### 4. Batch Operations for Gas Efficiency

```solidity
function placeMultiple(
    PoolKey calldata key,
    int24[] calldata ticks,
    bool[] calldata directions,
    uint128[] calldata liquidities
) external payable {
    require(ticks.length == directions.length, "Length mismatch");
    require(ticks.length == liquidities.length, "Length mismatch");
    
    for (uint i = 0; i < ticks.length; i++) {
        hook.place(
            key,
            ticks[i],
            directions[i],
            liquidities[i]
        );
    }
}
```

### 5. Monitor and Alert on Fill Events

```solidity
// Off-chain monitoring
event OrderFilled(address indexed user, bytes32 indexed bucketId);

// Contract
function afterSwap(...) external {
    // ... filling logic ...
    
    // Emit event for each filled bucket
    emit OrderFilled(user, bucketId);
}

// Frontend/Bot
contract.on("OrderFilled", async (user, bucketId) => {
    if (user === myAddress) {
        alert("Your order filled! Click to claim proceeds.");
    }
});
```

## Comparison with Traditional Limit Orders

| Feature | LimitOrder Hook | CEX Limit Order | Other DEX Limit Orders |
|---------|----------------|-----------------|------------------------|
| **Execution** | On-chain atomic | Off-chain matching | Varies (keeper, TWAP) |
| **Custody** | Non-custodial | Custodial | Non-custodial |
| **Price Guarantee** | Exact tick | Exact price | Slippage possible |
| **Fees** | LP fees while waiting | No fees while waiting | Varies |
| **Composability** | Full (Uniswap v4) | None | Limited |
| **Cancellation** | Instant, on-chain | Instant, off-chain | Varies |
| **Expiration** | Manual (gas cost) | Automatic (free) | Varies |
| **Partial Fill** | All-or-nothing per tick | Partial fills common | Varies |
| **Gas Cost** | Place + Take (~200k) | Free (off-chain) | Varies |

**When to Use LimitOrder Hook**:
- ✅ Want guaranteed execution at exact price
- ✅ Don't mind LP fees during wait
- ✅ Need composability with other DeFi protocols
- ✅ Prefer non-custodial solution

**When NOT to Use**:
- ❌ Very short-term trades (fees add up)
- ❌ High-frequency trading (gas costs)
- ❌ Need partial fills
- ❌ Want automatic expiration

## Security Considerations

### 1. Reentrancy Protection

**Current State**:

```solidity
// LimitOrder doesn't use ReentrancyGuard
// Why? PoolManager.unlock() has built-in reentrancy protection
// All state changes happen through unlock callback
```

**What's Protected**:
- Can't reenter `place()` during unlock
- Can't reenter `cancel()` during unlock
- `take()` doesn't use unlock, but transfers are after state changes

### 2. Front-Running Considerations

**Vulnerable Operation**: `place()` at specific tick

```solidity
// Attacker sees your place() transaction
// Front-runs with their own place() at same tick
// Now you share the bucket!
```

**Mitigation**:

```solidity
// Use private RPC (Flashbots, etc.)
// Or accept that limit orders are naturally competitive
```

### 3. Sandwich Attack Resistance

**Scenario**: Large limit order about to fill

```solidity
// Your order: Sell 100 ETH at $3050
// Attacker sees swap that will cross this tick
// Can't sandwich: Order execution is atomic within swap!
```

**Why Safe**:
- Order fills as part of swap transaction
- Price guarantee enforced by Uniswap v4 core
- No MEV extraction possible on the fill itself

### 4. Griefing Attacks

**Attack**: Place tiny orders to fragment buckets

```solidity
// Attacker places 1 wei orders at many ticks
// Minimal cost, but clutters state
```

**Mitigation**:

```solidity
// Could add minimum order size
uint128 constant MIN_LIQUIDITY = 1e6;  // 0.000001 ETH

function place(...) external {
    require(liquidity >= MIN_LIQUIDITY, "Order too small");
    // ...
}
```

### 5. Tick Manipulation

**Attack**: Manipulate price to trigger orders

```solidity
// Attacker wants to fill their own buy order
// Pushes price up temporarily
// Their sell order fills
// Price reverts (sandwich)
```

**Protection**:
- Expensive to manipulate price significantly
- Uniswap v4 core handles price impact
- Other LPs arbitrage away manipulation

## Gas Optimization Tips

### 1. Batch Place Orders

```solidity
// ❌ Expensive: 3 transactions
hook.place{value: 1 ether}(key, 85200, true, 1e18);  // ~150k gas
hook.place{value: 1 ether}(key, 85300, true, 1e18);  // ~150k gas
hook.place{value: 1 ether}(key, 85400, true, 1e18);  // ~150k gas
// Total: ~450k gas

// ✅ Cheaper: 1 transaction (if contract supports)
hook.placeMultiple{value: 3 ether}(
    key,
    [85200, 85300, 85400],
    [true, true, true],
    [1e18, 1e18, 1e18]
);  // ~300k gas (savings from shared tx overhead)
```

### 2. Cancel Multiple Orders When Last User

```solidity
// If you're the last user in multiple buckets, cancel all at once
// Gets all accumulated fees in one transaction
function cancelAll(
    PoolKey calldata key,
    int24[] calldata ticks,
    bool[] calldata directions
) external {
    for (uint i = 0; i < ticks.length; i++) {
        hook.cancel(key, ticks[i], directions[i]);
    }
}
```

### 3. Use Static Calls to Check State

```solidity
// ❌ Expensive: Send transaction that reverts
try hook.take(key, tickLower, zeroForOne) {
    // Success
} catch {
    // Failed, order not filled
}

// ✅ Cheap: Static call first
(bool filled,,,,) = hook.getBucket(bucketId, slot);
if (filled) {
    hook.take(key, tickLower, zeroForOne);  // Will succeed
}
```

## Extensions and Future Improvements

### Possible Extension 1: Time-Weighted Average Price (TWAP)

```solidity
// Instead of all-or-nothing fill, spread across multiple blocks
struct TWAPOrder {
    uint128 totalLiquidity;
    uint128 filledLiquidity;
    uint256 targetBlocks;
    uint256 startBlock;
}

// Fill gradually over time to achieve better average price
```

### Possible Extension 2: Conditional Orders

```solidity
// Execute order only if condition met
struct ConditionalOrder {
    bytes32 bucketId;
    address oracle;
    bytes conditionData;
}

// Example: Fill order only if ETH > $3000 on Chainlink
```

### Possible Extension 3: Partial Fill Support

```solidity
// Allow orders to partially fill
struct PartialOrder {
    uint128 totalSize;
    uint128 filledSize;
    uint128 minFillSize;
}

// More flexible, but adds complexity
```

### Possible Extension 4: Order Expiration

```solidity
// Automatic cancellation after time
struct ExpiringOrder {
    bytes32 bucketId;
    uint256 expiryTime;
}

// Keeper can call to cancel expired orders and earn fee
```

## Conclusion

The **LimitOrder** hook demonstrates advanced Uniswap V4 concepts:

### Key Takeaways

1. **Concentrated Liquidity as Orders**
   - Single-tick liquidity ranges act as limit orders
   - When price crosses, liquidity converts entirely
   - Provides exact price execution guarantee

2. **Bucket System**
   - Groups orders at same (pool, tick, direction)
   - Allows multiple users to share gas costs
   - Slot mechanism segregates filled vs unfilled orders

3. **Hook Integration**
   - `afterInitialize`: Tracks starting tick
   - `afterSwap`: Detects and fills crossed orders
   - Uses TStore pattern for cross-function communication

4. **User Operations**
   - `place()`: Add limit order, provide liquidity
   - `cancel()`: Remove unfilled order, reclaim tokens
   - `take()`: Claim proceeds from filled order

5. **Fee Distribution**
   - Orders earn LP fees while waiting
   - Last canceler in bucket gets all accumulated fees
   - Simple gas-efficient design

### When to Use This Pattern

**Good For**:
- Guaranteed price execution
- Medium to long-term orders
- Integration with other DeFi protocols
- Non-custodial requirements

**Not Ideal For**:
- Very short-term trades (fees)
- High-frequency trading (gas)
- Partial fills
- Automatic expiration

### Learning Path

1. **Start Here**: Understand bucket structure and lifecycle
2. **Next**: Study `afterSwap()` order filling logic
3. **Then**: Implement `place()`, `cancel()`, `take()`
4. **Finally**: Add your own features (expiration, TWAP, etc.)

### Resources

- **Uniswap V4 Docs**: https://docs.uniswap.org/contracts/v4/overview
- **Concentrated Liquidity**: https://docs.uniswap.org/concepts/protocol/concentrated-liquidity
- **Hook Development**: https://github.com/Uniswap/v4-periphery
- **Test File**: `test/LimitOrder.test.sol` in this repo

### Next Steps

1. **Run the tests**: `forge test --match-contract LimitOrder`
2. **Modify the code**: Try adding order expiration
3. **Deploy locally**: Use Anvil to test interactions
4. **Build a frontend**: Create UI for placing/managing orders

**Happy building! 🦄**

