# Uniswap V4 Reader - Complete Technical Guide

## Introduction

This document provides an in-depth technical explanation of the `Reader.sol` contract and how to read transient storage from Uniswap V4's PoolManager. This exercise demonstrates how to access the internal debt/credit tracking system that powers V4's flash accounting mechanism.

### What You'll Learn

- How Uniswap V4 stores currency deltas in transient storage
- The difference between transient storage (TSTORE/TLOAD) and permanent storage
- How to calculate storage slots for nested mappings
- Using `exttload()` to read external transient storage
- Understanding the debt/credit accounting system

### Key Concepts

**Transient Storage**: Temporary storage introduced in EIP-1153 that only exists during a transaction. Data is automatically cleared after execution.

**Currency Delta**: The debt/credit balance for a specific address and currency. Negative = owes tokens, Positive = owed tokens, Zero = settled.

**exttload**: An external function that allows reading transient storage from another contract (similar to `extsload` for permanent storage).

**Storage Slot Calculation**: Computing the exact location in storage where data is stored in nested mappings.

## Contract Overview

The `Reader.sol` contract demonstrates how to read the internal accounting state from the PoolManager's transient storage. This is useful for monitoring debt positions during the unlock callback.

### Core Features

| Feature | Description |
|---------|-------------|
| **Read Currency Delta** | Query debt/credit for any address and currency |
| **Transient Storage Access** | Use `exttload()` to read temporary state |
| **Storage Slot Calculation** | Compute slot locations for nested mappings |
| **Zero Gas Cost Reads** | View functions don't consume gas when called externally |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Storage Type**: Transient (TLOAD opcode)
- **Access Pattern**: Read-only via `exttload()`
- **Use Case**: Monitoring debt during unlock callbacks

## Contract Architecture

### Dependencies and Interfaces

#### Core Imports

```solidity
import {IPoolManager} from "../interfaces/IPoolManager.sol";
```

| Interface | Purpose | Key Functions Used |
|-----------|---------|-------------------|
| `IPoolManager` | Access to PoolManager transient storage | `exttload()` - Read transient storage slots |

**Why `exttload()` is Available**:

Even though we only import `IPoolManager`, the `exttload()` function is available because of **interface inheritance**:

```solidity
// In IPoolManager.sol
interface IPoolManager is IExtsload, IExttload {
    //           ↑               ↑
    //           |               └─ Contains exttload()
    //           └─ Contains extsload()
    
    // IPoolManager inherits ALL functions from IExttload
    function unlock(...) external;
    function swap(...) external;
    // ... other functions ...
}

// In IExttload.sol
interface IExttload {
    /// @notice Read transient storage from external contract
    function exttload(bytes32 slot) external view returns (bytes32);
    function exttload(bytes32[] calldata) external view returns (bytes32[] memory);
}
```

**Inheritance Chain**:
```
IPoolManager
    ├─ inherits IExtsload (for reading permanent storage)
    │   └─ extsload(bytes32 slot)
    │
    └─ inherits IExttload (for reading transient storage)
        └─ exttload(bytes32 slot)  ← This is why we can call it!
```

**In Our Code**:
```solidity
contract Reader {
    IPoolManager public immutable poolManager;
    
    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
        // ↑ This cast gives us access to:
        // - IPoolManager's own functions (swap, take, settle, etc.)
        // - IExtsload's functions (extsload)
        // - IExttload's functions (exttload) ← Available via inheritance!
    }
    
    function getCurrencyDelta(...) public view returns (int256) {
        // We can call exttload because IPoolManager extends IExttload
        return int256(uint256(poolManager.exttload(slot)));
        //                     ↑
        //                     Available via interface inheritance!
    }
}
```

**Key Point**: When a contract implements `IPoolManager`, it MUST also implement all functions from `IExtsload` and `IExttload` because of the inheritance. This means any `IPoolManager` reference automatically has access to `exttload()`.

### State Variables

```solidity
IPoolManager public immutable poolManager;
```

| Variable | Type | Purpose |
|----------|------|---------|
| `poolManager` | `IPoolManager` | Reference to Uniswap V4's PoolManager for storage access |

### Understanding Transient Storage

**What is Transient Storage?**

Introduced in [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153), transient storage provides temporary storage that:
- ✅ Only exists during transaction execution
- ✅ Automatically clears after transaction completes
- ✅ Cheaper than permanent storage (~100 gas vs ~20,000 gas)
- ✅ Perfect for temporary accounting (like debt tracking)

**Comparison with Permanent Storage**:

| Feature | Permanent Storage (SSTORE/SLOAD) | Transient Storage (TSTORE/TLOAD) |
|---------|-----------------------------------|-----------------------------------|
| **Lifetime** | Forever (until changed) | Transaction duration only |
| **Gas Cost** | ~20,000 gas (cold) / 2,100 (warm) | ~100 gas |
| **Cleared After TX** | ❌ No | ✅ Yes |
| **Use Case** | User balances, pool state | Temporary debt, reentrancy locks |
| **Opcodes** | SSTORE, SLOAD | TSTORE, TLOAD |

**Why PoolManager Uses Transient Storage**:

```solidity
// Inside PoolManager during unlock:
TSTORE currencyDelta[user][USDC] = -1000  // User owes 1000 USDC

// ... callback executes ...
// ... user settles debt ...

TSTORE currencyDelta[user][USDC] = 0       // Debt cleared

// Transaction ends → transient storage automatically clears
// No need to manually reset to 0 → saves gas!
```

### PoolManager's Currency Delta Storage

**Internal Structure** (simplified):

```solidity
// Inside PoolManager.sol
contract PoolManager {
    // Transient storage mapping (not in code, but conceptually):
    // mapping(address target => mapping(address currency => int256 delta))
    
    // Actual implementation uses assembly:
    // TSTORE at computed slots
}
```

**How Currency Delta Works**:

```solidity
// When you take() tokens:
currencyDelta[msg.sender][USDC] -= 100;  // You owe 100 USDC (negative)

// When you settle():
currencyDelta[msg.sender][USDC] += 100;  // Debt cleared (back to 0)

// At unlock end:
require(currencyDelta[msg.sender][currency] == 0);  // Must be settled!
```

## Storage Slot Calculation

### Understanding Nested Mapping Storage

Solidity stores nested mappings using a deterministic slot calculation:

```solidity
mapping(address => mapping(address => int256)) currencyDelta;
```

**Storage Layout**:

For `currencyDelta[target][currency]`, the slot is calculated as:

```
slot = keccak256(currency . keccak256(target . mappingSlot))
```

However, for a simplified version (which V4 uses):

```
slot = keccak256(target . currency)
```

### The `computeSlot()` Function

```solidity
function computeSlot(address target, address currency)
    public
    pure
    returns (bytes32 slot)
{
    assembly ("memory-safe") {
        mstore(0, and(target, 0xffffffffffffffffffffffffffffffffffffffff))
        mstore(32, and(currency, 0xffffffffffffffffffffffffffffffffffffffff))
        slot := keccak256(0, 64)
    }
}
```

**Breaking Down the Assembly**:

#### Step 1: Write `target` to Memory

```solidity
mstore(0, and(target, 0xffffffffffffffffffffffffffffffffffffffff))
```

**What This Does**:
1. `and(target, 0xfff...)` - Masks to ensure only lower 160 bits (address is 20 bytes)
2. `mstore(0, ...)` - Writes the address to memory position 0

**Memory After**:
```
Position 0-31: [0x0000...0000][target address (20 bytes)]
```

#### Step 2: Write `currency` to Memory

```solidity
mstore(32, and(currency, 0xffffffffffffffffffffffffffffffffffffffff))
```

**What This Does**:
1. `and(currency, 0xfff...)` - Masks currency address
2. `mstore(32, ...)` - Writes to memory position 32 (right after target)

**Memory After**:
```
Position 0-31:  [0x0000...0000][target address (20 bytes)]
Position 32-63: [0x0000...0000][currency address (20 bytes)]
```

#### Step 3: Hash to Get Storage Slot

```solidity
slot := keccak256(0, 64)
```

**What This Does**:
1. `keccak256(0, 64)` - Hash 64 bytes starting from memory position 0
2. This includes both target and currency addresses
3. Returns a unique 32-byte hash as the storage slot

**Result**: A deterministic storage slot that uniquely identifies `currencyDelta[target][currency]`

**Visual Representation**:

```
Input:
┌─────────────────────────────────┐
│ target:   0x1234...5678         │
│ currency: 0xABCD...EF00         │
└─────────────────────────────────┘
                ↓
       Memory Layout (64 bytes):
┌─────────────────────────────────┐
│ [0-31]:  0x000...01234...5678   │
│ [32-63]: 0x000...0ABCD...EF00   │
└─────────────────────────────────┘
                ↓
         keccak256(64 bytes)
                ↓
┌─────────────────────────────────┐
│ slot: 0x7a8f3c2...b5e4d1a9     │ ← Storage slot
└─────────────────────────────────┘
```

**Why Use Assembly?**

```solidity
// Pure Solidity (doesn't work for transient storage):
bytes32 slot = keccak256(abi.encodePacked(target, currency));
// ❌ This encodes with padding, doesn't match V4's slot calculation

// Assembly (matches V4's exact slot calculation):
assembly {
    mstore(0, target)
    mstore(32, currency)
    slot := keccak256(0, 64)
}
// ✅ Exact 64-byte layout that V4 uses
```

### The `getCurrencyDelta()` Function

```solidity
function getCurrencyDelta(address target, address currency)
    public
    view
    returns (int256 delta)
{
    bytes32 slot = computeSlot(target, currency);
    delta = int256(uint256(poolManager.exttload(slot)));
}
```

**Breaking Down the Function**:

#### Step 1: Compute Storage Slot

```solidity
bytes32 slot = computeSlot(target, currency);
```

**Purpose**: Calculate the exact storage location for `currencyDelta[target][currency]`

**Example**:
```solidity
// Want to read: currencyDelta[0x1234...][USDC]
bytes32 slot = computeSlot(0x1234..., USDC);
// Returns: 0x7a8f3c2b...
```

#### Step 2: Read Transient Storage

```solidity
poolManager.exttload(slot)
```

**What is `exttload()`?**

An external function on PoolManager that reads transient storage:

```solidity
// Inside IPoolManager interface
interface IExttload {
    /// @notice Called by external contracts to read transient storage of the contract
    function exttload(bytes32 slot) external view returns (bytes32);
}
```

**How It Works**:
```solidity
// Simplified internal implementation
function exttload(bytes32 slot) external view returns (bytes32 value) {
    assembly {
        value := tload(slot)  // TLOAD opcode - reads transient storage
    }
}
```

**Important**: 
- `exttload()` reads from **PoolManager's** transient storage, not the Reader contract's
- Similar to how `extsload()` reads permanent storage from external contracts

#### Step 3: Type Conversions

```solidity
int256(uint256(poolManager.exttload(slot)))
```

**Why Multiple Conversions?**

```solidity
// exttload() returns bytes32
bytes32 rawValue = poolManager.exttload(slot);

// Convert to uint256 (interpret bytes as number)
uint256 unsignedValue = uint256(rawValue);

// Convert to int256 (interpret as signed)
int256 delta = int256(unsignedValue);
```

**Why Needed**: Currency delta is stored as `int256` (can be negative for debt), but storage operations work with `bytes32`.

**Example**:
```solidity
// Delta is -1000 (user owes 1000)
bytes32 rawValue = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc18
                   // ↑ Two's complement representation of -1000
                   
uint256 unsignedValue = 115792089237316195423570985008687907853269984665640564039457584007913129638904
                        // ↑ Interpreting bytes as unsigned
                        
int256 delta = -1000  // ✅ Correct signed interpretation
```

## Complete Flow Example

Let's trace a complete example of reading currency delta:

### Scenario: User Takes 100 USDC from PoolManager

```solidity
// Inside unlock callback:

// 1. Check delta before any operations
int256 delta = reader.getCurrencyDelta(address(this), USDC);
// Result: 0 (no debt yet)

// 2. Take 100 USDC
poolManager.take(USDC, address(this), 100e6);
// PoolManager internally: currencyDelta[this][USDC] = -100e6

// 3. Check delta after take
delta = reader.getCurrencyDelta(address(this), USDC);
// Result: -100000000 (owes 100 USDC, 6 decimals)

// 4. Settle the debt
IERC20(USDC).transfer(address(poolManager), 100e6);
poolManager.settle();
// PoolManager internally: currencyDelta[this][USDC] = 0

// 5. Check delta after settle
delta = reader.getCurrencyDelta(address(this), USDC);
// Result: 0 (debt cleared)
```

### Step-by-Step Breakdown

#### Initial State

```
currencyDelta[UserContract][USDC] = 0
```

#### After `take(USDC, user, 100e6)`

**PoolManager Internal Operation**:
```solidity
// In PoolManager.take():
assembly {
    // Calculate slot
    let slot := keccak256(user, USDC)
    
    // Load current delta
    let currentDelta := tload(slot)
    
    // Subtract taken amount (creates debt)
    let newDelta := sub(currentDelta, 100000000)  // -100e6
    
    // Store updated delta
    tstore(slot, newDelta)
}

// Transfer tokens to user
IERC20(USDC).transfer(user, 100e6);
```

**State**:
```
currencyDelta[UserContract][USDC] = -100000000
Interpretation: User owes 100 USDC to PoolManager
```

**Reader.getCurrencyDelta()** would return: `-100000000`

#### After `settle()`

**PoolManager Internal Operation**:
```solidity
// User already transferred tokens:
IERC20(USDC).transfer(address(poolManager), 100e6);

// In PoolManager.settle():
assembly {
    // Calculate slot
    let slot := keccak256(user, USDC)
    
    // Load current delta
    let currentDelta := tload(slot)  // -100000000
    
    // Add settled amount
    let newDelta := add(currentDelta, 100000000)  // 0
    
    // Store cleared delta
    tstore(slot, newDelta)
}
```

**State**:
```
currencyDelta[UserContract][USDC] = 0
Interpretation: Debt cleared, all settled
```

**Reader.getCurrencyDelta()** would return: `0`

## Use Cases

### 1. Monitoring Debt During Unlock

```solidity
function unlockCallback(bytes calldata data) external returns (bytes memory) {
    // Check debt before operations
    int256 debtBefore = reader.getCurrencyDelta(address(this), USDC);
    console.log("Debt before: %d", debtBefore);  // 0
    
    // Take tokens (creates debt)
    poolManager.take(USDC, address(this), 1000e6);
    
    // Check debt after take
    int256 debtAfter = reader.getCurrencyDelta(address(this), USDC);
    console.log("Debt after take: %d", debtAfter);  // -1000000000
    
    // Execute logic...
    // ...
    
    // Settle debt
    IERC20(USDC).transfer(address(poolManager), 1000e6);
    poolManager.settle();
    
    // Verify debt cleared
    int256 debtFinal = reader.getCurrencyDelta(address(this), USDC);
    require(debtFinal == 0, "Debt not cleared!");
    
    return "";
}
```

### 2. Multi-Currency Debt Tracking

```solidity
function trackMultipleCurrencies() external {
    poolManager.unlock("");
}

function unlockCallback(bytes calldata) external returns (bytes memory) {
    // Take multiple currencies
    poolManager.take(USDC, address(this), 1000e6);
    poolManager.take(DAI, address(this), 1000e18);
    poolManager.take(WETH, address(this), 1e18);
    
    // Check all debts
    int256 usdcDebt = reader.getCurrencyDelta(address(this), USDC);
    int256 daiDebt = reader.getCurrencyDelta(address(this), DAI);
    int256 wethDebt = reader.getCurrencyDelta(address(this), WETH);
    
    console.log("USDC debt: %d", usdcDebt);  // -1000000000
    console.log("DAI debt: %d", daiDebt);    // -1000000000000000000000
    console.log("WETH debt: %d", wethDebt);  // -1000000000000000000
    
    // Settle all
    IERC20(USDC).transfer(address(poolManager), 1000e6);
    poolManager.settle();
    
    IERC20(DAI).transfer(address(poolManager), 1000e18);
    poolManager.settle();
    
    // WETH settled via different method...
    
    return "";
}
```

### 3. Flash Loan Accounting Verification

```solidity
function verifyFlashLoanSettlement() external {
    // Borrow via flash loan
    poolManager.take(USDC, address(this), 10000e6);
    
    // Check debt
    int256 debt = reader.getCurrencyDelta(address(this), USDC);
    require(debt == -10000e6, "Unexpected debt");
    
    // Execute arbitrage logic...
    uint256 profit = executeArbitrage();
    
    // Repay loan
    IERC20(USDC).transfer(address(poolManager), 10000e6);
    poolManager.settle();
    
    // Verify fully settled
    debt = reader.getCurrencyDelta(address(this), USDC);
    require(debt == 0, "Flash loan not repaid!");
    
    // Keep profit
    IERC20(USDC).transfer(msg.sender, profit);
}
```

## Understanding Currency Delta Signs

### Sign Convention

| Value | Meaning | Your Position |
|-------|---------|---------------|
| **Positive (`+`)** | PoolManager owes you | Credit - You'll receive tokens |
| **Zero (`0`)** | Balanced | No debt either way |
| **Negative (`-`)** | You owe PoolManager | Debt - You must pay tokens |

### Real Examples

```solidity
// Example 1: After take()
poolManager.take(USDC, address(this), 100e6);
delta = reader.getCurrencyDelta(address(this), USDC);
// Result: -100000000
// Interpretation: You owe 100 USDC (must settle)

// Example 2: After swap (you're owed output)
poolManager.swap(...);  // Swapped USDC for DAI
delta = reader.getCurrencyDelta(address(this), DAI);
// Result: +995000000000000000000 (positive)
// Interpretation: PoolManager owes you 995 DAI (can take)

// Example 3: After settle()
IERC20(USDC).transfer(address(poolManager), 100e6);
poolManager.settle();
delta = reader.getCurrencyDelta(address(this), USDC);
// Result: 0
// Interpretation: Debt cleared, balanced
```

### Visual Representation

```
Currency Delta Number Line:

     You owe PoolManager  │  PoolManager owes you
              ◄────────────┼────────────►
                           │
        -1000  -500   -100 │ +100  +500  +1000
                           │
                          [0]
                      (Balanced)

Negative (-)                   Positive (+)
Must settle                    Can take
Debt position                  Credit position
```

## Complete Code Example with Detailed Comments

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPoolManager} from "../interfaces/IPoolManager.sol";

/// @title Reader Contract for Uniswap V4 Currency Delta
/// @notice Demonstrates reading transient storage from PoolManager
/// @dev Uses exttload() to access external transient storage
contract Reader {
    /// @notice Reference to Uniswap V4's PoolManager
    IPoolManager public immutable poolManager;

    /// @notice Initialize with PoolManager address
    /// @param _poolManager Address of deployed Uniswap V4 PoolManager
    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @notice Compute storage slot for currencyDelta mapping
    /// @dev Calculates slot for currencyDelta[target][currency]
    /// @param target The address whose delta we want to query
    /// @param currency The currency address (token)
    /// @return slot The computed storage slot location
    function computeSlot(address target, address currency)
        public
        pure
        returns (bytes32 slot)
    {
        assembly ("memory-safe") {
            // Write target address to memory position 0
            // The AND mask ensures only the lower 160 bits (address size)
            mstore(0, and(target, 0xffffffffffffffffffffffffffffffffffffffff))
            
            // Write currency address to memory position 32
            // This places it right after target in memory
            mstore(32, and(currency, 0xffffffffffffffffffffffffffffffffffffffff))
            
            // Hash the 64 bytes (target + currency) to get storage slot
            // This matches V4's storage slot calculation
            slot := keccak256(0, 64)
        }
    }

    /// @notice Get the currency delta for a target address and currency
    /// @dev Reads transient storage from PoolManager
    /// @param target The address whose delta we want to query
    /// @param currency The currency address (token)
    /// @return delta The currency delta (negative = debt, positive = credit, 0 = settled)
    function getCurrencyDelta(address target, address currency)
        public
        view
        returns (int256 delta)
    {
        // Step 1: Calculate the storage slot
        // This gives us the exact location in PoolManager's transient storage
        bytes32 slot = computeSlot(target, currency);
        
        // Step 2: Read transient storage using exttload()
        // exttload() reads from PoolManager's transient storage
        // Returns bytes32, which we convert to int256
        //
        // Conversion breakdown:
        // bytes32 → uint256 → int256
        //   ↓         ↓         ↓
        // raw data  unsigned  signed
        delta = int256(uint256(poolManager.exttload(slot)));
        
        // Result interpretation:
        // delta < 0: target owes tokens (debt)
        // delta = 0: balanced (no debt)
        // delta > 0: target is owed tokens (credit)
    }
}
```

## Key Differences: Reader vs Other Contracts

| Aspect | Flash/Swap Contracts | Reader Contract |
|--------|---------------------|-----------------|
| **Purpose** | Execute operations (take, settle, swap) | Read state only |
| **Callback** | Implements `unlockCallback()` | No callback needed |
| **State Changes** | Modifies PoolManager state | Read-only |
| **Token Transfers** | Yes (take, settle) | No |
| **Assembly Usage** | Minimal | Yes (storage slot calculation) |
| **Transient Storage** | Writes via PoolManager | Reads via `exttload()` |

## Gas Costs

| Operation | Gas Cost | Notes |
|-----------|----------|-------|
| `computeSlot()` | ~200 gas | Pure calculation, no storage access |
| `exttload()` | ~100 gas | TLOAD opcode (cheaper than SLOAD) |
| `getCurrencyDelta()` | ~300 gas | computeSlot + exttload |

**Comparison**:
- Permanent storage (SLOAD): ~2,100 gas (warm) / ~20,000 gas (cold)
- Transient storage (TLOAD): ~100 gas
- **Savings**: ~95% cheaper than permanent storage!

## Common Mistakes and How to Avoid Them

### 1. Wrong Slot Calculation

**Problem**:
```solidity
// ❌ Using abi.encodePacked
bytes32 slot = keccak256(abi.encodePacked(target, currency));
// This adds extra padding and doesn't match V4's layout
```

**Solution**:
```solidity
// ✅ Use assembly for exact layout
assembly {
    mstore(0, target)
    mstore(32, currency)
    slot := keccak256(0, 64)
}
```

### 2. Incorrect Type Conversion

**Problem**:
```solidity
// ❌ Missing type conversion
bytes32 delta = poolManager.exttload(slot);
// Can't compare bytes32 with int256
```

**Solution**:
```solidity
// ✅ Proper conversion chain
int256 delta = int256(uint256(poolManager.exttload(slot)));
```

### 3. Reading Outside Unlock Context

**Problem**:
```solidity
// ❌ Reading when PoolManager is not locked
function externalRead() external view returns (int256) {
    return reader.getCurrencyDelta(address(this), USDC);
}
// Always returns 0 because transient storage is cleared
```

**Solution**:
```solidity
// ✅ Read during unlock callback
function unlockCallback(bytes calldata) external returns (bytes memory) {
    int256 delta = reader.getCurrencyDelta(address(this), USDC);
    // delta will be accurate during the unlock
    return "";
}
```

### 4. Misinterpreting Sign

**Problem**:
```solidity
// ❌ Wrong interpretation
int256 delta = -1000e6;
if (delta > 0) {
    // Think: "I have a positive delta, I'm owed tokens"
    // Wrong! Negative means you owe!
}
```

**Solution**:
```solidity
// ✅ Correct interpretation
int256 delta = -1000e6;
if (delta < 0) {
    // Correct: Negative means I owe tokens
    uint256 debt = uint256(-delta);
    // Settle the debt...
}
```

## Testing

### Example Test

```solidity
function test_currencyDelta() public {
    // Create reader
    Reader reader = new Reader(address(poolManager));
    
    // Unlock and check delta
    poolManager.unlock("");
}

function unlockCallback(bytes calldata) external returns (bytes memory) {
    // Initial delta should be 0
    int256 delta = reader.getCurrencyDelta(address(this), USDC);
    assertEq(delta, 0, "Initial delta should be 0");
    
    // Take tokens (creates debt)
    poolManager.take(USDC, address(this), 100e6);
    
    // Delta should be negative (debt)
    delta = reader.getCurrencyDelta(address(this), USDC);
    assertEq(delta, -100e6, "Delta should be -100 USDC");
    assertLt(delta, 0, "Should have debt");
    
    // Settle debt
    IERC20(USDC).transfer(address(poolManager), 100e6);
    poolManager.settle();
    
    // Delta should be back to 0
    delta = reader.getCurrencyDelta(address(this), USDC);
    assertEq(delta, 0, "Delta should be settled");
    
    return "";
}
```

### Running Tests

```bash
# Run Reader tests
forge test --fork-url $FORK_URL --match-path test/Reader.test.sol -vvv

# With detailed logs
forge test --fork-url $FORK_URL --match-path test/Reader.test.sol -vvvv
```

## Additional Resources

- [EIP-1153: Transient Storage](https://eips.ethereum.org/EIPS/eip-1153)
- [Uniswap V4 PoolManager](https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol)
- [Solidity Storage Layout](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html)
- [Assembly Documentation](https://docs.soliditylang.org/en/latest/assembly.html)
- [Cyfrin Updraft Course](https://updraft.cyfrin.io/)

## Frequently Asked Questions

### Q1: Why use transient storage instead of permanent storage?

**A:** Transient storage is perfect for temporary data that only matters during a transaction:
- ✅ **95% cheaper**: ~100 gas vs ~20,000 gas
- ✅ **Auto-cleanup**: No need to manually clear after use
- ✅ **Perfect for debt tracking**: Currency deltas only matter during unlock
- ✅ **Reentrancy protection**: Can store temporary locks

### Q2: Can I read currency delta outside of an unlock callback?

**A:** You can call `getCurrencyDelta()` anytime, but it will always return `0` outside an unlock callback because transient storage is automatically cleared when the transaction ends.

```solidity
// ✅ Inside unlock: Returns actual debt/credit
function unlockCallback(...) external returns (bytes memory) {
    int256 delta = reader.getCurrencyDelta(address(this), USDC);
    // delta = -1000 (actual debt)
}

// ❌ Outside unlock: Always returns 0
function externalCall() external {
    int256 delta = reader.getCurrencyDelta(address(this), USDC);
    // delta = 0 (transient storage cleared)
}
```

### Q3: What happens if I don't settle my debt before unlock ends?

**A:** The PoolManager will revert the entire transaction:

```solidity
// In PoolManager.unlock():
locked = false;
// Check all currencies are settled
for (each currency with debt) {
    require(currencyDelta[msg.sender][currency] == 0, "CurrencyNotSettled");
    // ↑ Transaction reverts here if any debt remains!
}
```

### Q4: Can I read another address's currency delta?

**A:** Yes! The `target` parameter allows you to query any address:

```solidity
// Read your own delta
int256 myDelta = reader.getCurrencyDelta(address(this), USDC);

// Read another contract's delta
int256 otherDelta = reader.getCurrencyDelta(otherContract, USDC);

// Read user's delta
int256 userDelta = reader.getCurrencyDelta(userAddress, USDC);
```

This is useful for monitoring or debugging multi-contract interactions.

### Q5: Why the complex type conversion in getCurrencyDelta?

**A:** The conversion chain handles the mismatch between storage format and the actual data type:

```solidity
bytes32 → uint256 → int256
```

1. `exttload()` returns `bytes32` (raw storage)
2. `uint256()` interprets bytes as unsigned number
3. `int256()` reinterprets as signed (handles negative values correctly)

Without this, negative numbers wouldn't work:
```solidity
// ❌ Wrong: treats negative as huge positive
bytes32 raw = 0xffff...fc18;  // -1000 in two's complement
uint256 wrong = uint256(raw);  // 115792...38904 (huge positive!)

// ✅ Correct: properly interprets as negative
int256 correct = int256(uint256(raw));  // -1000 ✅
```

### Q6: What's the difference between extsload and exttload?

**A:**

| Function | Storage Type | Opcode | Persistence | Use Case |
|----------|--------------|--------|-------------|----------|
| `extsload()` | Permanent | SLOAD | Forever | Read pool state, balances |
| `exttload()` | Transient | TLOAD | Transaction only | Read currency deltas, temp locks |

Both allow reading from external contracts, but access different storage types.

### Q7: Can currency delta be positive?

**A:** Yes! Positive deltas mean the PoolManager owes you tokens:

```solidity
// Scenario: Swap USDC for DAI
poolManager.swap(USDC → DAI);

// After swap:
int256 usdcDelta = reader.getCurrencyDelta(address(this), USDC);
// usdcDelta = -1000000000 (you owe 1000 USDC)

int256 daiDelta = reader.getCurrencyDelta(address(this), DAI);
// daiDelta = +995000000000000000000 (you're owed 995 DAI)

// You take() the DAI (positive delta):
poolManager.take(DAI, address(this), 995e18);
// daiDelta becomes 0

// You settle() the USDC (negative delta):
IERC20(USDC).transfer(poolManager, 1000e6);
poolManager.settle();
// usdcDelta becomes 0
```

### Q8: Is there a gas cost to having non-zero deltas?

**A:** During the transaction, maintaining deltas costs minimal gas (~100 gas per TSTORE). However:
- ✅ No storage refund needed (unlike permanent storage)
- ✅ Auto-clears at transaction end (no cleanup cost)
- ✅ Much cheaper than permanent storage alternative

The real cost is if you don't settle - the transaction reverts and you lose all gas!

### Q9: Can I use Reader in production?

**A:** Yes, but with considerations:

**Good for**:
- ✅ Debugging during development
- ✅ Monitoring debt in complex strategies
- ✅ Testing and verification
- ✅ Off-chain queries (via staticcall)

**Not needed for**:
- ❌ Simple swaps (delta tracking is internal)
- ❌ Production contracts (adds complexity)
- ❌ Gas-critical paths (adds ~300 gas per read)

Most production contracts don't need to read currency delta explicitly - they just ensure they settle properly before unlock ends.

### Q10: How does this relate to Flash Accounting?

**A:** The Reader contract demonstrates the foundation of Flash Accounting:

```solidity
// Flash Accounting in action:
take(1000 USDC)    // Delta: -1000 (debt created)
swap(USDC → DAI)   // Delta: -1000 USDC, +995 DAI
take(995 DAI)      // Delta: -1000 USDC, 0 DAI
// ... use DAI ...
settle(1000 USDC)  // Delta: 0, 0 (all settled)

// Result: Borrowed and used tokens WITHOUT upfront transfers!
// All tracked via transient storage deltas
```

The Reader lets you peek into this accounting system to verify everything balances.

## Conclusion

This guide has covered the complete implementation of reading currency deltas from Uniswap V4's PoolManager. Key takeaways:

✅ **Transient Storage**: Temporary, auto-clearing, 95% cheaper than permanent storage  
✅ **Storage Slot Calculation**: Use assembly for precise slot computation  
✅ **exttload()**: Read external transient storage from PoolManager  
✅ **Currency Delta**: Negative = debt, Positive = credit, Zero = settled  
✅ **Use Cases**: Monitoring, debugging, verification during unlock callbacks  

**Next Steps**:
1. Understand how currency delta drives Flash Accounting
2. Use Reader for debugging complex unlock callbacks
3. Study PoolManager's internal accounting system
4. Build more sophisticated debt tracking tools

**Remember**: Currency delta only exists during transactions. Always read within unlock callbacks for accurate results!
