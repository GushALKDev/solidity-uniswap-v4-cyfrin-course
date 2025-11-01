# Uniswap V4 Swap - Complete Technical Guide

## Introduction

This document provides an in-depth technical explanation of the `Swap.sol` contract and its integration with Uniswap V4's swap mechanism. Unlike flash loans which borrow and repay in one transaction, swaps exchange one token for another through liquidity pools.

### What You'll Learn

- How to perform token swaps using Uniswap V4's PoolManager
- The difference between Exact Input and Exact Output swaps
- Understanding `BalanceDelta` and how to interpret swap results
- The role of price limits and slippage protection
- How to handle both native ETH and ERC20 token swaps

### Key Concepts

**Token Swap**: Trading one cryptocurrency for another using liquidity from a pool.

**Exact Input Swap**: You specify exactly how much you want to give, and receive a variable amount in return.

**BalanceDelta**: A data structure that tracks the change in token balances after an operation (negative = outflow, positive = inflow).

**Price Impact**: How much your trade affects the pool's price ratio between tokens.

## Contract Overview

The `Swap.sol` contract demonstrates how to perform single-hop token swaps using Uniswap V4's PoolManager. This is part of the Cyfrin Updraft Uniswap V4 course exercises.

### Core Features

| Feature | Description |
|---------|-------------|
| **Exact Input Swaps** | Specify exact amount to trade, receive variable output |
| **Slippage Protection** | Set minimum output amount to prevent unfavorable trades |
| **Single Hop** | Direct swap between two tokens in one pool |
| **Multi-Currency Support** | Handle both native ETH and ERC20 tokens |
| **Atomic Execution** | All operations happen in one transaction via unlock callback |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Architecture Pattern**: Callback-based atomic execution (same as flash loans)
- **Swap Type**: Exact Input Single Hop
- **Swap Fee**: Determined by pool configuration (typically 0.05%, 0.3%, or 1%)

## Contract Architecture

### Dependencies and Interfaces

#### Core Imports

```solidity
import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/IUnlockCallback.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams} from "../types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CurrencyLib} from "../libraries/CurrencyLib.sol";
import {MIN_SQRT_PRICE, MAX_SQRT_PRICE} from "../Constants.sol";
```

| Interface/Library | Purpose | Key Usage |
|-------------------|---------|-----------|
| `IERC20` | ERC20 token operations | Transfer tokens to PoolManager |
| `IPoolManager` | Central coordinator for swaps | `swap()`, `take()`, `settle()`, `sync()` |
| `IUnlockCallback` | Callback interface | `unlockCallback()` - Execute swap logic |
| `BalanceDelta` | Track balance changes | Extract amount0 and amount1 from swap result |
| `SafeCast` | Safe type conversions | Convert between int128, uint128, int256, uint256 |
| `CurrencyLib` | Currency utilities | `transferIn()`, `transferOut()`, `balanceOf()` |

### State Variables

```solidity
IPoolManager public immutable poolManager;
```

| Variable | Type | Purpose |
|----------|------|---------|
| `poolManager` | `IPoolManager` | Reference to Uniswap V4's central pool coordinator |

### Custom Struct: SwapExactInputSingleHop

```solidity
struct SwapExactInputSingleHop {
    PoolKey poolKey;      // Identifies which pool to use
    bool zeroForOne;      // Swap direction: token0 → token1 (true) or token1 → token0 (false)
    uint128 amountIn;     // Exact amount of input tokens
    uint128 amountOutMin; // Minimum acceptable output (slippage protection)
}
```

**Purpose**: Encapsulates all parameters needed for an exact input swap in a single hop.

### Access Control

```solidity
modifier onlyPoolManager() {
    require(msg.sender == address(poolManager), "not pool manager");
    _;
}
```

**Security**: Ensures only the PoolManager can call `unlockCallback()`, preventing unauthorized access.

## Swap Execution Flow

### High-Level Overview

```
┌─────────────┐         ┌──────────────┐         ┌────────────────┐
│   User/EOA  │         │   Swap.sol   │         │  PoolManager   │
└──────┬──────┘         └──────┬───────┘         └───────┬────────┘
       │                       │                         │
       │  1. swap(params)      │                         │
       │──────────────────────>│                         │
       │                       │                         │
       │  2. transferIn(tokenIn)                         │
       │──────────────────────>│                         │
       │                       │                         │
       │                       │  3. unlock(data)        │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │  4. [LOCK STATE]        │
       │                       │                         │
       │                       │<─ 5. unlockCallback() ──│
       │                       │                         │
       │                       │  6. swap(params)        │
       │                       │────────────────────────>│
       │                       │<──── BalanceDelta ──────│
       │                       │                         │
       │                       │  7. take(tokenOut)      │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │  8. sync(tokenIn)       │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │  9. settle(tokenIn)     │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │  10. [UNLOCK STATE]     │
       │                       │<────────────────────────│
       │                       │                         │
       │                       │  11. Refund excess      │
       │<──────────────────────│                         │
       │   Success + tokens    │                         │
```

### Detailed Step-by-Step Execution

## Step 1: Initiation - `swap(SwapExactInputSingleHop calldata params)`

**Contract**: `Swap.sol`  
**Caller**: External user or contract  
**Function Signature**: `function swap(SwapExactInputSingleHop calldata params) external payable`

**Purpose**: Entry point for initiating a token swap.

**Code Breakdown**:

```solidity
function swap(SwapExactInputSingleHop calldata params) external payable {
    // 1. Determine input currency based on swap direction
    address currencyIn = params.zeroForOne
        ? params.poolKey.currency0
        : params.poolKey.currency1;

    // 2. Transfer input tokens from user to this contract
    currencyIn.transferIn(msg.sender, uint256(params.amountIn));
    
    // 3. Trigger swap via PoolManager unlock
    poolManager.unlock(abi.encode(msg.sender, params));

    // 4. Refund any remaining tokens to user
    uint256 bal = currencyIn.balanceOf(address(this));
    if (bal > 0) {
        currencyIn.transferOut(msg.sender, bal);
    }
}
```

### Sub-step 1.1: Determine Input Currency

```solidity
address currencyIn = params.zeroForOne
    ? params.poolKey.currency0
    : params.poolKey.currency1;
```

**Logic**:
- If `zeroForOne == true`: Swapping currency0 → currency1, so `currencyIn = currency0`
- If `zeroForOne == false`: Swapping currency1 → currency0, so `currencyIn = currency1`

**Example**:
```solidity
// Pool: USDC (currency0) / DAI (currency1)
// Swap 1000 USDC for DAI
params.zeroForOne = true;      // 0 → 1
currencyIn = currency0;        // USDC
currencyOut = currency1;       // DAI (determined in callback)
```

### Sub-step 1.2: Transfer Input Tokens

```solidity
currencyIn.transferIn(msg.sender, uint256(params.amountIn));
```

**Purpose**: Move tokens from user to the Swap contract before executing the swap.

**CurrencyLib.transferIn() explained**:
```solidity
// Handles both ETH and ERC20 tokens
function transferIn(address currency, address from, uint256 amount) internal {
    if (currency == address(0)) {
        // Native ETH: already received via msg.value
        require(msg.value >= amount, "Insufficient ETH");
    } else {
        // ERC20: transferFrom
        IERC20(currency).transferFrom(from, address(this), amount);
    }
}
```

### Sub-step 1.3: Trigger Unlock

```solidity
poolManager.unlock(abi.encode(msg.sender, params));
```

**What's Encoded**:
- `msg.sender`: Original caller (to send output tokens to)
- `params`: All swap parameters

**Why Encode Both?**: The callback needs to know:
1. Where to send the output tokens (`msg.sender`)
2. Swap details (`params`)

### Sub-step 1.4: Refund Excess

```solidity
uint256 bal = currencyIn.balanceOf(address(this));
if (bal > 0) {
    currencyIn.transferOut(msg.sender, bal);
}
```

**Why This Exists**: In some edge cases (like when using ETH), there might be leftover tokens. This ensures the user gets them back.

## Step 2: Callback Execution - `unlockCallback(bytes calldata data)`

**Contract**: `Swap.sol`  
**Caller**: `IPoolManager` (enforced by `onlyPoolManager` modifier)  
**Context**: Executing within PoolManager's locked state

### Sub-step 2.1: Decode Parameters

```solidity
(address msgSender, SwapExactInputSingleHop memory params) =
    abi.decode(data, (address, SwapExactInputSingleHop));
```

**Result**: Extract the original caller and swap parameters.

### Sub-step 2.2: Execute the Swap

```solidity
int256 d = poolManager.swap({
    key: params.poolKey,
    params: SwapParams({
        zeroForOne: params.zeroForOne,
        amountSpecified: -(params.amountIn.toInt256()),
        sqrtPriceLimitX96: params.zeroForOne
            ? MIN_SQRT_PRICE + 1
            : MAX_SQRT_PRICE - 1
    }),
    hookData: ""
});
```

**What `poolManager.swap()` Does**:

✅ **YES, it executes the actual swap** - This is NOT just a calculation!

**Internal Operations**:
1. **Updates pool state**: Changes `sqrtPriceX96`, `tick`, and `liquidity`
2. **Calculates amounts**: Determines exact input/output based on the pool's curve
3. **Updates accounting**: Records debt/credit in `currencyDelta` 
4. **Calls hooks**: Executes `beforeSwap` and `afterSwap` if the pool has hooks
5. **Returns BalanceDelta**: Packs the result (amount0, amount1) as int256

**What Actually Happens Inside the Pool**:
```solidity
// Simplified internal logic of poolManager.swap()
function swap(...) external returns (int256) {
    // 1. Load pool state
    Pool.State storage pool = pools[poolId];
    
    // 2. Execute the swap logic (concentrated liquidity math)
    //    - Move through ticks if needed
    //    - Calculate exact amounts using x*y=k formula
    //    - Update sqrtPriceX96 and tick
    (int256 amount0, int256 amount1) = pool.swap(...);
    
    // 3. Update internal accounting (debt tracking)
    currencyDelta[msg.sender][currency0] += amount0;  // Negative for input
    currencyDelta[msg.sender][currency1] += amount1;  // Positive for output
    
    // 4. Pack and return results
    return toBalanceDelta(amount0, amount1);
}
```

**Important**: After `poolManager.swap()` returns:
- ✅ The pool's price HAS changed
- ✅ The pool's liquidity distribution HAS updated
- ✅ Debt is recorded in PoolManager's accounting
- ❌ Tokens have NOT been physically transferred yet
- ❌ Debt has NOT been settled yet

**Token Transfer Happens Later**:
- `take()` withdraws output tokens (Step 2.6)
- `settle()` pays input tokens (Step 2.8)

**Why Separate `swap()` from `take()`/`settle()`?**

This is one of Uniswap V4's key innovations called **"Flash Accounting"**. Here's why:

**Old Way (Uniswap V2/V3)**:
```solidity
// Everything happens in one function
function swap(amountIn) {
    // Transfer tokens IN
    token0.transferFrom(user, pool, amountIn);  // Cost: ~20k gas
    
    // Calculate swap
    amountOut = calculateSwap(amountIn);
    
    // Transfer tokens OUT
    token1.transfer(user, amountOut);  // Cost: ~20k gas
}
// Total: ~40k gas in transfers per swap
```

**New Way (Uniswap V4)**:
```solidity
// 1. Update accounting (no transfers)
swap() → records debt/credit  // Cost: ~3k gas (just SSTORE)

// 2. Do multiple operations while locked
swap()     → debt: -100 USDC, credit: +99 DAI
swap()     → debt: -99 DAI, credit: +98 USDC  
swap()     → debt: -98 USDC, credit: +97 DAI
// Net: -99 USDC, +97 DAI

// 3. Only transfer net amounts once
take()    → transfer 97 DAI    // Cost: ~20k gas (only ONCE)
settle()  → transfer 99 USDC   // Cost: ~20k gas (only ONCE)
```

**Key Benefits**:

1. **Gas Efficiency with Multiple Operations**:
```solidity
// Example: Multi-hop swap USDC → DAI → WETH

// Old way (V3):
transfer USDC to pool1     // 20k gas
transfer DAI to pool2      // 20k gas
transfer WETH to user      // 20k gas
// Total: 60k gas in transfers

// New way (V4):
swap(USDC→DAI)   // 3k gas, records debt
swap(DAI→WETH)   // 3k gas, updates debt
take(WETH)       // 20k gas, final transfer
settle(USDC)     // 20k gas, final transfer
// Total: 46k gas (saves 14k gas!)
```

2. **Enables Flash Accounting** (what we saw in Flash Loans):
```solidity
// Borrow and repay without actual transfers!
take(1000 USDC)   // Record debt: +1000
// ... do stuff ...
settle(1000 USDC) // Clear debt: -1000
// Net: 0 → NO actual transfer needed if they cancel out!
```

3. **Atomic Operations**:
```solidity
// All operations must balance before unlock
swap()    // debt: -100, credit: +99
take()    // debt: +99
settle()  // debt: -100
// unlock() checks: debt == 0 ✅ or revert ❌
```

4. **Flexibility**:
```solidity
// You can choose:
- Where to send output tokens (take(to: user))
- When to settle debts
- How to combine multiple operations

// Old way: rigid, everything in one function
```

**Analogy**:

**Old Banking (V2/V3)**:
```
You: "Give me $100 DAI for $100 USDC"
Bank: "OK" 
      → takes your $100 USDC (physical)
      → gives you $100 DAI (physical)
```

**New Banking (V4)**:
```
You: "I want to make several trades"
Bank: "OK, I'll keep a tab"
      
Swap 1: You owe $100, you're owed $99    (just write it down)
Swap 2: You owe $99, you're owed $98     (update the tab)
Swap 3: You owe $98, you're owed $97     (update again)

Final: "You owe $99, you're owed $97"
Bank: "Pay me $99, I'll give you $97"    (one physical transfer)
```

**In Summary**:

V4 separates accounting from transfers:
- ✅ More gas efficient for multiple operations
- ✅ Enables flash accounting (borrow/repay without transfers)
- ✅ More flexible (you control when/where transfers happen)
- ✅ Simpler to compose complex DeFi strategies

**The "cost"**: Slightly more complex code (need to call `take()`/`settle()` separately), but the benefits far outweigh this.

**Breaking Down SwapParams**:

#### 1. `zeroForOne`

```solidity
zeroForOne: params.zeroForOne
```

**Purpose**: Defines swap direction
- `true`: currency0 → currency1 (e.g., USDC → DAI)
- `false`: currency1 → currency0 (e.g., DAI → USDC)

#### 2. `amountSpecified`

```solidity
amountSpecified: -(params.amountIn.toInt256())
```

**The Negative Sign is Critical**:

| Value | Meaning | Swap Type |
|-------|---------|-----------|
| **Negative (`-`)** | **Exact amount IN** | "I want to give EXACTLY this much" |
| **Positive (`+`)** | **Exact amount OUT** | "I want to receive EXACTLY this much" |

**Example**:
```solidity
// User wants to swap EXACTLY 1000 USDC
params.amountIn = 1000e6;                    // uint128
amountIn.toInt256() = +1000000000;          // Convert to int256
-(amountIn.toInt256()) = -1000000000;       // Make negative

// Result: "Swap exactly 1000 USDC, give me as much DAI as possible"
```

**Why Negative for Exact Input?**

Uniswap V4 uses signed integers to represent direction:
- **Negative**: You're **giving** this amount (input is exact)
- **Positive**: You're **receiving** this amount (output is exact)

**Visual Representation**:

```
EXACT INPUT (amountSpecified: -1000):
┌─────────────┐                    ┌─────────────┐
│  1000 USDC  │ ──────────────────>│   995 DAI   │
│  (EXACT)    │                    │  (variable) │
└─────────────┘                    └─────────────┘
         ↑                                ↓
    You specify                    Pool calculates
    
EXACT OUTPUT (amountSpecified: +1000):
┌─────────────┐                    ┌─────────────┐
│  1005 USDC  │ ──────────────────>│  1000 DAI   │
│  (variable) │                    │   (EXACT)   │
└─────────────┘                    └─────────────┘
         ↓                                ↑
    Pool calculates                 You specify
```

#### 3. `sqrtPriceLimitX96`

```solidity
sqrtPriceLimitX96: params.zeroForOne
    ? MIN_SQRT_PRICE + 1
    : MAX_SQRT_PRICE - 1
```

**Purpose**: Price limit to prevent excessive slippage or manipulation.

**What is sqrtPriceX96?**
- The square root of the price ratio between token1 and token0, in Q96 fixed-point format
- `price = (sqrtPriceX96 / 2^96)^2`

**Why Set Limits?**

| Swap Direction | Limit | Reasoning |
|----------------|-------|-----------|
| `zeroForOne = true` (0→1) | `MIN_SQRT_PRICE + 1` | Price decreases (more token1 per token0) |
| `zeroForOne = false` (1→0) | `MAX_SQRT_PRICE - 1` | Price increases (less token1 per token0) |

**Constants**:
```solidity
// From Constants.sol
uint160 constant MIN_SQRT_PRICE = 4295128739;
uint160 constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;
```

**Code Explanation**:
```solidity
sqrtPriceLimitX96: params.zeroForOne 
    ? MIN_SQRT_PRICE + 1    // If swapping 0→1
    : MAX_SQRT_PRICE - 1    // If swapping 1→0
```

**Why the +1 and -1?**
- Uniswap V4 requires the price limit to be **strictly within** the valid range
- MIN_SQRT_PRICE and MAX_SQRT_PRICE are the absolute boundaries
- Adding +1 or subtracting -1 ensures we stay within valid bounds
- Without this, the transaction would revert with "SPL" (SqrtPriceLimit invalid)

**Practical Effect**:
- Setting to MIN/MAX (±1) means "allow the swap to execute regardless of price impact"
- This is the most permissive setting - accepts any resulting price
- In production, you'd calculate tighter bounds based on acceptable slippage

**Why Different Values for Each Direction?**

When you swap, the price changes:
- **0 → 1 swap**: Price of token1 in terms of token0 **decreases** (more token1 per token0)
  - Need a lower bound → use `MIN_SQRT_PRICE + 1`
  - Prevents price from going below the minimum
  
- **1 → 0 swap**: Price of token1 in terms of token0 **increases** (less token1 per token0)
  - Need an upper bound → use `MAX_SQRT_PRICE - 1`
  - Prevents price from going above the maximum

**Visual Example**:

```
Initial State: 1 USDC = 1 DAI
Pool: USDC (currency0) / DAI (currency1)

Swap 0→1 (USDC → DAI):
┌─────────────────────────────────────┐
│ Before: 1 USDC = 1.00 DAI           │
│ After:  1 USDC = 0.99 DAI           │ ← Price decreased
│ sqrtPriceLimitX96: MIN_SQRT_PRICE+1 │ ← Allow decrease to minimum
└─────────────────────────────────────┘

Swap 1→0 (DAI → USDC):
┌─────────────────────────────────────┐
│ Before: 1 USDC = 1.00 DAI           │
│ After:  1 USDC = 1.01 DAI           │ ← Price increased
│ sqrtPriceLimitX96: MAX_SQRT_PRICE-1 │ ← Allow increase to maximum
└─────────────────────────────────────┘
```

**Example with 1% Slippage**:
```solidity
// Current price: 1 USDC = 1 DAI
// Swap 1000 USDC for DAI
// Acceptable slippage: 1%
// Minimum expected: 990 DAI

// Calculate sqrtPriceLimitX96 for 1% slippage:
// newPrice = currentPrice * 0.99
// sqrtPriceLimitX96 = sqrt(newPrice) * 2^96
```

### Sub-step 2.3: Extract Balance Delta

```solidity
BalanceDelta delta = BalanceDelta.wrap(d);
int128 amount0 = delta.amount0();
int128 amount1 = delta.amount1();
```

**What is BalanceDelta?**

A custom type that packs two `int128` values into one `int256`.

**What does `BalanceDelta.wrap()` do?**

Converts a raw `int256` into the `BalanceDelta` custom type, which provides helper methods to extract the individual amounts:

```solidity
// poolManager.swap() returns int256 (packed data)
int256 d = poolManager.swap(...);

// wrap() converts it to BalanceDelta type
BalanceDelta delta = BalanceDelta.wrap(d);

// Now you can extract individual amounts
int128 amount0 = delta.amount0();  // Extract first 128 bits
int128 amount1 = delta.amount1();  // Extract second 128 bits
```

**Internal Structure**:

```solidity
// Structure of BalanceDelta (int256):
// [128 bits: amount1][128 bits: amount0]

// Example after swap:
// amount0 = -1000e6  (gave 1000 USDC)
// amount1 = +995e18  (received 995 DAI)
```

**Sign Convention**:
| Sign | Meaning | Your Perspective |
|------|---------|------------------|
| **Negative (-)** | Tokens **paid/given** | You owe or gave these tokens |
| **Positive (+)** | Tokens **received/owed to you** | You receive these tokens |

**Real Example**:
```solidity
// Swap 1000 USDC (currency0) for DAI (currency1)
int128 amount0 = -1000000000;  // -1000 USDC (6 decimals) - YOU PAID
int128 amount1 = +995000000000000000000;  // +995 DAI (18 decimals) - YOU RECEIVE
```

### Sub-step 2.4: Determine Input/Output Amounts

```solidity
(
    address currencyIn,
    address currencyOut,
    uint256 amountIn,
    uint256 amountOut
) = params.zeroForOne
    ? (
        params.poolKey.currency0,
        params.poolKey.currency1,
        (-amount0).toUint256(),
        amount1.toUint256()
    )
    : (
        params.poolKey.currency1,
        params.poolKey.currency0,
        (-amount1).toUint256(),
        amount0.toUint256()
    );
```

**Purpose**: Map the BalanceDelta amounts to actual currencies based on swap direction.

**Case 1: zeroForOne = true** (0 → 1)

```solidity
currencyIn  = currency0;           // USDC
currencyOut = currency1;           // DAI
amountIn    = (-amount0).toUint256();  // Convert -1000 to +1000
amountOut   = amount1.toUint256();     // Already positive +995
```

**Why Negate amount0?**
- `amount0` is negative (-1000) because we paid it
- We need a positive uint256 (1000) for further calculations
- `-(-1000) = +1000`

**Case 2: zeroForOne = false** (1 → 0)

```solidity
currencyIn  = currency1;           // DAI
currencyOut = currency0;           // USDC
amountIn    = (-amount1).toUint256();  // Convert negative to positive
amountOut   = amount0.toUint256();     // Already positive
```

**Visual Example**:

```
Swap: 1000 USDC → ? DAI (zeroForOne = true)

BalanceDelta from poolManager.swap():
┌─────────────────────────────────────┐
│ amount0 = -1000000000 (6 decimals)  │ ← Negative = You paid USDC
│ amount1 = +995000000000000000000    │ ← Positive = You receive DAI
└─────────────────────────────────────┘

After mapping:
┌─────────────────────────────────────┐
│ currencyIn  = USDC (address)        │
│ currencyOut = DAI (address)         │
│ amountIn    = 1000000000            │ ← Made positive
│ amountOut   = 995000000000000000000 │
└─────────────────────────────────────┘
```

### Sub-step 2.5: Slippage Check

```solidity
require(amountOut >= params.amountOutMin, "amount out < min");
```

**Purpose**: Ensure the swap didn't result in unfavorable price execution.

**Example**:
```solidity
// User expects at least 990 DAI when swapping 1000 USDC
params.amountOutMin = 990e18;

// Actual swap result
amountOut = 995e18;  // ✅ PASS: 995 >= 990

// If market moved unfavorably:
amountOut = 985e18;  // ❌ FAIL: 985 < 990, transaction reverts
```

**Why This Matters**: Protects users from:
- Front-running attacks
- High price impact
- Unfavorable market conditions

### Sub-step 2.6: Withdraw Output Tokens

```solidity
poolManager.take({
    currency: currencyOut,
    to: msgSender,
    amount: amountOut
});
```

**Purpose**: Send the received tokens directly to the original caller.

**What `take()` does**:
- Transfers tokens from PoolManager to specified address (`msgSender`)
- Records this as a debt that must be settled before unlocking
- Similar to flash loan's `take()`, but here we're withdrawing our earned tokens

**Accounting**:
```
PoolManager Internal State:
  debt[Swap.sol][currencyOut] += amountOut
  // This debt will be cleared when we settle currencyIn
```

### Sub-step 2.7: Synchronize Input Currency

```solidity
poolManager.sync(currencyIn);
```

**Purpose**: Update PoolManager's internal balance tracking for the input token.

**Why Needed**: Before we transfer input tokens to the PoolManager (in the next step), we call `sync()` to prepare the PoolManager to recognize the incoming balance change. 

**What `sync()` Does**:
```solidity
// Simplified internal logic in PoolManager
function sync(Currency currency) external {
    // Record the current balance BEFORE tokens are transferred
    uint256 balanceBefore = IERC20(currency).balanceOf(address(this));
    // Store it for later comparison in settle()
}
```

**The Actual Flow**:
1. Tokens are currently in Swap.sol (from user transfer in Step 1.2)
2. We call `sync()` → PoolManager records its current balance
3. We transfer tokens → Swap.sol transfers to PoolManager
4. We call `settle()` → PoolManager compares new balance with synced balance
5. PoolManager updates debt accounting based on the difference

### Sub-step 2.8: Settle Input Tokens

```solidity
if (currencyIn == address(0)) {
    poolManager.settle{value: amountIn}();
} else {
    IERC20(currencyIn).transfer(address(poolManager), amountIn);
    poolManager.settle();
}
```

**Purpose**: Pay for the swap by transferring input tokens to PoolManager.

**ETH (Native Currency)**:
```solidity
poolManager.settle{value: amountIn}();
```
- Send ETH with the call
- PoolManager receives and updates accounting in one step

**ERC20 Tokens**:
```solidity
IERC20(currencyIn).transfer(address(poolManager), amountIn);
poolManager.settle();
```
- Transfer tokens first
- Then call `settle()` to update accounting

**Net Effect**:
After settlement, the PoolManager's debt/credit for this contract is balanced:
```
Debt from take (currencyOut): +amountOut
Credit from settle (currencyIn): -amountIn
Net: Balanced (assuming fair swap + fees)
```

### Sub-step 2.9: Return from Callback

```solidity
return "";
```

**Purpose**: Satisfy the `IUnlockCallback` interface requirement.

**What Happens Next**: Control returns to PoolManager, which verifies all debts are settled and unlocks.

## Step 3: Post-Callback Cleanup

**Back in `swap()` function**:

```solidity
// After poolManager.unlock() returns
uint256 bal = currencyIn.balanceOf(address(this));
if (bal > 0) {
    currencyIn.transferOut(msg.sender, bal);
}
```

**Purpose**: Refund any excess input tokens.

**When This Happens**:
- User sent ETH with extra value
- Rounding in token calculations
- Edge cases in swap execution

## Understanding the Unlock Pattern

The same unlock/callback pattern from flash loans applies here:

```solidity
// Simplified flow:
swap(params)                    // User calls
  ↓
transferIn(tokens)              // Get user's tokens
  ↓
poolManager.unlock(data)        // Enter locked state
  ↓
unlockCallback(data)            // PoolManager calls back
  ↓
  poolManager.swap()            // Execute actual swap
  ↓
  poolManager.take()            // Withdraw output tokens
  ↓
  poolManager.settle()          // Pay input tokens
  ↓
[return]                        // Exit callback
  ↓
[PoolManager verifies]          // All debts settled?
  ↓
[unlock]                        // Release lock
  ↓
refund()                        // Return excess tokens
```

## Key Differences: Swap vs Flash Loan

| Aspect | Flash Loan | Swap |
|--------|------------|------|
| **Purpose** | Borrow → Execute Logic → Repay | Give Token A → Receive Token B |
| **Token Flow** | Borrow same token, return same token | Give one token, receive different token |
| **Debt** | Must repay exactly what you borrowed | Debt is settled by paying input tokens |
| **User Intent** | Execute complex DeFi strategies | Exchange tokens |
| **Custom Logic** | Call external contracts during loan | No custom logic, just swap |
| **Fees** | 0% in V4 | Pool fees (0.05%, 0.3%, 1%, etc.) |

## Exact Input vs Exact Output

### Exact Input (This Contract)

```solidity
amountSpecified: -(params.amountIn.toInt256())  // Negative
```

**User Says**: "I want to trade EXACTLY 1000 USDC, give me as much DAI as possible"

**Result**:
- Input: Exactly 1000 USDC ✅
- Output: Variable amount (e.g., 995 DAI depending on price)

**Use Case**: When you want to trade a specific amount you have.

### Exact Output (Not Implemented)

```solidity
amountSpecified: +(params.amountOut.toInt256())  // Positive
```

**User Says**: "I need EXACTLY 1000 DAI, take however much USDC is needed"

**Result**:
- Input: Variable amount (e.g., 1005 USDC depending on price)
- Output: Exactly 1000 DAI ✅

**Use Case**: When you need a specific amount of output token.

### Comparison Table

| Feature | Exact Input | Exact Output |
|---------|-------------|--------------|
| **amountSpecified** | Negative | Positive |
| **Input Amount** | Fixed | Variable |
| **Output Amount** | Variable | Fixed |
| **Slippage Protection** | Set `amountOutMin` | Set `amountInMax` |
| **User Certainty** | Know what you're paying | Know what you're receiving |

## Price Limits and Slippage

### What is Slippage?

**Slippage**: The difference between expected and actual execution price.

**Example**:
```
Expected: 1 USDC = 1.00 DAI
Actual:   1 USDC = 0.99 DAI
Slippage: 1%
```

### How sqrtPriceLimitX96 Works

```solidity
sqrtPriceLimitX96: params.zeroForOne
    ? MIN_SQRT_PRICE + 1    // Allow price to decrease to minimum
    : MAX_SQRT_PRICE - 1    // Allow price to increase to maximum
```

**In This Contract**: We use MIN/MAX bounds, accepting any price.

**In Production**: Calculate tighter bounds:

```solidity
// Example: 1% slippage tolerance
function calculatePriceLimit(
    uint160 currentSqrtPrice,
    bool zeroForOne,
    uint256 slippageBps  // 100 = 1%
) internal pure returns (uint160) {
    if (zeroForOne) {
        // Price decreases when swapping 0 for 1
        // Allow up to slippageBps decrease
        return uint160(
            (uint256(currentSqrtPrice) * (10000 - slippageBps)) / 10000
        );
    } else {
        // Price increases when swapping 1 for 0
        // Allow up to slippageBps increase
        return uint160(
            (uint256(currentSqrtPrice) * (10000 + slippageBps)) / 10000
        );
    }
}
```

### Slippage Protection: Two Mechanisms

#### 1. `amountOutMin` (Used in this contract)

```solidity
require(amountOut >= params.amountOutMin, "amount out < min");
```

**Advantage**: Simple and direct
**Disadvantage**: Doesn't prevent the swap from happening at bad price, just reverts after

#### 2. `sqrtPriceLimitX96` (Not used strictly here)

**Advantage**: Prevents swap from executing at unfavorable price
**Disadvantage**: Requires price calculation

**Best Practice**: Use both for maximum protection.

## Complete Code Example with Comments

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/IUnlockCallback.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams} from "../types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CurrencyLib} from "../libraries/CurrencyLib.sol";
import {MIN_SQRT_PRICE, MAX_SQRT_PRICE} from "../Constants.sol";

/// @title Exact Input Single Hop Swap for Uniswap V4
/// @notice Demonstrates token swaps using PoolManager
/// @dev Implements IUnlockCallback for atomic swap execution
contract Swap is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for int128;
    using SafeCast for uint128;
    using CurrencyLib for address;

    /// @notice Reference to Uniswap V4's central pool coordinator
    IPoolManager public immutable poolManager;

    /// @notice Parameters for an exact input single hop swap
    /// @param poolKey Identifies the pool to swap in
    /// @param zeroForOne Swap direction (true = 0→1, false = 1→0)
    /// @param amountIn Exact amount of input tokens
    /// @param amountOutMin Minimum acceptable output (slippage protection)
    struct SwapExactInputSingleHop {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMin;
    }

    /// @notice Ensures only PoolManager can invoke callback
    /// @dev Critical security measure preventing unauthorized access
    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
        _;
    }

    /// @notice Initialize contract with PoolManager reference
    /// @param _poolManager Address of deployed Uniswap V4 PoolManager
    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @notice Allow contract to receive ETH for native swaps
    receive() external payable {}

    /// @notice Callback executed during PoolManager's locked state
    /// @param data Encoded swap parameters and caller address
    /// @return Empty bytes as required by interface
    /// @dev Only callable by PoolManager - contains swap execution logic
    function unlockCallback(bytes calldata data)
        external
        onlyPoolManager
        returns (bytes memory)
    {
        // 1. Decode parameters
        (address msgSender, SwapExactInputSingleHop memory params) =
            abi.decode(data, (address, SwapExactInputSingleHop));

        // 2. Execute the swap
        // Returns BalanceDelta: int256 with amount0 and amount1 packed
        int256 d = poolManager.swap({
            key: params.poolKey,
            params: SwapParams({
                zeroForOne: params.zeroForOne,
                // Negative = Exact Input
                // "I'm giving exactly this much"
                amountSpecified: -(params.amountIn.toInt256()),
                // Allow swap to execute at any price (MIN/MAX bounds)
                // In production: calculate based on acceptable slippage
                sqrtPriceLimitX96: params.zeroForOne
                    ? MIN_SQRT_PRICE + 1
                    : MAX_SQRT_PRICE - 1
            }),
            hookData: ""
        });

        // 3. Extract balance changes from swap result
        BalanceDelta delta = BalanceDelta.wrap(d);
        int128 amount0 = delta.amount0();  // Change in currency0
        int128 amount1 = delta.amount1();  // Change in currency1

        // 4. Map amounts to actual currencies based on swap direction
        (
            address currencyIn,
            address currencyOut,
            uint256 amountIn,
            uint256 amountOut
        ) = params.zeroForOne
            ? (
                // Swapping 0 → 1
                params.poolKey.currency0,          // Input = currency0
                params.poolKey.currency1,          // Output = currency1
                (-amount0).toUint256(),            // Negate and convert
                amount1.toUint256()                // Already positive
            )
            : (
                // Swapping 1 → 0
                params.poolKey.currency1,          // Input = currency1
                params.poolKey.currency0,          // Output = currency0
                (-amount1).toUint256(),            // Negate and convert
                amount0.toUint256()                // Already positive
            );

        // 5. Slippage protection - ensure minimum output received
        require(amountOut >= params.amountOutMin, "amount out < min");

        // 6. Withdraw output tokens to original caller
        poolManager.take({
            currency: currencyOut,
            to: msgSender,
            amount: amountOut
        });

        // 7. Sync PoolManager's balance tracking
        poolManager.sync(currencyIn);

        // 8. Settle input tokens (pay for the swap)
        if (currencyIn == address(0)) {
            // Native ETH: send with value
            poolManager.settle{value: amountIn}();
        } else {
            // ERC20: transfer then settle
            IERC20(currencyIn).transfer(address(poolManager), amountIn);
            poolManager.settle();
        }

        // 9. Return empty bytes
        return "";
    }

    /// @notice Execute an exact input single hop swap
    /// @param params Swap parameters including pool, direction, and amounts
    /// @dev User calls this function to initiate a swap
    function swap(SwapExactInputSingleHop calldata params) external payable {
        // 1. Determine which token is being swapped in
        address currencyIn = params.zeroForOne
            ? params.poolKey.currency0
            : params.poolKey.currency1;

        // 2. Transfer input tokens from user to this contract
        // For ETH: already received via msg.value
        // For ERC20: transferFrom user to this contract
        currencyIn.transferIn(msg.sender, uint256(params.amountIn));
        
        // 3. Trigger swap via PoolManager unlock mechanism
        // Encodes both the caller and params for the callback
        poolManager.unlock(abi.encode(msg.sender, params));

        // 4. Refund any excess input tokens
        // Can happen with ETH or in edge cases
        uint256 bal = currencyIn.balanceOf(address(this));
        if (bal > 0) {
            currencyIn.transferOut(msg.sender, bal);
        }
    }
}
```

## Real-World Usage Examples

### Example 1: Basic Token Swap

```solidity
// Swap 1000 USDC for DAI with 1% slippage tolerance
SwapExactInputSingleHop memory swapParams = SwapExactInputSingleHop({
    poolKey: PoolKey({
        currency0: USDC_ADDRESS,
        currency1: DAI_ADDRESS,
        fee: 3000,              // 0.3% fee
        tickSpacing: 60,
        hooks: IHooks(address(0))
    }),
    zeroForOne: true,           // USDC (0) → DAI (1)
    amountIn: 1000e6,          // 1000 USDC (6 decimals)
    amountOutMin: 990e18       // Minimum 990 DAI (1% slippage)
});

// Approve Swap contract to spend USDC
IERC20(USDC_ADDRESS).approve(address(swapContract), 1000e6);

// Execute swap
swapContract.swap(swapParams);
```

### Example 2: ETH to Token Swap

```solidity
// Swap 1 ETH for USDC
SwapExactInputSingleHop memory swapParams = SwapExactInputSingleHop({
    poolKey: PoolKey({
        currency0: address(0),  // ETH
        currency1: USDC_ADDRESS,
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(address(0))
    }),
    zeroForOne: true,           // ETH (0) → USDC (1)
    amountIn: 1 ether,         // 1 ETH
    amountOutMin: 2000e6       // Minimum 2000 USDC
});

// Execute swap with ETH
swapContract.swap{value: 1 ether}(swapParams);
```

### Example 3: Reverse Swap Direction

```solidity
// Swap DAI back to USDC (reverse direction)
SwapExactInputSingleHop memory swapParams = SwapExactInputSingleHop({
    poolKey: PoolKey({
        currency0: USDC_ADDRESS,
        currency1: DAI_ADDRESS,
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(address(0))
    }),
    zeroForOne: false,          // DAI (1) → USDC (0) ← Note: false!
    amountIn: 1000e18,         // 1000 DAI (18 decimals)
    amountOutMin: 990e6        // Minimum 990 USDC
});

IERC20(DAI_ADDRESS).approve(address(swapContract), 1000e18);
swapContract.swap(swapParams);
```

## Common Pitfalls and How to Avoid Them

### 1. Wrong Swap Direction

**Problem**:
```solidity
// Pool: USDC (currency0) / DAI (currency1)
// Want to swap DAI → USDC, but set zeroForOne = true ❌
```

**Solution**: Always verify:
- `zeroForOne = true`: currency0 → currency1
- `zeroForOne = false`: currency1 → currency0

### 2. Insufficient Slippage Protection

**Problem**:
```solidity
amountOutMin: 0  // ❌ Accepts any output!
```

**Solution**:
```solidity
// Calculate minimum with slippage tolerance
uint256 expectedOut = quoteSwap(amountIn);
uint256 slippage = 100;  // 1% = 100 basis points
amountOutMin: (expectedOut * (10000 - slippage)) / 10000
```

### 3. Decimal Mismatch

**Problem**:
```solidity
// USDC has 6 decimals, but using 18
amountIn: 1000e18  // ❌ Wrong!
```

**Solution**:
```solidity
// Check token decimals first
uint8 decimals = IERC20(token).decimals();
amountIn: 1000 * 10**decimals  // ✅ Correct
```

### 4. Not Approving Tokens

**Problem**:
```solidity
// Forgot to approve ❌
swapContract.swap(params);  // Will revert!
```

**Solution**:
```solidity
// Always approve before swap ✅
IERC20(tokenIn).approve(address(swapContract), amountIn);
swapContract.swap(params);
```

### 5. Using Wrong Pool

**Problem**:
```solidity
// Pool exists for DAI/USDT but trying to swap DAI/USDC ❌
```

**Solution**: Verify pool exists and is initialized:
```solidity
(uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
require(sqrtPriceX96 != 0, "Pool not initialized");
```

## Troubleshooting Guide

| Error | Possible Cause | Solution |
|-------|---------------|----------|
| "not pool manager" | Direct callback call | Always use `swap()` to initiate |
| "amount out < min" | Slippage exceeded | Increase slippage tolerance or split trade |
| "Insufficient balance" | Not enough input tokens | Check balance before swap |
| "STF" (Safe Transfer Failed) | Missing approval | Approve Swap contract first |
| Transaction reverts silently | Pool not initialized | Verify pool exists |
| "Price limit exceeded" | sqrtPriceLimitX96 too tight | Use wider bounds or update price |

## Gas Optimization Tips

1. **Use `calldata` for parameters**: Already implemented ✅
2. **Minimize storage reads**: Use `immutable` for poolManager ✅
3. **Avoid unnecessary checks**: Only refund if balance > 0 ✅
4. **Batch swaps**: If doing multiple swaps, use a multi-hop contract
5. **Reuse PoolKey**: Pass same PoolKey object for multiple swaps

## Security Considerations

### Access Control ✅

```solidity
modifier onlyPoolManager() {
    require(msg.sender == address(poolManager), "not pool manager");
    _;
}
```

**Prevents**: Unauthorized callback execution

### Slippage Protection ✅

```solidity
require(amountOut >= params.amountOutMin, "amount out < min");
```

**Prevents**: Unfavorable trade execution

### Atomic Execution ✅

**Benefit**: All-or-nothing swap (no partial states)

### Potential Vulnerabilities

#### 1. Front-Running

**Risk**: MEV bots see your transaction and trade before you

**Mitigation**:
- Use private mempools (e.g., Flashbots)
- Set tight slippage bounds
- Use limit orders instead

#### 2. Sandwich Attacks

**Risk**: Attacker trades before and after your swap to profit from price impact

**Mitigation**:
- Set reasonable `amountOutMin`
- Use sqrtPriceLimitX96 bounds
- Split large trades

#### 3. Reentrancy

**Status**: ✅ Protected by PoolManager lock mechanism

## Comparison: V3 vs V4 Swaps

| Feature | Uniswap V3 | Uniswap V4 |
|---------|------------|------------|
| **Architecture** | Separate Router contract | Direct PoolManager integration |
| **Callback Pattern** | Router handles everything | User contract implements callback |
| **Gas Cost** | Higher (Router overhead) | Lower (Direct interaction) |
| **Flexibility** | Limited to Router features | Full customization via callbacks |
| **ETH Support** | Through WETH wrapper | Native ETH supported |
| **Multi-hop** | Built into Router | Requires custom implementation |
| **Hooks** | Not available | Can customize swap behavior |

## Additional Resources

- [Uniswap V4 Documentation](https://docs.uniswap.org/contracts/v4/overview)
- [Understanding sqrtPriceX96](https://docs.uniswap.org/sdk/guides/fetching-prices)
- [BalanceDelta Type](https://github.com/Uniswap/v4-core/blob/main/src/types/BalanceDelta.sol)
- [SafeCast Library](https://github.com/Uniswap/v4-core/blob/main/src/libraries/SafeCast.sol)
- [Cyfrin Updraft Course](https://updraft.cyfrin.io/)

## Frequently Asked Questions

### Q1: Why use negative amountSpecified for exact input swaps?

**A:** Uniswap V4 uses signed integers to indicate direction. Negative means you're specifying the exact **input** amount, while positive means you're specifying the exact **output** amount. This allows one function to handle both swap types.

### Q2: What's the difference between `take()` and `settle()`?

**A:**
- **`take()`**: Withdraw tokens FROM PoolManager (receive output tokens)
- **`settle()`**: Send tokens TO PoolManager (pay input tokens)

Both create debt that must be balanced before unlocking.

### Q3: Can I perform multi-hop swaps with this contract?

**A:** No, this contract only supports single-hop (direct) swaps. For multi-hop swaps (e.g., USDC → ETH → DAI), you'd need to implement multiple swap calls in sequence within the callback.

### Q4: How do I calculate the optimal amountOutMin?

**A:** 
```solidity
// 1. Get quote for expected output
uint256 expectedOut = quoter.quote(amountIn, poolKey, zeroForOne);

// 2. Apply slippage tolerance (e.g., 0.5%)
uint256 slippageBps = 50;  // 0.5% = 50 basis points
uint256 amountOutMin = (expectedOut * (10000 - slippageBps)) / 10000;
```

### Q5: What happens if the pool doesn't have enough liquidity?

**A:** The swap will execute with higher price impact. If the resulting `amountOut` is below `amountOutMin`, the transaction reverts with "amount out < min". Consider splitting large trades into smaller chunks.

### Q6: Can I use this contract with any Uniswap V4 pool?

**A:** Yes, as long as the pool is initialized and you provide the correct `PoolKey`. The contract works with any fee tier and tick spacing.

### Q7: How do hooks affect swaps?

**A:** If a pool has hooks enabled, they can:
- Modify swap amounts (via `beforeSwap` and `afterSwap` hooks)
- Charge additional fees
- Block swaps under certain conditions
- Execute custom logic before/after swaps

Always review a pool's hook implementation before swapping.

### Q8: Is there a difference between swapping ETH and WETH?

**A:** In V4, native ETH (address(0)) is supported directly. You don't need to wrap/unwrap WETH. However, some pools might use WETH as a token. Check the pool's currencies:
- `currency0 = address(0)`: Native ETH
- `currency0 = WETH_ADDRESS`: Wrapped ETH

### Q9: What's the maximum price impact I can have?

**A:** By setting `sqrtPriceLimitX96` to MIN/MAX bounds (±1), you allow unlimited price impact. In production, calculate reasonable bounds based on:
- Pool liquidity
- Trade size
- Acceptable slippage
- Market conditions

### Q10: Can this contract handle tokens with transfer fees?

**A:** Not directly. Tokens with transfer fees (like some deflationary tokens) will cause accounting mismatches. The contract assumes the full `amountIn` reaches the PoolManager, but transfer fees reduce this. Special handling is required for such tokens.

## Conclusion

This guide has covered the complete implementation of token swaps in Uniswap V4, from basic concepts to production considerations. Key takeaways:

✅ **Atomic Execution**: All operations happen in one transaction via unlock/callback pattern  
✅ **Exact Input**: Use negative `amountSpecified` to trade exact input amount  
✅ **Slippage Protection**: Set `amountOutMin` to protect against unfavorable execution  
✅ **BalanceDelta**: Understand signed integers to interpret swap results  
✅ **Native ETH Support**: No need for WETH wrapping/unwrapping  

**Next Steps**:
1. Implement multi-hop swaps for indirect token pairs
2. Add exact output swap functionality
3. Integrate with quoter for better price estimates
4. Build UI for user-friendly swap experience
5. Conduct thorough testing and security audits

**Remember**: Always test on testnets first, start with small amounts, and never ignore slippage protection in production!
