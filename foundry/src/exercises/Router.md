# Uniswap V4 Router - Complete Technical Guide

## Introduction

This document provides an in-depth technical explanation of the `Router.sol` contract, a sophisticated routing system that enables both single-hop and multi-hop token swaps with support for exact input and exact output modes. Unlike the simple `Swap.sol` contract which only handles single-hop exact input swaps, the Router adds crucial functionality needed for real-world DeFi applications.

The starter code for this exercise is provided in [`foundry/src/exercises/Router.sol`](https://github.com/Cyfrin/defi-uniswap-v4/blob/main/foundry/src/exercises/Router.sol)

Solution is in [`foundry/src/solutions/Router.sol`](https://github.com/Cyfrin/defi-uniswap-v4/blob/main/foundry/src/solutions/Router.sol)

### What You'll Learn

- How to implement a flexible routing system for Uniswap V4
- The difference between Exact Input and Exact Output swaps in both single and multi-hop scenarios
- How to chain multiple swaps together (multi-hop routing)
- Managing action types using the TStore pattern
- Advanced slippage protection for complex swap paths
- How to handle token accounting across multiple pool interactions

### Key Concepts

**Router Contract**: A smart contract that orchestrates complex swap operations, including chaining multiple pools together for optimal trading paths.

**Single-Hop Swap**: A direct swap between two tokens using one liquidity pool (e.g., USDC → DAI).

**Multi-Hop Swap**: A swap that routes through multiple pools to exchange tokens that don't have a direct liquidity pool (e.g., USDC → ETH → WBTC).

**Exact Input**: You specify exactly how much you want to give; the output amount varies based on pool prices.

**Exact Output**: You specify exactly how much you want to receive; the input amount varies based on pool prices.

**Action Types**: Different swap modes identified by constants (SWAP_EXACT_IN_SINGLE, SWAP_EXACT_OUT, etc.) that determine how the router processes the swap.

**Path**: An ordered sequence of pools and intermediate tokens that defines the route a multi-hop swap will take.

## Contract Overview

The `Router.sol` contract is a comprehensive routing solution for Uniswap V4 that supports four distinct swap modes across both single and multi-hop scenarios. This is a more advanced implementation compared to the basic Swap contract.

### Core Features

| Feature | Description |
|---------|-------------|
| **Four Swap Modes** | Exact Input Single, Exact Output Single, Exact Input Multi-hop, Exact Output Multi-hop |
| **Multi-Hop Routing** | Chain multiple swaps across different pools in a single transaction |
| **Action Dispatcher** | Uses TStore pattern to track which swap mode is being executed |
| **Flexible Slippage Protection** | Set min/max amounts for both single and multi-hop swaps |
| **Hook Support** | Each swap can include custom hook data for pool customization |
| **Optimized Settlement** | Settles only net amounts after all swaps complete |
| **Native ETH Support** | Seamlessly handles both native ETH and ERC20 tokens |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Architecture Pattern**: Action-based callback system with TStore state management
- **Inheritance**: `TStore` (for action tracking), `IUnlockCallback` (for PoolManager integration)
- **Swap Types**: 4 modes (2 single-hop + 2 multi-hop)
- **Swap Fees**: Determined by each pool in the path (can vary across hops)

### Comparison: Swap.sol vs Router.sol

| Aspect | Swap.sol | Router.sol |
|--------|----------|------------|
| **Swap Types** | Exact Input only | Exact Input & Exact Output |
| **Hop Support** | Single-hop only | Single-hop & Multi-hop |
| **Complexity** | Simple, educational | Production-ready, comprehensive |
| **Action Types** | None (single mode) | 4 distinct action types |
| **Path Handling** | N/A | Full path management with PathKey |
| **Use Case** | Learning & simple swaps | Real-world DeFi routing |
| **State Management** | None | TStore for action tracking |

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
import {TStore} from "../TStore.sol";
```

| Interface/Library | Purpose | Key Usage in Router |
|-------------------|---------|---------------------|
| `IERC20` | ERC20 token operations | Transfer tokens to/from PoolManager |
| `IPoolManager` | Central coordinator | `swap()`, `take()`, `settle()`, `sync()`, `unlock()` |
| `IUnlockCallback` | Callback interface | `unlockCallback()` - Handles all 4 action types |
| `PoolKey` | Pool identification | Identifies each pool in single/multi-hop swaps |
| `SwapParams` | Swap configuration | Parameters for each `poolManager.swap()` call |
| `BalanceDelta` | Balance change tracking | Extract amount0/amount1 from each swap |
| `SafeCast` | Type conversions | Convert between int128, uint128, int256, uint256 |
| `CurrencyLib` | Currency utilities | `transferIn()`, `transferOut()`, `balanceOf()` |
| `TStore` | **Action state management** | **Store/retrieve current action type** |

#### What is TStore?

`TStore` is a base contract that provides transient storage for tracking the current action type being executed. This is crucial because the Router needs to know which of the 4 swap modes is active when `unlockCallback()` is invoked.

**TStore Pattern**:
```solidity
contract TStore {
    // Transient storage slot for action
    bytes32 private constant ACTION_SLOT = keccak256("action");
    
    // Store action type before unlock
    modifier setAction(uint256 action) {
        _setAction(action);
        _;
    }
    
    // Retrieve action type in callback
    function _getAction() internal view returns (uint256) {
        // Read from transient storage
    }
}
```

**Why Needed?**: When `poolManager.unlock()` calls back to `unlockCallback()`, the router needs to know which function initiated the call (swapExactInputSingle vs swapExactOutput, etc.) to execute the correct logic.

### State Variables

```solidity
// Action type constants
uint256 private constant SWAP_EXACT_IN_SINGLE = 0x06;
uint256 private constant SWAP_EXACT_IN = 0x07;
uint256 private constant SWAP_EXACT_OUT_SINGLE = 0x08;
uint256 private constant SWAP_EXACT_OUT = 0x09;

// PoolManager reference
IPoolManager public immutable poolManager;
```

| Variable | Type | Purpose |
|----------|------|---------|
| `SWAP_EXACT_IN_SINGLE` | `uint256` | Action ID for single-hop exact input swaps |
| `SWAP_EXACT_IN` | `uint256` | Action ID for multi-hop exact input swaps |
| `SWAP_EXACT_OUT_SINGLE` | `uint256` | Action ID for single-hop exact output swaps |
| `SWAP_EXACT_OUT` | `uint256` | Action ID for multi-hop exact output swaps |
| `poolManager` | `IPoolManager` | Reference to Uniswap V4's PoolManager |

**Action Constants Explained**:

These constants identify which swap mode is being executed. The values (0x06-0x09) are arbitrary but must be unique.

```solidity
// User calls swapExactInputSingle()
//   ↓
// setAction(SWAP_EXACT_IN_SINGLE) stores 0x06
//   ↓
// poolManager.unlock() triggers callback
//   ↓
// unlockCallback() calls _getAction() → returns 0x06
//   ↓
// Router knows to execute SWAP_EXACT_IN_SINGLE logic
```

### Custom Structs

The Router defines several structs to organize parameters for different swap types:

#### 1. ExactInputSingleParams

```solidity
struct ExactInputSingleParams {
    PoolKey poolKey;      // Identifies the pool to use
    bool zeroForOne;      // Swap direction
    uint128 amountIn;     // Exact input amount
    uint128 amountOutMin; // Minimum acceptable output (slippage protection)
    bytes hookData;       // Custom data for pool hooks
}
```

**Purpose**: Parameters for single-hop exact input swaps.

**New Field**: `hookData` allows passing custom data to pool hooks (not present in Swap.sol).

#### 2. ExactOutputSingleParams

```solidity
struct ExactOutputSingleParams {
    PoolKey poolKey;      // Identifies the pool to use
    bool zeroForOne;      // Swap direction
    uint128 amountOut;    // Exact output amount desired
    uint128 amountInMax;  // Maximum acceptable input (slippage protection)
    bytes hookData;       // Custom data for pool hooks
}
```

**Purpose**: Parameters for single-hop exact output swaps.

**Key Difference from ExactInput**:
- `amountOut` instead of `amountIn` - you specify what you want to receive
- `amountInMax` instead of `amountOutMin` - protection is on the input side

#### 3. PathKey

```solidity
struct PathKey {
    address currency;     // Next currency in the path
    uint24 fee;          // Pool fee tier (e.g., 500 = 0.05%)
    int24 tickSpacing;   // Pool tick spacing
    address hooks;       // Hook contract address
    bytes hookData;      // Custom data for this hop's hooks
}
```

**Purpose**: Defines one step (hop) in a multi-hop swap path.

**How Multi-Hop Works**:

```solidity
// Example: USDC → ETH → WBTC
PathKey[] memory path = new PathKey[](2);

// Hop 1: USDC → ETH
path[0] = PathKey({
    currency: ETH_ADDRESS,    // Next currency is ETH
    fee: 3000,               // 0.3% fee pool
    tickSpacing: 60,
    hooks: address(0),
    hookData: ""
});

// Hop 2: ETH → WBTC
path[1] = PathKey({
    currency: WBTC_ADDRESS,   // Final currency is WBTC
    fee: 3000,
    tickSpacing: 60,
    hooks: address(0),
    hookData: ""
});

// Starting currency (USDC) is specified separately in ExactInputParams.currencyIn
```

**Path Construction Logic**:

For each hop `i`:
- **Previous currency**: Either `currencyIn` (if first hop) or `path[i-1].currency`
- **Next currency**: `path[i].currency`
- **Pool**: Determined by (previous currency, next currency, fee, tickSpacing, hooks)

#### 4. ExactInputParams (Multi-Hop)

```solidity
struct ExactInputParams {
    address currencyIn;      // Starting currency
    PathKey[] path;          // Array of hops to execute
    uint128 amountIn;        // Exact input amount
    uint128 amountOutMin;    // Minimum final output (slippage protection)
}
```

**Purpose**: Parameters for multi-hop exact input swaps.

**Example Usage**:
```solidity
// Swap exactly 1000 USDC through ETH to get WBTC
ExactInputParams({
    currencyIn: USDC,        // Start with USDC
    path: [
        PathKey({currency: ETH, ...}),   // USDC → ETH
        PathKey({currency: WBTC, ...})   // ETH → WBTC
    ],
    amountIn: 1000e6,        // Exactly 1000 USDC
    amountOutMin: 0.001e8    // At least 0.001 WBTC
})
```

#### 5. ExactOutputParams (Multi-Hop)

```solidity
struct ExactOutputParams {
    address currencyOut;     // Final currency desired
    PathKey[] path;          // Array of hops (executed in REVERSE)
    uint128 amountOut;       // Exact output amount desired
    uint128 amountInMax;     // Maximum input willing to pay
}
```

**Purpose**: Parameters for multi-hop exact output swaps.

**Critical Difference**: For exact output, the path is traversed **backwards**!

**Why Backwards?**

```solidity
// Want exactly 0.001 WBTC, starting from USDC
// Need to work backwards: WBTC ← ETH ← USDC

// Path defines the FORWARD direction
path[0] = PathKey({currency: ETH, ...});    // USDC → ETH
path[1] = PathKey({currency: WBTC, ...});   // ETH → WBTC

// But execution works BACKWARDS:
// 1. Calculate: need X ETH to get 0.001 WBTC
// 2. Calculate: need Y USDC to get X ETH
// 3. Result: need Y USDC input
```

This is necessary because with exact output, you know the final amount but need to calculate backwards to determine the required input.

### Custom Error

```solidity
error UnsupportedAction(uint256 action);
```

**When Thrown**: If `unlockCallback()` receives an unknown action type.

**Purpose**: Fail-safe to catch programming errors where an invalid action is set.

### Access Control

```solidity
modifier onlyPoolManager() {
    require(msg.sender == address(poolManager), "not pool manager");
    _;
}
```

**Purpose**: Ensures only the PoolManager can invoke `unlockCallback()`.

**Security**: Critical modifier preventing unauthorized callback execution.

### Constructor and Receiver

```solidity
constructor(address _poolManager) {
    poolManager = IPoolManager(_poolManager);
}

receive() external payable {}
```

**Constructor**: Initializes the immutable poolManager reference.

**receive()**: Allows the contract to receive native ETH for ETH swaps.

---

## SWAP_EXACT_IN_SINGLE: Single-Hop Exact Input Swaps

This section covers the most straightforward swap mode: trading an exact amount of one token for another in a single pool.

### Function: `swapExactInputSingle()`

**Contract**: `Router.sol`  
**Visibility**: `external payable`  
**Modifier**: `setAction(SWAP_EXACT_IN_SINGLE)`  
**Returns**: `uint256 amountOut`

**Purpose**: Entry point for users to execute a single-hop swap with exact input amount.

#### Complete Function Code

```solidity
function swapExactInputSingle(ExactInputSingleParams calldata params)
    external
    payable
    setAction(SWAP_EXACT_IN_SINGLE)
    returns (uint256 amountOut)
{
    // 1. Determine input currency based on swap direction
    address currencyIn = params.zeroForOne 
        ? params.poolKey.currency0 
        : params.poolKey.currency1;

    // 2. Transfer input tokens from caller to router
    currencyIn.transferIn(msg.sender, params.amountIn);

    // 3. Unlock PoolManager and trigger callback
    bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
    amountOut = abi.decode(res, (uint256));

    // 4. Refund any remaining input tokens
    if (currencyIn.balanceOf(address(this)) > 0) {
        currencyIn.transferOut(msg.sender, currencyIn.balanceOf(address(this)));
    }
}
```

### Execution Flow: SWAP_EXACT_IN_SINGLE

```
┌─────────────┐         ┌──────────────┐         ┌────────────────┐
│   User/EOA  │         │  Router.sol  │         │  PoolManager   │
└──────┬──────┘         └──────┬───────┘         └───────┬────────┘
       │                       │                         │
       │ 1. swapExactInputSingle(params)                 │
       │──────────────────────>│                         │
       │                       │                         │
       │                       │ [setAction(0x06)]       │
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
       │                       │   [action = 0x06]       │
       │                       │                         │
       │                       │  6. _swap()             │
       │                       │────────────────────────>│
       │                       │<──── delta ─────────────│
       │                       │                         │
       │                       │  7. _takeAndSettle()    │
       │                       │    - take(tokenOut)     │
       │                       │    - sync(tokenIn)      │
       │                       │    - settle(tokenIn)    │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │  8. return amountOut    │
       │                       │<────────────────────────│
       │                       │                         │
       │                       │  9. [UNLOCK STATE]      │
       │                       │                         │
       │<─ 10. refund excess ──│                         │
       │   amountOut returned  │                         │
```

### Step-by-Step Breakdown

#### Step 1: Determine Input Currency

```solidity
address currencyIn = params.zeroForOne 
    ? params.poolKey.currency0 
    : params.poolKey.currency1;
```

**Logic**: Same as in Swap.sol
- If `zeroForOne = true`: Trading currency0 → currency1, so input is currency0
- If `zeroForOne = false`: Trading currency1 → currency0, so input is currency1

**Example**:
```solidity
// Pool: USDC (currency0) / DAI (currency1)
// Swap 1000 USDC for DAI

params.zeroForOne = true;
currencyIn = currency0;  // USDC
// Output will be currency1 (DAI), determined in callback
```

#### Step 2: Transfer Input Tokens

```solidity
currencyIn.transferIn(msg.sender, params.amountIn);
```

**Purpose**: Move tokens from user to Router before initiating the swap.

**CurrencyLib.transferIn()** (review from Swap.md):
```solidity
function transferIn(address currency, address from, uint256 amount) internal {
    if (currency == address(0)) {
        // Native ETH: already received via msg.value
        require(msg.value >= amount, "Insufficient ETH");
    } else {
        // ERC20: requires prior approval
        IERC20(currency).transferFrom(from, address(this), amount);
    }
}
```

**Important**: User must approve Router to spend tokens before calling this function.

```solidity
// Before calling swapExactInputSingle
IERC20(USDC).approve(address(router), 1000e6);

// Now safe to call
router.swapExactInputSingle(params);
```

#### Step 3: Set Action and Unlock

```solidity
setAction(SWAP_EXACT_IN_SINGLE)  // Modifier sets action to 0x06
```

The `setAction` modifier (from TStore) stores the action type before proceeding:

```solidity
modifier setAction(uint256 action) {
    _setAction(action);  // Store 0x06 in transient storage
    _;                   // Continue to function body
}
```

**Why This Matters**: When `unlockCallback()` is invoked, it needs to know which swap mode to execute.

```solidity
bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
amountOut = abi.decode(res, (uint256));
```

**What's Encoded**:
```solidity
abi.encode(msg.sender, params)
// Encodes:
// - address: original caller (where to send output)
// - ExactInputSingleParams: all swap parameters
```

**unlock() Behavior**:
1. PoolManager enters locked state
2. Calls `unlockCallback(data)` on Router
3. Router executes swap logic (see next section)
4. PoolManager verifies debts are settled
5. Returns to unlocked state
6. Returns response data

**Return Value**: The `amountOut` (how much output token was received).

#### Step 4: Refund Excess Tokens

```solidity
if (currencyIn.balanceOf(address(this)) > 0) {
    currencyIn.transferOut(msg.sender, currencyIn.balanceOf(address(this)));
}
```

**Why Needed**:
- For native ETH: User might send more than required via `msg.value`
- Edge cases: Rounding or unusual pool behavior
- Good practice: Always return leftover tokens

**Note**: In most ERC20 swaps, this balance will be zero since we transfer exactly `params.amountIn`.

### Callback: `unlockCallback()` - SWAP_EXACT_IN_SINGLE Branch

When `poolManager.unlock()` calls back, the Router's `unlockCallback()` function executes with `action = SWAP_EXACT_IN_SINGLE`.

#### Callback Code for SWAP_EXACT_IN_SINGLE

```solidity
function unlockCallback(bytes calldata data)
    external
    onlyPoolManager
    returns (bytes memory)
{
    uint256 action = _getAction();  // Retrieves 0x06
    
    if (action == SWAP_EXACT_IN_SINGLE) {
        // 1. Decode parameters
        (address caller, ExactInputSingleParams memory params) = 
            abi.decode(data, (address, ExactInputSingleParams));
        
        // 2. Execute the swap
        (int128 amount0, int128 amount1) = _swap({
            zeroForOne: params.zeroForOne,
            poolKey: params.poolKey,
            amountSpecified: -(params.amountIn.toInt256()),  // Negative = exact input
            hookData: params.hookData
        });

        // 3. Determine currencies and amounts based on direction
        (
            address currencyIn,
            address currencyOut,
            uint256 amountIn,
            uint256 amountOut
        ) = params.zeroForOne
            ? (
                params.poolKey.currency0,
                params.poolKey.currency1,
                (-amount0).toUint256(),  // Negate negative to get positive
                amount1.toUint256()      // Already positive
            )
            : (
                params.poolKey.currency1,
                params.poolKey.currency0,
                (-amount1).toUint256(),
                amount0.toUint256()
            );

        // 4. Slippage protection
        require(amountOut >= params.amountOutMin, "insufficient output amount");

        // 5. Finalize swap
        _takeAndSettle({
            caller: caller,
            currencyIn: currencyIn,
            amountIn: amountIn,
            currencyOut: currencyOut,
            amountOut: amountOut
        });

        // 6. Return result
        return abi.encode(amountOut);
    }
    
    // ... other action types ...
}
```

### Callback Step-by-Step

#### Callback Step 1: Retrieve Action

```solidity
uint256 action = _getAction();  // Returns 0x06 (SWAP_EXACT_IN_SINGLE)
```

This reads from the transient storage set by the `setAction` modifier.

#### Callback Step 2: Decode Parameters

```solidity
(address caller, ExactInputSingleParams memory params) = 
    abi.decode(data, (address, ExactInputSingleParams));
```

**Extracts**:
- `caller`: Original user address (where to send output tokens)
- `params`: All swap parameters (poolKey, direction, amounts, etc.)

#### Callback Step 3: Execute Swap via `_swap()`

```solidity
(int128 amount0, int128 amount1) = _swap({
    zeroForOne: params.zeroForOne,
    poolKey: params.poolKey,
    amountSpecified: -(params.amountIn.toInt256()),
    hookData: params.hookData
});
```

**The _swap() Helper Function**:

```solidity
function _swap(
    bool zeroForOne,
    PoolKey memory poolKey,
    int256 amountSpecified,
    bytes memory hookData
) internal returns (int128, int128) {
    SwapParams memory swapParams = SwapParams({
        zeroForOne: zeroForOne,
        amountSpecified: amountSpecified,
        sqrtPriceLimitX96: zeroForOne 
            ? MIN_SQRT_PRICE + 1 
            : MAX_SQRT_PRICE - 1
    });
    
    int256 d = poolManager.swap(poolKey, swapParams, hookData);
    BalanceDelta delta = BalanceDelta.wrap(d);
    
    return (delta.amount0(), delta.amount1());
}
```

**Key Point**: `amountSpecified: -(params.amountIn.toInt256())`

The **negative sign** indicates **exact input**:
- Negative: "I'm giving exactly this amount, calculate output"
- Positive: "I want exactly this output, calculate required input"

**Example**:
```solidity
params.amountIn = 1000e6;                    // 1000 USDC
params.amountIn.toInt256() = +1000000000;   // Positive int256
-(params.amountIn.toInt256()) = -1000000000; // Negative = exact input

// Tells pool: "User is giving exactly 1000 USDC, calculate DAI output"
```

**Return Value**: The balance delta (amount0, amount1) from the swap:
- **Negative value**: Tokens paid (input)
- **Positive value**: Tokens received (output)

#### Callback Step 4: Map Amounts to Currencies

```solidity
(
    address currencyIn,
    address currencyOut,
    uint256 amountIn,
    uint256 amountOut
) = params.zeroForOne
    ? (
        params.poolKey.currency0,      // Input
        params.poolKey.currency1,      // Output
        (-amount0).toUint256(),        // Make positive
        amount1.toUint256()
    )
    : (
        params.poolKey.currency1,
        params.poolKey.currency0,
        (-amount1).toUint256(),
        amount0.toUint256()
    );
```

**Why This Mapping?**

The swap returns (amount0, amount1) but we need to know:
1. Which is input and which is output?
2. How much of each?

**Case 1: zeroForOne = true** (currency0 → currency1)
```solidity
// Swap USDC (currency0) → DAI (currency1)
amount0 = -1000e6;  // Negative = paid 1000 USDC
amount1 = +995e18;  // Positive = received 995 DAI

// After mapping:
currencyIn  = currency0;         // USDC
currencyOut = currency1;         // DAI
amountIn    = 1000e6;           // Made positive
amountOut   = 995e18;
```

**Case 2: zeroForOne = false** (currency1 → currency0)
```solidity
// Swap DAI (currency1) → USDC (currency0)
amount0 = +995e6;   // Positive = received 995 USDC
amount1 = -1000e18; // Negative = paid 1000 DAI

// After mapping:
currencyIn  = currency1;         // DAI
currencyOut = currency0;         // USDC
amountIn    = 1000e18;          // Made positive
amountOut   = 995e6;
```

#### Callback Step 5: Slippage Protection

```solidity
require(amountOut >= params.amountOutMin, "insufficient output amount");
```

**Purpose**: Ensure the swap provided at least the minimum acceptable output.

**Example**:
```solidity
// User expects ~995 DAI but willing to accept 985 DAI (1% slippage)
params.amountOutMin = 985e18;

// If swap returns:
amountOut = 995e18;  // ✅ PASS: 995 >= 985
amountOut = 980e18;  // ❌ FAIL: 980 < 985, transaction reverts
```

**Why This Matters**: Protects against:
- Front-running attacks
- High price impact
- Unexpected market movements between transaction submission and execution

#### Callback Step 6: Finalize with `_takeAndSettle()`

```solidity
_takeAndSettle({
    caller: caller,
    currencyIn: currencyIn,
    amountIn: amountIn,
    currencyOut: currencyOut,
    amountOut: amountOut
});
```

**The _takeAndSettle() Helper Function**:

```solidity
function _takeAndSettle(
    address caller,
    uint256 amountIn,
    address currencyIn,
    address currencyOut,
    uint256 amountOut
) internal {
    // 1. Withdraw output tokens to user
    poolManager.take(currencyOut, caller, amountOut);

    // 2. Sync input currency balance
    poolManager.sync(currencyIn);

    // 3. Settle input tokens
    if (currencyIn == address(0)) {
        // Native ETH
        poolManager.settle{value: amountIn}();
    } else {
        // ERC20
        IERC20(currencyIn).transfer(address(poolManager), amountIn);
        poolManager.settle();
    }
}
```

**What Each Step Does**:

**1. take() - Withdraw Output**:
```solidity
poolManager.take(currencyOut, caller, amountOut);
```
- Transfers output tokens FROM PoolManager TO user
- Creates a debt in PoolManager's accounting
- User receives their swapped tokens directly

**2. sync() - Prepare for Settlement**:
```solidity
poolManager.sync(currencyIn);
```
- Records PoolManager's current balance of input currency
- Prepares for incoming token transfer
- Used to detect the balance change in settle()

**3. settle() - Pay Input**:
```solidity
if (currencyIn == address(0)) {
    poolManager.settle{value: amountIn}();  // Send ETH
} else {
    IERC20(currencyIn).transfer(address(poolManager), amountIn);
    poolManager.settle();  // Update accounting
}
```
- Transfers input tokens FROM Router TO PoolManager
- Clears the debt created by take()
- Net result: User's input is now in the pool

**Accounting Balance**:
```
Before take:     debt = 0
After take:      debt = +amountOut (owe user)
After settle:    debt = +amountOut - amountIn
                      ≈ 0 (pool earns small fee)
```

#### Callback Step 7: Return Result

```solidity
return abi.encode(amountOut);
```

**Purpose**: Return the output amount to the calling function.

**Flow**:
```solidity
// In swapExactInputSingle():
bytes memory res = poolManager.unlock(...);  // Triggers callback
amountOut = abi.decode(res, (uint256));      // Decode returned value
return amountOut;                             // Return to user
```

### Complete Example: ETH → USDC Swap

Let's trace a complete swap from start to finish:

**Setup**:
```solidity
// User wants to swap 1 ETH for USDC
// Pool: ETH (currency0) / USDC (currency1)
// Current price: 1 ETH = 2500 USDC
// Pool fee: 0.3%
```

**Step 1: User Calls Function**:
```solidity
router.swapExactInputSingle{value: 1 ether}(
    ExactInputSingleParams({
        poolKey: PoolKey({
            currency0: address(0),      // ETH
            currency1: USDC_ADDRESS,    // USDC
            fee: 3000,                  // 0.3%
            tickSpacing: 60,
            hooks: address(0)
        }),
        zeroForOne: true,               // ETH → USDC
        amountIn: 1 ether,             // 1 ETH exactly
        amountOutMin: 2475e6,          // Minimum 2475 USDC (1% slippage)
        hookData: ""
    })
);
```

**Step 2: Router Determines Input**:
```solidity
currencyIn = params.zeroForOne ? currency0 : currency1;
// currencyIn = address(0) (ETH)
```

**Step 3: Transfer Input** (ETH already received via msg.value):
```solidity
currencyIn.transferIn(msg.sender, 1 ether);
// For ETH, this just validates msg.value >= 1 ether
```

**Step 4: Set Action and Unlock**:
```solidity
setAction(SWAP_EXACT_IN_SINGLE);  // Stores 0x06
poolManager.unlock(abi.encode(msg.sender, params));
```

**Step 5: Callback Executes**:
```solidity
action = _getAction();  // Returns 0x06
// Branches to SWAP_EXACT_IN_SINGLE logic
```

**Step 6: Execute Swap**:
```solidity
(int128 amount0, int128 amount1) = _swap({
    zeroForOne: true,
    poolKey: poolKey,
    amountSpecified: -1000000000000000000,  // -1 ETH (negative = exact input)
    hookData: ""
});

// Pool calculates and returns:
// amount0 = -1000000000000000000 (paid 1 ETH)
// amount1 = +2492500000 (received 2492.5 USDC, after 0.3% fee)
```

**Step 7: Map Amounts**:
```solidity
currencyIn  = address(0);      // ETH
currencyOut = USDC_ADDRESS;    // USDC
amountIn    = 1 ether;         // 1000000000000000000
amountOut   = 2492500000;      // 2492.5 USDC (6 decimals)
```

**Step 8: Check Slippage**:
```solidity
require(2492500000 >= 2475000000, "insufficient output amount");
// ✅ PASS: 2492.5 >= 2475
```

**Step 9: Take and Settle**:
```solidity
// Take USDC to user
poolManager.take(USDC_ADDRESS, msg.sender, 2492500000);

// Sync ETH
poolManager.sync(address(0));

// Settle ETH
poolManager.settle{value: 1 ether}();
```

**Step 10: Return**:
```solidity
return abi.encode(2492500000);  // amountOut
```

**Step 11: Back in swapExactInputSingle**:
```solidity
amountOut = abi.decode(res, (uint256));  // 2492500000
// Check for refund (none needed for this swap)
return amountOut;  // User receives 2492.5 USDC
```

**Final State**:
- ✅ User paid: 1 ETH
- ✅ User received: 2492.5 USDC
- ✅ Pool fee: 7.5 USDC (0.3% of 2500)
- ✅ Slippage: 0.3% (better than 1% maximum)

---

## SWAP_EXACT_OUT_SINGLE: Single-Hop Exact Output Swaps

This section covers exact output swaps where you specify the exact amount you want to receive, and the pool calculates how much input is required.

### Function: `swapExactOutputSingle()`

**Contract**: `Router.sol`  
**Visibility**: `external payable`  
**Modifier**: `setAction(SWAP_EXACT_OUT_SINGLE)`  
**Returns**: `uint256 amountIn`

**Purpose**: Entry point for users to execute a single-hop swap with exact output amount.

#### Key Difference from Exact Input

| Aspect | Exact Input | Exact Output |
|--------|-------------|--------------|
| **User Specifies** | How much to give | How much to receive |
| **Pool Calculates** | How much you get | How much you need to give |
| **Input Amount** | Fixed | Variable |
| **Output Amount** | Variable | Fixed |
| **Slippage Protection** | `amountOutMin` | `amountInMax` |
| **amountSpecified Sign** | Negative (-) | Positive (+) |
| **Use Case** | "Sell my 1000 USDC" | "Buy exactly 1 ETH" |

#### Complete Function Code

```solidity
function swapExactOutputSingle(ExactOutputSingleParams calldata params)
    external
    payable
    setAction(SWAP_EXACT_OUT_SINGLE)
    returns (uint256 amountIn)
{
    // 1. Determine input currency based on swap direction
    address currencyIn = params.zeroForOne 
        ? params.poolKey.currency0 
        : params.poolKey.currency1;

    // 2. Transfer MAXIMUM input tokens from caller to router
    currencyIn.transferIn(msg.sender, params.amountInMax);
    
    // 3. Unlock PoolManager and trigger callback
    bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
    amountIn = abi.decode(res, (uint256));

    // 4. Refund unused input tokens (CRITICAL for exact output!)
    uint256 refunded = currencyIn.balanceOf(address(this));
    if (refunded > 0) {
        currencyIn.transferOut(msg.sender, refunded);
    }
}
```

### Critical Differences from Exact Input

#### 1. Transfer Maximum Amount First

```solidity
// Exact Input: Transfer exact amount
currencyIn.transferIn(msg.sender, params.amountIn);  // Transfer 1000 USDC

// Exact Output: Transfer maximum amount
currencyIn.transferIn(msg.sender, params.amountInMax);  // Transfer 1050 USDC (max)
```

**Why Transfer Maximum?**

With exact output, we don't know ahead of time how much input will be needed. The pool calculates this during the swap. So we:
1. Transfer the maximum we're willing to pay (`amountInMax`)
2. Execute the swap (uses only what's needed)
3. Refund the excess

**Example**:
```solidity
// User wants exactly 1 ETH
// Willing to pay up to 2600 USDC
params.amountInMax = 2600e6;

// Transfer 2600 USDC to router
// Swap executes, uses only 2525 USDC
// Refund 75 USDC back to user
```

#### 2. Decode `amountIn` (not `amountOut`)

```solidity
// Exact Input returns: how much you received
amountOut = abi.decode(res, (uint256));

// Exact Output returns: how much you paid
amountIn = abi.decode(res, (uint256));
```

The return value tells you how much input was actually used (important for knowing your refund).

#### 3. Refund is CRITICAL

```solidity
uint256 refunded = currencyIn.balanceOf(address(this));
if (refunded > 0) {
    currencyIn.transferOut(msg.sender, refunded);
}
```

**Why More Critical Here?**

- **Exact Input**: Refund is rare (only for ETH overpayment)
- **Exact Output**: Refund is EXPECTED (we always transfer max, use less)

**Without Refund**: User would lose the difference between `amountInMax` and actual `amountIn`!

### Execution Flow: SWAP_EXACT_OUT_SINGLE

```
┌─────────────┐         ┌──────────────┐         ┌────────────────┐
│   User/EOA  │         │  Router.sol  │         │  PoolManager   │
└──────┬──────┘         └──────┬───────┘         └───────┬────────┘
       │                       │                         │
       │ 1. swapExactOutputSingle(params)                │
       │    amountOut = 1 ETH                            │
       │    amountInMax = 2600 USDC                      │
       │──────────────────────>│                         │
       │                       │                         │
       │                       │ [setAction(0x08)]       │
       │                       │                         │
       │  2. transferIn(2600 USDC max)                   │
       │──────────────────────>│                         │
       │                       │                         │
       │                       │  3. unlock(data)        │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │  4. [LOCK STATE]        │
       │                       │                         │
       │                       │<─ 5. unlockCallback() ──│
       │                       │   [action = 0x08]       │
       │                       │                         │
       │                       │  6. _swap()             │
       │                       │    amountSpecified = +1 ETH (positive!)
       │                       │────────────────────────>│
       │                       │<──── delta ─────────────│
       │                       │  (requires 2525 USDC)   │
       │                       │                         │
       │                       │  7. _takeAndSettle()    │
       │                       │    - take(1 ETH)        │
       │                       │    - settle(2525 USDC)  │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │  8. return amountIn     │
       │                       │     (2525 USDC)         │
       │                       │<────────────────────────│
       │                       │                         │
       │                       │  9. [UNLOCK STATE]      │
       │                       │                         │
       │<─ 10. refund 75 USDC ─│                         │
       │   (2600 - 2525 = 75)  │                         │
       │   amountIn = 2525     │                         │
```

### Callback: `unlockCallback()` - SWAP_EXACT_OUT_SINGLE Branch

#### Callback Code for SWAP_EXACT_OUT_SINGLE

```solidity
function unlockCallback(bytes calldata data)
    external
    onlyPoolManager
    returns (bytes memory)
{
    uint256 action = _getAction();  // Retrieves 0x08
    
    if (action == SWAP_EXACT_OUT_SINGLE) {
        // 1. Decode parameters
        (address caller, ExactOutputSingleParams memory params) = 
            abi.decode(data, (address, ExactOutputSingleParams));
        
        // 2. Execute the swap
        (int128 amount0, int128 amount1) = _swap({
            zeroForOne: params.zeroForOne,
            poolKey: params.poolKey,
            amountSpecified: params.amountOut.toInt256(),  // POSITIVE = exact output
            hookData: params.hookData
        });

        // 3. Determine currencies and amounts based on direction
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

        // 4. Slippage protection (check INPUT not output!)
        require(amountIn <= params.amountInMax, "too much input amount");

        // 5. Finalize swap
        _takeAndSettle({
            caller: caller,
            currencyIn: currencyIn,
            amountIn: amountIn,
            currencyOut: currencyOut,
            amountOut: amountOut
        });

        // 6. Return actual input used (not output!)
        return abi.encode(amountIn);
    }
    
    // ... other action types ...
}
```

### Callback Step-by-Step Analysis

#### Key Difference 1: Positive `amountSpecified`

```solidity
// Exact Input:
amountSpecified: -(params.amountIn.toInt256())  // Negative

// Exact Output:
amountSpecified: params.amountOut.toInt256()    // Positive (no negative sign!)
```

**The Sign Tells the Pool What to Calculate**:

```solidity
// Negative: "I'm giving you this much, calculate output"
amountSpecified = -1000e6;  // Giving 1000 USDC, how much DAI do I get?

// Positive: "I want this much output, calculate required input"
amountSpecified = +1e18;     // Want 1 ETH, how much USDC do I need?
```

**Example**:
```solidity
params.amountOut = 1 ether;           // User wants exactly 1 ETH
params.amountOut.toInt256() = +1000000000000000000;  // Positive int256

// Tells pool: "User wants exactly 1 ETH, calculate required USDC input"
```

#### Key Difference 2: Slippage Check on Input

```solidity
// Exact Input: Check output meets minimum
require(amountOut >= params.amountOutMin, "insufficient output amount");

// Exact Output: Check input doesn't exceed maximum
require(amountIn <= params.amountInMax, "too much input amount");
```

**Why Different?**

- **Exact Input**: You know what you're paying, need to ensure you get enough
- **Exact Output**: You know what you're getting, need to ensure you don't pay too much

**Example**:
```solidity
// User wants exactly 1 ETH
params.amountOut = 1 ether;         // Fixed: will receive exactly this
params.amountInMax = 2600e6;        // Max willing to pay: 2600 USDC

// Swap executes, pool calculates:
amountIn = 2525e6;  // Needs 2525 USDC

// Check: Is 2525 <= 2600? ✅ YES, proceed
// If amountIn was 2650: ❌ NO, revert "too much input amount"
```

#### Key Difference 3: Return `amountIn`

```solidity
// Exact Input: Return how much user received
return abi.encode(amountOut);

// Exact Output: Return how much user paid
return abi.encode(amountIn);
```

This tells the main function how much to refund:
```solidity
// In swapExactOutputSingle():
amountIn = abi.decode(res, (uint256));  // Get actual amount used
// Refund = amountInMax - amountIn
```

### Balance Delta Sign Differences

**Understanding the Signs**:

| Scenario | amount0 | amount1 | Meaning |
|----------|---------|---------|---------|
| **Exact Input (0→1)** | Negative | Positive | Paid currency0, received currency1 |
| **Exact Output (0→1)** | Negative | Positive | **Same signs!** |
| **Exact Input (1→0)** | Positive | Negative | Received currency0, paid currency1 |
| **Exact Output (1→0)** | Positive | Negative | **Same signs!** |

**Important**: The signs are the same! The difference is in `amountSpecified`, not the result signs.

**Exact Output Example**:
```solidity
// Want exactly 1 ETH (currency0), paying USDC (currency1)
params.zeroForOne = false;  // 1 → 0 (USDC → ETH)
params.amountOut = 1 ether;

// Swap executes:
amount0 = +1000000000000000000;  // Received 1 ETH (positive)
amount1 = -2525000000;           // Paid 2525 USDC (negative)

// Mapping:
currencyIn  = currency1;     // USDC
currencyOut = currency0;     // ETH
amountIn    = 2525e6;       // Made positive from -amount1
amountOut   = 1 ether;      // Already positive from amount0
```

### Complete Example: Buy Exactly 1 ETH with USDC

Let's trace a complete exact output swap:

**Setup**:
```solidity
// User wants EXACTLY 1 ETH, willing to pay up to 2600 USDC
// Pool: ETH (currency0) / USDC (currency1)
// Current price: 1 ETH = 2500 USDC
// Pool fee: 0.3%
// Expected input: ~2507.5 USDC (2500 + 0.3%)
```

**Step 1: User Calls Function**:
```solidity
// User must approve router first
USDC.approve(address(router), 2600e6);

router.swapExactOutputSingle(
    ExactOutputSingleParams({
        poolKey: PoolKey({
            currency0: address(0),      // ETH
            currency1: USDC_ADDRESS,    // USDC
            fee: 3000,                  // 0.3%
            tickSpacing: 60,
            hooks: address(0)
        }),
        zeroForOne: false,              // USDC → ETH
        amountOut: 1 ether,            // Want exactly 1 ETH
        amountInMax: 2600e6,           // Max pay 2600 USDC (4% slippage)
        hookData: ""
    })
);
```

**Step 2: Determine Input Currency**:
```solidity
currencyIn = params.zeroForOne ? currency0 : currency1;
// currencyIn = USDC_ADDRESS
```

**Step 3: Transfer Maximum**:
```solidity
currencyIn.transferIn(msg.sender, 2600e6);
// Router now holds 2600 USDC
```

**Step 4: Set Action and Unlock**:
```solidity
setAction(SWAP_EXACT_OUT_SINGLE);  // Stores 0x08
poolManager.unlock(abi.encode(msg.sender, params));
```

**Step 5: Callback Executes**:
```solidity
action = _getAction();  // Returns 0x08
// Branches to SWAP_EXACT_OUT_SINGLE logic
```

**Step 6: Execute Swap**:
```solidity
(int128 amount0, int128 amount1) = _swap({
    zeroForOne: false,
    poolKey: poolKey,
    amountSpecified: +1000000000000000000,  // +1 ETH (positive = exact output!)
    hookData: ""
});

// Pool calculates backwards and returns:
// amount0 = +1000000000000000000 (will receive 1 ETH)
// amount1 = -2507500000 (need to pay 2507.5 USDC)
```

**Step 7: Map Amounts**:
```solidity
// zeroForOne = false, so:
currencyIn  = currency1;       // USDC
currencyOut = currency0;       // ETH
amountIn    = 2507500000;     // 2507.5 USDC (from -amount1)
amountOut   = 1 ether;        // 1 ETH (from amount0)
```

**Step 8: Check Slippage (on input!)**:
```solidity
require(2507500000 <= 2600000000, "too much input amount");
// ✅ PASS: 2507.5 <= 2600
```

**Step 9: Take and Settle**:
```solidity
// Take ETH to user
poolManager.take(address(0), msg.sender, 1 ether);

// Sync USDC
poolManager.sync(USDC_ADDRESS);

// Settle USDC (only what's needed!)
IERC20(USDC).transfer(address(poolManager), 2507500000);
poolManager.settle();
```

**Step 10: Return Actual Input**:
```solidity
return abi.encode(2507500000);  // amountIn
```

**Step 11: Back in swapExactOutputSingle**:
```solidity
amountIn = abi.decode(res, (uint256));  // 2507500000

// Calculate refund
uint256 refunded = currencyIn.balanceOf(address(this));
// refunded = 2600e6 - 2507.5e6 = 92.5e6 USDC

// Refund to user
currencyIn.transferOut(msg.sender, 92500000);

return amountIn;  // Return 2507500000 to user
```

**Final State**:
- ✅ User received: Exactly 1 ETH (as requested)
- ✅ User paid: 2507.5 USDC (actual cost)
- ✅ User refunded: 92.5 USDC (2600 - 2507.5)
- ✅ Pool fee: ~7.5 USDC (0.3% of 2500)
- ✅ Slippage protection: Pass (2507.5 < 2600 max)

### When to Use Exact Output vs Exact Input

#### Use Exact Output When:

1. **You need a specific amount**:
   ```solidity
   // "I need exactly 1 ETH to pay for something"
   swapExactOutputSingle({amountOut: 1 ether, ...})
   ```

2. **Paying for services/goods**:
   ```solidity
   // NFT costs 0.5 ETH, you have USDC
   swapExactOutputSingle({amountOut: 0.5 ether, ...})
   ```

3. **Liquidation scenarios**:
   ```solidity
   // Need exactly 1000 USDC to cover debt
   swapExactOutputSingle({amountOut: 1000e6, ...})
   ```

4. **Limit order fills**:
   ```solidity
   // Want to receive exactly X tokens at price Y
   swapExactOutputSingle({amountOut: X, amountInMax: Y, ...})
   ```

#### Use Exact Input When:

1. **Selling a specific balance**:
   ```solidity
   // "Sell all my 1000 USDC"
   swapExactInputSingle({amountIn: 1000e6, ...})
   ```

2. **Market orders**:
   ```solidity
   // "Trade this amount, accept market price"
   swapExactInputSingle({amountIn: amount, amountOutMin: minAcceptable, ...})
   ```

3. **Simpler logic**:
   - No need to guess maximum input
   - No refund logic needed (usually)

### Common Pitfalls: Exact Output

#### Pitfall 1: Not Setting Sufficient `amountInMax`

```solidity
// ❌ WRONG: Too tight maximum
params.amountInMax = 2500e6;  // Expected exact price
// If price moves slightly: REVERT "too much input amount"

// ✅ CORRECT: Add slippage buffer
params.amountInMax = 2575e6;  // 3% slippage tolerance
```

#### Pitfall 2: Forgetting to Approve Enough

```solidity
// ❌ WRONG: Only approve expected amount
USDC.approve(router, 2500e6);
router.swapExactOutputSingle({amountInMax: 2600e6, ...});
// REVERT: Insufficient allowance

// ✅ CORRECT: Approve maximum
USDC.approve(router, 2600e6);  // Or type(uint256).max
```

#### Pitfall 3: Not Handling Refund

```solidity
// The Router handles this, but if you're building your own:

// ❌ WRONG: Lose the difference
function mySwap() {
    router.swapExactOutputSingle{value: 1 ether}(...);
    // If only 0.9 ETH used, 0.1 ETH stuck in router!
}

// ✅ CORRECT: Router returns excess automatically
// Or handle it explicitly in your contract
```

#### Pitfall 4: Wrong Slippage Check

```solidity
// ❌ WRONG: Checking output (it's always exact!)
require(amountOut >= minOut, "slippage");  // amountOut is ALWAYS exact

// ✅ CORRECT: Check input
require(amountIn <= maxIn, "slippage");
```

### Gas Comparison: Exact Input vs Exact Output

| Operation | Exact Input | Exact Output | Difference |
|-----------|-------------|--------------|------------|
| **Transfer In** | Exact amount | Maximum amount | Same gas |
| **Swap Calculation** | Forward | Backward | ~Same gas |
| **Refund** | Rare | Common | +5k-10k gas for output |
| **Total Gas** | ~150k | ~160k | Exact output slightly more expensive |

**Why Exact Output Costs More**:
- Additional refund transfer
- More complex pool calculations (working backwards)

**When Worth It**: The extra ~10k gas is negligible compared to getting the exact amount you need.

---

## SWAP_EXACT_IN: Multi-Hop Exact Input Swaps

This section covers multi-hop swaps where you chain multiple pools together to trade tokens that don't have a direct liquidity pool, specifying an exact input amount.

### Why Multi-Hop Swaps?

**Problem**: Not all token pairs have direct liquidity pools.

**Example**:
```solidity
// Want to swap USDC → WBTC
// But no USDC/WBTC pool exists (or has poor liquidity)

// Solution: Route through ETH
// USDC → ETH → WBTC
// Using two pools: USDC/ETH and ETH/WBTC
```

**Benefits**:
- Access to more trading pairs
- Better prices through optimal routing
- Single transaction for complex swaps
- Atomic execution (all-or-nothing)

### Function: `swapExactInput()`

**Contract**: `Router.sol`  
**Visibility**: `external payable`  
**Modifier**: `setAction(SWAP_EXACT_IN)`  
**Returns**: `uint256 amountOut`

**Purpose**: Execute a multi-hop swap with exact input amount.

#### Complete Function Code

```solidity
function swapExactInput(ExactInputParams calldata params)
    external
    payable
    setAction(SWAP_EXACT_IN)
    returns (uint256 amountOut)
{
    // 1. Determine input currency
    address currencyIn = params.currencyIn;

    // 2. Transfer input tokens from caller to router
    if (currencyIn != address(0)) {
        currencyIn.transferIn(msg.sender, params.amountIn);
    }

    // 3. Unlock PoolManager and trigger callback
    bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
    amountOut = abi.decode(res, (uint256));

    // 4. Refund any remaining input tokens
    if (currencyIn.balanceOf(address(this)) > 0) {
        currencyIn.transferOut(msg.sender, currencyIn.balanceOf(address(this)));
    }
}
```

**Similar to Single-Hop**: The entry point is nearly identical to `swapExactInputSingle`. The complexity is in the callback!

### Understanding the Path Structure

#### ExactInputParams

```solidity
struct ExactInputParams {
    address currencyIn;      // Starting currency
    PathKey[] path;          // Array of hops
    uint128 amountIn;        // Exact input amount
    uint128 amountOutMin;    // Minimum final output
}
```

#### PathKey (Review)

```solidity
struct PathKey {
    address currency;     // NEXT currency in the path
    uint24 fee;          // Pool fee for this hop
    int24 tickSpacing;   // Pool tick spacing
    address hooks;       // Hook contract
    bytes hookData;      // Hook data for this hop
}
```

#### Path Construction Logic

**Key Concept**: Each PathKey defines the **destination** of a hop, not the source.

```solidity
// Example: USDC → ETH → WBTC (3 currencies = 2 PathKey elements)

ExactInputParams({
    currencyIn: USDC,    // Starting point (NOT in path)
    path: [
        PathKey({
            currency: address(0),   // ETH - first destination
            fee: 500,
            tickSpacing: 10,
            hooks: address(0),
            hookData: ""
        }),
        PathKey({
            currency: WBTC,         // WBTC - second destination (final)
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0),
            hookData: ""
        })
    ],
    amountIn: 1000e6,        // Start with 1000 USDC
    amountOutMin: 0.001e8    // Expect at least 0.001 WBTC
})
```

**How It Works**:

For USDC → ETH → WBTC:
- `currencyIn` = USDC (specified in params, **NOT in path**)
- `path[0].currency` = ETH (first destination/intermediate)
- `path[1].currency` = WBTC (second destination, final output)

| Hop | Source | Destination | Pool Used |
|-----|--------|-------------|-----------|
| 1 | `currencyIn` (USDC) | `path[0].currency` (ETH) | USDC/ETH pool |
| 2 | `path[0].currency` (ETH) | `path[1].currency` (WBTC) | ETH/WBTC pool |

**General Pattern**:
```
Hop i: 
  Source = (i == 0) ? currencyIn : path[i-1].currency
  Dest   = path[i].currency
  
For N currencies → (N-1) PathKey elements!
Example: 3 currencies → 2 PathKey elements
```

### Execution Flow: SWAP_EXACT_IN

```
┌─────────────┐         ┌──────────────┐         ┌────────────────┐
│   User/EOA  │         │  Router.sol  │         │  PoolManager   │
└──────┬──────┘         └──────┬───────┘         └───────┬────────┘
       │                       │                         │
       │ 1. swapExactInput(params)                       │
       │    currencyIn: USDC                             │
       │    path: [ETH, WBTC]                            │
       │    amountIn: 1000 USDC                          │
       │──────────────────────>│                         │
       │                       │                         │
       │  2. transferIn(1000 USDC)                       │
       │──────────────────────>│                         │
       │                       │                         │
       │                       │  3. unlock(data)        │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │<─ 4. unlockCallback() ──│
       │                       │   [action = 0x07]       │
       │                       │                         │
       │                       │  [START LOOP]           │
       │                       │                         │
       │                       │  5. Hop 1: USDC → ETH   │
       │                       │    _swap(USDC/ETH pool) │
       │                       │────────────────────────>│
       │                       │<──── 0.4 ETH ───────────│
       │                       │                         │
       │                       │  6. Hop 2: ETH → WBTC   │
       │                       │    _swap(ETH/WBTC pool) │
       │                       │────────────────────────>│
       │                       │<──── 0.0105 WBTC ───────│
       │                       │                         │
       │                       │  [END LOOP]             │
       │                       │                         │
       │                       │  7. Check slippage:     │
       │                       │    0.0105 >= 0.001? ✅  │
       │                       │                         │
       │                       │  8. _takeAndSettle()    │
       │                       │    (only ONCE at end!)  │
       │                       │────────────────────────>│
       │                       │                         │
       │<─ 9. receive WBTC ────│                         │
       │   amountOut = 0.0105  │                         │
```

### Callback: `unlockCallback()` - SWAP_EXACT_IN Branch

This is where the magic happens! The callback loops through each hop in the path.

#### Callback Code for SWAP_EXACT_IN

```solidity
function unlockCallback(bytes calldata data)
    external
    onlyPoolManager
    returns (bytes memory)
{
    uint256 action = _getAction();
    
    if (action == SWAP_EXACT_IN) {
        // 1. Decode parameters
        (address caller, ExactInputParams memory params) = 
            abi.decode(data, (address, ExactInputParams));

        // 2. Get path length
        uint256 pathLength = params.path.length;

        // 3. Initialize loop variables
        address currencyIn = params.currencyIn;
        int256 amountIn = params.amountIn.toInt256();

        // 4. Loop through each hop
        for (uint256 i = 0; i < pathLength; i++) {
            PathKey memory path = params.path[i];

            // 4a. Determine currency pair for this hop
            (address currency0, address currency1) = currencyIn < path.currency
                ? (currencyIn, path.currency)
                : (path.currency, currencyIn);

            // 4b. Determine swap direction
            bool zeroForOne = currency0 == currencyIn;

            // 4c. Build PoolKey
            PoolKey memory poolKey = PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: path.fee,
                tickSpacing: path.tickSpacing,
                hooks: path.hooks
            });

            // 4d. Execute swap for this hop
            (int128 amount0, int128 amount1) = _swap({
                zeroForOne: zeroForOne,
                poolKey: poolKey,
                amountSpecified: -amountIn,  // Negative = exact input
                hookData: path.hookData
            });
            
            // 4e. Prepare for next hop
            currencyIn = path.currency;  // Output becomes next input
            amountIn = (zeroForOne ? amount1 : amount0).toInt256();
        }

        // 5. After loop: currencyIn = final output currency
        //                 amountIn = final output amount
        
        // 6. Check slippage
        require(
            uint256(amountIn) >= uint256(params.amountOutMin),
            "insufficient output amount"
        );

        // 7. Settle everything at once
        _takeAndSettle({
            caller: caller,
            currencyIn: params.currencyIn,      // Original input
            amountIn: params.amountIn,          // Original amount
            currencyOut: currencyIn,            // Final output (from loop)
            amountOut: uint256(amountIn)       // Final amount (from loop)
        });

        // 8. Return final output amount
        return abi.encode(uint256(amountIn));
    }
    
    // ... other action types ...
}
```

### Loop Breakdown: Step-by-Step

Let's trace through the loop with our USDC → ETH → WBTC example.

**Initial State**:
```solidity
currencyIn = USDC;
amountIn = 1000e6;  // 1000 USDC
pathLength = 2;
```

#### Iteration 1: USDC → ETH

**Step 4a: Determine Currency Pair**

```solidity
path = params.path[0];  // First hop
// path.currency = ETH

(address currency0, address currency1) = currencyIn < path.currency
    ? (currencyIn, path.currency)
    : (path.currency, currencyIn);
```

**Address Comparison**:
```solidity
currencyIn = USDC;  // e.g., 0xA0b8...
path.currency = ETH (address(0));  // 0x0000...

// Compare: 0xA0b8... < 0x0000...? NO
// So: currency0 = ETH, currency1 = USDC
```

**Why This Works**: Uniswap V4 pools always have `currency0 < currency1` by address. We need to figure out the correct ordering.

**Result**:
```solidity
currency0 = address(0);  // ETH
currency1 = USDC;
```

**Step 4b: Determine Swap Direction**

```solidity
bool zeroForOne = currency0 == currencyIn;
// zeroForOne = (ETH == USDC)? NO
// zeroForOne = false
```

**Interpretation**:
```solidity
// Pool is ETH/USDC (currency0/currency1)
// We're swapping USDC → ETH
// That's 1 → 0, so zeroForOne = false ✅
```

**Step 4c: Build PoolKey**

```solidity
PoolKey memory poolKey = PoolKey({
    currency0: address(0),     // ETH
    currency1: USDC,           // USDC
    fee: 3000,                 // 0.3%
    tickSpacing: 60,
    hooks: address(0)
});
```

**Step 4d: Execute Swap**

```solidity
(int128 amount0, int128 amount1) = _swap({
    zeroForOne: false,             // 1 → 0
    poolKey: poolKey,
    amountSpecified: -1000e6,     // Negative = exact input of 1000 USDC
    hookData: ""
});

// Pool calculates and returns:
// amount0 = +399200000000000000  // Received ~0.4 ETH
// amount1 = -1000000000          // Paid 1000 USDC
```

**Step 4e: Prepare for Next Hop**

```solidity
currencyIn = path.currency;  // ETH (next input)
amountIn = (zeroForOne ? amount1 : amount0).toInt256();
// zeroForOne = false, so amountIn = amount0
// amountIn = +399200000000000000  // ~0.4 ETH
```

**After Iteration 1**:
```solidity
currencyIn = ETH;
amountIn = 0.3992 ether;  // Output from first swap
```

#### Iteration 2: ETH → WBTC

**Step 4a: Determine Currency Pair**

```solidity
path = params.path[1];  // Second hop
// path.currency = WBTC

currencyIn = ETH (address(0));
path.currency = WBTC;  // e.g., 0x2260...

// Compare: 0x0000... < 0x2260...? YES
// So: currency0 = ETH, currency1 = WBTC
```

**Result**:
```solidity
currency0 = address(0);  // ETH
currency1 = WBTC;
```

**Step 4b: Determine Swap Direction**

```solidity
bool zeroForOne = currency0 == currencyIn;
// zeroForOne = (ETH == ETH)? YES
// zeroForOne = true ✅
```

**Step 4c: Build PoolKey**

```solidity
PoolKey memory poolKey = PoolKey({
    currency0: address(0),     // ETH
    currency1: WBTC,
    fee: 3000,
    tickSpacing: 60,
    hooks: address(0)
});
```

**Step 4d: Execute Swap**

```solidity
(int128 amount0, int128 amount1) = _swap({
    zeroForOne: true,                      // 0 → 1
    poolKey: poolKey,
    amountSpecified: -399200000000000000,  // Negative = exact input of 0.3992 ETH
    hookData: ""
});

// Pool calculates and returns:
// amount0 = -399200000000000000  // Paid 0.3992 ETH
// amount1 = +1050000             // Received 0.0105 WBTC (8 decimals)
```

**Step 4e: Prepare for Next Hop** (but loop ends)

```solidity
currencyIn = path.currency;  // WBTC
amountIn = (zeroForOne ? amount1 : amount0).toInt256();
// zeroForOne = true, so amountIn = amount1
// amountIn = +1050000  // 0.0105 WBTC
```

**After Loop Completion**:
```solidity
currencyIn = WBTC;       // Final output currency
amountIn = 0.0105e8;     // Final output amount
```

### Post-Loop: Settlement

#### Check Slippage

```solidity
require(
    uint256(amountIn) >= uint256(params.amountOutMin),
    "insufficient output amount"
);

// Check: 0.0105e8 >= 0.001e8? 
// 1050000 >= 100000? ✅ YES
```

**Important**: Slippage is checked on the **final** output, not intermediate hops.

#### Single Settlement for All Hops

```solidity
_takeAndSettle({
    caller: caller,
    currencyIn: USDC,           // Original input
    amountIn: 1000e6,           // Original amount
    currencyOut: WBTC,          // Final output
    amountOut: 0.0105e8        // Final amount
});
```

**Why Settle Once?**

This is the power of Uniswap V4's flash accounting:

```solidity
// During swaps (all accounting, no transfers):
Hop 1: debt[USDC] = -1000, debt[ETH] = +0.4
Hop 2: debt[ETH] = +0.4-0.4 = 0, debt[WBTC] = +0.0105

// After both swaps:
Net debt: USDC = -1000, WBTC = +0.0105, ETH = 0

// Settlement (actual transfers):
take(WBTC, user, 0.0105)    // Transfer WBTC to user
settle(USDC, 1000)          // Transfer USDC to pool
// ETH: net zero, no transfer needed!
```

**Gas Savings**: Only 2 transfers instead of 4 (no intermediate ETH transfers)!

### Complete Example: USDC → ETH → WBTC

**Setup**:
```solidity
// User has 1000 USDC
// Wants WBTC
// No direct USDC/WBTC pool
// Route: USDC → ETH → WBTC
```

**Step 1: Construct Parameters**:

```solidity
ExactInputParams memory params = ExactInputParams({
    currencyIn: USDC_ADDRESS,
    path: [
        PathKey({
            currency: address(0),      // First hop: USDC → ETH
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0),
            hookData: ""
        }),
        PathKey({
            currency: WBTC_ADDRESS,    // Second hop: ETH → WBTC
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0),
            hookData: ""
        })
    ],
    amountIn: 1000e6,          // 1000 USDC exactly
    amountOutMin: 0.001e8      // At least 0.001 WBTC (generous slippage)
});
```

**Step 2: Call Router**:

```solidity
// Approve router
IERC20(USDC).approve(address(router), 1000e6);

// Execute multi-hop swap
uint256 amountOut = router.swapExactInput(params);
// Returns: 1050000 (0.0105 WBTC)
```

**Step 3: Execution** (detailed above in loop breakdown)

**Final Result**:
```solidity
// User traded:
// - Input: 1000 USDC
// - Output: 0.0105 WBTC
// 
// Route taken:
// 1000 USDC → 0.4 ETH → 0.0105 WBTC
//
// Effective price: 1000 USDC per 0.0105 WBTC
//                = ~95,238 USDC per WBTC
```

### Key Insights: Multi-Hop Exact Input

#### 1. Output of Hop N = Input of Hop N+1

```solidity
// This is the critical chaining logic:
currencyIn = path.currency;  // Output currency becomes next input
amountIn = outputAmount;      // Output amount becomes next input amount
```

#### 2. Only Final Output Checked

```solidity
// Slippage check is ONLY on final output
require(finalAmount >= params.amountOutMin, "insufficient output");

// Intermediate amounts are not checked!
// This is okay because if intermediates are bad, final will be bad too
```

#### 3. Single Settlement

```solidity
// All swaps happen in accounting only
// Single transfer at the end
// This is why V4 is more gas efficient for multi-hop!
```

#### 4. Flexible Path Length

```solidity
// Can have any number of hops:
pathLength = 1;  // Actually just single-hop
pathLength = 2;  // Two hops (A → B → C)
pathLength = 3;  // Three hops (A → B → C → D)
pathLength = 5;  // Five hops! (rarely practical due to gas)
```

### Advanced: Three-Hop Example

**Scenario**: USDC → DAI → ETH → WBTC

```solidity
ExactInputParams({
    currencyIn: USDC,
    path: [
        PathKey({currency: DAI, ...}),    // Hop 1: USDC → DAI
        PathKey({currency: ETH, ...}),    // Hop 2: DAI → ETH
        PathKey({currency: WBTC, ...})    // Hop 3: ETH → WBTC
    ],
    amountIn: 1000e6,
    amountOutMin: 0.001e8
})
```

**Loop Execution**:

| Iteration | Source | Destination | amountIn (start) | amountOut (end) |
|-----------|--------|-------------|------------------|-----------------|
| i=0 | USDC | DAI | 1000 USDC | ~999 DAI |
| i=1 | DAI | ETH | ~999 DAI | ~0.4 ETH |
| i=2 | ETH | WBTC | ~0.4 ETH | ~0.0105 WBTC |

**Total Gas**: Still just 2 transfers (USDC in, WBTC out)!

### When to Use Multi-Hop

#### Use Multi-Hop When:

1. **No Direct Pool**:
   ```solidity
   // Want to trade TokenA ↔ TokenB
   // But no TokenA/TokenB pool exists
   // Route through common pair: TokenA → ETH → TokenB
   ```

2. **Better Liquidity**:
   ```solidity
   // Direct pool exists but has low liquidity
   // Indirect route through high-liquidity pools gives better price
   ```

3. **Lower Price Impact**:
   ```solidity
   // Large trade in one pool: high price impact
   // Split across multiple hops: lower overall impact
   ```

#### Avoid Multi-Hop When:

1. **Direct Pool Has Good Liquidity**: Extra gas not worth it
2. **Many Hops**: Each hop adds gas and potential for worse pricing
3. **High Fee Tiers**: Multiple 1% fee pools add up quickly

---

## SWAP_EXACT_OUT: Multi-Hop Exact Output Swaps

This is the most complex swap mode: multi-hop routing where you specify the exact final output amount, and the router calculates required input by working **backwards** through the path.

### Why Backwards Execution?

**The Problem**:
```solidity
// User wants EXACTLY 0.01 WBTC
// Route: USDC → ETH → WBTC
// 
// Question: How much USDC do they need?
//
// Can't work forwards because:
// - Don't know input amount yet!
// - Need to work backwards from desired output
```

**The Solution**: Start from the end and work backwards:

```
Step 1: "I want 0.01 WBTC"
  → Calculate: "Need 0.4 ETH to get 0.01 WBTC"

Step 2: "I need 0.4 ETH"
  → Calculate: "Need 1005 USDC to get 0.4 ETH"

Result: "Need 1005 USDC to end up with 0.01 WBTC"
```

### Function: `swapExactOutput()`

**Contract**: `Router.sol`  
**Visibility**: `external payable`  
**Modifier**: `setAction(SWAP_EXACT_OUT)`  
**Returns**: `uint256 amountIn`

#### Complete Function Code

```solidity
function swapExactOutput(ExactOutputParams calldata params)
    external
    payable
    setAction(SWAP_EXACT_OUT)
    returns (uint256 amountIn)
{
    // 1. Determine input currency (from FIRST path element!)
    address currencyIn = params.path[0].currency;

    // 2. Trigger swap (no transfer here, happens in callback!)
    bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
    amountIn = abi.decode(res, (uint256));

    // 3. Refund any remaining input tokens
    if (currencyIn.balanceOf(address(this)) > 0) {
        currencyIn.transferOut(msg.sender, currencyIn.balanceOf(address(this)));
    }
}
```

**Critical Difference**: No `transferIn` here! The callback handles it.

### Understanding the Path for Exact Output

#### ExactOutputParams

```solidity
struct ExactOutputParams {
    address currencyOut;     // FINAL output currency (destination)
    PathKey[] path;          // Hops (traversed BACKWARDS!)
    uint128 amountOut;       // Exact FINAL output amount
    uint128 amountInMax;     // Maximum INITIAL input willing to pay
}
```

#### Path Direction: FORWARD Definition, BACKWARD Execution

**Path Still Defined Forward** (same as exact input):

```solidity
// Want: USDC → ETH → WBTC (get exactly 0.01 WBTC)

ExactOutputParams({
    currencyOut: WBTC,    // Final destination
    path: [
        PathKey({
            currency: ETH,      // Path defined forward: USDC → ETH
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0),
            hookData: ""
        }),
        PathKey({
            currency: WBTC,     // Path defined forward: ETH → WBTC
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0),
            hookData: ""
        })
    ],
    amountOut: 0.01e8,       // Want exactly 0.01 WBTC
    amountInMax: 1100e6      // Willing to pay up to 1100 USDC
})
```

**But Executed Backwards**:

| Loop Order | Actual Hop | Calculation |
|------------|------------|-------------|
| i=2 (last) | ETH → WBTC | "Need X ETH to get 0.01 WBTC" |
| i=1 (first) | USDC → ETH | "Need Y USDC to get X ETH" |

**Key Point**: `path[0].currency` is the **starting** currency (USDC in our example).

### Execution Flow: SWAP_EXACT_OUT

```
┌─────────────┐         ┌──────────────┐         ┌────────────────┐
│   User/EOA  │         │  Router.sol  │         │  PoolManager   │
└──────┬──────┘         └──────┬───────┘         └───────┬────────┘
       │                       │                         │
       │ 1. swapExactOutput(params)                      │
       │    currencyOut: WBTC                            │
       │    path: [ETH, WBTC] (but traverse backwards!)  │
       │    amountOut: 0.01 WBTC                         │
       │──────────────────────>│                         │
       │                       │                         │
       │                       │  2. unlock(data)        │
       │                       │    (NO transferIn yet!) │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │<─ 3. unlockCallback() ──│
       │                       │   [action = 0x09]       │
       │                       │                         │
       │                       │  [BACKWARDS LOOP]       │
       │                       │                         │
       │                       │  4. Hop 2 (i=1): ETH → WBTC │
       │                       │    "Need X ETH for 0.01 WBTC" │
       │                       │    _swap(+0.01 WBTC)    │
       │                       │────────────────────────>│
       │                       │<──── need 0.4 ETH ──────│
       │                       │                         │
       │                       │  5. Hop 1 (i=0): USDC → ETH │
       │                       │    "Need Y USDC for 0.4 ETH" │
       │                       │    _swap(+0.4 ETH)      │
       │                       │────────────────────────>│
       │                       │<──── need 1005 USDC ────│
       │                       │                         │
       │                       │  [END LOOP]             │
       │                       │  Result: need 1005 USDC │
       │                       │                         │
       │  6. transferIn(1005 USDC max)                   │
       │──────────────────────>│                         │
       │                       │                         │
       │                       │  7. _takeAndSettle()    │
       │                       │────────────────────────>│
       │                       │                         │
       │<─ 8. receive WBTC ────│                         │
       │   amountIn = 1005     │                         │
```

### Callback: `unlockCallback()` - SWAP_EXACT_OUT Branch

#### Callback Code for SWAP_EXACT_OUT

```solidity
function unlockCallback(bytes calldata data)
    external
    onlyPoolManager
    returns (bytes memory)
{
    uint256 action = _getAction();
    
    if (action == SWAP_EXACT_OUT) {
        // 1. Decode parameters
        (address caller, ExactOutputParams memory params) = 
            abi.decode(data, (address, ExactOutputParams));

        // 2. Get path length
        uint256 pathLength = params.path.length;

        // 3. Initialize loop variables
        address currencyOut = params.currencyOut;     // Start from END
        int256 amountOut = params.amountOut.toInt256();

        // 4. Loop BACKWARDS through path
        for (uint256 i = pathLength; i > 0; i--) {
            PathKey memory path = params.path[i - 1];  // Note: i-1!

            // 4a. Determine currency pair
            (address currency0, address currency1) = path.currency < currencyOut
                ? (path.currency, currencyOut)
                : (currencyOut, path.currency);

            // 4b. Determine swap direction (REVERSED logic!)
            bool zeroForOne = currencyOut == currency1;

            // 4c. Build PoolKey
            PoolKey memory poolKey = PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: path.fee,
                tickSpacing: path.tickSpacing,
                hooks: path.hooks
            });

            // 4d. Execute swap for this hop
            (int128 amount0, int128 amount1) = _swap({
                zeroForOne: zeroForOne,
                poolKey: poolKey,
                amountSpecified: amountOut,  // POSITIVE = exact output
                hookData: path.hookData
            });
            
            // 4e. Prepare for previous hop (going backwards!)
            currencyOut = path.currency;  // Move to previous currency
            amountOut = (zeroForOne ? -amount0 : -amount1).toInt256();  // NEGATE!
        }

        // 5. After loop: currencyOut = initial input currency
        //                 amountOut = required input amount
        
        // 6. Check slippage (on INPUT!)
        require(
            uint256(amountOut) <= uint256(params.amountInMax),
            "amount in > max"
        );

        // 7. NOW transfer input from user (we know how much!)
        if (currencyOut != address(0)) {
            currencyOut.transferIn(caller, uint256(amountOut));
        }

        // 8. Settle everything
        _takeAndSettle({
            caller: caller,
            currencyIn: currencyOut,           // Calculated input
            amountIn: uint256(amountOut),     // Calculated amount
            currencyOut: params.currencyOut,  // Original output
            amountOut: params.amountOut       // Original amount
        });

        // 9. Return required input amount
        return abi.encode(uint256(amountOut));
    }
    
    // ... other action types ...
}
```

### Loop Breakdown: Backwards Execution

Let's trace the backwards loop with USDC → ETH → WBTC (want exactly 0.01 WBTC).

**Initial State**:
```solidity
currencyOut = WBTC;
amountOut = 0.01e8;  // Want exactly 0.01 WBTC
pathLength = 2;
```

#### Iteration 1: i=2 (Last Hop: ETH → WBTC)

**Array Access**:
```solidity
i = 2;
path = params.path[i - 1];  // path[1]
// This is the SECOND PathKey (ETH → WBTC)
```

**Step 4a: Determine Currency Pair**

```solidity
path.currency = WBTC;  // From path[1]
currencyOut = WBTC;    // Current output

// Compare: WBTC < WBTC? NO (they're equal)
// Actually: path.currency (ETH) < currencyOut (WBTC)?

// Wait, let me recheck:
// path[1].currency = WBTC (final destination)
// But we're at i=2, working backwards, so:
// We're calculating hop FROM path[0].currency (ETH) TO currencyOut (WBTC)
```

**Let me clarify the logic**:

```solidity
// At i=2 (first iteration of backwards loop):
currencyOut = WBTC;           // We want WBTC
path = params.path[1];         // Last path element
// path[1].currency = WBTC... 

// Actually, in exact output, the path represents the FORWARD route
// So path[0].currency is intermediate (ETH)
// And path[1].currency is final (WBTC)

// But we need to figure out THIS hop's source
// Source = path[i-2].currency if i > 1, else initial currency
```

Wait, let me re-examine the actual code from Router.sol:

```solidity
PathKey memory path = params.path[i-1];

(address currency0, address currency1) = path.currency < currencyOut
    ? (path.currency, currencyOut)
    : (currencyOut, path.currency);

bool zeroForOne = currencyOut == currency1;
```

**Ah! The key insight**:

- `currencyOut` = what we're trying to GET (starts as WBTC)
- `path.currency` = the intermediate currency for this hop
- We're swapping `path.currency` → `currencyOut`

**Let me retrace**:

**Iteration 1: i=2 (pathLength)**

```solidity
i = 2;
path = params.path[1];  // Last element
// path.currency = WBTC (final destination)

currencyOut = WBTC;

// But wait, this doesn't make sense...
// Let me check the actual path structure again
```

**Path Structure for Exact Output** (from test files):

For route USDC → ETH → WBTC (want exactly 0.01 WBTC):

```solidity
ExactOutputParams({
    currencyOut: WBTC,  // Final destination (NOT in path)
    path: [
        PathKey({currency: USDC, ...}),   // First currency (source)
        PathKey({currency: ETH, ...})     // Second currency (intermediate)
    ],
    amountOut: 0.01e8
})
```

**The Pattern** (3 currencies = 2 PathKey elements):
- `path[0].currency` = USDC (starting point)
- `path[1].currency` = ETH (intermediate)  
- `currencyOut` = WBTC (final destination, **NOT in path**)

**Route**: USDC → ETH → WBTC

**Backwards Execution**:
- Iteration 1 (i=2): Calculate ETH → WBTC (using `path[1]` and `currencyOut`)
- Iteration 2 (i=1): Calculate USDC → ETH (using `path[0]` and previous result)

### Loop Iteration Breakdown

**Iteration 1: i=2 (Last Hop: ETH → WBTC)**

```solidity
i = 2;  // pathLength
path = params.path[i - 1];  // params.path[1]
// path.currency = ETH (intermediate currency)

currencyOut = WBTC;  // What we want (final destination)
```

**Step 4a: Determine Currency Pair**

```solidity
// Determine pool:
(address currency0, address currency1) = path.currency < currencyOut
    ? (path.currency, currencyOut)
    : (currencyOut, path.currency);

// ETH (address(0)) < WBTC (0x2260...)? YES
// currency0 = ETH, currency1 = WBTC
```

**Step 4b: Determine Direction**

```solidity
bool zeroForOne = currencyOut == currency1;
// zeroForOne = (WBTC == WBTC)? YES
// zeroForOne = true

// Interpretation:
// - We want WBTC (currency1) as output
// - So we're trading currency0 (ETH) → currency1 (WBTC)
// - Direction: 0 → 1, so zeroForOne = true ✅
```

**Step 4c: Build PoolKey**

```solidity
PoolKey memory poolKey = PoolKey({
    currency0: address(0),     // ETH
    currency1: WBTC,
    fee: 3000,
    tickSpacing: 60,
    hooks: address(0)
});
```

**Step 4d: Execute Swap**

```solidity
(int128 amount0, int128 amount1) = _swap({
    zeroForOne: true,
    poolKey: poolKey,
    amountSpecified: +1000000,  // +0.01 WBTC (POSITIVE = exact output)
    hookData: ""
});

// Pool calculates BACKWARDS and returns:
// amount0 = -400000000000000000  // Need to pay 0.4 ETH
// amount1 = +1000000              // Will receive 0.01 WBTC
```

**Step 4e: Prepare for Previous Hop**

```solidity
currencyOut = path.currency;  // ETH (for next iteration)
amountOut = (zeroForOne ? -amount0 : -amount1).toInt256();
// zeroForOne = true, so amountOut = -amount0
// amountOut = -(-400000000000000000) = +400000000000000000
// amountOut = +0.4 ETH (positive = exact output for previous hop)
```

**After Iteration 1**:
```solidity
currencyOut = ETH;           // Need ETH for next calculation
amountOut = 0.4 ether;       // Need exactly 0.4 ETH
```

---

**Iteration 2: i=1 (First Hop: USDC → ETH)**

```solidity
i = 1;
path = params.path[i - 1];  // params.path[0]
// path.currency = USDC (source currency)

currencyOut = ETH;  // What we need (from previous iteration)
```

**Step 4a: Determine Currency Pair**

```solidity
// Determine pool:
(address currency0, address currency1) = path.currency < currencyOut
    ? (path.currency, currencyOut)
    : (currencyOut, path.currency);

// ETH (0x000...) < USDC (0xA0b...)? YES  
// currency0 = ETH, currency1 = USDC
```

**Step 4b: Determine Direction**

```solidity
bool zeroForOne = currencyOut == currency1;
// zeroForOne = (ETH == USDC)? NO
// zeroForOne = false

// Interpretation:
// - We want ETH (currency0) as output
// - So we're trading currency1 (USDC) → currency0 (ETH)
// - Direction: 1 → 0, so zeroForOne = false ✅
```

**Step 4c: Build PoolKey**

```solidity
PoolKey memory poolKey = PoolKey({
    currency0: address(0),     // ETH
    currency1: USDC,
    fee: 500,
    tickSpacing: 10,
    hooks: address(0)
});
```

**Step 4d: Execute Swap**

```solidity
(int128 amount0, int128 amount1) = _swap({
    zeroForOne: false,
    poolKey: poolKey,
    amountSpecified: +400000000000000000,  // +0.4 ETH (POSITIVE = exact output)
    hookData: ""
});

// Pool calculates BACKWARDS:
// amount0 = +400000000000000000  // Will receive 0.4 ETH
// amount1 = -1005000000           // Need to pay 1005 USDC
```

**Step 4e: Prepare for "Next" (loop ends after this)**

```solidity
currencyOut = path.currency;  // USDC (source)
amountOut = (zeroForOne ? -amount0 : -amount1).toInt256();
// zeroForOne = false, so amountOut = -amount1
// amountOut = -(-1005000000) = +1005000000
// amountOut = +1005 USDC (required input!)
```

**After Loop Completion**:
```solidity
currencyOut = USDC;      // Initial input currency
amountOut = 1005e6;      // Required input amount
```

### Post-Loop: Settlement

#### Check Slippage (on INPUT)

```solidity
require(
    uint256(amountOut) <= uint256(params.amountInMax),
    "amount in > max"
);

// Check: 1005e6 <= 1100e6? ✅ YES
```

#### Transfer Input (NOW we know how much!)

```solidity
if (currencyOut != address(0)) {
    currencyOut.transferIn(caller, uint256(amountOut));
}

// Transfer 1005 USDC from user to router
```

**Why Transfer Here?** In exact output, we don't know the input amount until AFTER we calculate backwards through all hops!

#### Single Settlement

```solidity
_takeAndSettle({
    caller: caller,
    currencyIn: USDC,           // Calculated input
    amountIn: 1005e6,           // Calculated amount
    currencyOut: WBTC,          // Original output goal
    amountOut: 0.01e8          // Original amount goal
});
```

### Complete Example: Want Exactly 0.01 WBTC

**Setup**:
```solidity
// User wants EXACTLY 0.01 WBTC
// Has USDC, willing to pay up to 1100 USDC
// Route: USDC → ETH → WBTC (3 currencies)
```

**Step 1: Construct Parameters**:

```solidity
// For 3 currencies, we need 2 PathKey elements!
Router.PathKey[] memory path = new Router.PathKey[](2);

// path[0] = SOURCE currency
path[0] = Router.PathKey({
    currency: USDC_ADDRESS,    // Starting point (NOT intermediate!)
    fee: 500,
    tickSpacing: 10,
    hooks: address(0),
    hookData: ""
});

// path[1] = INTERMEDIATE currency
path[1] = Router.PathKey({
    currency: address(0),      // ETH (intermediate)
    fee: 3000,
    tickSpacing: 60,
    hooks: address(0),
    hookData: ""
});

// currencyOut = DESTINATION (NOT in path!)
ExactOutputParams memory params = ExactOutputParams({
    currencyOut: WBTC_ADDRESS,  // Final output (not in path array!)
    path: path,                 // [USDC, ETH] - no WBTC!
    amountOut: 0.01e8,          // Exactly 0.01 WBTC
    amountInMax: 1100e6         // Max 1100 USDC
});
```

**Step 2: Call Router**:

```solidity
// Approve router (for max amount)
IERC20(USDC).approve(address(router), 1100e6);

// Execute multi-hop exact output swap
uint256 amountIn = router.swapExactOutput(params);
// Returns: 1005000000 (1005 USDC actually used)
```

**Step 3: Execution** (detailed in loop breakdown above)

**Final Result**:
```solidity
// User received: Exactly 0.01 WBTC (as requested) ✅
// User paid: 1005 USDC (calculated amount)
// Refund: 95 USDC (1100 - 1005)
//
// Route taken (backwards calculation):
// 0.01 WBTC ← 0.4 ETH ← 1005 USDC
```

### Key Insights: Multi-Hop Exact Output

#### 1. Loop Goes Backwards

```solidity
// Forward definition:
path = [USDC, ETH]  // USDC → ETH → WBTC

// Backwards execution:
for (i = pathLength; i > 0; i--)  // 2, 1 (not 0, 1)
```

#### 2. Amount Negation

```solidity
// Each iteration:
amountOut = (zeroForOne ? -amount0 : -amount1).toInt256();

// Why negate? 
// Pool returns: "need to PAY X" (negative)
// Next iteration needs: "want to RECEIVE X" (positive)
// Negation flips the sign correctly
```

#### 3. Transfer After Calculation

```solidity
// Exact Input: Transfer BEFORE unlock
currencyIn.transferIn(msg.sender, amountIn);
poolManager.unlock(...);

// Exact Output: Transfer INSIDE callback AFTER calculation
poolManager.unlock(...);
  → callback calculates required input
  → currencyOut.transferIn(caller, amountOut);
```

#### 4. Direction Logic is Reversed

```solidity
// Exact Input: currencyIn determines direction
bool zeroForOne = currency0 == currencyIn;

// Exact Output: currencyOut determines direction
bool zeroForOne = currencyOut == currency1;
```

### Common Pitfalls: Multi-Hop Exact Output

#### Pitfall 1: Wrong Path Construction

```solidity
// For USDC → ETH → WBTC exact output:

// ❌ WRONG: Including destination in path
path[0] = PathKey({currency: USDC, ...});
path[1] = PathKey({currency: ETH, ...});
path[2] = PathKey({currency: WBTC, ...});  // NO! WBTC is currencyOut!

// ❌ WRONG: Backwards path
path[0] = PathKey({currency: ETH, ...});
path[1] = PathKey({currency: USDC, ...});

// ✅ CORRECT: Source and intermediate only (2 elements for 3 currencies)
path[0] = PathKey({currency: USDC, ...});  // Source
path[1] = PathKey({currency: ETH, ...});   // Intermediate
// currencyOut = WBTC (not in path!)
```

#### Pitfall 2: Insufficient `amountInMax`

```solidity
// ❌ WRONG: No slippage buffer
params.amountInMax = 1005e6;  // Exact expected
// If price moves slightly: REVERT

// ✅ CORRECT: Add buffer
params.amountInMax = 1105e6;  // ~10% buffer
```

#### Pitfall 3: Not Approving Enough

```solidity
// ❌ WRONG: Approve only expected
USDC.approve(router, 1005e6);
router.swapExactOutput({amountInMax: 1100e6, ...});
// Might REVERT if actually needs 1010 USDC

// ✅ CORRECT: Approve maximum
USDC.approve(router, 1100e6);
```

#### Pitfall 4: Forgetting It's a Different Path Structure

```solidity
// Exact Input (USDC → ETH → WBTC):
// - currencyIn = USDC (in params, not in path)
// - path[0].currency = ETH (first destination)
// - path[1].currency = WBTC (second destination, final output)

// Exact Output (USDC → ETH → WBTC):
// - path[0].currency = USDC (source)
// - path[1].currency = ETH (intermediate)
// - currencyOut = WBTC (in params, not in path)

// Key difference:
// - Exact Input: path contains DESTINATIONS
// - Exact Output: path contains SOURCE + INTERMEDIATES (not final destination!)
```

---

## Helper Functions: The Internal Machinery

The Router contract uses two critical internal helper functions that abstract complex operations. Understanding these is essential for implementing the callbacks correctly.

### `_swap()` - The Core Swap Executor

```solidity
function _swap(
    bool zeroForOne,
    PoolKey memory poolKey,
    int256 amountSpecified,
    bytes memory hookData
) internal returns (int128 amount0, int128 amount1) {
    BalanceDelta delta = poolManager.swap(
        poolKey,
        IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne
                ? MIN_PRICE_LIMIT
                : MAX_PRICE_LIMIT
        }),
        hookData
    );

    (amount0, amount1) = (delta.amount0(), delta.amount1());
}
```

**Purpose**: Executes a single swap on a specific pool and returns the exact amounts exchanged.

**Parameters Breakdown**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `zeroForOne` | `bool` | Direction: `true` = token0 → token1, `false` = token1 → token0 |
| `poolKey` | `PoolKey` | Identifies the pool (currencies, fee, tick spacing, hooks) |
| `amountSpecified` | `int256` | Positive = exact output, Negative = exact input |
| `hookData` | `bytes` | Optional data passed to pool hooks |

**Returns**:

| Return | Type | Description |
|--------|------|-------------|
| `amount0` | `int128` | Change in token0 balance (negative = paid, positive = received) |
| `amount1` | `int128` | Change in token1 balance (negative = paid, positive = received) |

#### Amount Signs Convention

| Sign | Meaning | Used For |
|------|---------|----------|
| **Negative** | Exact Input - "Spend exactly X tokens" | Exact Input Swaps |
| **Positive** | Exact Output - "Receive exactly X tokens" | Exact Output Swaps |

**Example**:

```solidity
// Exact Input: Spend exactly 1 ETH
_swap({
    zeroForOne: true,
    amountSpecified: -1e18,  // Negative = exact input
    ...
});
// Returns: amount0 = -1000000000000000000, amount1 = +2500000000
// Interpretation: Paid 1 ETH (token0), received 2500 USDC (token1)

// Exact Output: Receive exactly 0.01 WBTC
_swap({
    zeroForOne: true,
    amountSpecified: +1000000,  // Positive = exact output
    ...
});
// Returns: amount0 = -400000000000000000, amount1 = +1000000
// Interpretation: Paid 0.4 ETH (token0), received 0.01 WBTC (token1)
```

### `_takeAndSettle()` - The Settlement Function

```solidity
function _takeAndSettle(
    address caller,
    address currencyIn,
    uint256 amountIn,
    address currencyOut,
    uint256 amountOut
) internal {
    poolManager.take(
        Currency.wrap(currencyOut),
        caller,
        amountOut
    );

    poolManager.settle(Currency.wrap(currencyIn));
}
```

**Purpose**: Finalizes the swap by transferring tokens IN to the pool and OUT to the user.

**The Two Operations**:

#### 1. `take()` - Transfer Output to User

```solidity
poolManager.take(Currency.wrap(currencyOut), caller, amountOut);
```

**What It Does**: Transfers `amountOut` of `currencyOut` from the PoolManager's reserves to the `caller`. This creates a DEBT for the Router in the PoolManager's accounting system.

#### 2. `settle()` - Pay Input Debt

```solidity
poolManager.settle(Currency.wrap(currencyIn));
```

**What It Does**: Settles the Router's debt by transferring tokens from the Router's balance to the PoolManager. The Router must already have the tokens (transferred earlier via `transferIn`).

---

## Tasks Overview

Now that you understand the architecture and helper functions, here are the implementation tasks:

## Task 1 - Swap Exact Input Single

```solidity
function swapExactInputSingle(ExactInputSingleParams calldata params)
    external
    payable
    setAction(SWAP_EXACT_IN_SINGLE)
    returns (uint256 amountOut)
{
    // Write your code here
}
```

- Determine the input currency based on the swap direction (`zeroForOne`).
- Transfer the input amount from the caller to the router (skip if native currency).
- Unlock the `PoolManager` contract by encoding `msg.sender` and `params`.
- Decode the `amountOut` from the unlock callback response.
- Refund any remaining input currency back to the caller.

## Task 2 - Swap Exact Output Single

```solidity
function swapExactOutputSingle(ExactOutputSingleParams calldata params)
    external
    payable
    setAction(SWAP_EXACT_OUT_SINGLE)
    returns (uint256 amountIn)
{
    // Write your code here
}
```

- Determine the input currency based on the swap direction (`zeroForOne`).
- Transfer the maximum input amount (`amountInMax`) from the caller to the router.
- Unlock the `PoolManager` contract by encoding `msg.sender` and `params`.
- Decode the actual `amountIn` used from the unlock callback response.
- Refund any unused input currency back to the caller.

## Task 3 - Swap Exact Input (Multi-hop)

```solidity
function swapExactInput(ExactInputParams calldata params)
    external
    payable
    setAction(SWAP_EXACT_IN)
    returns (uint256 amountOut)
{
    // Write your code here
}
```

- Transfer the input amount from the caller to the router (skip if native currency).
- Unlock the `PoolManager` contract by encoding `msg.sender` and `params`.
- Decode the final `amountOut` from the unlock callback response.
- Refund any remaining input currency back to the caller.

## Task 4 - Swap Exact Output (Multi-hop)

```solidity
function swapExactOutput(ExactOutputParams calldata params)
    external
    payable
    setAction(SWAP_EXACT_OUT)
    returns (uint256 amountIn)
{
    // Write your code here
}
```

- Determine the input currency from the first element in the path.
- Transfer the maximum input amount from the caller to the router.
- Unlock the `PoolManager` contract by encoding `msg.sender` and `params`.
- Decode the actual `amountIn` used from the unlock callback response.
- Refund any unused input currency back to the caller.

## Task 5 - Unlock Callback

```solidity
function unlockCallback(bytes calldata data)
    external
    onlyPoolManager
    returns (bytes memory)
{
    uint256 action = _getAction();
    // Write your code here
}
```

This function handles all four swap types. For each action:

### SWAP_EXACT_IN_SINGLE

- Decode `caller` and `ExactInputSingleParams` from data.
- Execute the swap using `_swap()` with negative `amountIn`.
- Determine `currencyIn`, `currencyOut`, `amountIn`, and `amountOut` based on `zeroForOne`.
- Verify `amountOut >= amountOutMin`.
- Call `_takeAndSettle()` to finalize the swap.
- Return encoded `amountOut`.

### SWAP_EXACT_OUT_SINGLE

- Decode `caller` and `ExactOutputSingleParams` from data.
- Execute the swap using `_swap()` with positive `amountOut`.
- Determine `currencyIn`, `currencyOut`, `amountIn`, and `amountOut` based on `zeroForOne`.
- Verify `amountIn <= amountInMax`.
- Call `_takeAndSettle()` to finalize the swap.
- Return encoded `amountIn`.

### SWAP_EXACT_IN (Multi-hop)

- Decode `caller` and `ExactInputParams` from data.
- Initialize `currencyIn` and `amountIn` from params.
- Loop through each hop in the path:
  - Determine `currency0` and `currency1` by comparing addresses.
  - Build the `PoolKey` for the current hop.
  - Determine `zeroForOne` direction.
  - Execute `_swap()` with negative `amountIn`.
  - Update `currencyIn` to the next currency in the path.
  - Update `amountIn` to the output of the current swap.
- Verify final output `>= amountOutMin`.
- Call `_takeAndSettle()` with the initial and final currencies/amounts.
- Return encoded final `amountOut`.

### SWAP_EXACT_OUT (Multi-hop)

- Decode `caller` and `ExactOutputParams` from data.
- Initialize `currencyOut` and `amountOut` from params.
- Loop backwards through the path:
  - Determine `currency0` and `currency1` by comparing addresses.
  - Build the `PoolKey` for the current hop.
  - Determine `zeroForOne` direction (output currency determines direction).
  - Execute `_swap()` with positive `amountOut`.
  - Update `currencyOut` to the previous currency in the path.
  - Update `amountOut` to the negative input of the current swap.
- Verify final input `<= amountInMax`.
- Call `_takeAndSettle()` with the initial and final currencies/amounts.
- Return encoded final `amountIn`.

---

## Real-World Usage Examples

### Example 1: Simple ETH → USDC Swap

**Scenario**: User wants to sell exactly 1 ETH for USDC with 0.5% slippage tolerance.

```solidity
// 1. Calculate minimum output (0.5% slippage)
uint256 expectedUSDC = 2500e6;  // Assume 1 ETH = 2500 USDC
uint256 minOutput = expectedUSDC * 995 / 1000;  // 2487.5 USDC

// 2. Prepare parameters
Router.ExactInputSingleParams memory params = Router.ExactInputSingleParams({
    poolKey: PoolKey({
        currency0: address(0),          // ETH
        currency1: USDC_ADDRESS,        // USDC
        fee: 3000,                      // 0.3%
        tickSpacing: 60,
        hooks: address(0)
    }),
    zeroForOne: true,                   // ETH → USDC
    amountIn: 1 ether,
    amountOutMin: minOutput,
    hookData: ""
});

// 3. Execute swap (send ETH with call)
uint256 amountOut = router.swapExactInputSingle{value: 1 ether}(params);

// Result: Received 2493 USDC (within slippage)
```

### Example 2: Buy Exact Amount of Token

**Scenario**: User needs exactly 0.5 WBTC, willing to pay up to 11 ETH.

```solidity
// 1. Prepare parameters
Router.ExactOutputSingleParams memory params = Router.ExactOutputSingleParams({
    poolKey: PoolKey({
        currency0: address(0),          // ETH
        currency1: WBTC_ADDRESS,        // WBTC
        fee: 3000,
        tickSpacing: 60,
        hooks: address(0)
    }),
    zeroForOne: true,                   // ETH → WBTC
    amountOut: 0.5e8,                   // Exactly 0.5 WBTC
    amountInMax: 11 ether,              // Max 11 ETH
    hookData: ""
});

// 2. Execute swap (send max ETH)
uint256 amountIn = router.swapExactOutputSingle{value: 11 ether}(params);

// Result: 
// - Received: Exactly 0.5 WBTC ✅
// - Paid: 10.3 ETH
// - Refunded: 0.7 ETH (11 - 10.3)
```

### Example 3: Multi-Hop Arbitrage

**Scenario**: Swap DAI → USDC → WETH → WBTC to exploit price differences.

```solidity
// 1. Build path
Router.PathKey[] memory path = new Router.PathKey[](3);

// Hop 1: DAI → USDC
path[0] = Router.PathKey({
    currency: USDC_ADDRESS,
    fee: 100,        // 0.01% (stablecoin pair)
    tickSpacing: 1,
    hooks: address(0),
    hookData: ""
});

// Hop 2: USDC → WETH
path[1] = Router.PathKey({
    currency: address(0),  // WETH
    fee: 3000,
    tickSpacing: 60,
    hooks: address(0),
    hookData: ""
});

// Hop 3: WETH → WBTC
path[2] = Router.PathKey({
    currency: WBTC_ADDRESS,
    fee: 3000,
    tickSpacing: 60,
    hooks: address(0),
    hookData: ""
});

// 2. Prepare parameters
Router.ExactInputParams memory params = Router.ExactInputParams({
    currencyIn: DAI_ADDRESS,
    path: path,
    amountIn: 10000e18,        // 10,000 DAI
    amountOutMin: 0.15e8       // Min 0.15 WBTC
});

// 3. Approve and execute
IERC20(DAI).approve(address(router), 10000e18);
uint256 amountOut = router.swapExactInput(params);

// Result: Received 0.16 WBTC from 10,000 DAI
```

### Example 4: Limit Order Simulation

**Scenario**: Only execute swap if can get at least target price.

```solidity
// Target: 1 WBTC = 20 ETH maximum
uint256 targetWBTC = 1e8;
uint256 maxETH = 20 ether;

Router.ExactOutputSingleParams memory params = Router.ExactOutputSingleParams({
    poolKey: PoolKey({
        currency0: address(0),
        currency1: WBTC_ADDRESS,
        fee: 3000,
        tickSpacing: 60,
        hooks: address(0)
    }),
    zeroForOne: true,
    amountOut: targetWBTC,
    amountInMax: maxETH,
    hookData: ""
});

try router.swapExactOutputSingle{value: maxETH}(params) returns (uint256 amountIn) {
    console.log("Swap executed! Paid:", amountIn);
    // Refund: (maxETH - amountIn) automatically sent back
} catch {
    console.log("Price too high, swap not executed");
    // All ETH refunded
}
```

---

## Troubleshooting Guide

### Error: "amount in > max"

**Cause**: In exact output swaps, the calculated input exceeded `amountInMax`.

**Solutions**:
```solidity
// ❌ Problem
params.amountInMax = 1000e6;  // Too tight

// ✅ Solution 1: Increase max
params.amountInMax = 1100e6;  // Add 10% buffer

// ✅ Solution 2: Use exact input instead
// If you can't accept uncertainty, switch to exact input swaps
```

### Error: "amount out < min"

**Cause**: In exact input swaps, the output was less than `amountOutMin`.

**Solutions**:
```solidity
// ❌ Problem
params.amountOutMin = 2500e6;  // Too optimistic

// ✅ Solution 1: Decrease minimum
params.amountOutMin = 2450e6;  // More realistic (2% slippage)

// ✅ Solution 2: Split into smaller swaps
// Large swaps have more slippage
router.swapExactInputSingle({amountIn: 0.5 ether, ...});
router.swapExactInputSingle({amountIn: 0.5 ether, ...});
```

### Error: "STF" (SafeTransferFrom failed)

**Cause**: Token transfer failed, usually due to insufficient approval or balance.

**Solutions**:
```solidity
// ❌ Problem
IERC20(token).approve(router, 1000e6);
router.swapExactInput({amountIn: 2000e6, ...});  // Not enough approval

// ✅ Solution 1: Approve enough
IERC20(token).approve(router, type(uint256).max);

// ✅ Solution 2: Check balance first
uint256 balance = IERC20(token).balanceOf(msg.sender);
require(balance >= amountIn, "Insufficient balance");
```

### Error: "Invalid pool"

**Cause**: The specified pool doesn't exist in PoolManager.

**Solutions**:
```solidity
// ❌ Problem
PoolKey({
    currency0: USDC,
    currency1: DAI,
    fee: 3000,
    tickSpacing: 60,   // Wrong! USDC/DAI usually uses tickSpacing=1
    hooks: address(0)
});

// ✅ Solution: Verify pool exists
// Check on Uniswap interface or etherscan
// Stablecoin pairs typically use:
// - fee: 100 (0.01%)
// - tickSpacing: 1
```

### Error: "Unauthorized" in `unlockCallback`

**Cause**: Someone other than PoolManager called the callback.

**Solutions**:
```solidity
// This is a security check - don't remove it!
function unlockCallback(bytes calldata data) 
    external
    onlyPoolManager  // ← This prevents attacks
    returns (bytes memory)
{
    // Implementation
}

// If error persists, verify:
// - poolManager address is correct
// - You're calling unlock from the right place
```

### Error: Wrong output amount in multi-hop

**Cause**: Path construction error or wrong loop logic.

**Debug Steps**:

```solidity
// Add logging to each hop
for (uint256 i = 0; i < pathLength; i++) {
    console.log("Hop", i);
    console.log("  Input:", currencyIn, amountIn);
    
    (int128 amount0, int128 amount1) = _swap(...);
    
    console.log("  amount0:", amount0);
    console.log("  amount1:", amount1);
    console.log("  Output:", currencyOut, amountOut);
}

// Check:
// 1. Is path[] in correct order?
// 2. Is zeroForOne calculated correctly each hop?
// 3. Is amountIn updated correctly for next hop?
```

---

## Frequently Asked Questions

### Q1: What's the difference between Router and Swap contracts?

**Swap Contract**:
- Single pool only
- Direct pool interaction
- Simpler, more gas efficient
- Limited routing capabilities

**Router Contract**:
- Multi-hop routing
- Handles complex paths
- More flexible
- Slightly higher gas cost

**When to use which?**
- Use **Swap** for direct pool swaps (A → B in one pool)
- Use **Router** for multi-hop routes (A → B → C across pools)

### Q2: Why do we need both exact input AND exact output?

**Different Use Cases**:

| Scenario | Use Exact Input | Use Exact Output |
|----------|----------------|------------------|
| "Sell all my 10 ETH" | ✅ YES | ❌ NO |
| "Buy exactly 1 WBTC" | ❌ NO | ✅ YES |
| "Convert my entire balance" | ✅ YES | ❌ NO |
| "Need exact amount for payment" | ❌ NO | ✅ YES |
| "DCA strategy (fixed input)" | ✅ YES | ❌ NO |
| "Repay exact debt amount" | ❌ NO | ✅ YES |

### Q3: How do I handle native ETH vs WETH?

**Native ETH** (address(0)):
```solidity
// Sending ETH
router.swapExactInputSingle{value: 1 ether}(params);

// Receiving ETH
// Router automatically sends ETH, no wrapping needed
```

**WETH** (token address):
```solidity
// Sending WETH
IERC20(WETH).approve(router, 1 ether);
router.swapExactInputSingle(params);  // No {value:}

// Receiving WETH
// Router sends WETH tokens to your address
```

**Key**: Use `currency0/currency1 = address(0)` for native ETH, use WETH address for wrapped ETH.

### Q4: How much slippage should I set?

**Guidelines**:

| Pair Type | Volatility | Recommended Slippage |
|-----------|------------|---------------------|
| Stablecoins (USDC/DAI) | Very Low | 0.1% - 0.5% |
| Major pairs (ETH/USDC) | Low | 0.5% - 1% |
| Altcoins | Medium | 1% - 3% |
| Low liquidity | High | 3% - 5% |
| Multi-hop (3+ hops) | Varies | 2% - 5% |

**Formula**:
```solidity
// For exact input:
uint256 minOutput = expectedOutput * (10000 - slippageBps) / 10000;
// 1% slippage = 100 bps
// minOutput = expected * 9900 / 10000

// For exact output:
uint256 maxInput = expectedInput * (10000 + slippageBps) / 10000;
// 1% slippage = 100 bps
// maxInput = expected * 10100 / 10000
```

### Q5: Can I use hooks with the Router?

**Yes!** Specify hooks in the `PoolKey`:

```solidity
PoolKey({
    currency0: token0,
    currency1: token1,
    fee: 3000,
    tickSpacing: 60,
    hooks: HOOK_CONTRACT_ADDRESS,  // ← Your hook
})

// Pass hook data:
ExactInputSingleParams({
    ...,
    hookData: abi.encode(customData)  // ← Passed to hooks
})
```

**Hook Execution Points**:
- `beforeSwap()` - Before each swap
- `afterSwap()` - After each swap
- In multi-hop, hooks are called for EACH hop

### Q6: What's the gas cost comparison?

**Approximate Gas Costs** (mainnet):

| Operation | Gas Cost |
|-----------|----------|
| Single-hop exact input | ~120k |
| Single-hop exact output | ~130k |
| 2-hop exact input | ~200k |
| 2-hop exact output | ~220k |
| 3-hop exact input | ~280k |
| 3-hop exact output | ~310k |

**Why exact output costs more?**
- Backwards calculation
- Additional arithmetic
- Slippage check on calculated value

### Q7: Can I implement custom routing logic?

**Yes!** Extend the Router:

```solidity
contract CustomRouter is Router {
    function smartRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        // 1. Query multiple paths
        PathKey[] memory path1 = _getDirectPath(tokenIn, tokenOut);
        PathKey[] memory path2 = _getIndirectPath(tokenIn, tokenOut);
        
        // 2. Simulate both (off-chain or via quoter)
        uint256 out1 = quoter.quote(path1, amountIn);
        uint256 out2 = quoter.quote(path2, amountIn);
        
        // 3. Choose best path
        PathKey[] memory bestPath = out1 > out2 ? path1 : path2;
        
        // 4. Execute
        return swapExactInput(ExactInputParams({
            currencyIn: tokenIn,
            path: bestPath,
            amountIn: amountIn,
            amountOutMin: /* calculate */
        }));
    }
}
```

---

## Best Practices

### 1. Always Set Realistic Slippage

```solidity
// ❌ BAD: Zero slippage (will fail often)
params.amountOutMin = expectedOutput;

// ✅ GOOD: Reasonable buffer
params.amountOutMin = expectedOutput * 99 / 100;  // 1% slippage
```

### 2. Approve Once, Use Many Times

```solidity
// ✅ GOOD: Infinite approval (saves gas)
IERC20(token).approve(router, type(uint256).max);

// Then multiple swaps without re-approving
router.swapExactInputSingle(params1);
router.swapExactInputSingle(params2);
```

### 3. Check Pool Existence Before Swapping

```solidity
// ✅ GOOD: Verify pool exists
PoolId poolId = poolKey.toId();
(uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
require(sqrtPriceX96 != 0, "Pool doesn't exist");

// Then swap
router.swapExactInputSingle(params);
```

### 4. Use Try/Catch for Price Protection

```solidity
// ✅ GOOD: Graceful failure
try router.swapExactOutputSingle(params) returns (uint256 amountIn) {
    emit SwapExecuted(amountIn);
} catch Error(string memory reason) {
    emit SwapFailed(reason);
    // Handle failure (e.g., return funds to user)
}
```

### 5. Consider Gas Costs for Multi-Hop

```solidity
// ❌ POTENTIALLY BAD: 5-hop route
path = [USDC, DAI, USDT, WETH, WBTC];  // Very expensive gas

// ✅ BETTER: Split into 2 swaps or find shorter path
// Swap 1: USDC → WETH
// Swap 2: WETH → WBTC
// Total: 2 transactions but possibly cheaper than 1 multi-hop
```

### 6. Batch Approvals for Multiple Tokens

```solidity
// ✅ GOOD: Approve all tokens at once
address[] memory tokens = [USDC, DAI, WETH];
for (uint i = 0; i < tokens.length; i++) {
    IERC20(tokens[i]).approve(router, type(uint256).max);
}
```

### 7. Use Events for Debugging

```solidity
// Add to your wrapper:
event SwapExecuted(
    address indexed user,
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut
);

function mySwap(...) external {
    uint256 amountOut = router.swapExactInputSingle(params);
    emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
}
```

---

## Conclusion

The **Router** contract represents a sophisticated multi-hop routing solution for Uniswap V4, built on top of the fundamental swap primitives. It enables complex trading strategies through:

### Key Capabilities

1. **Four Swap Modes**: Single-hop and multi-hop, exact input and exact output
2. **Flexible Routing**: Arbitrary paths through multiple pools
3. **Gas Efficiency**: Single settlement for multi-hop routes via flash accounting
4. **Slippage Protection**: Built-in checks for both input and output swaps

### Implementation Checklist

When implementing your Router exercise, ensure you:

- [ ] Handle all four action types correctly in `unlockCallback`
- [ ] Implement proper direction logic (`zeroForOne`) for each hop
- [ ] Use correct sign convention for `amountSpecified` (negative = exact in, positive = exact out)
- [ ] Loop forward for exact input, backwards for exact output
- [ ] Extract amounts correctly based on swap direction
- [ ] Verify slippage (output for exact in, input for exact out)
- [ ] Transfer tokens at the right time (before for exact in, after calculation for exact out)
- [ ] Call `_takeAndSettle` with first and last currencies only
- [ ] Return correctly encoded values from callback

### Next Steps

1. **Complete the Exercise**: Implement all functions following the patterns in this guide
2. **Run Tests**: Verify your implementation with `forge test`
3. **Study the Solution**: Compare with `solutions/Router.sol` to see alternative approaches
4. **Experiment**: Try creating custom routing logic or integrating with quoter contracts
5. **Deploy**: Test on testnet with real multi-hop routes

### Further Learning

- **Quoter Contract**: Learn to simulate swaps before executing
- **Universal Router**: Study how Uniswap combines V2/V3/V4 routing
- **Custom Hooks**: Implement pools with special routing logic
- **MEV Protection**: Explore private mempools and sandwich attack prevention

The Router is your gateway to building sophisticated DeFi applications on Uniswap V4. Master it, and you'll understand the backbone of decentralized exchange routing! 🚀

---

## Test

```shell
forge test --fork-url $FORK_URL --fork-block-number $FORK_BLOCK_NUM --match-path test/Router.test.sol -vvv
```
