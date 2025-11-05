# Uniswap V4 CounterHook - Complete Technical Guide

## Introduction

This document provides an in-depth technical explanation of the `CounterHook.sol` contract and how to build custom hooks for Uniswap V4. Hooks are one of the most powerful features of Uniswap V4, allowing developers to add custom logic that executes before and after key pool operations.

### What You'll Learn

- How to create a custom hook contract for Uniswap V4
- Understanding hook permissions and validation
- Implementing hook callback functions for swaps, liquidity operations
- How to track and store hook-specific data per pool
- The hook address mining process and CREATE2 deployment
- Best practices for hook development and testing

### Key Concepts

**Hook**: A smart contract that can inject custom logic before and after pool operations (swaps, liquidity changes, donations, initialization).

**Hook Permissions**: A bitmap that declares which pool operations your hook wants to intercept.

**Hook Address Mining**: The process of finding a CREATE2 salt that produces an address with specific prefix bits matching your enabled permissions.

**PoolId**: A unique identifier for each pool, computed from the PoolKey (currency0, currency1, fee, tickSpacing, hooks).

**Function Selector**: The first 4 bytes of a function's keccak256 hash, used to verify successful hook execution.

## Contract Overview

The `CounterHook.sol` contract demonstrates how to build a simple but complete hook that counts the number of times specific operations occur on a pool. This is part of the Cyfrin Updraft Uniswap V4 course exercises.

### Core Features

| Feature | Description |
|---------|-------------|
| **Operation Counting** | Tracks beforeSwap, afterSwap, beforeAddLiquidity, beforeRemoveLiquidity calls |
| **Per-Pool Storage** | Maintains separate counters for each pool using PoolId |
| **Selective Hooks** | Only implements 4 out of 14 possible hook functions |
| **Permission Validation** | Validates hook address matches enabled permissions |
| **Security** | Restricts callback access to PoolManager only |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Architecture Pattern**: Hook callback-based
- **Deployment Method**: CREATE2 with salt mining
- **Hook Permissions**: beforeSwap, afterSwap, beforeAddLiquidity, beforeRemoveLiquidity
- **Storage Pattern**: Nested mapping (PoolId → operation name → count)

## Understanding Uniswap V4 Hooks

### What Are Hooks?

Hooks are smart contracts that can execute custom logic at specific points in a pool's lifecycle:

```
Pool Operation Lifecycle:
┌─────────────────┐
│  beforeSwap()   │ ← Hook can intercept here
├─────────────────┤
│  Core Swap      │ ← PoolManager executes
├─────────────────┤
│  afterSwap()    │ ← Hook can intercept here
└─────────────────┘
```

### The 14 Hook Functions

Uniswap V4 provides 14 potential hook points:

| Hook Function | When It Executes | Can Return Delta |
|---------------|------------------|------------------|
| `beforeInitialize` | Before pool initialization | No |
| `afterInitialize` | After pool initialization | No |
| `beforeAddLiquidity` | Before adding liquidity | No |
| `afterAddLiquidity` | After adding liquidity | Yes (with permission) |
| `beforeRemoveLiquidity` | Before removing liquidity | No |
| `afterRemoveLiquidity` | After removing liquidity | Yes (with permission) |
| `beforeSwap` | Before executing swap | Yes (with permission) |
| `afterSwap` | After executing swap | Yes (with permission) |
| `beforeDonate` | Before donating to fees | No |
| `afterDonate` | After donating to fees | No |

**Delta Return Permissions** (4 additional flags):
- `beforeSwapReturnDelta`: Allows beforeSwap to modify swap amounts
- `afterSwapReturnDelta`: Allows afterSwap to modify swap amounts
- `afterAddLiquidityReturnDelta`: Allows afterAddLiquidity to modify amounts
- `afterRemoveLiquidityReturnDelta`: Allows afterRemoveLiquidity to modify amounts

### Hook Address Requirements

**Critical**: A hook's address must have specific bits set based on its enabled permissions!

```solidity
// Hook address format (last 2 bytes):
0x...XXXX
     ││││
     ││││└─ Bit 0: beforeInitialize
     │││└── Bit 1: afterInitialize
     ││└─── Bit 2: beforeAddLiquidity
     │└──── Bit 3: afterAddLiquidity
     └───── etc. (14 bits total)
```

**Example**:
```
Permissions enabled:
- beforeAddLiquidity (bit 2)
- beforeRemoveLiquidity (bit 4)
- beforeSwap (bit 6)
- afterSwap (bit 7)

Required address bits: 0b11010100 = 0xD4
Hook address must end with: 0x...XXD4
```

This is enforced by `Hooks.validateHookPermissions()` during deployment.

## Contract Architecture

### Dependencies and Imports

#### Core Imports

```solidity
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "../types/PoolOperation.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../types/BeforeSwapDelta.sol";
```

| Interface/Library | Purpose | Key Usage |
|-------------------|---------|-----------|
| `IPoolManager` | Pool operations coordinator | Reference to call operations |
| `Hooks` | Hook utilities | `validateHookPermissions()`, `Permissions` struct |
| `PoolIdLibrary` | Pool identification | `toId()` - Convert PoolKey to PoolId |
| `PoolKey` | Pool identifier struct | Passed to every hook function |
| `SwapParams` | Swap parameters | Passed to swap hooks |
| `ModifyLiquidityParams` | Liquidity operation params | Passed to liquidity hooks |
| `BalanceDelta` | Balance change tracking | Passed to after hooks |
| `BeforeSwapDelta` | Pre-swap delta modifications | Returned by beforeSwap if enabled |

### State Variables

```solidity
IPoolManager public immutable poolManager;
mapping(PoolId => mapping(string => uint256)) public counts;
```

| Variable | Type | Purpose |
|----------|------|---------|
| `poolManager` | `IPoolManager` | Reference to Uniswap V4's pool coordinator |
| `counts` | `mapping(PoolId => mapping(string => uint256))` | Tracks operation counts per pool |

**Storage Pattern Explanation**:

```solidity
// Access count for a specific pool and operation:
PoolId poolId = poolKey.toId();
uint256 swapCount = counts[poolId]["beforeSwap"];

// Example:
// Pool 1 (ETH/USDC): 100 swaps, 10 liquidity adds
// Pool 2 (DAI/USDC): 50 swaps, 5 liquidity adds
```

### Custom Errors

```solidity
error NotPoolManager();
error HookNotImplemented();
```

| Error | When Thrown | Purpose |
|-------|-------------|---------|
| `NotPoolManager()` | Callback called by non-PoolManager | Security check |
| `HookNotImplemented()` | Hook function not enabled but called | Placeholder for unused hooks |

### Access Control

```solidity
modifier onlyPoolManager() {
    if (msg.sender != address(poolManager)) revert NotPoolManager();
    _;
}
```

**Security**: Ensures only the PoolManager can invoke hook callbacks, preventing:
- Unauthorized state changes
- Fake hook calls
- Replay attacks

## Constructor and Deployment

### Constructor Implementation

```solidity
constructor(address _poolManager) {
    poolManager = IPoolManager(_poolManager);
    Hooks.validateHookPermissions(address(this), getHookPermissions());
}
```

**Step-by-Step Breakdown**:

#### Step 1: Store PoolManager Reference

```solidity
poolManager = IPoolManager(_poolManager);
```

**Purpose**: Save immutable reference to the PoolManager for all future interactions.

**Why Immutable?** 
- Gas savings (no SLOAD needed)
- Security (can't be changed after deployment)
- Trust (users know which PoolManager this hook works with)

#### Step 2: Validate Hook Permissions

```solidity
Hooks.validateHookPermissions(address(this), getHookPermissions());
```

**What This Does**:

1. **Gets hook address**: `address(this)` - The deployed address of this contract
2. **Gets permissions**: `getHookPermissions()` - Returns which hooks are enabled
3. **Extracts address bits**: Takes last 14 bits of the address
4. **Compares with permissions**: Ensures address bits match enabled hooks
5. **Reverts if mismatch**: Prevents deployment with wrong address

**Why This Matters**:

```solidity
// ❌ WRONG: Address doesn't match permissions
// Address: 0x...1234
// Required: 0x...00D4 (based on enabled hooks)
// Result: Transaction REVERTS in constructor

// ✅ CORRECT: Address matches permissions
// Address: 0x...00D4
// Required: 0x...00D4
// Result: Deployment succeeds
```

### Hook Address Mining Process

**Problem**: You need a contract address with specific bits set BEFORE deployment.

**Solution**: Use CREATE2 with salt mining.

#### Step 1: Calculate Required Address Pattern

```solidity
function getHookPermissions() public pure returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize: false,           // Bit 0: 0
        afterInitialize: false,            // Bit 1: 0
        beforeAddLiquidity: true,          // Bit 2: 1
        afterAddLiquidity: false,          // Bit 3: 0
        beforeRemoveLiquidity: true,       // Bit 4: 1
        afterRemoveLiquidity: false,       // Bit 5: 0
        beforeSwap: true,                  // Bit 6: 1
        afterSwap: true,                   // Bit 7: 1
        beforeDonate: false,               // Bit 8: 0
        afterDonate: false,                // Bit 9: 0
        beforeSwapReturnDelta: false,      // Bit 10: 0
        afterSwapReturnDelta: false,       // Bit 11: 0
        afterAddLiquidityReturnDelta: false,    // Bit 12: 0
        afterRemoveLiquidityReturnDelta: false  // Bit 13: 0
    });
}
```

**Bit Pattern**: `0b00000011010100` = `0x00D4`

**Required Address**: `0x????????????????????????????????????????????????00D4`

#### Step 2: Run Salt Mining Script

```bash
# Run FindHookSalt.test.sol
forge test --match-path test/FindHookSalt.test.sol -vvv

# Output will show found salt:
# Found salt: 0x1234567890abcdef...
```

**What The Script Does**:

```solidity
// Pseudo-code of salt mining:
for (uint256 salt = 0; salt < type(uint256).max; salt++) {
    address predictedAddress = computeCreate2Address(
        deployer,
        salt,
        keccak256(contractBytecode)
    );
    
    uint160 addressBits = uint160(predictedAddress);
    uint16 lastTwoBytes = uint16(addressBits);
    
    if (lastTwoBytes & PERMISSION_MASK == REQUIRED_PATTERN) {
        console.log("Found salt:", salt);
        return salt;
    }
}
```

#### Step 3: Deploy With Found Salt

```bash
# Set the found salt
export SALT=0x1234567890abcdef...

# Deploy with CREATE2
new CounterHook{salt: salt}(POOL_MANAGER);
```

**CREATE2 Deployment**:

```solidity
// In test/deployment:
bytes32 salt = vm.envBytes32("SALT");
hook = new CounterHook{salt: salt}(POOL_MANAGER);

// Behind the scenes:
address predictedAddress = keccak256(
    0xff,
    deployer,
    salt,
    keccak256(contractBytecode)
);

// Result: Address with correct bit pattern!
```

## Hook Permissions Function

### `getHookPermissions()` - Declare Your Hooks

```solidity
function getHookPermissions()
    public
    pure
    returns (Hooks.Permissions memory)
{
    return Hooks.Permissions({
        beforeInitialize: false,
        afterInitialize: false,
        beforeAddLiquidity: true,
        afterAddLiquidity: false,
        beforeRemoveLiquidity: true,
        afterRemoveLiquidity: false,
        beforeSwap: true,
        afterSwap: true,
        beforeDonate: false,
        afterDonate: false,
        beforeSwapReturnDelta: false,
        afterSwapReturnDelta: false,
        afterAddLiquidityReturnDelta: false,
        afterRemoveLiquidityReturnDelta: false
    });
}
```

**Purpose**: Declares which hook functions this contract implements.

**Enabled Hooks** (set to `true`):
1. ✅ `beforeAddLiquidity` - Called before liquidity is added
2. ✅ `beforeRemoveLiquidity` - Called before liquidity is removed
3. ✅ `beforeSwap` - Called before a swap executes
4. ✅ `afterSwap` - Called after a swap completes

**Disabled Hooks** (set to `false`):
- ❌ All initialization hooks
- ❌ After liquidity hooks
- ❌ Donation hooks
- ❌ All delta return permissions

### Why Selective Implementation?

**Gas Efficiency**:
```solidity
// ❌ BAD: Implementing all hooks
// Gas cost per operation: HIGH (14 callbacks)

// ✅ GOOD: Only implement needed hooks
// Gas cost per operation: LOWER (4 callbacks max)
```

**Complexity**:
```solidity
// ❌ BAD: Unused hooks add code complexity
function afterDonate(...) external {
    revert HookNotImplemented();  // Dead code!
}

// ✅ GOOD: Only implement what you need
// Less code = fewer bugs
```

## Implemented Hook Functions

### 1. `beforeSwap()` - Pre-Swap Hook

```solidity
function beforeSwap(
    address sender,
    PoolKey calldata key,
    SwapParams calldata params,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
    counts[key.toId()]["beforeSwap"]++;
    return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
}
```

**When Called**: Immediately before a swap is executed in the PoolManager.

**Parameters Breakdown**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `sender` | `address` | The address that initiated the swap |
| `key` | `PoolKey` | Identifies the pool (currency0, currency1, fee, tickSpacing, hooks) |
| `params` | `SwapParams` | Swap details (zeroForOne, amountSpecified, sqrtPriceLimitX96) |
| `hookData` | `bytes` | Custom data passed from the swapper to the hook |

**Return Values**:

| Return | Type | Meaning |
|--------|------|---------|
| `bytes4` | Function selector | Must return `this.beforeSwap.selector` to confirm success |
| `BeforeSwapDelta` | Delta struct | Amount adjustments (ZERO_DELTA = no changes) |
| `uint24` | LP fee override | Override fee (0 = use pool's default fee) |

**Execution Flow**:

```
User calls swap()
       ↓
PoolManager.swap()
       ↓
hook.beforeSwap() ← We are here
       ↓
[Hook increments counter]
       ↓
[Returns success selector]
       ↓
PoolManager executes actual swap
       ↓
hook.afterSwap()
```

**Code Breakdown**:

#### Step 1: Increment Counter

```solidity
counts[key.toId()]["beforeSwap"]++;
```

**What Happens**:
1. `key.toId()` - Converts PoolKey to unique PoolId hash
2. Access nested mapping: `counts[poolId]["beforeSwap"]`
3. Increment the counter by 1

**Example**:
```solidity
// Pool: ETH/USDC
PoolId poolId = key.toId();  // 0xabc123...

// First swap:
counts[poolId]["beforeSwap"] = 0 → 1

// Second swap:
counts[poolId]["beforeSwap"] = 1 → 2
```

#### Step 2: Return Success

```solidity
return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
```

**Return Value 1: Function Selector**
```solidity
this.beforeSwap.selector
// = bytes4(keccak256("beforeSwap(address,PoolKey,SwapParams,bytes)"))
// = 0x... (first 4 bytes)
```

**Why?** PoolManager verifies the hook executed successfully by checking this selector matches.

**Return Value 2: BeforeSwapDelta**
```solidity
BeforeSwapDeltaLibrary.ZERO_DELTA
// = No amount adjustments
// Hook doesn't want to modify swap amounts
```

**If we wanted to modify amounts** (requires `beforeSwapReturnDelta` permission):
```solidity
// Example: Take 1% fee on input
BeforeSwapDelta delta = toBeforeSwapDelta(
    int128(amountSpecified / 100),  // specified delta
    0                                // unspecified delta
);
return (selector, delta, 0);
```

**Return Value 3: LP Fee Override**
```solidity
0  // Use pool's default fee (e.g., 3000 = 0.3%)
```

**If we wanted to override fee**:
```solidity
// Example: Dynamic fee based on volatility
uint24 dynamicFee = calculateDynamicFee();
return (selector, ZERO_DELTA, dynamicFee);
```

### 2. `afterSwap()` - Post-Swap Hook

```solidity
function afterSwap(
    address sender,
    PoolKey calldata key,
    SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4, int128) {
    counts[key.toId()]["afterSwap"]++;
    return (this.afterSwap.selector, 0);
}
```

**When Called**: Immediately after a swap completes in the PoolManager.

**Parameters Breakdown**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `sender` | `address` | The address that initiated the swap |
| `key` | `PoolKey` | Identifies the pool |
| `params` | `SwapParams` | Swap details (same as beforeSwap) |
| `delta` | `BalanceDelta` | Actual balance changes from the swap |
| `hookData` | `bytes` | Custom data |

**New Parameter: `delta`**

```solidity
BalanceDelta delta  // The actual swap result!

int128 amount0 = delta.amount0();  // Change in currency0
int128 amount1 = delta.amount1();  // Change in currency1

// Negative = paid/sent to pool
// Positive = received/taken from pool
```

**Example**:
```solidity
// Swap: 1 ETH → 2500 USDC
// Pool: ETH (currency0) / USDC (currency1)

delta.amount0() = -1000000000000000000  // Paid 1 ETH
delta.amount1() = +2500000000           // Received 2500 USDC
```

**Return Values**:

| Return | Type | Meaning |
|--------|------|---------|
| `bytes4` | Function selector | Must return `this.afterSwap.selector` |
| `int128` | Unspecified delta | Amount adjustment (0 = no change) |

**Execution Flow**:

```
hook.beforeSwap()
       ↓
PoolManager executes swap
       ↓
[Swap completes with BalanceDelta]
       ↓
hook.afterSwap() ← We are here
       ↓
[Hook increments counter]
       ↓
[Hook could analyze delta]
       ↓
[Returns success]
       ↓
Swap operation complete
```

**Code Breakdown**:

#### Step 1: Increment Counter

```solidity
counts[key.toId()]["afterSwap"]++;
```

Same pattern as beforeSwap - track how many times afterSwap was called for this pool.

#### Step 2: Return Success

```solidity
return (this.afterSwap.selector, 0);
```

**Return Value 1**: Function selector for verification

**Return Value 2**: `0` = No delta adjustment

**If we wanted to modify amounts** (requires `afterSwapReturnDelta` permission):
```solidity
// Example: Take 0.1% protocol fee on output
int128 protocolFee = delta.amount1() / 1000;
return (this.afterSwap.selector, protocolFee);
```

### 3. `beforeAddLiquidity()` - Pre-Liquidity Hook

```solidity
function beforeAddLiquidity(
    address sender,
    PoolKey calldata key,
    ModifyLiquidityParams calldata params,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4) {
    counts[key.toId()]["beforeAddLiquidity"]++;
    return this.beforeAddLiquidity.selector;
}
```

**When Called**: Before liquidity is added to a pool.

**Parameters Breakdown**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `sender` | `address` | The address adding liquidity |
| `key` | `PoolKey` | Identifies the pool |
| `params` | `ModifyLiquidityParams` | Liquidity operation details |
| `hookData` | `bytes` | Custom data |

**ModifyLiquidityParams Structure**:

```solidity
struct ModifyLiquidityParams {
    int24 tickLower;        // Lower bound of liquidity position
    int24 tickUpper;        // Upper bound of liquidity position
    int256 liquidityDelta;  // Amount of liquidity to add (positive)
    bytes32 salt;           // For position identification
}
```

**Example**:
```solidity
// Add liquidity to ETH/USDC pool
// Price range: $2000 - $3000
// Amount: 10 ETH worth of liquidity

ModifyLiquidityParams({
    tickLower: -887220,        // ≈ $2000
    tickUpper: 887220,         // ≈ $3000
    liquidityDelta: 10e18,     // Positive = add
    salt: bytes32(0)
});
```

**Return Value**: Function selector only (no delta modifications for before hooks)

**Use Cases**:
- 📊 Track liquidity provision events
- 🚫 Whitelist/blacklist certain addresses
- ⏰ Time-based restrictions (e.g., no adds during volatile periods)
- 💰 Charge custom fees for adding liquidity

### 4. `beforeRemoveLiquidity()` - Pre-Removal Hook

```solidity
function beforeRemoveLiquidity(
    address sender,
    PoolKey calldata key,
    ModifyLiquidityParams calldata params,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4) {
    counts[key.toId()]["beforeRemoveLiquidity"]++;
    return this.beforeRemoveLiquidity.selector;
}
```

**When Called**: Before liquidity is removed from a pool.

**Parameters**: Same as `beforeAddLiquidity`

**Key Difference**: `liquidityDelta` is NEGATIVE

```solidity
// Remove liquidity
ModifyLiquidityParams({
    tickLower: -887220,
    tickUpper: 887220,
    liquidityDelta: -10e18,    // Negative = remove
    salt: bytes32(0)
});
```

**Use Cases**:
- 📊 Track liquidity withdrawal events
- ⏳ Enforce lock-up periods
- 💸 Apply exit fees
- 📉 Restrict removals during certain conditions

## Unimplemented Hook Functions

The following hooks are declared but intentionally not implemented (they revert):

### Initialization Hooks

```solidity
function beforeInitialize(
    address sender,
    PoolKey calldata key,
    uint160 sqrtPriceX96
) external onlyPoolManager returns (bytes4) {
    revert HookNotImplemented();
}

function afterInitialize(
    address sender,
    PoolKey calldata key,
    uint160 sqrtPriceX96,
    int24 tick
) external onlyPoolManager returns (bytes4) {
    revert HookNotImplemented();
}
```

**Why Unimplemented?** 
- CounterHook doesn't need to track initialization
- Permission is `false` in `getHookPermissions()`
- If somehow called, reverts with clear error

**When These Would Be Useful**:
- Set initial hook state for a new pool
- Validate pool parameters
- Initialize pool-specific configuration

### After Liquidity Hooks

```solidity
function afterAddLiquidity(
    address sender,
    PoolKey calldata key,
    ModifyLiquidityParams calldata params,
    BalanceDelta delta,
    BalanceDelta feesAccrued,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4, BalanceDelta) {
    revert HookNotImplemented();
}

function afterRemoveLiquidity(
    address sender,
    PoolKey calldata key,
    ModifyLiquidityParams calldata params,
    BalanceDelta delta,
    BalanceDelta feesAccrued,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4, BalanceDelta) {
    revert HookNotImplemented();
}
```

**When These Would Be Useful**:
- Modify amounts after liquidity operations
- Distribute rewards based on actual amounts
- Update internal accounting with precise deltas

### Donation Hooks

```solidity
function beforeDonate(
    address sender,
    PoolKey calldata key,
    uint256 amount0,
    uint256 amount1,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4) {
    revert HookNotImplemented();
}

function afterDonate(
    address sender,
    PoolKey calldata key,
    uint256 amount0,
    uint256 amount1,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4) {
    revert HookNotImplemented();
}
```

**What Are Donations?**
Donations add tokens directly to pool fees without affecting liquidity positions.

**When These Would Be Useful**:
- Track charitable donations
- Redistribute donations to LPs
- Apply custom donation rules

## Complete Execution Examples

### Example 1: Simple Swap With Counter Updates

**Scenario**: User swaps 1 ETH for USDC in an ETH/USDC pool with CounterHook.

```solidity
// Setup
PoolKey memory key = PoolKey({
    currency0: address(0),      // ETH
    currency1: USDC,
    fee: 500,
    tickSpacing: 10,
    hooks: address(counterHook)
});

// Before swap
uint256 beforeCount = counterHook.counts(key.toId(), "beforeSwap");
uint256 afterCount = counterHook.counts(key.toId(), "afterSwap");
// beforeCount = 0
// afterCount = 0
```

**Execution Flow**:

```
┌─────────────┐         ┌──────────────┐         ┌────────────────┐
│   User/EOA  │         │  Swap.sol    │         │  PoolManager   │
└──────┬──────┘         └──────┬───────┘         └───────┬────────┘
       │                       │                         │
       │ 1. swap(1 ETH)        │                         │
       │──────────────────────>│                         │
       │                       │                         │
       │                       │  2. unlock()            │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │  3. unlockCallback()    │
       │                       │<────────────────────────│
       │                       │                         │
       │                       │  4. swap()              │
       │                       │────────────────────────>│
       │                       │                         │
       │                       │ ┌─────────────────────┐│
       │                       │ │ CounterHook         ││
       │                       │ │ beforeSwap()        ││
       │                       │<┤ counts[pool]["beforeSwap"]++
       │                       │ │ return selector     ││
       │                       │ └─────────────────────┘│
       │                       │                         │
       │                       │  [Core swap executes]   │
       │                       │                         │
       │                       │ ┌─────────────────────┐│
       │                       │ │ CounterHook         ││
       │                       │ │ afterSwap()         ││
       │                       │<┤ counts[pool]["afterSwap"]++
       │                       │ │ return selector     ││
       │                       │ └─────────────────────┘│
       │                       │                         │
       │                       │<──── BalanceDelta ──────│
       │                       │                         │
       │<─ Received 2500 USDC ─│                         │
```

**After swap**:

```solidity
uint256 beforeCount = counterHook.counts(key.toId(), "beforeSwap");
uint256 afterCount = counterHook.counts(key.toId(), "afterSwap");
// beforeCount = 1  ← Incremented!
// afterCount = 1   ← Incremented!
```

### Example 2: Adding Liquidity With Counter Updates

**Scenario**: LP adds liquidity to ETH/USDC pool.

```solidity
// Before adding liquidity
uint256 count = counterHook.counts(key.toId(), "beforeAddLiquidity");
// count = 0

// Add liquidity
poolManager.unlock(abi.encode(ADD_LIQUIDITY));
// This triggers:
// 1. unlockCallback()
// 2. poolManager.modifyLiquidity()
// 3. hook.beforeAddLiquidity() ← Counter increments here
// 4. [Core liquidity addition]

// After adding liquidity
count = counterHook.counts(key.toId(), "beforeAddLiquidity");
// count = 1  ← Incremented!
```

### Example 3: Multiple Pools, Independent Counters

**Scenario**: Two different pools, each tracked separately.

```solidity
// Pool 1: ETH/USDC
PoolKey memory pool1 = PoolKey({
    currency0: address(0),
    currency1: USDC,
    fee: 500,
    tickSpacing: 10,
    hooks: address(counterHook)
});

// Pool 2: DAI/USDC
PoolKey memory pool2 = PoolKey({
    currency0: DAI,
    currency1: USDC,
    fee: 100,
    tickSpacing: 1,
    hooks: address(counterHook)
});

// Swap in Pool 1 (3 times)
swap(pool1, 1 ether);
swap(pool1, 1 ether);
swap(pool1, 1 ether);

// Swap in Pool 2 (1 time)
swap(pool2, 1000e18);

// Check counters
PoolId pool1Id = pool1.toId();
PoolId pool2Id = pool2.toId();

counterHook.counts(pool1Id, "beforeSwap");  // = 3
counterHook.counts(pool1Id, "afterSwap");   // = 3
counterHook.counts(pool2Id, "beforeSwap");  // = 1
counterHook.counts(pool2Id, "afterSwap");   // = 1

// ✅ Each pool has independent counters!
```

## Testing Your Hook

### Test Setup

```solidity
contract CounterHookTest is Test {
    using PoolIdLibrary for PoolKey;

    IPoolManager constant poolManager = IPoolManager(POOL_MANAGER);
    PoolKey key;
    CounterHook hook;

    function setUp() public {
        // 1. Find valid salt (run FindHookSalt.test.sol first)
        bytes32 salt = vm.envBytes32("SALT");
        
        // 2. Deploy hook with CREATE2
        hook = new CounterHook{salt: salt}(POOL_MANAGER);
        
        // 3. Create pool with this hook
        key = PoolKey({
            currency0: address(0),
            currency1: USDC,
            fee: 500,
            tickSpacing: 10,
            hooks: address(hook)
        });
        
        // 4. Initialize pool
        poolManager.initialize(key, SQRT_PRICE_1_1);
    }
}
```

### Test 1: Permission Validation

```solidity
function test_permissions() public {
    // Verify hook address matches permissions
    Hooks.validateHookPermissions(
        address(hook),
        hook.getHookPermissions()
    );
    // ✅ Passes if address has correct bits
}
```

### Test 2: Swap Counter

```solidity
function test_swap() public {
    // Before swap
    uint256 beforeCount = hook.counts(key.toId(), "beforeSwap");
    uint256 afterCount = hook.counts(key.toId(), "afterSwap");
    assertEq(beforeCount, 0);
    assertEq(afterCount, 0);
    
    // Execute swap
    action = SWAP;
    poolManager.unlock("");
    
    // After swap
    assertEq(hook.counts(key.toId(), "beforeSwap"), 1);
    assertEq(hook.counts(key.toId(), "afterSwap"), 1);
}
```

### Test 3: Liquidity Counter

```solidity
function test_liquidity() public {
    // Add liquidity
    action = ADD_LIQUIDITY;
    poolManager.unlock("");
    assertEq(hook.counts(key.toId(), "beforeAddLiquidity"), 1);
    
    // Remove liquidity
    action = REMOVE_LIQUIDITY;
    poolManager.unlock("");
    assertEq(hook.counts(key.toId(), "beforeRemoveLiquidity"), 1);
}
```

## Common Pitfalls and Solutions

### Pitfall 1: Wrong Hook Address

```solidity
// ❌ PROBLEM: Deploy without salt mining
hook = new CounterHook(POOL_MANAGER);
// Error: Address doesn't match permissions

// ✅ SOLUTION: Use CREATE2 with mined salt
bytes32 salt = vm.envBytes32("SALT");
hook = new CounterHook{salt: salt}(POOL_MANAGER);
```

### Pitfall 2: Forgetting onlyPoolManager

```solidity
// ❌ PROBLEM: No access control
function beforeSwap(...) external returns (...) {
    counts[key.toId()]["beforeSwap"]++;
    return (this.beforeSwap.selector, ZERO_DELTA, 0);
}
// Anyone can call this!

// ✅ SOLUTION: Add modifier
function beforeSwap(...) external onlyPoolManager returns (...) {
    counts[key.toId()]["beforeSwap"]++;
    return (this.beforeSwap.selector, ZERO_DELTA, 0);
}
```

### Pitfall 3: Wrong Function Selector

```solidity
// ❌ PROBLEM: Returning wrong selector
function beforeSwap(...) external onlyPoolManager returns (bytes4, ...) {
    counts[key.toId()]["beforeSwap"]++;
    return (this.afterSwap.selector, ...);  // Wrong!
}

// ✅ SOLUTION: Return correct selector
function beforeSwap(...) external onlyPoolManager returns (bytes4, ...) {
    counts[key.toId()]["beforeSwap"]++;
    return (this.beforeSwap.selector, ...);  // Correct!
}
```

### Pitfall 4: Enabling Wrong Permissions

```solidity
// ❌ PROBLEM: Permission enabled but not implemented
function getHookPermissions() public pure returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        ...
        beforeDonate: true,  // Enabled!
        ...
    });
}

function beforeDonate(...) external onlyPoolManager returns (bytes4) {
    revert HookNotImplemented();  // But not implemented!
}

// Result: All donations will fail!

// ✅ SOLUTION: Only enable implemented hooks
function getHookPermissions() public pure returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        ...
        beforeDonate: false,  // Disabled if not needed
        ...
    });
}
```

### Pitfall 5: Not Using PoolId Correctly

```solidity
// ❌ PROBLEM: Using address as key
counts[address(hook)]["beforeSwap"]++;  // Wrong!

// ✅ SOLUTION: Use PoolId from PoolKey
counts[key.toId()]["beforeSwap"]++;  // Correct!
```

## Advanced Hook Concepts

### Delta Modifications

**What Are Deltas?**

Deltas represent changes in token amounts. Hooks with special permissions can modify these amounts.

**Example: Taking a Fee in beforeSwap**

```solidity
function beforeSwap(
    address sender,
    PoolKey calldata key,
    SwapParams calldata params,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
    // Take 1% fee on input
    int128 fee = int128(params.amountSpecified / 100);
    
    BeforeSwapDelta delta = toBeforeSwapDelta(
        fee,  // Specified delta (reduce input by fee)
        0     // Unspecified delta
    );
    
    // Store fee for later claiming
    accumulatedFees[key.toId()] += uint128(fee);
    
    return (this.beforeSwap.selector, delta, 0);
}
```

**Requirements**: Must have `beforeSwapReturnDelta: true` in permissions!

### Dynamic Fees

Hooks can override pool fees dynamically:

```solidity
function beforeSwap(
    address sender,
    PoolKey calldata key,
    SwapParams calldata params,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
    // Calculate dynamic fee based on volatility
    uint24 dynamicFee = calculateVolatilityFee(key);
    
    // Return dynamic fee (overrides pool's static fee)
    return (this.beforeSwap.selector, ZERO_DELTA, dynamicFee);
}

function calculateVolatilityFee(PoolKey calldata key) 
    internal 
    view 
    returns (uint24) 
{
    // Example: Higher volatility = higher fee
    uint256 volatility = getVolatility(key);
    
    if (volatility > HIGH_THRESHOLD) return 10000;  // 1%
    if (volatility > MED_THRESHOLD) return 5000;    // 0.5%
    return 3000;  // 0.3% (default)
}
```

### Accessing Hook Data

Custom data can be passed from the caller to the hook:

```solidity
// Caller side:
bytes memory hookData = abi.encode(referrer, discount);
poolManager.swap(key, params, hookData);

// Hook side:
function beforeSwap(
    address sender,
    PoolKey calldata key,
    SwapParams calldata params,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
    // Decode custom data
    (address referrer, uint256 discount) = abi.decode(
        hookData,
        (address, uint256)
    );
    
    // Apply referral logic
    if (referrer != address(0)) {
        applyReferralReward(referrer, discount);
    }
    
    return (this.beforeSwap.selector, ZERO_DELTA, 0);
}
```

## Real-World Hook Use Cases

### 1. TWAP Oracle Hook

Track time-weighted average prices:

```solidity
mapping(PoolId => TWAPData) public twapData;

struct TWAPData {
    uint256 priceAccumulator;
    uint256 lastUpdateTime;
    uint256 lastPrice;
}

function afterSwap(..., BalanceDelta delta, ...) 
    external 
    onlyPoolManager 
    returns (bytes4, int128) 
{
    PoolId poolId = key.toId();
    
    // Calculate current price from delta
    uint256 price = calculatePrice(delta);
    
    // Update TWAP
    TWAPData storage data = twapData[poolId];
    uint256 elapsed = block.timestamp - data.lastUpdateTime;
    data.priceAccumulator += data.lastPrice * elapsed;
    data.lastPrice = price;
    data.lastUpdateTime = block.timestamp;
    
    return (this.afterSwap.selector, 0);
}
```

### 2. Whitelist Hook

Restrict pool access to approved addresses:

```solidity
mapping(PoolId => mapping(address => bool)) public whitelist;

function beforeSwap(
    address sender,
    PoolKey calldata key,
    SwapParams calldata params,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
    require(whitelist[key.toId()][sender], "Not whitelisted");
    return (this.beforeSwap.selector, ZERO_DELTA, 0);
}
```

### 3. Limit Order Hook

Execute limit orders when price is hit:

```solidity
struct LimitOrder {
    address owner;
    uint256 amountIn;
    uint256 targetPrice;
    bool zeroForOne;
}

mapping(PoolId => LimitOrder[]) public limitOrders;

function afterSwap(
    address sender,
    PoolKey calldata key,
    SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4, int128) {
    PoolId poolId = key.toId();
    uint256 currentPrice = calculatePrice(delta);
    
    // Check and execute limit orders
    LimitOrder[] storage orders = limitOrders[poolId];
    for (uint i = 0; i < orders.length; i++) {
        if (shouldExecute(orders[i], currentPrice)) {
            executeLimitOrder(orders[i], key);
            // Remove executed order
            orders[i] = orders[orders.length - 1];
            orders.pop();
        }
    }
    
    return (this.afterSwap.selector, 0);
}
```

### 4. Liquidity Mining Hook

Distribute rewards to liquidity providers:

```solidity
mapping(PoolId => mapping(address => uint256)) public rewards;

function beforeAddLiquidity(
    address sender,
    PoolKey calldata key,
    ModifyLiquidityParams calldata params,
    bytes calldata hookData
) external onlyPoolManager returns (bytes4) {
    // Track LP position
    PoolId poolId = key.toId();
    rewards[poolId][sender] += calculateReward(params.liquidityDelta);
    
    return this.beforeAddLiquidity.selector;
}

function claimRewards(PoolId poolId) external {
    uint256 reward = rewards[poolId][msg.sender];
    rewards[poolId][msg.sender] = 0;
    rewardToken.transfer(msg.sender, reward);
}
```

## Best Practices

### 1. Gas Efficiency

```solidity
// ✅ GOOD: Use immutable for PoolManager
IPoolManager public immutable poolManager;

// ❌ BAD: Storage variable
IPoolManager public poolManager;  // Costs extra SLOAD
```

### 2. Reentrancy Protection

```solidity
// ✅ GOOD: onlyPoolManager prevents reentrancy
modifier onlyPoolManager() {
    if (msg.sender != address(poolManager)) revert NotPoolManager();
    _;
}

// The unlock mechanism ensures atomicity
```

### 3. Error Handling

```solidity
// ✅ GOOD: Custom errors (gas efficient)
error NotPoolManager();
error HookNotImplemented();

// ❌ BAD: String reverts (expensive)
require(msg.sender == address(poolManager), "not pool manager");
```

### 4. Permission Minimalism

```solidity
// ✅ GOOD: Only enable needed hooks
beforeSwap: true,
afterSwap: true,
beforeAddLiquidity: true,
// ... rest false

// ❌ BAD: Enable everything "just in case"
beforeSwap: true,
afterSwap: true,
beforeAddLiquidity: true,
afterAddLiquidity: true,  // Not needed!
```

### 5. State Management

```solidity
// ✅ GOOD: Use PoolId as key
mapping(PoolId => mapping(string => uint256)) public counts;

// ❌ BAD: Single global counter
uint256 public totalSwaps;  // Loses per-pool granularity
```

## Deployment Checklist

Before deploying your hook to production:

- [ ] Run salt mining script (`FindHookSalt.test.sol`)
- [ ] Verify hook permissions match intended functionality
- [ ] Test all implemented hook functions
- [ ] Verify `onlyPoolManager` on all callbacks
- [ ] Test with multiple pools to ensure isolation
- [ ] Gas optimization review
- [ ] Security audit (if handling value/fees)
- [ ] Test on testnet with real pool operations
- [ ] Document hook behavior for users
- [ ] Deploy with CREATE2 using mined salt

## Conclusion

The **CounterHook** contract demonstrates the fundamental patterns for building Uniswap V4 hooks:

### Key Takeaways

1. **Hook Permissions**: Declare which operations you want to intercept
2. **Address Mining**: Use CREATE2 to find valid hook addresses
3. **Selective Implementation**: Only implement needed hook functions
4. **Security**: Always use `onlyPoolManager` modifier
5. **Storage**: Use PoolId for per-pool state management
6. **Return Values**: Always return correct function selectors

### Implementation Summary

✅ **Implemented**:
- `beforeSwap()` - Count swaps before execution
- `afterSwap()` - Count swaps after execution
- `beforeAddLiquidity()` - Count liquidity additions
- `beforeRemoveLiquidity()` - Count liquidity removals

❌ **Not Implemented** (intentionally):
- All initialization hooks
- After liquidity hooks
- Donation hooks
- Delta return hooks

### Next Steps

1. **Complete the Exercise**: Implement the 4 hook functions
2. **Run Tests**: Execute `CounterHook.test.sol`
3. **Experiment**: Try modifying to track additional metrics
4. **Advanced Hooks**: Study delta modifications, dynamic fees
5. **Real Projects**: Build production hooks (TWAP, limit orders, etc.)

The hook system is one of Uniswap V4's most powerful features, enabling endless customization possibilities. Master the basics with CounterHook, then build sophisticated DeFi primitives! 🚀

---

## Test

```shell
# Step 1: Find valid salt
forge test --match-path test/FindHookSalt.test.sol -vvv

# Step 2: Set salt environment variable
export SALT=0x... # Use the salt from step 1

# Step 3: Run CounterHook tests
forge test --fork-url $FORK_URL --match-path test/CounterHook.test.sol -vvv
```
