# Uniswap V4 Position Manager (POSM) - Complete Technical Guide

## Introduction

This document provides a comprehensive technical explanation of the Position Manager (POSM) exercise, which teaches you how to interact with Uniswap V4's **Position Manager** contract to manage liquidity positions as NFTs. This is the primary interface for liquidity providers in Uniswap V4.

### What You'll Learn

- How to use the Position Manager to create and manage NFT-based liquidity positions
- Understanding the Actions pattern for batch operations
- Managing ETH and ERC20 tokens in liquidity operations
- The lifecycle of a liquidity position: mint, increase, decrease, and burn
- Payment settlement patterns: SETTLE_PAIR, CLOSE_CURRENCY, TAKE_PAIR
- Error handling and debugging techniques for fork-based tests
- Transient storage optimization with Permit2

### Key Concepts

**Position Manager (POSM)**: A peripheral contract that manages liquidity positions as ERC721 NFTs. Each position represents liquidity provided to a specific pool at a specific price range.

**NFT Position**: An ERC721 token representing ownership of a liquidity position. Contains metadata about the pool, tick range, and liquidity amount.

**Actions Pattern**: A batch execution system where multiple operations are encoded as a sequence of action types and parameters, executed atomically.

**Tick Range**: The price range where liquidity is active. Defined by `tickLower` and `tickUpper`. Liquidity only earns fees when price is within this range.

**Liquidity Delta**: The amount of liquidity to add (positive) or remove (negative) from a position.

**Settlement**: The process of paying tokens to or receiving tokens from the PoolManager. Uses various actions: SETTLE, SETTLE_PAIR, CLOSE_CURRENCY, TAKE, TAKE_PAIR.

**Permit2**: A token approval system that allows batch approvals and signatures, reducing gas costs and improving UX.

## Contract Overview

The `PosmExercises.sol` contract demonstrates how to interact with the Position Manager for the four core operations:

1. **Mint**: Create a new liquidity position (NFT)
2. **Increase Liquidity**: Add more liquidity to an existing position
3. **Decrease Liquidity**: Remove liquidity from a position
4. **Burn**: Close a position entirely and reclaim all tokens

### Core Features

| Feature | Description |
|---------|-------------|
| **NFT-Based Positions** | Each position is a unique ERC721 token |
| **Batch Actions** | Multiple operations in single transaction |
| **Multi-Currency** | Supports ETH and ERC20 tokens |
| **Slippage Protection** | amount0Max/Min, amount1Max/Min parameters |
| **Automatic Settlement** | Built-in payment handling via actions |
| **Leftover Recovery** | SWEEP action returns unused ETH |
| **Permit2 Integration** | Gas-efficient token approvals |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Position Manager**: `0x1B1C77B606d13b09C84d1c7394B96b147bC03147` (Mainnet)
- **Pattern**: Actions + Parameters batch encoding
- **Currency0**: Native ETH (address(0))
- **Currency1**: USDC (0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
- **Approval Pattern**: ERC20 → Permit2 → Position Manager
- **Settlement**: Automatic via SETTLE_PAIR/CLOSE_CURRENCY/TAKE_PAIR actions

## 🏗️ Architecture Overview

### The Three-Layer Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                          USER / FRONTEND                         │
│                     (Your Contract / EOA)                        │
└───────────────────────────────┬──────────────────────────────────┘
                                │
                                │ Calls modifyLiquidities()
                                │ with encoded actions + params
                                ↓
┌──────────────────────────────────────────────────────────────────┐
│                      POSITION MANAGER (POSM)                     │
│                   ERC721 + Batch Action Executor                 │
│                                                                  │
│  • Manages NFT positions                                         │
│  • Decodes actions array                                         │
│  • Executes each action sequentially                             │
│  • Handles token approvals via Permit2                           │
│  • Tracks position metadata (pool, ticks, liquidity)             │
└───────────────────────────────┬──────────────────────────────────┘
                                │
                                │ Calls unlock() / modifyLiquidity()
                                ↓
┌──────────────────────────────────────────────────────────────────┐
│                         POOL MANAGER                             │
│                    Core Liquidity Management                     │
│                                                                  │
│  • Manages liquidity positions in pools                          │
│  • Executes swaps                                                │
│  • Tracks token deltas (debits/credits)                          │
│  • Settles payments via sync() + settle()                        │
│  • Handles flash accounting (transient storage)                  │
└──────────────────────────────────────────────────────────────────┘
```

### Approval Flow (One-Time Setup)

```
ERC20 Token (USDC)
    │
    │ approve(Permit2, type(uint256).max)
    ↓
Permit2 Contract
    │
    │ approve(PositionManager, type(uint160).max, type(uint48).max)
    ↓
Position Manager
    │
    │ Can now spend tokens on your behalf
    ↓
Pool Manager
```

**Why Permit2?**
- Single approval for all pools and positions
- More gas efficient than individual approvals
- Supports signature-based approvals (gasless)
- Time-limited permissions for security

## 🔄 Execution Flow Diagrams

### Flow 1: Minting a Position (Creating NFT)

```
USER                POSM CONTRACT           POSITION MANAGER         POOL MANAGER
 │                        │                        │                       │
 │  mint(key, ticks,      │                        │                       │
 │       liquidity)       │                        │                       │
 │───────────────────────>│                        │                       │
 │                        │                        │                       │
 │                        │ [1. Encode actions]    │                       │
 │                        │ MINT_POSITION          │                       │
 │                        │ SETTLE_PAIR            │                       │
 │                        │ SWEEP                  │                       │
 │                        │                        │                       │
 │                        │ [2. Encode params]     │                       │
 │                        │ params[0] = MINT data  │                       │
 │                        │ params[1] = currencies │                       │
 │                        │ params[2] = sweep addr │                       │
 │                        │                        │                       │
 │                        │ [3. Get next tokenId]  │                       │
 │                        │ tokenId = nextTokenId()│                       │
 │                        │                        │                       │
 │                        │  modifyLiquidities{    │                       │
 │                        │    value: balance}(    │                       │
 │                        │    abi.encode(actions, │                       │
 │                        │    params), deadline)  │                       │
 │                        │───────────────────────>│                       │
 │                        │                        │                       │
 │                        │                        │ [4. Execute MINT]     │
 │                        │                        │  unlock(data)         │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │                        │                       │ Mint NFT
 │                        │                        │                       │ Call modifyLiquidity
 │                        │                        │                       │ Add liquidity
 │                        │                        │                       │ 
 │                        │                        │  delta0, delta1       │
 │                        │                        │<──────────────────────│
 │                        │                        │                       │
 │                        │                        │ [5. Execute SETTLE_PAIR]
 │                        │                        │ Receive ETH {value}   │
 │                        │                        │ Transfer USDC via     │
 │                        │                        │ Permit2               │
 │                        │                        │                       │
 │                        │                        │  sync(ETH)            │
 │                        │                        │──────────────────────>│
 │                        │                        │  sync(USDC)           │
 │                        │                        │──────────────────────>│
 │                        │                        │  settle()             │
 │                        │                        │──────────────────────>│
 │                        │                        │  settle()             │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │                        │ [6. Execute SWEEP]    │
 │                        │                        │ Return leftover ETH   │
 │                        │                        │                       │
 │                        │                        │  take(ETH, recipient) │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │                        │  send ETH back        │
 │                        │                        │<──────────────────────│
 │                        │                        │                       │
 │                        │  ✅ Success             │                       │
 │                        │<───────────────────────│                       │
 │                        │                        │                       │
 │  return tokenId        │                        │                       │
 │<───────────────────────│                        │                       │
 │                        │                        │                       │
```

**Key Steps**:
1. **Encode Actions**: Define the sequence of operations
2. **Encode Parameters**: Provide specific data for each action
3. **Get Token ID**: Reserve the next NFT token ID
4. **Mint Position**: Create NFT and add liquidity to pool
5. **Settle Payment**: Transfer tokens to PoolManager
6. **Sweep Leftovers**: Recover any unused ETH

### Flow 2: Increasing Liquidity

```
USER                POSM CONTRACT           POSITION MANAGER         POOL MANAGER
 │                        │                        │                       │
 │  increaseLiquidity(    │                        │                       │
 │    tokenId, liquidity) │                        │                       │
 │───────────────────────>│                        │                       │
 │                        │                        │                       │
 │                        │ [1. Encode actions]    │                       │
 │                        │ INCREASE_LIQUIDITY     │                       │
 │                        │ CLOSE_CURRENCY (ETH)   │                       │
 │                        │ CLOSE_CURRENCY (USDC)  │                       │
 │                        │ SWEEP                  │                       │
 │                        │                        │                       │
 │                        │ [2. Encode params]     │                       │
 │                        │ params[0] = tokenId,   │                       │
 │                        │   liquidity, amounts   │                       │
 │                        │ params[1] = ETH, USDC  │                       │
 │                        │ params[2] = USDC       │                       │
 │                        │ params[3] = sweep addr │                       │
 │                        │                        │                       │
 │                        │  modifyLiquidities{    │                       │
 │                        │    value: balance}(...)│                       │
 │                        │───────────────────────>│                       │
 │                        │                        │                       │
 │                        │                        │ [3. Execute INCREASE] │
 │                        │                        │ Load position data    │
 │                        │                        │ Add more liquidity    │
 │                        │                        │                       │
 │                        │                        │  modifyLiquidity(+Δ)  │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │                        │  delta0, delta1       │
 │                        │                        │<──────────────────────│
 │                        │                        │                       │
 │                        │                        │ [4. CLOSE_CURRENCY]   │
 │                        │                        │ Pay owed ETH          │
 │                        │                        │  sync() + settle()    │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │                        │ [5. CLOSE_CURRENCY]   │
 │                        │                        │ Pay owed USDC         │
 │                        │                        │  sync() + settle()    │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │                        │ [6. SWEEP]            │
 │                        │                        │ Return leftover ETH   │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │  ✅ Success             │                       │
 │                        │<───────────────────────│                       │
 │                        │                        │                       │
 │  ✅ Transaction done    │                        │                       │
 │<───────────────────────│                        │                       │
```

**Differences from Mint**:
- Uses **INCREASE_LIQUIDITY** instead of MINT_POSITION
- Uses **CLOSE_CURRENCY** per token instead of SETTLE_PAIR
- References existing **tokenId** instead of creating new one
- Position metadata already exists, just updates liquidity amount

### Flow 3: Decreasing Liquidity

```
USER                POSM CONTRACT           POSITION MANAGER         POOL MANAGER
 │                        │                        │                       │
 │  decreaseLiquidity(    │                        │                       │
 │    tokenId, liquidity) │                        │                       │
 │───────────────────────>│                        │                       │
 │                        │                        │                       │
 │                        │ [1. Get position info] │                       │
 │                        │ poolKey = getPool...() │                       │
 │                        │                        │                       │
 │                        │ [2. Encode actions]    │                       │
 │                        │ DECREASE_LIQUIDITY     │                       │
 │                        │ TAKE_PAIR              │                       │
 │                        │                        │                       │
 │                        │ [3. Encode params]     │                       │
 │                        │ params[0] = tokenId,   │                       │
 │                        │   liquidity, amounts   │                       │
 │                        │ params[1] = currencies,│                       │
 │                        │   recipient            │                       │
 │                        │                        │                       │
 │                        │  modifyLiquidities(...)│                       │
 │                        │───────────────────────>│                       │
 │                        │                        │                       │
 │                        │                        │ [4. Execute DECREASE] │
 │                        │                        │ Load position         │
 │                        │                        │ Remove liquidity      │
 │                        │                        │                       │
 │                        │                        │  modifyLiquidity(-Δ)  │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │                        │  delta0, delta1       │
 │                        │                        │<──────────────────────│
 │                        │                        │  (negative = owed)    │
 │                        │                        │                       │
 │                        │                        │ [5. Execute TAKE_PAIR]│
 │                        │                        │ Claim both tokens     │
 │                        │                        │                       │
 │                        │                        │  take(ETH, this)      │
 │                        │                        │──────────────────────>│
 │                        │                        │  take(USDC, this)     │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │                        │  ETH transfer         │
 │                        │                        │<──────────────────────│
 │                        │                        │  USDC transfer        │
 │                        │                        │<──────────────────────│
 │                        │                        │                       │
 │                        │  Receive tokens        │                       │
 │                        │<───────────────────────│                       │
 │                        │                        │                       │
 │  ✅ Tokens received     │                        │                       │
 │<───────────────────────│                        │                       │
```

**Key Differences**:
- **Negative liquidity delta**: Removing instead of adding
- **TAKE_PAIR instead of SETTLE_PAIR**: Receiving tokens instead of paying
- **No ETH sent**: No {value: ...} needed since we're withdrawing
- **Slippage protection**: amount0Min, amount1Min ensure minimum received

### Flow 4: Burning Position (Complete Closure)

```
USER                POSM CONTRACT           POSITION MANAGER         POOL MANAGER
 │                        │                        │                       │
 │  burn(tokenId,         │                        │                       │
 │       amount0Min,      │                        │                       │
 │       amount1Min)      │                        │                       │
 │───────────────────────>│                        │                       │
 │                        │                        │                       │
 │                        │ [1. Get position info] │                       │
 │                        │ poolKey = getPool...() │                       │
 │                        │                        │                       │
 │                        │ [2. Encode actions]    │                       │
 │                        │ BURN_POSITION          │                       │
 │                        │ TAKE_PAIR              │                       │
 │                        │                        │                       │
 │                        │ [3. Encode params]     │                       │
 │                        │ params[0] = tokenId,   │                       │
 │                        │   minimums, hookData   │                       │
 │                        │ params[1] = currencies,│                       │
 │                        │   recipient            │                       │
 │                        │                        │                       │
 │                        │  modifyLiquidities(...)│                       │
 │                        │───────────────────────>│                       │
 │                        │                        │                       │
 │                        │                        │ [4. Execute BURN]     │
 │                        │                        │ Load position         │
 │                        │                        │ Remove ALL liquidity  │
 │                        │                        │ Delete position data  │
 │                        │                        │ Burn NFT              │
 │                        │                        │                       │
 │                        │                        │  modifyLiquidity(-L)  │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │                        │  final deltas         │
 │                        │                        │<──────────────────────│
 │                        │                        │                       │
 │                        │                        │ [5. Execute TAKE_PAIR]│
 │                        │                        │ Claim final tokens    │
 │                        │                        │ Including any fees    │
 │                        │                        │                       │
 │                        │                        │  take(ETH, this)      │
 │                        │                        │──────────────────────>│
 │                        │                        │  take(USDC, this)     │
 │                        │                        │──────────────────────>│
 │                        │                        │                       │
 │                        │  Receive final tokens  │                       │
 │                        │<───────────────────────│                       │
 │                        │                        │                       │
 │                        │                        │ [6. NFT destroyed]    │
 │                        │                        │ tokenId no longer     │
 │                        │                        │ exists                │
 │                        │                        │                       │
 │  ✅ Position closed     │                        │                       │
 │<───────────────────────│                        │                       │
```

**Burn vs Decrease**:
- **BURN_POSITION**: Removes ALL liquidity and destroys NFT
- **DECREASE_LIQUIDITY**: Removes partial liquidity, keeps NFT
- After burn, tokenId cannot be used anymore
- Burn claims any accrued fees automatically

## 📚 Complete Actions Library Reference

The `Actions` library defines all possible operations in the Position Manager. This is your complete reference guide.

### Action Categories Overview

```
Actions Library (25 total actions)
├── Liquidity Management (6 actions)
│   ├── Standard operations
│   └── Delta-based operations
├── Swapping (4 actions)
│   ├── Exact input
│   └── Exact output
├── Settlement (3 actions)
│   ├── SETTLE
│   ├── SETTLE_ALL
│   └── SETTLE_PAIR
├── Taking (4 actions)
│   ├── TAKE
│   ├── TAKE_ALL
│   ├── TAKE_PORTION
│   └── TAKE_PAIR
├── Utility (5 actions)
│   ├── CLOSE_CURRENCY
│   ├── CLEAR_OR_TAKE
│   ├── SWEEP
│   ├── WRAP
│   └── UNWRAP
└── Advanced (3 actions)
    ├── DONATE
    ├── MINT_6909
    └── BURN_6909
```

---

## 🏗️ Liquidity Management Actions

### `INCREASE_LIQUIDITY` (0x00)

**Purpose**: Add more liquidity to an existing position

**When to Use**: 
- Increasing size of existing LP position
- Adding to position after price moves
- Compounding earned fees

**Parameters**:
```solidity
abi.encode(
    uint256 tokenId,        // NFT position ID
    uint256 liquidityDelta, // Amount of liquidity to add
    uint128 amount0Max,     // Max token0 willing to pay
    uint128 amount1Max,     // Max token1 willing to pay
    bytes hookData          // Data for hooks (usually empty)
)
```

**Example**:
```solidity
bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
bytes[] memory params = new bytes[](1);
params[0] = abi.encode(
    tokenId,
    1e18,           // Add 1e18 liquidity
    type(uint128).max,
    type(uint128).max,
    ""
);
```

**Common Pairs**: CLOSE_CURRENCY, SETTLE_PAIR, SWEEP

---

### `DECREASE_LIQUIDITY` (0x01)

**Purpose**: Remove liquidity from an existing position

**When to Use**:
- Partial withdrawal from LP position
- Rebalancing portfolio
- Taking profits while keeping position open

**Parameters**:
```solidity
abi.encode(
    uint256 tokenId,        // NFT position ID
    uint256 liquidityDelta, // Amount of liquidity to remove
    uint128 amount0Min,     // Min token0 to receive
    uint128 amount1Min,     // Min token1 to receive
    bytes hookData          // Data for hooks
)
```

**Example**:
```solidity
bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
bytes[] memory params = new bytes[](1);
params[0] = abi.encode(
    tokenId,
    5e17,       // Remove 0.5e18 liquidity
    1,          // Minimum amounts (slippage protection)
    1,
    ""
);
```

**Common Pairs**: TAKE_PAIR, TAKE_ALL

---

### `MINT_POSITION` (0x02)

**Purpose**: Create a new liquidity position and mint NFT

**When to Use**:
- Initial LP deployment
- Creating new position at different range
- First time providing liquidity

**Parameters**:
```solidity
abi.encode(
    PoolKey key,            // Pool identifier
    int24 tickLower,        // Lower tick of range
    int24 tickUpper,        // Upper tick of range
    uint256 liquidity,      // Initial liquidity amount
    uint128 amount0Max,     // Max token0 to pay
    uint128 amount1Max,     // Max token1 to pay
    address owner,          // NFT recipient
    bytes hookData          // Data for hooks
)
```

**Example**:
```solidity
bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
bytes[] memory params = new bytes[](1);
params[0] = abi.encode(
    poolKey,
    -100,               // tickLower
    100,                // tickUpper
    1e18,               // liquidity
    type(uint128).max,
    type(uint128).max,
    address(this),      // owner
    ""
);
```

**Common Pairs**: SETTLE_PAIR, SWEEP

**Important**: tickLower and tickUpper must be multiples of tickSpacing!

---

### `BURN_POSITION` (0x03)

**Purpose**: Remove all liquidity and destroy NFT

**When to Use**:
- Complete exit from LP position
- Closing position permanently
- Final withdrawal

**Parameters**:
```solidity
abi.encode(
    uint256 tokenId,        // NFT to burn
    uint128 amount0Min,     // Min token0 to receive
    uint128 amount1Min,     // Min token1 to receive
    bytes hookData          // Data for hooks
)
```

**Example**:
```solidity
bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
bytes[] memory params = new bytes[](1);
params[0] = abi.encode(
    tokenId,
    1,          // Slippage protection
    1,
    ""
);
```

**Common Pairs**: TAKE_PAIR

**Note**: After burn, tokenId no longer exists!

---

### `INCREASE_LIQUIDITY_FROM_DELTAS` (0x04)

**Purpose**: Increase liquidity using existing deltas (advanced)

**When to Use**:
- Composing multiple operations
- Using tokens already owed by PoolManager
- Complex DeFi strategies

**Parameters**:
```solidity
abi.encode(
    uint256 tokenId,        // Position ID
    uint256 liquidityDelta, // Liquidity to add
    bytes hookData          // Data for hooks
)
```

**Example**:
```solidity
// After a swap creates deltas:
bytes memory actions = abi.encodePacked(
    uint8(Actions.SWAP_EXACT_IN_SINGLE),
    uint8(Actions.INCREASE_LIQUIDITY_FROM_DELTAS)
);
```

**Note**: Rarely used in simple applications

---

### `MINT_POSITION_FROM_DELTAS` (0x05)

**Purpose**: Mint position using existing deltas (advanced)

**When to Use**:
- Creating position from swap output
- Complex multi-step operations
- Advanced DeFi composability

**Parameters**:
```solidity
abi.encode(
    PoolKey key,
    int24 tickLower,
    int24 tickUpper,
    uint256 liquidity,
    address owner,
    bytes hookData
)
```

**Note**: No amount0Max/amount1Max - uses current deltas

---

## 💱 Swapping Actions

### `SWAP_EXACT_IN_SINGLE` (0x06)

**Purpose**: Swap exact input amount in single pool

**When to Use**:
- Trading tokens
- Rebalancing before LP operations
- Arbitrage

**Parameters**:
```solidity
abi.encode(
    PoolKey key,            // Pool to swap in
    bool zeroForOne,        // Direction (true = token0→token1)
    uint128 amountIn,       // Exact input amount
    uint128 amountOutMinimum, // Min output (slippage)
    uint160 sqrtPriceLimitX96, // Price limit
    bytes hookData          // Data for hooks
)
```

**Example**:
```solidity
params[0] = abi.encode(
    poolKey,
    true,               // Swap token0 for token1
    1 ether,            // Input 1 ETH
    0.95 ether,         // Min output 0.95 token1
    0,                  // No price limit
    ""
);
```

---

### `SWAP_EXACT_IN` (0x07)

**Purpose**: Swap exact input across multiple pools (path)

**When to Use**:
- Multi-hop swaps
- Better pricing through routing
- Complex trading strategies

**Parameters**:
```solidity
abi.encode(
    PoolKey[] path,         // Array of pools to route through
    uint128 amountIn,       // Exact input amount
    uint128 amountOutMinimum, // Min final output
    bytes hookData          // Data for hooks
)
```

**Example**: ETH → USDC → DAI
```solidity
PoolKey[] memory path = new PoolKey[](2);
path[0] = ethUsdcKey;
path[1] = usdcDaiKey;

params[0] = abi.encode(path, 1 ether, 990e18, "");
```

---

### `SWAP_EXACT_OUT_SINGLE` (0x08)

**Purpose**: Swap to get exact output amount in single pool

**When to Use**:
- Need specific output amount
- Paying exact bill
- Precise token acquisition

**Parameters**:
```solidity
abi.encode(
    PoolKey key,
    bool zeroForOne,
    uint128 amountOut,      // Exact output desired
    uint128 amountInMaximum, // Max input willing to pay
    uint160 sqrtPriceLimitX96,
    bytes hookData
)
```

**Example**:
```solidity
params[0] = abi.encode(
    poolKey,
    true,
    1000e6,             // Want exactly 1000 USDC
    1.05 ether,         // Pay max 1.05 ETH
    0,
    ""
);
```

---

### `SWAP_EXACT_OUT` (0x09)

**Purpose**: Swap to get exact output across multiple pools

**When to Use**:
- Multi-hop with specific output needed
- Complex routing for exact amounts

**Parameters**:
```solidity
abi.encode(
    PoolKey[] path,
    uint128 amountOut,      // Exact final output
    uint128 amountInMaximum, // Max initial input
    bytes hookData
)
```

---

## 💰 Settlement Actions (Paying to PoolManager)

### `SETTLE` (0x0b)

**Purpose**: Pay specific amount of single currency

**When to Use**:
- Paying exact known amount
- Custom payment logic
- Advanced settlement control

**Parameters**:
```solidity
abi.encode(
    address currency,       // Token to settle
    uint256 amount,         // Exact amount to pay
    bool payerIsUser        // true = user pays, false = contract pays
)
```

**Example**:
```solidity
params[0] = abi.encode(
    address(0),         // ETH
    1 ether,            // Pay exactly 1 ETH
    false               // Contract pays
);
```

**Important**: Requires prior transfer or approval!

---

### `SETTLE_ALL` (0x0c)

**Purpose**: Pay all available balance of currency

**When to Use**:
- Depositing entire balance
- Simplifying payment logic
- "Use everything I have" scenarios

**Parameters**:
```solidity
abi.encode(
    address currency,       // Token to settle
    uint256 maxAmount       // Safety cap
)
```

**Example**:
```solidity
params[0] = abi.encode(
    USDC,
    type(uint256).max   // No cap
);
```

**Behavior**: Settles `min(balance, maxAmount)`

---

### `SETTLE_PAIR` (0x0d)

**Purpose**: Pay both currencies in a pair

**When to Use**:
- Minting new positions
- Adding liquidity with both tokens
- Most common for initial deposits

**Parameters**:
```solidity
abi.encode(
    address currency0,      // First token
    address currency1       // Second token
)
```

**Example**:
```solidity
params[0] = abi.encode(
    address(0),         // ETH
    USDC                // USDC
);
```

**How it works**: Automatically settles positive deltas for both currencies

**Most Common Usage**: After MINT_POSITION or INCREASE_LIQUIDITY

---

## 💸 Taking Actions (Receiving from PoolManager)

### `TAKE` (0x0e)

**Purpose**: Receive specific amount of single currency

**When to Use**:
- Withdrawing exact amount
- Partial claims
- Custom withdrawal logic

**Parameters**:
```solidity
abi.encode(
    address currency,       // Token to receive
    address recipient,      // Where to send
    uint256 amount          // Exact amount
)
```

**Example**:
```solidity
params[0] = abi.encode(
    USDC,
    msg.sender,
    1000e6              // Take exactly 1000 USDC
);
```

---

### `TAKE_ALL` (0x0f)

**Purpose**: Receive all owed balance of currency

**When to Use**:
- Complete withdrawal
- Claiming all available tokens
- Simplifying take logic

**Parameters**:
```solidity
abi.encode(
    address currency,       // Token to take
    uint256 minAmount       // Safety check (revert if less)
)
```

**Example**:
```solidity
params[0] = abi.encode(
    address(0),         // ETH
    0.1 ether           // Minimum 0.1 ETH or revert
);
```

---

### `TAKE_PORTION` (0x10)

**Purpose**: Take percentage of owed balance

**When to Use**:
- Partial withdrawals by percentage
- Fee splitting
- Proportional distributions

**Parameters**:
```solidity
abi.encode(
    address currency,       // Token to take
    address recipient,      // Where to send
    uint256 bips            // Basis points (10000 = 100%)
)
```

**Example**:
```solidity
params[0] = abi.encode(
    USDC,
    treasury,
    500                 // Take 5% (500 bips)
);
```

**Calculation**: `amount = (balance * bips) / 10000`

---

### `TAKE_PAIR` (0x11)

**Purpose**: Receive both currencies in a pair

**When to Use**:
- Decreasing liquidity
- Burning positions
- Withdrawing both tokens together

**Parameters**:
```solidity
abi.encode(
    address currency0,      // First token
    address currency1,      // Second token
    address recipient       // Where to send both
)
```

**Example**:
```solidity
params[0] = abi.encode(
    address(0),         // ETH
    USDC,               // USDC
    address(this)       // Receive here
);
```

**Most Common Usage**: After DECREASE_LIQUIDITY or BURN_POSITION

---

## 🔧 Utility Actions

### `CLOSE_CURRENCY` (0x12)

**Purpose**: Automatically settle or take based on delta direction

**When to Use**:
- Flexible payment/receipt
- Don't know if you'll pay or receive
- Simplifying complex flows

**Parameters**:
```solidity
abi.encode(
    address currency        // Token to close (settle or take)
)
```

**Example**:
```solidity
params[0] = abi.encode(address(0));  // Close ETH
params[1] = abi.encode(USDC);        // Close USDC
```

**Behavior**:
- If delta > 0: Settles (you pay)
- If delta < 0: Takes (you receive)
- If delta == 0: No-op

**Why Use**: Most flexible! Works for increase or decrease operations.

---

### `CLEAR_OR_TAKE` (0x13)

**Purpose**: Clear small dust amounts or take if significant

**When to Use**:
- Handling rounding errors
- Ignoring tiny amounts
- Gas optimization

**Parameters**:
```solidity
abi.encode(
    address currency,       // Token to handle
    uint256 minAmount       // Threshold (take if >= this)
)
```

**Example**:
```solidity
params[0] = abi.encode(
    USDC,
    1e6                 // Take if >= 1 USDC, otherwise clear
);
```

**Behavior**:
- If |delta| >= minAmount: Takes the amount
- If |delta| < minAmount: Clears (burns/donates)

---

### `SWEEP` (0x14)

**Purpose**: Return leftover native currency (ETH)

**When to Use**:
- After operations that may not use all ETH sent
- Preventing ETH from getting stuck
- Always include when sending ETH!

**Parameters**:
```solidity
abi.encode(
    address currency,       // Native currency (address(0))
    address recipient       // Where to send leftovers
)
```

**Example**:
```solidity
params[2] = abi.encode(
    address(0),         // ETH
    address(this)       // Return to contract
);
```

**Critical**: Always use SWEEP when sending ETH to Position Manager!

**Why**: You send full balance, but actual needed depends on price. SWEEP returns difference.

---

### `WRAP` (0x15)

**Purpose**: Wrap native ETH to WETH

**When to Use**:
- Converting ETH to WETH for operations
- Interop with contracts requiring WETH
- Rarely needed in Position Manager (supports native ETH)

**Parameters**:
```solidity
abi.encode(
    uint256 amount          // Amount to wrap
)
```

---

### `UNWRAP` (0x16)

**Purpose**: Unwrap WETH to native ETH

**When to Use**:
- Converting WETH back to ETH
- Receiving native currency
- Rarely needed in Position Manager

**Parameters**:
```solidity
abi.encode(
    uint256 amount          // Amount to unwrap
)
```

---

## 🔬 Advanced Actions (Not Supported in Position Manager)

### `DONATE` (0x0a)

**Purpose**: Donate tokens to pool (increases fees for LPs)

**Supported**: PoolManager only, NOT in Position Manager

**When to Use**:
- Incentivizing liquidity
- Rewarding LPs
- Custom hook logic

---

### `MINT_6909` (0x17)

**Purpose**: Mint ERC-6909 token claims

**Supported**: PoolManager only, NOT in Position Manager

**Use Case**: Advanced flash accounting patterns

---

### `BURN_6909` (0x18)

**Purpose**: Burn ERC-6909 token claims

**Supported**: PoolManager only, NOT in Position Manager

**Use Case**: Advanced flash accounting patterns

---

## 📋 Quick Reference Tables

### Actions by Use Case

| Use Case | Actions to Use |
|----------|---------------|
| **Create new position** | MINT_POSITION → SETTLE_PAIR → SWEEP |
| **Add to position** | INCREASE_LIQUIDITY → CLOSE_CURRENCY × 2 → SWEEP |
| **Remove from position** | DECREASE_LIQUIDITY → TAKE_PAIR |
| **Close position** | BURN_POSITION → TAKE_PAIR |
| **Swap then LP** | SWAP_EXACT_IN_SINGLE → INCREASE_LIQUIDITY → ... |
| **LP then swap leftovers** | MINT_POSITION → SETTLE_PAIR → SWAP_EXACT_IN_SINGLE |

### Actions by Value (Hex)

| Hex | Decimal | Action | Category |
|-----|---------|--------|----------|
| 0x00 | 0 | INCREASE_LIQUIDITY | Liquidity |
| 0x01 | 1 | DECREASE_LIQUIDITY | Liquidity |
| 0x02 | 2 | MINT_POSITION | Liquidity |
| 0x03 | 3 | BURN_POSITION | Liquidity |
| 0x04 | 4 | INCREASE_LIQUIDITY_FROM_DELTAS | Liquidity |
| 0x05 | 5 | MINT_POSITION_FROM_DELTAS | Liquidity |
| 0x06 | 6 | SWAP_EXACT_IN_SINGLE | Swap |
| 0x07 | 7 | SWAP_EXACT_IN | Swap |
| 0x08 | 8 | SWAP_EXACT_OUT_SINGLE | Swap |
| 0x09 | 9 | SWAP_EXACT_OUT | Swap |
| 0x0a | 10 | DONATE | Advanced |
| 0x0b | 11 | SETTLE | Settlement |
| 0x0c | 12 | SETTLE_ALL | Settlement |
| 0x0d | 13 | SETTLE_PAIR | Settlement |
| 0x0e | 14 | TAKE | Taking |
| 0x0f | 15 | TAKE_ALL | Taking |
| 0x10 | 16 | TAKE_PORTION | Taking |
| 0x11 | 17 | TAKE_PAIR | Taking |
| 0x12 | 18 | CLOSE_CURRENCY | Utility |
| 0x13 | 19 | CLEAR_OR_TAKE | Utility |
| 0x14 | 20 | SWEEP | Utility |
| 0x15 | 21 | WRAP | Utility |
| 0x16 | 22 | UNWRAP | Utility |
| 0x17 | 23 | MINT_6909 | Advanced |
| 0x18 | 24 | BURN_6909 | Advanced |

### Common Action Combinations

```solidity
// Pattern 1: Mint Position
bytes memory actions = abi.encodePacked(
    uint8(0x02),  // MINT_POSITION
    uint8(0x0d),  // SETTLE_PAIR
    uint8(0x14)   // SWEEP
);

// Pattern 2: Increase Liquidity
bytes memory actions = abi.encodePacked(
    uint8(0x00),  // INCREASE_LIQUIDITY
    uint8(0x12),  // CLOSE_CURRENCY (token0)
    uint8(0x12),  // CLOSE_CURRENCY (token1)
    uint8(0x14)   // SWEEP
);

// Pattern 3: Decrease Liquidity
bytes memory actions = abi.encodePacked(
    uint8(0x01),  // DECREASE_LIQUIDITY
    uint8(0x11)   // TAKE_PAIR
);

// Pattern 4: Burn Position
bytes memory actions = abi.encodePacked(
    uint8(0x03),  // BURN_POSITION
    uint8(0x11)   // TAKE_PAIR
);

// Pattern 5: Swap then Add Liquidity
bytes memory actions = abi.encodePacked(
    uint8(0x06),  // SWAP_EXACT_IN_SINGLE
    uint8(0x00),  // INCREASE_LIQUIDITY
    uint8(0x12),  // CLOSE_CURRENCY
    uint8(0x12),  // CLOSE_CURRENCY
    uint8(0x14)   // SWEEP
);
```

### Settlement vs Taking Decision Matrix

| Your Delta | You Need To | Action to Use | Direction |
|------------|-------------|---------------|-----------|
| delta > 0 | Pay tokens | SETTLE, SETTLE_ALL, SETTLE_PAIR | Contract → PoolManager |
| delta < 0 | Receive tokens | TAKE, TAKE_ALL, TAKE_PAIR | PoolManager → Contract |
| delta unknown | Auto-handle | CLOSE_CURRENCY | Bidirectional |
| delta ≈ 0 | Ignore or take | CLEAR_OR_TAKE | Smart handling |

### How to Choose Between Settlement Actions

| Scenario | Best Action | Why |
|----------|-------------|-----|
| Adding liquidity, need both tokens | SETTLE_PAIR | One action for both |
| Exact amount known | SETTLE | Precise control |
| Use entire balance | SETTLE_ALL | Simple, efficient |
| Each token separately | CLOSE_CURRENCY × 2 | Flexible, per-currency |
| Delta direction uncertain | CLOSE_CURRENCY | Auto-detects pay/receive |

### How to Choose Between Taking Actions

| Scenario | Best Action | Why |
|----------|-------------|-----|
| Removing liquidity | TAKE_PAIR | Gets both at once |
| Want everything | TAKE_ALL | Maximizes withdrawal |
| Exact amount needed | TAKE | Precise control |
| Percentage-based | TAKE_PORTION | Proportional split |
| Dust handling | CLEAR_OR_TAKE | Ignores tiny amounts |

---

## 🎯 Action Usage Examples

### Example 1: Complete Mint Flow

```solidity
function mintPosition() external payable {
    // Define 3 actions
    bytes memory actions = abi.encodePacked(
        uint8(Actions.MINT_POSITION),    // 0x02
        uint8(Actions.SETTLE_PAIR),      // 0x0d
        uint8(Actions.SWEEP)             // 0x14
    );
    
    // Prepare 3 parameter sets
    bytes[] memory params = new bytes[](3);
    
    // Action 1: MINT_POSITION
    params[0] = abi.encode(
        poolKey,                    // Which pool
        -100,                       // tickLower
        100,                        // tickUpper
        1e18,                       // liquidity
        type(uint128).max,          // amount0Max
        type(uint128).max,          // amount1Max
        address(this),              // owner
        ""                          // hookData
    );
    
    // Action 2: SETTLE_PAIR
    params[1] = abi.encode(
        address(0),                 // currency0 (ETH)
        USDC                        // currency1 (USDC)
    );
    
    // Action 3: SWEEP
    params[2] = abi.encode(
        address(0),                 // Sweep ETH
        address(this)               // Return to this contract
    );
    
    // Execute all 3 actions atomically
    posm.modifyLiquidities{value: address(this).balance}(
        abi.encode(actions, params),
        block.timestamp
    );
}
```

### Example 2: Flexible Increase

```solidity
function flexibleIncrease(uint256 tokenId) external payable {
    // 4 actions for maximum flexibility
    bytes memory actions = abi.encodePacked(
        uint8(Actions.INCREASE_LIQUIDITY),  // 0x00
        uint8(Actions.CLOSE_CURRENCY),      // 0x12 - ETH
        uint8(Actions.CLOSE_CURRENCY),      // 0x12 - USDC
        uint8(Actions.SWEEP)                // 0x14
    );
    
    bytes[] memory params = new bytes[](4);
    
    // Action 1: INCREASE_LIQUIDITY
    params[0] = abi.encode(tokenId, 1e18, type(uint128).max, type(uint128).max, "");
    
    // Action 2: CLOSE_CURRENCY for ETH
    // If delta > 0: pays ETH
    // If delta < 0: receives ETH
    // If delta == 0: does nothing
    params[1] = abi.encode(address(0), USDC);
    
    // Action 3: CLOSE_CURRENCY for USDC
    params[2] = abi.encode(USDC);
    
    // Action 4: SWEEP leftover ETH
    params[3] = abi.encode(address(0), address(this));
    
    posm.modifyLiquidities{value: address(this).balance}(
        abi.encode(actions, params),
        block.timestamp
    );
}
```

### Example 3: Decrease with Minimum Check

```solidity
function safeDecrease(uint256 tokenId, uint256 liquidityDelta) external {
    bytes memory actions = abi.encodePacked(
        uint8(Actions.DECREASE_LIQUIDITY),
        uint8(Actions.TAKE_ALL),        // Take all ETH
        uint8(Actions.TAKE_ALL)         // Take all USDC
    );
    
    bytes[] memory params = new bytes[](3);
    
    // Action 1: DECREASE_LIQUIDITY
    params[0] = abi.encode(
        tokenId,
        liquidityDelta,
        0.9 ether,          // Minimum ETH (slippage)
        1800e6,             // Minimum USDC (slippage)
        ""
    );
    
    // Action 2: TAKE_ALL for ETH
    params[1] = abi.encode(
        address(0),         // ETH
        0.9 ether           // Revert if less than 0.9 ETH
    );
    
    // Action 3: TAKE_ALL for USDC
    params[2] = abi.encode(
        USDC,
        1800e6              // Revert if less than 1800 USDC
    );
    
    posm.modifyLiquidities(
        abi.encode(actions, params),
        block.timestamp
    );
}
```

### Example 4: Complex Multi-Step

```solidity
function swapAndProvideLiquidity() external payable {
    // 6-action sequence
    bytes memory actions = abi.encodePacked(
        uint8(Actions.SWAP_EXACT_IN_SINGLE),    // 1. Swap half ETH for USDC
        uint8(Actions.MINT_POSITION),           // 2. Create position
        uint8(Actions.SETTLE_PAIR),             // 3. Pay both tokens
        uint8(Actions.CLEAR_OR_TAKE),           // 4. Handle dust USDC
        uint8(Actions.SWEEP)                    // 5. Return leftover ETH
    );
    
    bytes[] memory params = new bytes[](5);
    
    // Swap 50% of ETH for USDC
    params[0] = abi.encode(
        poolKey,
        true,                           // ETH → USDC
        address(this).balance / 2,      // Half the ETH
        0,                              // No minimum (example)
        0,                              // No price limit
        ""
    );
    
    // Mint position with resulting balances
    params[1] = abi.encode(poolKey, -100, 100, 1e18, type(uint128).max, type(uint128).max, address(this), "");
    
    // Settle both
    params[2] = abi.encode(address(0), USDC);
    
    // Clear tiny leftover USDC (< 1 cent)
    params[3] = abi.encode(USDC, 1e4);  // 0.01 USDC threshold
    
    // Return leftover ETH
    params[4] = abi.encode(address(0), address(this));
    
    posm.modifyLiquidities{value: address(this).balance}(
        abi.encode(actions, params),
        block.timestamp
    );
}
```

---

## ⚠️ Common Mistakes with Actions

### Mistake 1: Mismatched Actions and Params Count

```solidity
// ❌ WRONG: 3 actions, 2 params
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),
    uint8(Actions.SETTLE_PAIR),
    uint8(Actions.SWEEP)
);
bytes[] memory params = new bytes[](2);  // MISMATCH!
```

```solidity
// ✅ CORRECT: 3 actions, 3 params
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),
    uint8(Actions.SETTLE_PAIR),
    uint8(Actions.SWEEP)
);
bytes[] memory params = new bytes[](3);  // MATCHES!
```

### Mistake 2: Wrong Action Order

```solidity
// ❌ WRONG: Settling before creating position
bytes memory actions = abi.encodePacked(
    uint8(Actions.SETTLE_PAIR),      // Nothing to settle yet!
    uint8(Actions.MINT_POSITION)
);
```

```solidity
// ✅ CORRECT: Position first, then settle
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),    // Creates deltas
    uint8(Actions.SETTLE_PAIR)       // Settles those deltas
);
```

### Mistake 3: Forgetting SWEEP

```solidity
// ❌ WRONG: ETH might get stuck
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),
    uint8(Actions.SETTLE_PAIR)
    // Missing SWEEP!
);
```

```solidity
// ✅ CORRECT: Always include SWEEP for ETH
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),
    uint8(Actions.SETTLE_PAIR),
    uint8(Actions.SWEEP)             // Returns leftover
);
```

### Mistake 4: Using Wrong Settlement Action

```solidity
// ❌ SUBOPTIMAL: Two separate settles
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),
    uint8(Actions.SETTLE),           // ETH
    uint8(Actions.SETTLE),           // USDC
    uint8(Actions.SWEEP)
);
// Needs 4 params, more gas
```

```solidity
// ✅ BETTER: SETTLE_PAIR
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),
    uint8(Actions.SETTLE_PAIR),      // Both at once!
    uint8(Actions.SWEEP)
);
// Only 3 params, less gas
```

---

## 🎓 Actions Mastery Checklist

- [ ] Understand all 6 liquidity management actions
- [ ] Know when to use SETTLE_PAIR vs CLOSE_CURRENCY
- [ ] Can explain difference between TAKE_PAIR and TAKE_ALL
- [ ] Always remember SWEEP for ETH operations
- [ ] Can build 5+ action sequences correctly
- [ ] Understand action execution order matters
- [ ] Know which actions are Position Manager vs PoolManager only
- [ ] Can debug action parameter mismatches
- [ ] Understand delta-based actions (advanced)
- [ ] Can optimize action sequences for gas

**Congratulations!** You now have a complete reference for all Uniswap V4 Position Manager actions. Bookmark this section for quick lookup! 📖

## 💡 Understanding SETTLE vs CLOSE_CURRENCY vs TAKE_PAIR

These three action types handle payments differently:

### SETTLE_PAIR
```solidity
// Used for: Initial payment when adding liquidity
// Behavior: Transfers BOTH tokens to PoolManager
// When: You owe tokens (positive deltas)

params[1] = abi.encode(address(0), USDC);
// PoolManager will:
// 1. Receive ETH via {value: ...}
// 2. Pull USDC via Permit2.transferFrom()
```

### CLOSE_CURRENCY
```solidity
// Used for: Flexible payment/receipt per currency
// Behavior: Automatically settles if positive delta, takes if negative
// When: Delta could be either direction

params[1] = abi.encode(address(0), USDC);  // ETH
params[2] = abi.encode(USDC);               // USDC
// PoolManager will:
// - If delta > 0: you pay (settle)
// - If delta < 0: you receive (take)
// - If delta == 0: no-op
```

### TAKE_PAIR
```solidity
// Used for: Receiving tokens when removing liquidity
// Behavior: Transfers BOTH tokens TO recipient
// When: You're owed tokens (negative deltas)

params[1] = abi.encode(address(0), USDC, address(this));
// PoolManager will:
// 1. Send ETH to recipient
// 2. Send USDC to recipient
```

### Decision Matrix

| Scenario | Action to Use | Why |
|----------|---------------|-----|
| Minting position | SETTLE_PAIR | You pay both tokens |
| Increasing liquidity | CLOSE_CURRENCY (each) | Flexibility + leftover handling |
| Decreasing liquidity | TAKE_PAIR | You receive both tokens |
| Burning position | TAKE_PAIR | You receive final tokens |
| Unknown direction | CLOSE_CURRENCY | Auto-detects pay vs receive |

## 🔍 Deep Dive: Understanding Token Deltas

Token deltas are the core accounting primitive in Uniswap V4.

### What is a Delta?

A **delta** represents a change in token balance:
- **Positive delta (+)**: You owe tokens to PoolManager
- **Negative delta (-)**: PoolManager owes tokens to you
- **Zero delta (0)**: No tokens owed in either direction

### Delta Flow Example

```
Initial State:
PoolManager: 1000 ETH, 2000000 USDC
Your Contract: 100 ETH, 1000000 USDC

Action: Add liquidity requiring 10 ETH + 20000 USDC
-------------------------------------------------
After modifyLiquidity():
  delta0 (ETH) = +10 (you owe 10 ETH)
  delta1 (USDC) = +20000 (you owe 20000 USDC)

After SETTLE_PAIR:
  Your Contract: 90 ETH, 980000 USDC
  PoolManager: 1010 ETH, 2020000 USDC
  delta0 = 0 (settled)
  delta1 = 0 (settled)
```

### Reading Deltas in Code

```solidity
// After modifyLiquidity, PoolManager has deltas stored

// SETTLE_PAIR looks at deltas:
if (delta0 > 0) {
    // You owe ETH, transfer from you to PoolManager
    poolManager.sync(currency0);
    poolManager.settle();
}
if (delta1 > 0) {
    // You owe USDC, transfer from you to PoolManager
    poolManager.sync(currency1);
    poolManager.settle();
}

// TAKE_PAIR looks at deltas:
if (delta0 < 0) {
    // PM owes you ETH, transfer from PM to you
    poolManager.take(currency0, recipient, amount);
}
if (delta1 < 0) {
    // PM owes you USDC, transfer from PM to you
    poolManager.take(currency1, recipient, amount);
}
```

### Why Deltas Matter

1. **Gas Efficiency**: Only track net changes, not individual operations
2. **Flash Accounting**: Use transient storage (cleared after transaction)
3. **Composability**: Multiple operations can modify same delta
4. **Safety**: Transactions revert if deltas not settled at end

### Slippage Protection via Deltas

```solidity
// When increasing liquidity:
amount0Max: 1 ether  // Max willing to pay in ETH
amount1Max: 2000e6   // Max willing to pay in USDC

// If actual delta exceeds max:
if (delta0 > amount0Max) revert SlippageExceeded();
if (delta1 > amount1Max) revert SlippageExceeded();

// When decreasing liquidity:
amount0Min: 0.9 ether  // Min willing to receive in ETH
amount1Min: 1800e6     // Min willing to receive in USDC

// If actual delta below min:
if (-delta0 < amount0Min) revert InsufficientOutput();
if (-delta1 < amount1Min) revert InsufficientOutput();
```

## 🎯 Common Patterns and Best Practices

### Pattern 1: Always Send Full Balance for ETH

```solidity
// ❌ WRONG: Sending msg.value
posm.modifyLiquidities{value: msg.value}(...)

// ✅ CORRECT: Sending contract's full balance
posm.modifyLiquidities{value: address(this).balance}(...)
```

**Why?** 
- Contract may have ETH from previous operations
- Tests often pre-fund the contract with ETH
- `msg.value` is 0 if function isn't payable or not called with ETH
- PoolManager needs enough ETH to satisfy the delta

### Pattern 2: Always Include SWEEP for ETH Positions

```solidity
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),
    uint8(Actions.SETTLE_PAIR),
    uint8(Actions.SWEEP)  // ✅ Returns leftover ETH
);

params[2] = abi.encode(address(0), address(this));
```

**Why?**
- You typically send more ETH than needed
- Exact amount required depends on current price
- SWEEP returns the difference
- Without it, leftover ETH stuck in PoolManager

### Pattern 3: Get Position Info Before Modify

```solidity
// For increaseLiquidity, decreaseLiquidity, burn:
(PoolKey memory poolKey, ) = posm.getPoolAndPositionInfo(tokenId);

// Now you have:
// - poolKey.currency0
// - poolKey.currency1  
// - poolKey.fee
// - poolKey.tickSpacing
// - poolKey.hooks
```

**Why?**
- You need correct currencies for CLOSE_CURRENCY/TAKE_PAIR
- Pool params required for proper encoding
- Validates tokenId exists

### Pattern 4: Use Type-Safe Amount Maxes

```solidity
// ❌ WRONG: Hardcoded or arbitrary values
amount0Max: 1000 ether
amount1Max: 1000000e6

// ✅ CORRECT: Based on actual balance
amount0Max: uint128(address(this).balance)
amount1Max: uint128(token.balanceOf(address(this)))
```

**Why?**
- Prevents "insufficient balance" errors
- Uses available funds efficiently
- More flexible for different scenarios

### Pattern 5: Understand Action Order

```solidity
// Mint: Position first, payment second
MINT_POSITION → SETTLE_PAIR → SWEEP

// Increase: Position first, payment per currency
INCREASE_LIQUIDITY → CLOSE_CURRENCY → CLOSE_CURRENCY → SWEEP

// Decrease: Position first, receive together
DECREASE_LIQUIDITY → TAKE_PAIR

// Burn: Position first, receive final tokens
BURN_POSITION → TAKE_PAIR
```

**Why?**
- Position actions modify deltas
- Payment actions settle deltas
- Order matters for proper accounting

## 📝 Function-by-Function Implementation Guide

### Function 1: `mint()` - Create New Position

**Purpose**: Mint a new NFT representing a liquidity position in a specific price range.

**Signature**:
```solidity
function mint(
    PoolKey calldata key,
    int24 tickLower,
    int24 tickUpper,
    uint256 liquidity
) external payable returns (uint256)
```

**Parameters**:
- `key`: Pool identifier containing currency0, currency1, fee, tickSpacing, hooks
- `tickLower`: Lower tick of the range (must be multiple of tickSpacing)
- `tickUpper`: Upper tick of the range (must be multiple of tickSpacing)
- `liquidity`: Amount of liquidity to add (≈ sqrt(amount0 * amount1))

**Returns**: `tokenId` - The newly minted NFT token ID

#### Implementation Steps

**Step 1: Define Actions**
```solidity
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),  // Create new position
    uint8(Actions.SETTLE_PAIR),    // Pay both tokens
    uint8(Actions.SWEEP)           // Return leftover ETH
);
```

**Step 2: Create Parameters Array**
```solidity
bytes[] memory params = new bytes[](3);
```

**Step 3: Encode MINT_POSITION Parameters**
```solidity
params[0] = abi.encode(
    key,                      // PoolKey struct
    tickLower,                // int24
    tickUpper,                // int24
    liquidity,                // uint256
    type(uint128).max,        // amount0Max - max ETH willing to pay
    type(uint128).max,        // amount1Max - max USDC willing to pay
    address(this),            // owner - who receives the NFT
    ""                        // hookData - empty for this exercise
);
```

**Why `type(uint128).max`?** We're saying "use however much is needed". Real applications should calculate actual max amounts based on price and slippage tolerance.

**Step 4: Encode SETTLE_PAIR Parameters**
```solidity
params[1] = abi.encode(address(0), USDC);
```
- `address(0)` = Native ETH (currency0)
- `USDC` = ERC20 token (currency1)

**Step 5: Encode SWEEP Parameters**
```solidity
params[2] = abi.encode(address(0), address(this));
```
- `address(0)` = Sweep native ETH
- `address(this)` = Send leftover to this contract

**Step 6: Get Next Token ID**
```solidity
uint256 tokenId = posm.nextTokenId();
```

**Why before the call?** `nextTokenId()` is a counter that increments. We can predict what ID will be minted.

**Step 7: Execute Transaction**
```solidity
posm.modifyLiquidities{value: address(this).balance}(
    abi.encode(actions, params),
    block.timestamp  // deadline
);
```

**Critical**: Send `address(this).balance`, NOT `msg.value`!

**Step 8: Return Token ID**
```solidity
return tokenId;
```

#### Complete Function

```solidity
function mint(
    PoolKey calldata key,
    int24 tickLower,
    int24 tickUpper,
    uint256 liquidity
) external payable returns (uint256) {
    bytes memory actions = abi.encodePacked(
        uint8(Actions.MINT_POSITION),
        uint8(Actions.SETTLE_PAIR),
        uint8(Actions.SWEEP)
    );
    bytes[] memory params = new bytes[](3);

    // MINT_POSITION params
    params[0] = abi.encode(
        key,
        tickLower,
        tickUpper,
        liquidity,
        type(uint128).max,  // amount0Max
        type(uint128).max,  // amount1Max
        address(this),      // owner
        ""                  // hook data
    );

    // SETTLE_PAIR params
    params[1] = abi.encode(address(0), USDC);

    // SWEEP params
    params[2] = abi.encode(address(0), address(this));

    uint256 tokenId = posm.nextTokenId();

    posm.modifyLiquidities{value: address(this).balance}(
        abi.encode(actions, params),
        block.timestamp
    );

    return tokenId;
}
```

#### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `OutOfFunds` | Not enough ETH sent | Use `address(this).balance` not `msg.value` |
| `ERC20: insufficient allowance` | USDC not approved | Check constructor approval setup |
| `TickSpacing` | tickLower/Upper not aligned | Ensure `tick % tickSpacing == 0` |
| `PriceLimit` | Liquidity too high for range | Reduce liquidity or widen range |

---

### Function 2: `increaseLiquidity()` - Add to Existing Position

**Purpose**: Add more liquidity to an already-minted position without creating a new NFT.

**Signature**:
```solidity
function increaseLiquidity(
    uint256 tokenId,
    uint256 liquidity,
    uint128 amount0Max,
    uint128 amount1Max
) external payable
```

**Parameters**:
- `tokenId`: The NFT token ID of the position to modify
- `liquidity`: Additional liquidity to add
- `amount0Max`: Maximum ETH willing to pay
- `amount1Max`: Maximum USDC willing to pay

**Returns**: Nothing (void)

#### Implementation Steps

**Step 1: Define Actions**
```solidity
bytes memory actions = abi.encodePacked(
    uint8(Actions.INCREASE_LIQUIDITY),  // Add to existing position
    uint8(Actions.CLOSE_CURRENCY),      // Handle ETH payment/receipt
    uint8(Actions.CLOSE_CURRENCY),      // Handle USDC payment/receipt
    uint8(Actions.SWEEP)                // Return leftover ETH
);
```

**Why CLOSE_CURRENCY instead of SETTLE_PAIR?**
- More flexible - handles both positive and negative deltas
- Per-currency control
- Better for situations where one currency might be owed back

**Step 2: Create Parameters Array**
```solidity
bytes[] memory params = new bytes[](4);
```

**Step 3: Encode INCREASE_LIQUIDITY Parameters**
```solidity
params[0] = abi.encode(
    tokenId,         // uint256 - existing position
    liquidity,       // uint256 - amount to add
    amount0Max,      // uint128 - max ETH
    amount1Max,      // uint128 - max USDC
    ""               // bytes - hookData
);
```

**Step 4: Encode First CLOSE_CURRENCY (ETH)**
```solidity
params[1] = abi.encode(address(0), USDC);
```

**Wait, what?** This encodes BOTH currencies for the first CLOSE_CURRENCY. It's a special encoding for pairs.

**Alternative (more explicit)**:
```solidity
params[1] = abi.encode(address(0));  // Close ETH
params[2] = abi.encode(USDC);        // Close USDC
```

**Step 5: Encode Second CLOSE_CURRENCY (USDC)**
```solidity
params[2] = abi.encode(USDC);
```

**Step 6: Encode SWEEP**
```solidity
params[3] = abi.encode(address(0), address(this));
```

**Step 7: Execute Transaction**
```solidity
posm.modifyLiquidities{value: address(this).balance}(
    abi.encode(actions, params),
    block.timestamp
);
```

#### Complete Function (Solution Pattern)

```solidity
function increaseLiquidity(
    uint256 tokenId,
    uint256 liquidity,
    uint128 amount0Max,
    uint128 amount1Max
) external payable {
    bytes memory actions = abi.encodePacked(
        uint8(Actions.INCREASE_LIQUIDITY),
        uint8(Actions.CLOSE_CURRENCY),
        uint8(Actions.CLOSE_CURRENCY),
        uint8(Actions.SWEEP)
    );
    bytes[] memory params = new bytes[](4);

    // INCREASE_LIQUIDITY params
    params[0] = abi.encode(
        tokenId,
        liquidity,
        amount0Max,
        amount1Max,
        ""  // hook data
    );

    // CLOSE_CURRENCY params - currency 0
    params[1] = abi.encode(address(0), USDC);

    // CLOSE_CURRENCY params - currency 1
    params[2] = abi.encode(USDC);

    // SWEEP params
    params[3] = abi.encode(address(0), address(this));

    posm.modifyLiquidities{value: address(this).balance}(
        abi.encode(actions, params),
        block.timestamp
    );
}
```

#### Alternative Implementation (Using SETTLE_PAIR)

```solidity
function increaseLiquidity(
    uint256 tokenId,
    uint256 liquidity,
    uint128 amount0Max,
    uint128 amount1Max
) external payable {
    bytes memory actions = abi.encodePacked(
        uint8(Actions.INCREASE_LIQUIDITY),
        uint8(Actions.SETTLE_PAIR),  // Could use this instead
        uint8(Actions.SWEEP)
    );
    bytes[] memory params = new bytes[](3);

    params[0] = abi.encode(tokenId, liquidity, amount0Max, amount1Max, "");
    params[1] = abi.encode(address(0), USDC);
    params[2] = abi.encode(address(0), address(this));

    posm.modifyLiquidities{value: address(this).balance}(
        abi.encode(actions, params),
        block.timestamp
    );
}
```

**SETTLE_PAIR vs CLOSE_CURRENCY**: Both work for increase, but CLOSE_CURRENCY is more flexible for edge cases.

#### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `OutOfFunds` | `msg.value` used instead of balance | Change to `address(this).balance` |
| `InvalidTokenId` | Position doesn't exist | Check tokenId is valid |
| `InsufficientLiquidity` | amount0Max/1Max too low | Increase max amounts |
| `Unauthorized` | Contract doesn't own NFT | Ensure NFT owned by contract |

---

### Function 3: `decreaseLiquidity()` - Remove from Position

**Purpose**: Remove liquidity from a position and receive the underlying tokens back.

**Signature**:
```solidity
function decreaseLiquidity(
    uint256 tokenId,
    uint256 liquidity,
    uint128 amount0Min,
    uint128 amount1Min
) external
```

**Parameters**:
- `tokenId`: Position to modify
- `liquidity`: Amount of liquidity to remove
- `amount0Min`: Minimum ETH to receive (slippage protection)
- `amount1Min`: Minimum USDC to receive (slippage protection)

**Returns**: Nothing (void)

#### Implementation Steps

**Step 1: Get Position Information**
```solidity
(PoolKey memory poolKey, ) = posm.getPoolAndPositionInfo(tokenId);
```

**Why?** We need the currencies to properly encode TAKE_PAIR.

**Step 2: Define Actions**
```solidity
bytes memory actions = abi.encodePacked(
    uint8(Actions.DECREASE_LIQUIDITY),  // Remove liquidity
    uint8(Actions.TAKE_PAIR)            // Receive both tokens
);
```

**No SWEEP needed**: We're receiving tokens, not sending them.

**Step 3: Create Parameters Array**
```solidity
bytes[] memory params = new bytes[](2);
```

**Step 4: Encode DECREASE_LIQUIDITY Parameters**
```solidity
params[0] = abi.encode(
    tokenId,       // uint256
    liquidity,     // uint256
    amount0Min,    // uint128
    amount1Min,    // uint128
    ""             // hookData
);
```

**Step 5: Encode TAKE_PAIR Parameters**
```solidity
params[1] = abi.encode(
    poolKey.currency0,  // address - ETH
    poolKey.currency1,  // address - USDC
    address(this)       // address - recipient
);
```

**Step 6: Execute Transaction**
```solidity
posm.modifyLiquidities(
    abi.encode(actions, params),
    block.timestamp
);
```

**Note**: No `{value: ...}` because we're receiving, not paying!

#### Complete Function

```solidity
function decreaseLiquidity(
    uint256 tokenId,
    uint256 liquidity,
    uint128 amount0Min,
    uint128 amount1Min
) external {
    bytes memory actions = abi.encodePacked(
        uint8(Actions.DECREASE_LIQUIDITY),
        uint8(Actions.TAKE_PAIR)
    );
    bytes[] memory params = new bytes[](2);

    // DECREASE_LIQUIDITY params
    params[0] = abi.encode(
        tokenId,
        liquidity,
        amount0Min,
        amount1Min,
        ""  // hook data
    );

    // TAKE_PAIR params
    (PoolKey memory poolKey, ) = posm.getPoolAndPositionInfo(tokenId);
    params[1] = abi.encode(
        poolKey.currency0,
        poolKey.currency1,
        address(this)
    );

    posm.modifyLiquidities(
        abi.encode(actions, params),
        block.timestamp
    );
}
```

#### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `InsufficientLiquidity` | Trying to remove more than exists | Check position liquidity first |
| `SlippageTooHigh` | Received < minimums | Increase amount0Min/1Min tolerance |
| `InvalidTokenId` | Position doesn't exist | Validate tokenId |
| `Unauthorized` | Not position owner | Ensure contract owns NFT |

---

### Function 4: `burn()` - Close Position Completely

**Purpose**: Remove all liquidity from a position and burn the NFT.

**Signature**:
```solidity
function burn(
    uint256 tokenId,
    uint128 amount0Min,
    uint128 amount1Min
) external
```

**Parameters**:
- `tokenId`: Position to burn
- `amount0Min`: Minimum ETH to receive
- `amount1Min`: Minimum USDC to receive

**Returns**: Nothing (void)

#### Implementation Steps

**Step 1: Get Position Information**
```solidity
(PoolKey memory poolKey, ) = posm.getPoolAndPositionInfo(tokenId);
```

**Step 2: Define Actions**
```solidity
bytes memory actions = abi.encodePacked(
    uint8(Actions.BURN_POSITION),  // Remove all liquidity & destroy NFT
    uint8(Actions.TAKE_PAIR)       // Receive final tokens
);
```

**Step 3: Create Parameters Array**
```solidity
bytes[] memory params = new bytes[](2);
```

**Step 4: Encode BURN_POSITION Parameters**
```solidity
params[0] = abi.encode(
    tokenId,       // uint256
    amount0Min,    // uint128
    amount1Min,    // uint128
    ""             // hookData
);
```

**Note**: No liquidity parameter - burns ALL liquidity automatically.

**Step 5: Encode TAKE_PAIR Parameters**
```solidity
params[1] = abi.encode(
    poolKey.currency0,
    poolKey.currency1,
    address(this)
);
```

**Step 6: Execute Transaction**
```solidity
posm.modifyLiquidities(
    abi.encode(actions, params),
    block.timestamp
);
```

#### Complete Function

```solidity
function burn(
    uint256 tokenId,
    uint128 amount0Min,
    uint128 amount1Min
) external {
    bytes memory actions = abi.encodePacked(
        uint8(Actions.BURN_POSITION),
        uint8(Actions.TAKE_PAIR)
    );
    bytes[] memory params = new bytes[](2);

    // BURN_POSITION params
    params[0] = abi.encode(
        tokenId,
        amount0Min,
        amount1Min,
        ""  // hook data
    );

    // TAKE_PAIR params
    (PoolKey memory poolKey, ) = posm.getPoolAndPositionInfo(tokenId);
    params[1] = abi.encode(
        poolKey.currency0,
        poolKey.currency1,
        address(this)
    );

    posm.modifyLiquidities(
        abi.encode(actions, params),
        block.timestamp
    );
}
```

#### Burn vs Decrease

| Aspect | Decrease | Burn |
|--------|----------|------|
| **NFT** | Kept | Destroyed |
| **Liquidity** | Partial removal | Complete removal |
| **Reuse** | Can add back later | Cannot reuse tokenId |
| **Use Case** | Temporary withdrawal | Final exit |
| **Fees** | Accrued fees remain claimable | All fees claimed automatically |

#### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `InvalidTokenId` | Already burned or doesn't exist | Check before burning |
| `Unauthorized` | Not owner | Ensure contract owns NFT |
| `LiquidityRemaining` | Should be impossible | Position Manager bug? |

---

## 🧪 Testing Guide

### Test Setup

```solidity
contract PositionManagerTest is Test {
    PosmExercises ex;
    PoolKey key;
    
    function setUp() public {
        ex = new PosmExercises(USDC);
        
        // Fund contract
        deal(USDC, address(ex), 1_000_000e6);  // 1M USDC
        deal(address(ex), 100 ether);           // 100 ETH
        
        // Define pool
        key = PoolKey({
            currency0: address(0),
            currency1: USDC,
            fee: 500,               // 0.05%
            tickSpacing: 10,
            hooks: address(0)
        });
    }
}
```

### Test 1: Mint and Burn

```solidity
function test_mint_burn() public {
    int24 tick = getTick(key.toId());
    int24 tickLower = getTickLower(tick, 10);
    uint256 liquidity = 1e12;
    
    // Mint position
    uint256 tokenId = ex.mint({
        key: key,
        tickLower: tickLower - 100,
        tickUpper: tickLower + 100,
        liquidity: liquidity
    });
    
    // Verify position created
    assertEq(posm.getPositionLiquidity(tokenId), liquidity);
    
    // Burn position
    ex.burn({
        tokenId: tokenId,
        amount0Min: 1,
        amount1Min: 1
    });
    
    // Verify position destroyed
    assertEq(posm.getPositionLiquidity(tokenId), 0);
}
```

### Test 2: Increase and Decrease Liquidity

```solidity
function test_inc_dec_liq() public {
    // Create initial position
    uint256 tokenId = ex.mint(...);
    uint256 initialLiq = 1e12;
    
    // Increase liquidity
    ex.increaseLiquidity({
        tokenId: tokenId,
        liquidity: initialLiq,
        amount0Max: uint128(address(ex).balance),
        amount1Max: uint128(usdc.balanceOf(address(ex)))
    });
    
    // Verify doubled
    assertEq(
        posm.getPositionLiquidity(tokenId),
        2 * initialLiq
    );
    
    // Decrease liquidity
    ex.decreaseLiquidity({
        tokenId: tokenId,
        liquidity: initialLiq,
        amount0Min: 1,
        amount1Min: 1
    });
    
    // Verify back to original
    assertEq(
        posm.getPositionLiquidity(tokenId),
        initialLiq
    );
}
```

### Running Tests

```bash
# Run all tests
forge test --fork-url $FORK_URL --match-path test/Posm.test.sol -vvv

# Run specific test
forge test --fork-url $FORK_URL --match-test test_mint_burn -vvvv

# With gas report
forge test --fork-url $FORK_URL --match-path test/Posm.test.sol --gas-report
```

### Expected Output

```
Running 2 tests for test/Posm.test.sol:PositionManagerTest
[PASS] test_mint_burn() (gas: 497048)
Logs:
  --- mint ---
  ETH before: 100000000000000000000
  USDC before: 1000000000000
  ETH after: 99999915927166590370
  USDC after: 999999704569
  liquidity: 1.0e12
  ETH delta: -8.407283340963e13
  USDC delta: -2.95431e5
  --- burn ---
  ETH before: 99999915927166590370
  USDC before: 999999704569
  ETH after: 99999999999999999989
  USDC after: 999999999999
  liquidity: 0.0e0
  ETH delta: 8.4072833409619e13
  USDC delta: 2.9543e5

[PASS] test_inc_dec_liq() (gas: 634581)
Logs:
  --- increase liquidity ---
  liquidity: 2.0e12
  ETH delta: -8.407283340963e13
  USDC delta: -2.95431e5
  --- decrease liquidity ---
  ETH delta: 8.4072833409619e13
  USDC delta: 2.9543e5

Test result: ok. 2 passed; 0 failed; finished in 1.23s
```

---

## 🐛 Debugging Guide

### Problem 1: OutOfFunds Error

**Symptom**:
```
[FAIL] test_inc_dec_liq()
├─ [0] PosmExercises::increaseLiquidity(...)
│   └─ [OutOfFunds] EvmError: OutOfFunds
```

**Root Cause**: Using `msg.value` instead of `address(this).balance`

**Analysis Steps**:

1. **Read the Trace with -vvv**
```bash
forge test --fork-url $FORK_URL --match-test test_inc_dec_liq -vvv
```

2. **Look for {value: X} markers**
```
├─ posm.modifyLiquidities{value: 0}(...)  ← msg.value is 0!
│   └─ poolManager.settle{value: 84072833409630}()
│       └─ [OutOfFunds] ← Not enough ETH sent!
```

3. **Check Contract Balance**
```solidity
console.log("Contract ETH:", address(ex).balance);
// Output: 99999915927166590370 (plenty of ETH!)
```

4. **Compare with Working Function**
```solidity
// mint() - WORKS ✅
posm.modifyLiquidities{value: address(this).balance}(...)

// increaseLiquidity() - FAILS ❌
posm.modifyLiquidities{value: msg.value}(...)  // msg.value = 0
```

**Solution**:
```solidity
// Change this:
posm.modifyLiquidities{value: msg.value}(...)

// To this:
posm.modifyLiquidities{value: address(this).balance}(...)
```

### Problem 2: Insufficient Allowance

**Symptom**:
```
Error: ERC20: insufficient allowance
```

**Root Cause**: USDC not approved for Permit2 or Position Manager

**Solution**:
```solidity
constructor(address currency1) {
    // Approve Permit2
    IERC20(currency1).approve(PERMIT2, type(uint256).max);
    
    // Approve Position Manager via Permit2
    IPermit2(PERMIT2).approve(
        currency1,
        address(posm),
        type(uint160).max,
        type(uint48).max
    );
}
```

### Problem 3: Tick Spacing Error

**Symptom**:
```
Error: TickSpacing
```

**Root Cause**: tickLower or tickUpper not aligned to tickSpacing

**Solution**:
```solidity
// ❌ WRONG
tickLower = currentTick - 100;  // Might not be divisible by 10

// ✅ CORRECT
int24 tickLower = getTickLower(currentTick, TICK_SPACING);
// Ensures tick % tickSpacing == 0
```

### Problem 4: Invalid Token ID

**Symptom**:
```
Error: InvalidTokenId
```

**Causes**:
1. Position doesn't exist (wrong tokenId)
2. Position already burned
3. Using tokenId before minting

**Debug**:
```solidity
// Check if position exists
uint128 liquidity = posm.getPositionLiquidity(tokenId);
console.log("Position liquidity:", liquidity);

// Check NFT ownership
address owner = posm.ownerOf(tokenId);
console.log("Position owner:", owner);
```

### Debugging Checklist

When a test fails:

- [ ] Read trace with `-vvv` or `-vvvv`
- [ ] Check for `{value: X}` markers in trace
- [ ] Verify contract has sufficient balance
- [ ] Compare with working similar functions
- [ ] Check approvals are set up in constructor
- [ ] Validate tick alignment with tickSpacing
- [ ] Verify tokenId exists and is owned by contract
- [ ] Look for delta mismatches (paid vs required)
- [ ] Search solutions folder for patterns

---

## 💼 Real-World Applications

### Use Case 1: Auto-Compounding LP

```solidity
// Collect fees and reinvest into same position
function compound(uint256 tokenId) external {
    // 1. Collect fees (decrease 0, immediate increase)
    decreaseLiquidity(tokenId, 0, 0, 0);
    
    // 2. Calculate liquidity from collected fees
    uint256 eth = address(this).balance;
    uint256 usdc = IERC20(USDC).balanceOf(address(this));
    uint256 additionalLiq = calculateLiquidity(eth, usdc);
    
    // 3. Reinvest
    increaseLiquidity(
        tokenId,
        additionalLiq,
        uint128(eth),
        uint128(usdc)
    );
}
```

### Use Case 2: Range Rebalancing

```solidity
// Move position to new range
function rebalance(
    uint256 oldTokenId,
    int24 newTickLower,
    int24 newTickUpper
) external returns (uint256 newTokenId) {
    // 1. Close old position
    burn(oldTokenId, 1, 1);
    
    // 2. Open new position at different range
    uint256 liquidity = calculateLiquidity(
        address(this).balance,
        IERC20(USDC).balanceOf(address(this))
    );
    
    newTokenId = mint(
        key,
        newTickLower,
        newTickUpper,
        liquidity
    );
}
```

### Use Case 3: Gradual Entry/Exit

```solidity
// DCA into liquidity position
function dcaIncrease(uint256 tokenId) external {
    uint256 weeklyAmount = 0.1 ether;
    
    if (address(this).balance >= weeklyAmount) {
        increaseLiquidity(
            tokenId,
            calculateLiquidity(weeklyAmount, ...),
            uint128(weeklyAmount),
            type(uint128).max
        );
    }
}

// Gradual exit
function dcaDecrease(uint256 tokenId) external {
    uint256 totalLiq = posm.getPositionLiquidity(tokenId);
    uint256 weeklyDecrease = totalLiq / 10;  // 10% per week
    
    decreaseLiquidity(
        tokenId,
        weeklyDecrease,
        1,
        1
    );
}
```

---

## 🎓 Advanced Concepts

### Liquidity Mathematics

Understanding how liquidity relates to token amounts:

```
Liquidity (L) ≈ sqrt(amount0 * amount1)

For a given price range [pA, pB]:
amount0 = L * (sqrt(pB) - sqrt(pA))
amount1 = L * (1/sqrt(pA) - 1/sqrt(pB))

Where price p = 1.0001^tick
```

**Example Calculation**:
```solidity
// Current tick = 0 (price = 1)
// Range: tick -100 to +100
// Liquidity = 1e12

// Price at tick -100: 1.0001^(-100) ≈ 0.99
// Price at tick +100: 1.0001^100 ≈ 1.01

// amount0 (ETH) ≈ 1e12 * (sqrt(1.01) - sqrt(0.99))
//              ≈ 1e12 * 0.01
//              ≈ 1e10 wei ≈ 0.00000001 ETH

// amount1 (USDC) ≈ 1e12 * (1/sqrt(0.99) - 1/sqrt(1.01))
//                ≈ similar ratio
```

### Position Value Calculation

```solidity
function getPositionValue(uint256 tokenId)
    public
    view
    returns (uint256 value0, uint256 value1)
{
    (PoolKey memory poolKey, PositionInfo memory info) =
        posm.getPoolAndPositionInfo(tokenId);
    
    uint128 liquidity = info.liquidity;
    int24 tickLower = info.tickLower;
    int24 tickUpper = info.tickUpper;
    int24 currentTick = getCurrentTick(poolKey.toId());
    
    // Calculate amounts based on position relative to current tick
    if (currentTick < tickLower) {
        // All token0 (ETH)
        value0 = getAmount0ForLiquidity(
            sqrtPrice(tickLower),
            sqrtPrice(tickUpper),
            liquidity
        );
        value1 = 0;
    } else if (currentTick >= tickUpper) {
        // All token1 (USDC)
        value0 = 0;
        value1 = getAmount1ForLiquidity(
            sqrtPrice(tickLower),
            sqrtPrice(tickUpper),
            liquidity
        );
    } else {
        // Mixed
        value0 = getAmount0ForLiquidity(
            sqrtPrice(currentTick),
            sqrtPrice(tickUpper),
            liquidity
        );
        value1 = getAmount1ForLiquidity(
            sqrtPrice(tickLower),
            sqrtPrice(currentTick),
            liquidity
        );
    }
}
```

### Impermanent Loss in Positions

When price moves outside your range:

```
Initial: 1 ETH + 2000 USDC in range [1800, 2200]
Price moves to 2500 (above range)

Position converts to: ~0 ETH + ~2090 USDC
If held: 1 ETH + 2000 USDC = 2500 + 2000 = 4500 USDC
Position value: 2090 USDC
Impermanent Loss: (4500 - 2090) / 4500 = 53.5%
```

**Mitigation Strategies**:
1. **Narrow ranges near current price**: Less IL but more rebalancing
2. **Wide ranges**: More IL but less rebalancing
3. **Active management**: Rebalance when price moves
4. **Fee income**: Offset IL with trading fees

### Gas Optimization Patterns

#### Pattern 1: Batch Multiple Positions

```solidity
// Instead of separate calls:
mint(key, -100, 100, 1e12);
mint(key, -200, 200, 1e12);
mint(key, -300, 300, 1e12);

// Use multicall:
bytes[] memory calls = new bytes[](3);
calls[0] = abi.encodeCall(this.mint, (key, -100, 100, 1e12));
calls[1] = abi.encodeCall(this.mint, (key, -200, 200, 1e12));
calls[2] = abi.encodeCall(this.mint, (key, -300, 300, 1e12));

posm.multicall(calls);  // ~30% gas savings
```

#### Pattern 2: Use SETTLE_ALL for Dust

```solidity
// If you want to use all remaining balance:
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),
    uint8(Actions.SETTLE_ALL),    // Use all ETH
    uint8(Actions.SETTLE_ALL)     // Use all USDC
);
```

#### Pattern 3: Minimize State Reads

```solidity
// ❌ Multiple reads
for (uint i = 0; i < tokenIds.length; i++) {
    (PoolKey memory key,) = posm.getPoolAndPositionInfo(tokenIds[i]);
    // Uses key...
}

// ✅ Cache result
PoolKey memory key;
(key,) = posm.getPoolAndPositionInfo(tokenIds[0]);
// Reuse key if same pool
```

### Permit2 Deep Dive

**What is Permit2?**
- Universal token approval contract
- Single approval for all protocols
- Supports EIP-2612 permit signatures
- Time-limited approvals for security

**Approval Hierarchy**:
```
Token → Permit2: approve(Permit2, type(uint256).max)
Permit2 → Spender: approve(spender, amount, expiration)
Spender: Can now spend up to amount until expiration
```

**Benefits**:
1. **Gas Savings**: One approval for all positions
2. **Security**: Time-limited permissions
3. **UX**: Signature-based approvals (no gas)
4. **Composability**: Works across protocols

**Constructor Pattern**:
```solidity
constructor(address token) {
    // 1. Approve Permit2 to spend token
    IERC20(token).approve(PERMIT2, type(uint256).max);
    
    // 2. Permit2 approves Position Manager
    IPermit2(PERMIT2).approve(
        token,                    // Token to approve
        address(posm),            // Spender
        type(uint160).max,        // Amount (max)
        type(uint48).max          // Expiration (never)
    );
}
```

### Transient Storage Optimization

Uniswap V4 uses transient storage (EIP-1153) for gas efficiency:

```solidity
// Traditional storage: ~20k gas per slot
mapping(address => int256) balances;

// Transient storage: ~100 gas per slot
// Automatically cleared at end of transaction
tstore(slot, value);
tload(slot);
```

**Use in Position Manager**:
- Delta tracking during transaction
- Temporary state in unlock callback
- Flash accounting without permanent storage

**Why It Matters**:
- 200x cheaper than SSTORE
- Enables complex multi-step operations
- No cleanup needed (auto-clears)

---

## 🛡️ Security Considerations

### 1. Reentrancy Protection

**Risk**: Position Manager callbacks could be exploited

**Mitigation**:
```solidity
// Position Manager uses ReentrancyGuard
modifier nonReentrant() {
    require(!locked, "No reentrancy");
    locked = true;
    _;
    locked = false;
}
```

**Your Contract**:
```solidity
// If your contract has payable fallback/receive:
receive() external payable {
    // Only accept ETH from Position Manager
    require(msg.sender == POSITION_MANAGER, "Invalid sender");
}
```

### 2. Slippage Protection

**Always use appropriate minimums/maximums**:

```solidity
// ❌ DANGEROUS: No slippage protection
increaseLiquidity(tokenId, liquidity, type(uint128).max, type(uint128).max);

// ✅ SAFE: Calculated slippage bounds
uint256 maxEth = calculateMaxEth(liquidity, currentPrice, slippageBps);
uint256 maxUsdc = calculateMaxUsdc(liquidity, currentPrice, slippageBps);
increaseLiquidity(tokenId, liquidity, uint128(maxEth), uint128(maxUsdc));
```

### 3. Deadline Protection

```solidity
// ❌ DANGEROUS: Transaction can be held indefinitely
posm.modifyLiquidities(data, type(uint256).max);

// ✅ SAFE: Reasonable deadline
posm.modifyLiquidities(data, block.timestamp + 300);  // 5 minutes
```

### 4. Token Approval Management

```solidity
// Review approvals periodically
function revokeApproval(address token) external onlyOwner {
    IERC20(token).approve(PERMIT2, 0);
}

// Use specific amounts when possible
IPermit2(PERMIT2).approve(
    token,
    spender,
    specificAmount,    // Not type(uint160).max
    shortExpiration    // Not type(uint48).max
);
```

### 5. NFT Ownership Verification

```solidity
function onlyPositionOwner(uint256 tokenId) internal view {
    require(
        posm.ownerOf(tokenId) == address(this),
        "Not position owner"
    );
}

function safeBurn(uint256 tokenId) external {
    onlyPositionOwner(tokenId);
    burn(tokenId, 1, 1);
}
```

### 6. Price Manipulation Protection

**Risk**: Flash loan attacks manipulating pool price

**Mitigation**:
```solidity
// Use TWAP instead of spot price
uint32[] memory secondsAgos = new uint32[](2);
secondsAgos[0] = 1800;  // 30 minutes ago
secondsAgos[1] = 0;     // now

(int56[] memory tickCumulatives,) = pool.observe(secondsAgos);
int24 avgTick = int24((tickCumulatives[1] - tickCumulatives[0]) / 1800);
```

### 7. Frontrunning Protection

**Risk**: MEV bots can frontrun position changes

**Mitigations**:
1. **Private RPC**: Flashbots, Eden Network
2. **Tight Deadlines**: Short transaction validity
3. **Slippage Bounds**: Acceptable price movement
4. **Commit-Reveal**: Two-step process

---

## 📊 Comparison with Uniswap V3

| Aspect | V3 NonfungiblePositionManager | V4 Position Manager |
|--------|-------------------------------|---------------------|
| **Architecture** | Monolithic contract | Modular with Actions |
| **Storage** | Permanent mappings | Transient storage |
| **Gas Cost** | Higher (~500k mint) | Lower (~350k mint) |
| **Extensibility** | Limited | Highly extensible |
| **Hooks** | None | Full hook support |
| **Batching** | Basic multicall | Advanced action sequences |
| **Fee Collection** | Separate function | Integrated with modify |
| **Native ETH** | Wrapped to WETH | Direct ETH support |

### Migration Path V3 → V4

```solidity
// V3 Pattern:
INonfungiblePositionManager.MintParams memory params =
    INonfungiblePositionManager.MintParams({
        token0: token0,
        token1: token1,
        fee: fee,
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: amount0Min,
        amount1Min: amount1Min,
        recipient: recipient,
        deadline: deadline
    });
positionManagerV3.mint(params);

// V4 Pattern:
bytes memory actions = abi.encodePacked(
    uint8(Actions.MINT_POSITION),
    uint8(Actions.SETTLE_PAIR),
    uint8(Actions.SWEEP)
);
bytes[] memory params = new bytes[](3);
params[0] = abi.encode(key, tickLower, tickUpper, liquidity, ...);
params[1] = abi.encode(currency0, currency1);
params[2] = abi.encode(currency0, recipient);

positionManagerV4.modifyLiquidities{value: ...}(
    abi.encode(actions, params),
    deadline
);
```

**Key Differences**:
1. V4 uses liquidity amount, V3 uses token amounts
2. V4 has flexible action sequences
3. V4 requires explicit settlement actions
4. V4 supports direct ETH (no WETH wrapping)

---

## 📚 Additional Resources

### Official Documentation
- [Uniswap V4 Docs](https://docs.uniswap.org/contracts/v4/overview)
- [Position Manager Source](https://github.com/Uniswap/v4-periphery/blob/main/src/PositionManager.sol)
- [Actions Library](https://github.com/Uniswap/v4-periphery/blob/main/src/libraries/Actions.sol)
- [Permit2 Docs](https://docs.uniswap.org/contracts/permit2/overview)

### Learning Resources
- [V4 Whitepaper](https://uniswap.org/whitepaper-v4.pdf)
- [Concentrated Liquidity Math](https://atiselsts.github.io/pdfs/uniswap-v3-liquidity-math.pdf)
- [EIP-1153 Transient Storage](https://eips.ethereum.org/EIPS/eip-1153)
- [EIP-2612 Permit](https://eips.ethereum.org/EIPS/eip-2612)

### Code Examples
- [V4 Core Tests](https://github.com/Uniswap/v4-core/tree/main/test)
- [V4 Periphery Tests](https://github.com/Uniswap/v4-periphery/tree/main/test)
- [Position Manager Examples](https://github.com/Uniswap/v4-periphery/tree/main/test/position-managers)

### Tools
- [Foundry Book](https://book.getfoundry.sh/)
- [Uniswap V4 Explorer](https://v4-explorer.uniswap.org/)
- [Tick Math Calculator](https://www.desmos.com/calculator/qk3yqjxuvc)

---

## 🎯 Exercise Checklist

Before moving on, ensure you can:

- [ ] Explain the difference between Position Manager and Pool Manager
- [ ] Understand the Actions pattern and why it's used
- [ ] Implement all four core functions (mint, increase, decrease, burn)
- [ ] Debug OutOfFunds errors using trace analysis
- [ ] Calculate appropriate slippage parameters
- [ ] Use SETTLE_PAIR, CLOSE_CURRENCY, and TAKE_PAIR correctly
- [ ] Understand token deltas and settlement flow
- [ ] Set up proper token approvals via Permit2
- [ ] Write and run fork-based tests
- [ ] Interpret test output and gas reports

### Self-Assessment Questions

1. **Why use `address(this).balance` instead of `msg.value`?**
   <details>
   <summary>Answer</summary>
   The contract may have ETH from previous operations or test setup. `msg.value` is only the ETH sent with the current call (often 0), while `address(this).balance` is the total available balance.
   </details>

2. **When should you use SETTLE_PAIR vs CLOSE_CURRENCY?**
   <details>
   <summary>Answer</summary>
   SETTLE_PAIR when you're definitely paying both tokens (minting). CLOSE_CURRENCY when delta direction is uncertain or you want per-currency control (increasing/decreasing).
   </details>

3. **Why include SWEEP after mint/increase?**
   <details>
   <summary>Answer</summary>
   You typically send more ETH than needed (full balance). The exact amount depends on current price. SWEEP returns the leftover, preventing ETH from getting stuck.
   </details>

4. **What's the difference between DECREASE_LIQUIDITY and BURN_POSITION?**
   <details>
   <summary>Answer</summary>
   DECREASE removes partial liquidity, keeps NFT alive. BURN removes all liquidity and destroys the NFT. After burn, the tokenId cannot be used again.
   </details>

5. **Why do we need Permit2?**
   <details>
   <summary>Answer</summary>
   Single approval for all positions and protocols. More gas efficient, supports signature-based approvals, time-limited permissions for better security.
   </details>

---

## 🚀 Next Steps

Now that you've mastered Position Manager basics:

1. **Explore Advanced Actions**:
   - TAKE_PORTION for partial withdrawals
   - SETTLE_ALL for efficient full-balance deposits
   - CLEAR_OR_TAKE for dust handling

2. **Build Real Applications**:
   - Auto-compounding vault
   - Range order system
   - LP farming strategies
   - Rebalancing bot

3. **Study Hooks Integration**:
   - How hooks interact with Position Manager
   - Custom position logic
   - Fee modifications
   - Dynamic ranges

4. **Optimize Gas**:
   - Batch operations
   - Efficient action sequences
   - Transient storage patterns

5. **Security Auditing**:
   - Review actual Position Manager code
   - Study past exploits
   - Practice secure patterns

---

## 📝 Summary

The **Position Manager (POSM)** is Uniswap V4's peripheral contract for managing NFT-based liquidity positions. Key takeaways:

### Core Concepts
- **NFT Positions**: Each position is an ERC721 token with metadata
- **Actions Pattern**: Batch operations via encoded action sequences
- **Deltas**: Core accounting primitive (positive = owe, negative = owed)
- **Settlement**: Explicit payment handling via SETTLE/TAKE actions
- **Permit2**: Universal approval system for gas efficiency

### Four Main Operations
1. **Mint**: Create new position → MINT_POSITION + SETTLE_PAIR + SWEEP
2. **Increase**: Add liquidity → INCREASE_LIQUIDITY + CLOSE_CURRENCY + SWEEP
3. **Decrease**: Remove liquidity → DECREASE_LIQUIDITY + TAKE_PAIR
4. **Burn**: Close position → BURN_POSITION + TAKE_PAIR

### Critical Patterns
- Always send `address(this).balance`, not `msg.value`
- Include SWEEP to recover leftover ETH
- Use appropriate slippage protection (min/max amounts)
- Set reasonable deadlines (not type(uint256).max)
- Get position info before modify operations

### Debugging Strategy
1. Run with `-vvv` to see full traces
2. Look for `{value: X}` markers
3. Compare with working functions
4. Check balances and approvals
5. Validate tick alignment

### Gas Optimization
- Use transient storage benefits
- Batch multiple operations
- Minimize state reads
- Efficient action sequences

### Security
- Slippage protection on all operations
- Deadline enforcement
- NFT ownership verification
- Reentrancy guards
- TWAP for price feeds

---

**Congratulations!** You now understand how to manage Uniswap V4 liquidity positions programmatically. This is a foundational skill for building DeFi applications, vaults, and trading strategies on Uniswap V4.

Continue to the next exercise to learn about more advanced V4 features! 🎓

