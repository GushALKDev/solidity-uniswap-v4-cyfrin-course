# Uniswap Universal Router - Complete Technical Guide

## Introduction

This document provides comprehensive technical documentation for **Uniswap's Universal Router**, a powerful routing contract that unifies multiple DeFi protocols into a single entry point. This exercise demonstrates how to execute Uniswap V4 swaps through the Universal Router architecture.

### What You'll Learn

- Understanding the Universal Router architecture
- The command-based execution pattern
- Permit2 integration for token approvals
- Multi-protocol routing capabilities
- Action sequences for V4 swaps
- SETTLE and TAKE patterns for token management
- Gas-efficient batch operations
- Integration with Uniswap V2, V3, and V4

### Key Concepts

**Universal Router**: A single entry point for executing operations across multiple Uniswap versions (V2, V3, V4) and other DeFi protocols. Uses a command-based architecture.

**Commands**: High-level operations like V4_SWAP, V3_SWAP, PERMIT2_TRANSFER. Each command can contain multiple actions.

**Actions**: Granular operations within V4 like SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL. Combined to form complex transactions.

**Permit2**: A token approval system that provides signature-based approvals and efficient approval management across protocols.

**SETTLE**: Paying tokens into the PoolManager to settle negative deltas.

**TAKE**: Withdrawing tokens from the PoolManager to claim positive deltas.

**Command-Based Execution**: Instead of calling specific functions, you pass encoded commands and inputs that the router decodes and executes.

## Contract Overview

The `UniversalRouterExercises.sol` contract demonstrates:

1. Transferring tokens from users via Permit2
2. Encoding V4 actions for swapping
3. Using SETTLE_ALL and TAKE_ALL for token management
4. Executing swaps through Universal Router
5. Handling both native ETH and ERC20 tokens

### Core Features

| Feature | Description |
|---------|-------------|
| **Multi-Protocol** | Single interface for V2, V3, V4, and more |
| **Command Pattern** | Flexible, extensible execution model |
| **Permit2 Integration** | Efficient signature-based approvals |
| **Batch Operations** | Execute multiple commands in one transaction |
| **Gas Efficient** | Optimized routing and execution |
| **Native ETH Support** | Seamless handling of ETH and wrapped tokens |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Key Dependencies**: IUniversalRouter, IPermit2, IV4Router
- **Core Commands**: V4_SWAP (and many others for V2/V3)
- **Core Actions**: SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL
- **Pattern**: Transfer → Approve → Execute → Withdraw

## 🏗️ Architecture Overview

### Universal Router Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    UNIVERSAL ROUTER ECOSYSTEM                    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   Universal Router                         │ │
│  │                  (Command Dispatcher)                      │ │
│  │                                                            │ │
│  │  Commands:                                                │ │
│  │   • V2_SWAP_EXACT_IN                                      │ │
│  │   • V3_SWAP_EXACT_IN                                      │ │
│  │   • V4_SWAP             ← This exercise                   │ │
│  │   • PERMIT2_TRANSFER                                      │ │
│  │   • WRAP_ETH / UNWRAP_WETH                               │ │
│  │   • SWEEP (withdraw tokens)                               │ │
│  │   • PAY_PORTION                                           │ │
│  │   • +30 more commands                                     │ │
│  └─────────┬──────────────────────────────────────────────────┘ │
│            │                                                     │
│            │ Dispatch Command                                   │
│            ↓                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              V4Router Module                            │   │
│  │         (Handles V4-specific logic)                     │   │
│  │                                                          │   │
│  │  Decodes Actions:                                       │   │
│  │   • SWAP_EXACT_IN_SINGLE                               │   │
│  │   • SWAP_EXACT_IN (multi-hop)                          │   │
│  │   • SWAP_EXACT_OUT_SINGLE                              │   │
│  │   • SWAP_EXACT_OUT (multi-hop)                         │   │
│  │   • SETTLE_ALL / SETTLE / SETTLE_PAIR                  │   │
│  │   • TAKE_ALL / TAKE / TAKE_PAIR                        │   │
│  │   • SETTLE_TAKE_PAIR                                    │   │
│  │   • And more...                                         │   │
│  └─────────┬───────────────────────────────────────────────┘   │
│            │                                                     │
│            │ Execute Actions                                    │
│            ↓                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Pool Manager (V4 Core)                     │   │
│  │                                                          │   │
│  │  • Manages pools and liquidity                          │   │
│  │  • Executes swaps via unlock callback                   │   │
│  │  • Tracks deltas for each token                         │   │
│  │  • Settles owed tokens (SETTLE)                         │   │
│  │  • Pays out claimed tokens (TAKE)                       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                      PERMIT2 SYSTEM                              │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Permit2 Contract                        │ │
│  │                                                            │ │
│  │  Features:                                                │ │
│  │   • Signature-based approvals                             │ │
│  │   • Batch approvals                                       │ │
│  │   • Expiring approvals                                    │ │
│  │   • Nonce management                                      │ │
│  │   • Gas-efficient transfers                               │ │
│  │                                                            │ │
│  │  Flow:                                                    │ │
│  │   1. User approves Permit2 (one-time)                    │ │
│  │   2. User approves spender via Permit2                   │ │
│  │   3. Spender transfers via Permit2                       │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### Command vs Actions Hierarchy

```
COMMAND (High-Level)
    │
    └─── V4_SWAP
            │
            ├─── Inputs: encoded (actions, params)
            │
            └─── ACTIONS (Low-Level)
                    │
                    ├─── SWAP_EXACT_IN_SINGLE
                    │      └─── params[0]: ExactInputSingleParams
                    │
                    ├─── SETTLE_ALL
                    │      └─── params[1]: (currency, maxAmount)
                    │
                    └─── TAKE_ALL
                           └─── params[2]: (currency, minAmount)
```

### Swap Execution Flow

```
USER                    YOUR CONTRACT         UNIVERSAL ROUTER       V4ROUTER          POOL MANAGER
 │                           │                        │                  │                   │
 │ swap(key, amt, min, dir)  │                        │                  │                   │
 │──────────────────────────>│                        │                  │                   │
 │                           │                        │                  │                   │
 │                           │ [1. Transfer tokens]   │                  │                   │
 │                           │ transferFrom(user)     │                  │                   │
 │                           │                        │                  │                   │
 │                           │ [2. Approve Permit2]   │                  │                   │
 │                           │ ERC20.approve(permit2) │                  │                   │
 │                           │ permit2.approve(router)│                  │                   │
 │                           │                        │                  │                   │
 │                           │ [3. Encode command]    │                  │                   │
 │                           │ commands = V4_SWAP     │                  │                   │
 │                           │ inputs = (actions, params)                │                   │
 │                           │                        │                  │                   │
 │                           │ [4. Execute]           │                  │                   │
 │                           │ router.execute(        │                  │                   │
 │                           │   commands, inputs)    │                  │                   │
 │                           │───────────────────────>│                  │                   │
 │                           │                        │                  │                   │
 │                           │                        │ [5. Dispatch]    │                   │
 │                           │                        │ Call V4Router    │                   │
 │                           │                        │─────────────────>│                   │
 │                           │                        │                  │                   │
 │                           │                        │                  │ [6. Action 1]     │
 │                           │                        │                  │ SWAP_EXACT_IN     │
 │                           │                        │                  │ unlock(callback)  │
 │                           │                        │                  │──────────────────>│
 │                           │                        │                  │                   │
 │                           │                        │                  │  Execute swap     │
 │                           │                        │                  │  delta0 = -X      │
 │                           │                        │                  │  delta1 = +Y      │
 │                           │                        │                  │<──────────────────│
 │                           │                        │                  │                   │
 │                           │                        │                  │ [7. Action 2]     │
 │                           │                        │                  │ SETTLE_ALL        │
 │                           │                        │                  │ Pay token (delta0)│
 │                           │                        │                  │──────────────────>│
 │                           │                        │                  │  delta0 = 0       │
 │                           │                        │                  │<──────────────────│
 │                           │                        │                  │                   │
 │                           │                        │                  │ [8. Action 3]     │
 │                           │                        │                  │ TAKE_ALL          │
 │                           │                        │                  │ Claim token(delta1)│
 │                           │                        │                  │──────────────────>│
 │                           │                        │                  │  send tokens      │
 │                           │                        │                  │  delta1 = 0       │
 │                           │                        │                  │<──────────────────│
 │                           │                        │                  │                   │
 │                           │                        │  Return          │                   │
 │                           │                        │<─────────────────│                   │
 │                           │  Return                │                  │                   │
 │                           │<───────────────────────│                  │                   │
 │                           │                        │                  │                   │
 │                           │ [9. Withdraw to user]  │                  │                   │
 │                           │ withdraw(currency0)    │                  │                   │
 │                           │ withdraw(currency1)    │                  │                   │
 │                           │                        │                  │                   │
 │  Return                   │                        │                  │                   │
 │<──────────────────────────│                        │                  │                   │
 │                           │                        │                  │                   │
```

## 📚 Understanding Permit2

Permit2 is a critical component that makes Universal Router gas-efficient and user-friendly.

### Traditional ERC20 Approvals

```solidity
// Problem: Need separate approval for each spender
token.approve(routerV2, type(uint256).max);
token.approve(routerV3, type(uint256).max);
token.approve(routerV4, type(uint256).max);
token.approve(aggregator, type(uint256).max);
// Gas cost: 4 transactions, ~200k gas

// Security: Unlimited approvals are risky
```

### Permit2 Solution

```solidity
// Step 1: One-time approval to Permit2 (per token)
token.approve(PERMIT2, type(uint256).max);

// Step 2: Grant spending rights to specific contracts via Permit2
permit2.approve(
    token,           // Which token
    spender,         // Who can spend (Universal Router)
    amount,          // How much
    expiration       // When it expires
);

// Benefits:
// - Single Permit2 approval works for all protocols using it
// - Expiring approvals (better security)
// - Signature-based approvals (gasless)
// - Batched approvals (multiple tokens at once)
```

### Permit2 Flow in Our Contract

```solidity
function approve(address token, uint160 amount, uint48 expiration) private {
    // 1. Approve Permit2 to spend our tokens
    IERC20(token).approve(address(permit2), uint256(amount));
    
    // 2. Tell Permit2 to allow Universal Router to spend via Permit2
    permit2.approve(token, address(router), amount, expiration);
}

// Now Universal Router can transfer tokens on our behalf via Permit2
```

### Why This Matters

**Without Permit2**:
```
User → approve Router → Router pulls tokens
Problem: Need approval for every new router version
```

**With Permit2**:
```
User → approve Permit2 (once) → approve spender via Permit2 → spender pulls via Permit2
Benefit: Same Permit2 approval works for all future contracts
```


## Universal Router Commands Reference

The Universal Router supports multiple commands for different operations. Here's the complete reference:

### Command Categories

Commands are organized in groups based on their function type:

```
0x00 - 0x07: V3 Swaps and Token Management
0x08 - 0x0f: V2 Swaps and Utilities  
0x10 - 0x20: V4 Operations and Position Management
0x21 - 0x3f: Advanced Features and Sub-Plans
```

### Complete Command List

#### Group 1: V3 and Token Operations (0x00 - 0x07)

##### 0x00: V3_SWAP_EXACT_IN

Execute exact input swap on Uniswap V3

**Parameters**:
```solidity
abi.encode(
    address recipient,      // Who receives output tokens
    uint256 amountIn,       // Exact amount of input token
    uint256 amountOutMin,   // Minimum output (slippage protection)
    bytes path,             // Encoded path: token0, fee, token1, fee, token2...
    bool payerIsUser        // true = pull from msg.sender, false = use contract balance
)
```

**Example**:
```solidity
bytes memory commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
bytes[] memory inputs = new bytes[](1);
inputs[0] = abi.encode(
    msg.sender,             // Recipient
    1e18,                   // 1 token in
    0.95e18,                // At least 0.95 tokens out
    path,                   // V3 encoded path
    true                    // Pull from user
);
router.execute(commands, inputs, deadline);
```

##### 0x01: V3_SWAP_EXACT_OUT

Execute exact output swap on Uniswap V3

**Parameters**:
```solidity
abi.encode(
    address recipient,      // Who receives output tokens
    uint256 amountOut,      // Exact amount of output token desired
    uint256 amountInMax,    // Maximum input willing to pay
    bytes path,             // Encoded path (reversed for exact out)
    bool payerIsUser        // true = pull from msg.sender, false = use contract balance
)
```

##### 0x02: PERMIT2_TRANSFER_FROM

Transfer tokens from user via Permit2

**Parameters**:
```solidity
abi.encode(
    address token,          // Token to transfer
    address recipient,      // Who receives tokens
    uint160 amount          // Amount to transfer
)
```

**Use Case**: Pull tokens from user without requiring direct approval to your contract

##### 0x03: PERMIT2_PERMIT_BATCH

Batch permit signature verification for multiple tokens

**Parameters**:
```solidity
abi.encode(
    IAllowanceTransfer.PermitBatch permitBatch,
    bytes signature         // User's signature
)

// PermitBatch structure:
struct PermitBatch {
    PermitDetails[] details;
    address spender;
    uint256 sigDeadline;
}

struct PermitDetails {
    address token;
    uint160 amount;
    uint48 expiration;
    uint48 nonce;
}
```

##### 0x04: SWEEP

Sweep all tokens from contract to recipient (minimum threshold)

**Parameters**:
```solidity
abi.encode(
    address token,          // Token to sweep (address(0) for ETH)
    address recipient,      // Who receives swept tokens
    uint160 amountMin       // Minimum amount required to sweep
)
```

**Use Case**: Clean up leftover tokens after operations

##### 0x05: TRANSFER

Transfer exact amount of tokens

**Parameters**:
```solidity
abi.encode(
    address token,          // Token to transfer (address(0) for ETH)
    address recipient,      // Who receives tokens
    uint256 value           // Exact amount to transfer
)
```

##### 0x06: PAY_PORTION

Pay a percentage (in basis points) of contract's token balance

**Parameters**:
```solidity
abi.encode(
    address token,          // Token to pay
    address recipient,      // Who receives payment
    uint256 bips            // Basis points (100 bips = 1%)
)
```

**Example**: Pay 50% of balance: `bips = 5000`

#### Group 2: V2 and Utilities (0x08 - 0x0f)

##### 0x08: V2_SWAP_EXACT_IN

Execute exact input swap on Uniswap V2

**Parameters**:
```solidity
abi.encode(
    address recipient,      // Who receives output tokens
    uint256 amountIn,       // Exact amount of input token
    uint256 amountOutMin,   // Minimum output (slippage protection)
    address[] path,         // Array of token addresses [tokenIn, tokenOut]
    bool payerIsUser        // true = pull from msg.sender, false = use contract balance
)
```

##### 0x09: V2_SWAP_EXACT_OUT

Execute exact output swap on Uniswap V2

**Parameters**:
```solidity
abi.encode(
    address recipient,      // Who receives output tokens
    uint256 amountOut,      // Exact amount of output token desired
    uint256 amountInMax,    // Maximum input willing to pay
    address[] path,         // Array of token addresses
    bool payerIsUser        // true = pull from msg.sender, false = use contract balance
)
```

##### 0x0a: PERMIT2_PERMIT

Single token permit signature verification

**Parameters**:
```solidity
abi.encode(
    IAllowanceTransfer.PermitSingle permitSingle,
    bytes signature         // User's signature
)

// PermitSingle structure:
struct PermitSingle {
    PermitDetails details;
    address spender;
    uint256 sigDeadline;
}
```

##### 0x0b: WRAP_ETH

Wrap ETH to WETH

**Parameters**:
```solidity
abi.encode(
    address recipient,      // Who receives WETH
    uint256 amount          // Amount of ETH to wrap (use CONTRACT_BALANCE for all)
)
```

**Special Value**: `amount = type(uint256).max` wraps entire contract balance

##### 0x0c: UNWRAP_WETH

Unwrap WETH to ETH

**Parameters**:
```solidity
abi.encode(
    address recipient,      // Who receives ETH
    uint256 amountMin       // Minimum amount to unwrap (revert if balance < min)
)
```

##### 0x0d: PERMIT2_TRANSFER_FROM_BATCH

Batch transfer multiple tokens via Permit2

**Parameters**:
```solidity
abi.encode(
    IAllowanceTransfer.AllowanceTransferDetails[] batchDetails
)

// AllowanceTransferDetails structure:
struct AllowanceTransferDetails {
    address from;
    address to;
    uint160 amount;
    address token;
}
```

##### 0x0e: BALANCE_CHECK_ERC20

Verify an address has minimum token balance

**Parameters**:
```solidity
abi.encode(
    address owner,          // Address to check
    address token,          // Token to check balance of
    uint256 minBalance      // Minimum required balance
)
```

**Behavior**: Allows revert if used with FLAG_ALLOW_REVERT

#### Group 3: V4 Operations (0x10 - 0x20)

##### 0x10: V4_SWAP ← **This Exercise**

Execute swap on Uniswap V4 pool

**Parameters**:
```solidity
abi.encode(
    bytes actions,          // Packed action IDs (Actions.SWAP_EXACT_IN_SINGLE, etc.)
    bytes[] params          // Parameters for each action
)
```

**Actions for V4_SWAP**:
```solidity
// Swap actions
Actions.SWAP_EXACT_IN_SINGLE    // Single pool exact input
Actions.SWAP_EXACT_IN           // Multi-hop exact input
Actions.SWAP_EXACT_OUT_SINGLE   // Single pool exact output
Actions.SWAP_EXACT_OUT          // Multi-hop exact output

// Settlement actions
Actions.SETTLE                  // Settle specific amount
Actions.SETTLE_ALL              // Settle all debt
Actions.SETTLE_PAIR             // Settle both tokens in pair

// Take actions
Actions.TAKE                    // Take specific amount
Actions.TAKE_ALL                // Take all credit
Actions.TAKE_PAIR               // Take both tokens in pair
Actions.TAKE_PORTION            // Take percentage of credit

// Combined actions
Actions.SETTLE_TAKE_PAIR        // Settle and take in one action
Actions.CLOSE_CURRENCY          // Close out currency position
Actions.CLEAR_OR_TAKE           // Clear if possible, otherwise take
Actions.SWEEP                   // Sweep tokens from contract
```

**Example** (see detailed implementation in main guide):
```solidity
bytes memory actions = abi.encodePacked(
    uint8(Actions.SWAP_EXACT_IN_SINGLE),
    uint8(Actions.SETTLE_ALL),
    uint8(Actions.TAKE_ALL)
);

bytes[] memory params = new bytes[](3);
params[0] = abi.encode(
    IV4Router.ExactInputSingleParams({
        poolKey: poolKey,
        zeroForOne: true,
        amountIn: 1e18,
        amountOutMinimum: 0.95e18,
        hookData: ""
    })
);
params[1] = abi.encode(currency0, 1e18);        // SETTLE_ALL
params[2] = abi.encode(currency1, 0.95e18);     // TAKE_ALL

bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
bytes[] memory inputs = new bytes[](1);
inputs[0] = abi.encode(actions, params);
```

##### 0x11: V3_POSITION_MANAGER_PERMIT

Call permit on V3 NFT Position Manager

**Parameters**: Raw calldata for permit function

**Use Case**: Allow someone to operate on V3 position via signature

##### 0x12: V3_POSITION_MANAGER_CALL

Call any function on V3 NFT Position Manager

**Parameters**: Raw calldata for the function call

**Security**: Validates the caller owns the position being modified

##### 0x13: V4_INITIALIZE_POOL

Initialize a new V4 pool

**Parameters**:
```solidity
abi.encode(
    PoolKey poolKey,        // Pool parameters
    uint160 sqrtPriceX96    // Initial price
)
```

##### 0x14: V4_POSITION_MANAGER_CALL

Call modifyLiquidities on V4 Position Manager

**Parameters**: Raw calldata for modifyLiquidities

**Use Case**: Mint/modify liquidity positions through Universal Router

#### Group 4: Advanced (0x21+)

##### 0x21: EXECUTE_SUB_PLAN

Execute a nested set of commands

**Parameters**:
```solidity
abi.encode(
    bytes commands,         // Nested command bytes
    bytes[] inputs          // Nested command inputs
)
```

**Use Case**: Create reusable command sequences or conditional execution

### Command Flags

Commands can be modified with flags:

```solidity
// Allow command to revert without failing entire transaction
bytes1 commandWithFlag = bytes1(uint8(Commands.BALANCE_CHECK_ERC20) | uint8(Commands.FLAG_ALLOW_REVERT));

// Example: Check balance, continue if fails
bytes memory commands = abi.encodePacked(
    bytes1(uint8(Commands.BALANCE_CHECK_ERC20) | 0x80),  // With FLAG_ALLOW_REVERT
    uint8(Commands.V4_SWAP)                               // Continue with swap
);
```

**Flags**:
- `0x80`: FLAG_ALLOW_REVERT - Command can fail without reverting transaction
- `0x3f`: COMMAND_TYPE_MASK - Mask to extract command type

### Special Address Constants

Used in recipient parameters:

```solidity
// From ActionConstants
address constant MSG_SENDER = address(1);      // Resolves to original caller
address constant ADDRESS_THIS = address(2);    // Resolves to Universal Router

// Example
bytes memory commands = abi.encodePacked(uint8(Commands.SWEEP));
bytes[] memory inputs = new bytes[](1);
inputs[0] = abi.encode(
    USDC,
    ActionConstants.MSG_SENDER,  // Send to original caller
    0
);
```

### Command Chaining Example

Execute multiple operations atomically:

```solidity
// Wrap ETH → Swap on V4 → Unwrap WETH → Sweep to user
bytes memory commands = abi.encodePacked(
    uint8(Commands.WRAP_ETH),           // 1. Wrap ETH to WETH
    uint8(Commands.V4_SWAP),            // 2. Swap WETH for USDC
    uint8(Commands.UNWRAP_WETH),        // 3. Unwrap any leftover WETH
    uint8(Commands.SWEEP)               // 4. Sweep USDC to user
);

bytes[] memory inputs = new bytes[](4);
// ... encode inputs for each command

router.execute{value: 1 ether}(commands, inputs, deadline);
```

### V4 Actions Reference (Used within V4_SWAP Command)

When using the `V4_SWAP` command, you specify actions from the V4 Actions library:

#### Swap Actions

| Action | Value | Parameters | Description |
|--------|-------|------------|-------------|
| SWAP_EXACT_IN_SINGLE | 0x01 | `ExactInputSingleParams` | Swap exact input in single pool |
| SWAP_EXACT_IN | 0x02 | `ExactInputParams` | Swap exact input across multiple pools |
| SWAP_EXACT_OUT_SINGLE | 0x03 | `ExactOutputSingleParams` | Swap for exact output in single pool |
| SWAP_EXACT_OUT | 0x04 | `ExactOutputParams` | Swap for exact output across multiple pools |

#### Settlement Actions

| Action | Value | Parameters | Description |
|--------|-------|------------|-------------|
| SETTLE | 0x09 | `(Currency, uint256 amount, bool payerIsUser)` | Settle exact amount |
| SETTLE_ALL | 0x10 | `(Currency, uint256 maxAmount)` | Settle all debt up to max |
| SETTLE_PAIR | 0x11 | `(Currency, Currency)` | Settle both currencies in pair |
| SETTLE_TAKE_PAIR | 0x12 | `(Currency, Currency)` | Settle and take both in pair |

#### Take Actions

| Action | Value | Parameters | Description |
|--------|-------|------------|-------------|
| TAKE | 0x13 | `(Currency, address recipient, uint256 amount)` | Take exact amount |
| TAKE_ALL | 0x14 | `(Currency, uint256 minAmount)` | Take all credit, at least min |
| TAKE_PAIR | 0x15 | `(Currency, Currency, address recipient)` | Take both currencies |
| TAKE_PORTION | 0x16 | `(Currency, address recipient, uint256 bips)` | Take percentage |

#### Utility Actions

| Action | Value | Parameters | Description |
|--------|-------|------------|-------------|
| CLOSE_CURRENCY | 0x17 | `(Currency)` | Close out currency (settle debt or take credit) |
| CLEAR_OR_TAKE | 0x18 | `(Currency, uint256 minAmount)` | Clear if even, take if credit |
| SWEEP | 0x19 | `(Currency, address recipient)` | Transfer contract balance |

### ExactInputSingleParams Structure

Used with `SWAP_EXACT_IN_SINGLE` action:

```solidity
struct ExactInputSingleParams {
    PoolKey poolKey;            // Pool to swap in
    bool zeroForOne;            // Swap direction
    uint128 amountIn;           // Exact input amount
    uint128 amountOutMinimum;   // Minimum output
    bytes hookData;             // Data for pool's hook
}
```

### ExactInputParams Structure

Used with `SWAP_EXACT_IN` multi-hop action:

```solidity
struct ExactInputParams {
    Currency currencyIn;        // Input currency
    PathKey[] path;             // Multi-hop path
    uint128 amountIn;           // Exact input amount
    uint128 amountOutMinimum;   // Minimum final output
}

struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}
```

## Function Implementation Guide

### Function: `swap()`

**Purpose**: Execute a token swap on Uniswap V4 via Universal Router

**Signature**:
```solidity
function swap(
    PoolKey calldata key,
    uint128 amountIn,
    uint128 amountOutMin,
    bool zeroForOne
) external payable
```

**Parameters**:
- `key`: Pool identifier (currencies, fee, tickSpacing, hooks)
- `amountIn`: Exact amount of input token to swap
- `amountOutMin`: Minimum output token to receive (slippage protection)
- `zeroForOne`: Direction (true = currency0 → currency1, false = reverse)

**Returns**: Nothing (tokens transferred directly to caller)

### Implementation Steps

**Step 1: Determine Swap Direction**

```solidity
(address currencyIn, address currencyOut) = zeroForOne
    ? (key.currency0, key.currency1)
    : (key.currency1, key.currency0);
```

**Why?**
- Need to know which token to pull from user
- Need to know which token to return to user
- V4 uses currency0/currency1, but user thinks in terms of "in" and "out"

**Step 2: Transfer Input Tokens**

```solidity
transferFrom(currencyIn, msg.sender, uint256(amountIn));
```

**Implementation**:
```solidity
function transferFrom(address currency, address src, uint256 amt) private {
    if (currency == address(0)) {
        // Native ETH: verify msg.value
        require(msg.value == amt, "not enough ETH sent");
    } else {
        // ERC20: pull tokens from user
        IERC20(currency).transferFrom(src, address(this), amt);
    }
}
```

**Why?**
- Universal Router doesn't pull tokens directly from users
- We act as intermediary: user → us → router
- Special handling for ETH (address(0) convention)

**Step 3: Approve Permit2 and Universal Router**

```solidity
if (currencyIn != address(0)) {
    approve(currencyIn, uint160(amountIn), uint48(block.timestamp));
}
```

**Why skip ETH?**
- ETH doesn't need approvals (sent as msg.value)
- Only ERC20 tokens need approval mechanism

**Implementation**:
```solidity
function approve(address token, uint160 amount, uint48 expiration) private {
    // Step 1: Approve Permit2
    IERC20(token).approve(address(permit2), uint256(amount));
    
    // Step 2: Approve Universal Router via Permit2
    permit2.approve(token, address(router), amount, expiration);
}
```

**Permit2 Approve Signature**:
```solidity
function approve(
    address token,      // Token to approve
    address spender,    // Who can spend (Universal Router)
    uint160 amount,     // How much
    uint48 expiration   // When approval expires
) external
```

**Step 4: Encode Universal Router Command**

```solidity
bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
bytes[] memory inputs = new bytes[](1);
```

**Command Structure**:
- `commands`: Byte array where each byte is a command ID
- `inputs`: Array of encoded parameters, one per command
- Can have multiple commands in a single call

**Available Commands** (excerpt):
```solidity
library Commands {
    uint256 constant V2_SWAP_EXACT_IN = 0x00;
    uint256 constant V2_SWAP_EXACT_OUT = 0x01;
    uint256 constant V3_SWAP_EXACT_IN = 0x08;
    uint256 constant V3_SWAP_EXACT_OUT = 0x09;
    uint256 constant V4_SWAP = 0x10;              // ← We use this
    uint256 constant PERMIT2_TRANSFER = 0x0c;
    uint256 constant WRAP_ETH = 0x0b;
    uint256 constant UNWRAP_WETH = 0x0a;
    uint256 constant SWEEP = 0x04;
    // ... 30+ more commands
}
```

**Step 5: Encode V4 Actions**

```solidity
bytes memory actions = abi.encodePacked(
    uint8(Actions.SWAP_EXACT_IN_SINGLE),
    uint8(Actions.SETTLE_ALL),
    uint8(Actions.TAKE_ALL)
);
```

**Action Sequence Explained**:

1. **SWAP_EXACT_IN_SINGLE**: Execute the actual swap
   - Swaps exact `amountIn` for as much output as possible
   - Creates deltas: negative for input token, positive for output token

2. **SETTLE_ALL**: Pay the input token to PoolManager
   - Settles the negative delta (debt)
   - Transfers tokens from us to PoolManager

3. **TAKE_ALL**: Claim the output token from PoolManager
   - Claims the positive delta (credit)
   - Transfers tokens from PoolManager to us

**Why This Order?**
- Swap must happen first (creates deltas)
- SETTLE pays our debt (negative delta → 0)
- TAKE claims our credit (positive delta → 0)
- All deltas must be 0 by end of transaction

**Step 6: Encode Action Parameters**

```solidity
bytes[] memory params = new bytes[](3);
```

One parameter set per action.

**Parameter 1: SWAP_EXACT_IN_SINGLE**

```solidity
params[0] = abi.encode(
    IV4Router.ExactInputSingleParams({
        poolKey: key,
        zeroForOne: zeroForOne,
        amountIn: amountIn,
        amountOutMinimum: amountOutMin,
        hookData: bytes("")
    })
);
```

**ExactInputSingleParams Structure**:
```solidity
struct ExactInputSingleParams {
    PoolKey poolKey;        // Which pool to swap in
    bool zeroForOne;        // Swap direction
    uint128 amountIn;       // Exact input amount
    uint128 amountOutMinimum; // Slippage protection
    bytes hookData;         // Data for hook (if pool has hooks)
}
```

**Parameter 2: SETTLE_ALL**

```solidity
params[1] = abi.encode(currencyIn, uint256(amountIn));
```

**SETTLE_ALL Signature**:
```solidity
// Settle all of a currency up to maxAmount
function _handleAction(uint8 action, bytes calldata params) {
    if (action == Actions.SETTLE_ALL) {
        (Currency currency, uint256 maxAmount) = abi.decode(params, (Currency, uint256));
        // Pay debt to PoolManager
    }
}
```

**Why maxAmount?**
- Actual debt might be less than amountIn (due to fees, slippage)
- maxAmount is upper limit - only actual debt is paid

**Parameter 3: TAKE_ALL**

```solidity
params[2] = abi.encode(currencyOut, uint256(amountOutMin));
```

**TAKE_ALL Signature**:
```solidity
// Take all of a currency, at least minAmount
function _handleAction(uint8 action, bytes calldata params) {
    if (action == Actions.TAKE_ALL) {
        (Currency currency, uint256 minAmount) = abi.decode(params, (Currency, uint256));
        // Claim credit from PoolManager
        require(amountReceived >= minAmount, "Insufficient output");
    }
}
```

**Why minAmount?**
- Slippage protection at the action level
- Transaction reverts if we receive less than minimum

**Step 7: Encode Inputs for Universal Router**

```solidity
inputs[0] = abi.encode(actions, params);
```

**Structure**:
```
inputs[0] (for V4_SWAP command) =
    abi.encode(
        actions,  // bytes: encoded action IDs
        params    // bytes[]: array of encoded parameters
    )
```

This becomes the "input" parameter for the V4_SWAP command.

**Step 8: Execute via Universal Router**

```solidity
router.execute{value: msg.value}(commands, inputs, block.timestamp);
```

**Execute Signature**:
```solidity
function execute(
    bytes calldata commands,     // Command IDs to execute
    bytes[] calldata inputs,     // Inputs for each command
    uint256 deadline             // Transaction must execute before this
) external payable
```

**Why send msg.value?**
- If swapping ETH, need to send it with the call
- Universal Router will use it for SETTLE
- If not swapping ETH, msg.value will be 0

**Why deadline?**
- Prevents transactions from executing after too much time
- Protects against stale prices
- Common pattern in DeFi

**Step 9: Withdraw Tokens to User**

```solidity
withdraw(key.currency0, msg.sender);
withdraw(key.currency1, msg.sender);
```

**Implementation**:
```solidity
function withdraw(address currency, address receiver) private {
    if (currency == address(0)) {
        // Withdraw ETH
        uint256 bal = address(this).balance;
        if (bal > 0) {
            (bool ok,) = receiver.call{value: bal}("");
            require(ok, "Transfer ETH failed");
        }
    } else {
        // Withdraw ERC20
        uint256 bal = IERC20(currency).balanceOf(address(this));
        if (bal > 0) {
            IERC20(currency).transfer(receiver, bal);
        }
    }
}
```

**Why withdraw both currencies?**
- We only swapped one direction, but we don't know which at this point
- Safer to withdraw all tokens
- Only one will have a balance (the output token)
- Other will have balance = 0 (skip transfer)

**Alternative**: Could track which currency is output and only withdraw that one.

### Complete Function

```solidity
function swap(
    PoolKey calldata key,
    uint128 amountIn,
    uint128 amountOutMin,
    bool zeroForOne
) external payable {
    // 1. Determine swap direction
    (address currencyIn, address currencyOut) = zeroForOne
        ? (key.currency0, key.currency1)
        : (key.currency1, key.currency0);

    // 2. Transfer tokens from user
    transferFrom(currencyIn, msg.sender, uint256(amountIn));

    // 3. Approve Permit2 and Universal Router (if ERC20)
    if (currencyIn != address(0)) {
        approve(currencyIn, uint160(amountIn), uint48(block.timestamp));
    }

    // 4. Encode Universal Router command
    bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
    bytes[] memory inputs = new bytes[](1);

    // 5. Encode V4 actions
    bytes memory actions = abi.encodePacked(
        uint8(Actions.SWAP_EXACT_IN_SINGLE),
        uint8(Actions.SETTLE_ALL),
        uint8(Actions.TAKE_ALL)
    );
    bytes[] memory params = new bytes[](3);

    // 6. SWAP_EXACT_IN_SINGLE params
    params[0] = abi.encode(
        IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            hookData: bytes("")
        })
    );

    // 7. SETTLE_ALL params
    params[1] = abi.encode(currencyIn, uint256(amountIn));

    // 8. TAKE_ALL params
    params[2] = abi.encode(currencyOut, uint256(amountOutMin));

    // 9. Encode input for Universal Router
    inputs[0] = abi.encode(actions, params);

    // 10. Execute swap
    router.execute{value: msg.value}(commands, inputs, block.timestamp);

    // 11. Withdraw output tokens to user
    withdraw(key.currency0, msg.sender);
    withdraw(key.currency1, msg.sender);
}
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "not enough ETH sent" | msg.value < amountIn when swapping ETH | Send correct ETH amount |
| "STF" (SafeTransferFrom failed) | User didn't approve contract | User must approve tokens first |
| "Permit2: insufficient allowance" | Permit2 not approved | Call approve() for token |
| "Insufficient output" | Output < amountOutMin | Increase slippage or use better amountOutMin |
| "Transaction too old" | block.timestamp > deadline | Send transaction faster |
| "Transfer ETH failed" | Receiver can't receive ETH | Ensure receiver has receive() |

## 🧪 Testing Guide

### Test Setup

```solidity
contract UniversalRouterTest is Test, TestHelper {
    IERC20 constant usdc = IERC20(USDC);
    
    UniversalRouterExercises ex;
    PoolKey poolKey;
    
    receive() external payable {}
    
    function setUp() public {
        // 1. Fund test contract with USDC
        deal(USDC, address(this), 1000 * 1e6);
        
        // 2. Deploy exercise contract
        ex = new UniversalRouterExercises();
        
        // 3. Approve exercise contract to spend USDC
        usdc.approve(address(ex), type(uint256).max);
        
        // 4. Define pool key (ETH/USDC)
        poolKey = PoolKey({
            currency0: address(0),      // ETH
            currency1: USDC,            // USDC
            fee: 500,                   // 0.05% fee
            tickSpacing: 10,
            hooks: address(0)           // No hooks
        });
    }
}
```

### Test Scenarios

#### Test 1: Swap ETH for USDC (Zero for One)

```solidity
function test_swap_zero_for_one() public {
    // Record balances before swap
    uint256 usdcBefore = usdc.balanceOf(address(this));
    uint256 ethBefore = address(this).balance;
    
    // Swap 1 ETH for USDC
    uint128 amountIn = 1e18;
    ex.swap{value: uint256(amountIn)}({
        key: poolKey,
        amountIn: amountIn,
        amountOutMin: 1,             // Accept any output (for testing)
        zeroForOne: true             // ETH → USDC
    });
    
    // Record balances after swap
    uint256 usdcAfter = usdc.balanceOf(address(this));
    uint256 ethAfter = address(this).balance;
    
    // Calculate deltas
    int256 ethDelta = int256(ethAfter) - int256(ethBefore);
    int256 usdcDelta = int256(usdcAfter) - int256(usdcBefore);
    
    console.log("ETH delta: %e", ethDelta);
    console.log("USDC delta: %e", usdcDelta);
    
    // Assertions
    assertLt(ethDelta, 0, "ETH should decrease");
    assertGt(usdcDelta, 0, "USDC should increase");
    
    // Verify approximately 1 ETH was spent
    assertEq(ethDelta, -int256(uint256(amountIn)), "ETH spent");
    
    // Verify we received meaningful USDC (depends on pool price)
    assertGt(usdcDelta, 1000 * 1e6, "Should receive > 1000 USDC");
}
```

**What's Tested:**
- ETH balance decreases by amountIn
- USDC balance increases
- Can swap native ETH through Universal Router
- Output amount is reasonable

**Expected Output:**
```
ETH delta: -1e18
USDC delta: ~3000e6 (depends on pool price)
```

#### Test 2: Swap USDC for ETH (One for Zero)

```solidity
function test_swap_one_for_zero() public {
    // Record balances before swap
    uint256 usdcBefore = usdc.balanceOf(address(this));
    uint256 ethBefore = address(this).balance;
    
    // Swap 1000 USDC for ETH
    uint128 amountIn = 1000 * 1e6;
    ex.swap({
        key: poolKey,
        amountIn: amountIn,
        amountOutMin: 1,             // Accept any output
        zeroForOne: false            // USDC → ETH
    });
    
    // Record balances after swap
    uint256 usdcAfter = usdc.balanceOf(address(this));
    uint256 ethAfter = address(this).balance;
    
    // Calculate deltas
    int256 ethDelta = int256(ethAfter) - int256(ethBefore);
    int256 usdcDelta = int256(usdcAfter) - int256(usdcBefore);
    
    console.log("ETH delta: %e", ethDelta);
    console.log("USDC delta: %e", usdcDelta);
    
    // Assertions
    assertGt(ethDelta, 0, "ETH should increase");
    assertLt(usdcDelta, 0, "USDC should decrease");
    
    // Verify approximately 1000 USDC was spent
    assertEq(usdcDelta, -int256(uint256(amountIn)), "USDC spent");
    
    // Verify we received meaningful ETH
    assertGt(ethDelta, 0.3 ether, "Should receive > 0.3 ETH");
}
```

**What's Tested:**
- USDC balance decreases by amountIn
- ETH balance increases
- Can swap ERC20 for native ETH
- Output amount is reasonable

**Expected Output:**
```
ETH delta: ~0.33e18 (depends on pool price)
USDC delta: -1000e6
```

### Running Tests

```bash
# Run all Universal Router tests
forge test --fork-url $FORK_URL --match-contract UniversalRouterTest -vv

# Run specific test with detailed output
forge test --fork-url $FORK_URL --match-test test_swap_zero_for_one -vvv

# Run with gas report
forge test --fork-url $FORK_URL --match-contract UniversalRouterTest --gas-report

# Run with traces (see all calls)
forge test --fork-url $FORK_URL --match-test test_swap_one_for_zero -vvvv
```

**Note**: Requires forking mainnet where Universal Router is deployed.

### Expected Gas Costs

| Operation | Gas Cost | Notes |
|-----------|----------|-------|
| swap() - ETH → USDC | ~180,000 | Includes all approvals |
| swap() - USDC → ETH | ~190,000 | Similar cost |
| First-time Permit2 approval | +45,000 | One-time per token |
| Universal Router execute | ~120,000 | Core routing logic |
| V4 swap execution | ~60,000 | Actual swap in PoolManager |

**Comparison**:
- Direct V4Router: ~140,000 gas
- Universal Router: ~180,000 gas (+40k overhead)
- **Benefit**: Single interface for V2/V3/V4, worth the overhead

## 🔍 Debugging Guide

### Debug Technique 1: Log Commands and Actions

```solidity
function swap(...) external payable {
    // Log what we're encoding
    console.log("Command:", uint8(Commands.V4_SWAP));
    
    bytes memory actions = abi.encodePacked(
        uint8(Actions.SWAP_EXACT_IN_SINGLE),
        uint8(Actions.SETTLE_ALL),
        uint8(Actions.TAKE_ALL)
    );
    
    console.log("Action 1:", uint8(actions[0]));
    console.log("Action 2:", uint8(actions[1]));
    console.log("Action 3:", uint8(actions[2]));
    
    // Continue...
}
```

### Debug Technique 2: Verify Approvals

```solidity
function debugApprovals(address token) public view {
    // Check token → Permit2 approval
    uint256 permit2Allowance = IERC20(token).allowance(
        address(this),
        address(permit2)
    );
    console.log("Token → Permit2 allowance:", permit2Allowance);
    
    // Check Permit2 → Universal Router approval
    (uint160 amount, uint48 expiration, uint48 nonce) = permit2.allowance(
        address(this),
        token,
        address(router)
    );
    console.log("Permit2 → Router allowance:", amount);
    console.log("Expiration:", expiration);
}
```

### Debug Technique 3: Track Token Flow

```solidity
function swap(...) external payable {
    console.log("=== BEFORE SWAP ===");
    console.log("Contract balance:", IERC20(currencyIn).balanceOf(address(this)));
    console.log("User balance:", IERC20(currencyIn).balanceOf(msg.sender));
    
    // Transfer from user
    transferFrom(currencyIn, msg.sender, uint256(amountIn));
    
    console.log("=== AFTER TRANSFER ===");
    console.log("Contract balance:", IERC20(currencyIn).balanceOf(address(this)));
    console.log("User balance:", IERC20(currencyIn).balanceOf(msg.sender));
    
    // Execute swap
    router.execute{value: msg.value}(commands, inputs, block.timestamp);
    
    console.log("=== AFTER SWAP ===");
    console.log("Contract balance (in):", IERC20(currencyIn).balanceOf(address(this)));
    console.log("Contract balance (out):", IERC20(currencyOut).balanceOf(address(this)));
    
    // Withdraw
    withdraw(key.currency0, msg.sender);
    withdraw(key.currency1, msg.sender);
    
    console.log("=== AFTER WITHDRAW ===");
    console.log("User balance (out):", IERC20(currencyOut).balanceOf(msg.sender));
}
```

### Common Issues and Solutions

#### Issue 1: "Transaction too old"

**Symptom**: Transaction reverts with deadline error

**Cause**: Using timestamp that's too early

**Debug**:
```solidity
console.log("Current timestamp:", block.timestamp);
console.log("Deadline:", deadline);
```

**Solution**:
```solidity
// Use current timestamp as deadline
router.execute{value: msg.value}(commands, inputs, block.timestamp);

// Or add buffer for pending transactions
router.execute{value: msg.value}(commands, inputs, block.timestamp + 60);
```

#### Issue 2: "Permit2: insufficient allowance"

**Symptom**: Transaction reverts when Universal Router tries to transfer tokens

**Cause**: Permit2 not approved or expired

**Debug**:
```solidity
(uint160 amount, uint48 expiration,) = permit2.allowance(
    address(this),
    token,
    address(router)
);
console.log("Allowance:", amount);
console.log("Expiration:", expiration);
console.log("Current time:", block.timestamp);
console.log("Expired?", block.timestamp > expiration);
```

**Solution**:
```solidity
// Use future expiration
permit2.approve(token, address(router), amount, uint48(block.timestamp + 3600));

// Or max expiration
permit2.approve(token, address(router), amount, type(uint48).max);
```

#### Issue 3: Wrong Output Amount

**Symptom**: Received tokens don't match expectations

**Cause**: Price impact, fees, or wrong pool

**Debug**:
```solidity
// Check pool state before swap
int24 tick = getCurrentTick(poolKey);
console.log("Pool tick:", tick);
console.log("Pool fee:", poolKey.fee);

// Check actual amounts
console.log("Expected out:", expectedOut);
console.log("Actual out:", actualOut);
console.log("Difference:", expectedOut - actualOut);
console.log("Slippage %:", (expectedOut - actualOut) * 100 / expectedOut);
```

**Solution**:
- Adjust `amountOutMin` based on acceptable slippage
- Check you're using correct pool
- Account for pool fees (0.05% = 500, 0.3% = 3000)

#### Issue 4: "Insufficient output"

**Symptom**: Transaction reverts during TAKE_ALL

**Cause**: `amountOutMin` is too high for current price

**Debug**:
```solidity
// Simulate swap first to get expected output
uint256 expectedOut = quoter.quoteExactInputSingle(
    poolKey,
    zeroForOne,
    amountIn,
    ""
);
console.log("Expected output:", expectedOut);
console.log("Your amountOutMin:", amountOutMin);
```

**Solution**:
```solidity
// Use 0 for testing (no protection)
amountOutMin: 1

// For production: expected output - slippage
uint256 expected = getQuote(poolKey, amountIn);
uint256 minOut = expected * 95 / 100;  // 5% slippage tolerance
```

#### Issue 5: ETH Not Received

**Symptom**: Contract has ETH but user doesn't receive it

**Cause**: Withdraw function not working or receiver can't accept ETH

**Debug**:
```solidity
console.log("Contract ETH balance:", address(this).balance);
console.log("Receiver:", receiver);

// Try withdraw
withdraw(address(0), receiver);

console.log("Contract ETH balance after:", address(this).balance);
```

**Solution**:
```solidity
// Ensure receiver can receive ETH
receive() external payable {}

// Check withdraw implementation
function withdraw(address currency, address receiver) private {
    if (currency == address(0)) {
        uint256 bal = address(this).balance;
        console.log("Withdrawing ETH:", bal);
        if (bal > 0) {
            (bool ok,) = receiver.call{value: bal}("");
            require(ok, "Transfer ETH failed");
            console.log("ETH transfer success");
        }
    }
}
```

## 🎯 Real-World Applications

### Use Case 1: Multi-Protocol Aggregator

Universal Router enables routing through V2, V3, and V4 in a single transaction:

```solidity
contract MultiProtocolAggregator {
    function bestSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        // Get quotes from all versions
        uint256 v2Out = getV2Quote(tokenIn, tokenOut, amountIn);
        uint256 v3Out = getV3Quote(tokenIn, tokenOut, amountIn);
        uint256 v4Out = getV4Quote(tokenIn, tokenOut, amountIn);
        
        // Route through best option using Universal Router
        if (v4Out > v3Out && v4Out > v2Out) {
            // Use V4_SWAP command
            return executeV4Swap(tokenIn, tokenOut, amountIn);
        } else if (v3Out > v2Out) {
            // Use V3_SWAP_EXACT_IN command
            return executeV3Swap(tokenIn, tokenOut, amountIn);
        } else {
            // Use V2_SWAP_EXACT_IN command
            return executeV2Swap(tokenIn, tokenOut, amountIn);
        }
    }
}
```

### Use Case 2: Complex Multi-Hop Routing

Execute swaps across multiple pools and versions:

```solidity
function complexRoute(
    uint256 amountIn
) external returns (uint256 finalAmount) {
    // Route: ETH → USDC (V4) → WBTC (V3) → DAI (V2)
    
    bytes memory commands = abi.encodePacked(
        uint8(Commands.V4_SWAP),      // ETH → USDC on V4
        uint8(Commands.V3_SWAP_EXACT_IN), // USDC → WBTC on V3
        uint8(Commands.V2_SWAP_EXACT_IN)  // WBTC → DAI on V2
    );
    
    bytes[] memory inputs = new bytes[](3);
    // ... encode inputs for each command
    
    router.execute{value: amountIn}(commands, inputs, block.timestamp);
}
```

### Use Case 3: Atomic Arbitrage

Take advantage of price differences across versions:

```solidity
contract ArbitrageBot {
    function arbitrage() external {
        // Buy on V3 (lower price), sell on V4 (higher price)
        
        bytes memory commands = abi.encodePacked(
            uint8(Commands.V3_SWAP_EXACT_IN),  // Buy USDC with ETH on V3
            uint8(Commands.V4_SWAP)             // Sell USDC for ETH on V4
        );
        
        bytes[] memory inputs = new bytes[](2);
        // ... configure to make profit
        
        router.execute{value: 1 ether}(commands, inputs, block.timestamp);
        
        // Profit = final ETH - initial ETH - gas
    }
}
```

### Use Case 4: Gas-Efficient Batch Swaps

Execute multiple swaps for different users in one transaction:

```solidity
contract BatchSwapService {
    struct SwapRequest {
        address user;
        PoolKey poolKey;
        uint128 amountIn;
        uint128 amountOutMin;
        bool zeroForOne;
    }
    
    function batchSwap(SwapRequest[] calldata requests) external {
        // Build commands array
        bytes memory commands;
        bytes[] memory inputs = new bytes[](requests.length);
        
        for (uint i = 0; i < requests.length; i++) {
            commands = bytes.concat(
                commands,
                abi.encodePacked(uint8(Commands.V4_SWAP))
            );
            
            // Encode inputs for each swap
            inputs[i] = encodeV4SwapInput(requests[i]);
        }
        
        // Execute all swaps in single transaction
        router.execute(commands, inputs, block.timestamp);
        
        // Distribute outputs to respective users
        // ...
    }
}
```

### Use Case 5: DCA (Dollar Cost Averaging) Automation

Automated recurring swaps:

```solidity
contract DCAAutomation {
    struct DCAConfig {
        address user;
        PoolKey poolKey;
        uint128 amountPerSwap;
        uint256 interval;
        uint256 lastSwap;
    }
    
    mapping(address => DCAConfig) public configs;
    
    function executeDCA(address user) external {
        DCAConfig storage config = configs[user];
        require(block.timestamp >= config.lastSwap + config.interval, "Too soon");
        
        // Execute swap via Universal Router
        // ... (use V4_SWAP command)
        
        config.lastSwap = block.timestamp;
    }
}
```

## 🚀 Advanced Concepts

### Understanding Command Chaining

Commands can be chained for complex operations:

```solidity
// Example: Swap + Add Liquidity
bytes memory commands = abi.encodePacked(
    uint8(Commands.V4_SWAP),           // 1. Swap to get both tokens
    uint8(Commands.V4_POSITION_CALL)   // 2. Add liquidity with results
);
```

**Benefits**:
- Atomic execution (all or nothing)
- Gas efficient (single transaction)
- No intermediate approvals needed

### The SETTLE vs SETTLE_ALL Pattern

```solidity
// SETTLE: Settle specific amount
params = abi.encode(currency, exactAmount);

// SETTLE_ALL: Settle up to max (actual debt might be less)
params = abi.encode(currency, maxAmount);
```

**When to use SETTLE_ALL**:
- Don't know exact amount needed (depends on swap output)
- Want to settle any remaining debt
- More flexible but slightly less gas efficient

**When to use SETTLE**:
- Know exact amount to settle
- More precise control
- Slightly more gas efficient

### The TAKE vs TAKE_ALL Pattern

```solidity
// TAKE: Take specific amount
params = abi.encode(currency, exactAmount);

// TAKE_ALL: Take everything owed, at least minimum
params = abi.encode(currency, minAmount);
```

**When to use TAKE_ALL**:
- Want to claim all credits
- Don't know exact amount (depends on swap)
- Common pattern for swaps

**When to use TAKE**:
- Want specific amount
- Leaving remainder for future operations
- More precise control

### Gas Optimization Techniques

#### 1. Reuse Permit2 Approvals

```solidity
// Instead of approving every time
function approve(address token, uint160 amount, uint48 expiration) private {
    // Check if already approved
    (uint160 existing,, ) = permit2.allowance(
        address(this),
        token,
        address(router)
    );
    
    if (existing >= amount) {
        return; // Skip approval
    }
    
    // Only approve if needed
    IERC20(token).approve(address(permit2), uint256(amount));
    permit2.approve(token, address(router), amount, expiration);
}
```

**Savings**: ~45,000 gas per swap (after first)

#### 2. Batch Multiple Swaps

```solidity
// Single command per swap: High gas
swap(pool1, amount1, min1, true);
swap(pool2, amount2, min2, false);
// Cost: 2 × 180k = 360k gas

// Multiple commands in one execute: Lower gas
bytes memory commands = abi.encodePacked(
    uint8(Commands.V4_SWAP),
    uint8(Commands.V4_SWAP)
);
router.execute(commands, inputs, deadline);
// Cost: ~280k gas (saves 80k)
```

#### 3. Optimize Action Sequences

```solidity
// Inefficient: Individual SETTLE and TAKE
SETTLE, TAKE, SETTLE, TAKE

// Efficient: Batch with SETTLE_PAIR and TAKE_PAIR
SETTLE_PAIR, TAKE_PAIR
```

### Integration with Permit (EIP-2612)

For gasless approvals using signatures:

```solidity
function swapWithPermit(
    PoolKey calldata key,
    uint128 amountIn,
    uint128 amountOutMin,
    bool zeroForOne,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
) external {
    address tokenIn = zeroForOne ? key.currency0 : key.currency1;
    
    // Use signature for approval (gasless for user)
    IERC20Permit(tokenIn).permit(
        msg.sender,
        address(this),
        amountIn,
        deadline,
        v, r, s
    );
    
    // Now can transferFrom
    transferFrom(tokenIn, msg.sender, amountIn);
    
    // Continue with swap...
}
```

### Multi-Version Routing Strategy

Intelligent routing based on liquidity and price:

```solidity
contract IntelligentRouter {
    function getBestRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view returns (
        uint8 version,     // 2, 3, or 4
        uint256 expectedOut
    ) {
        // Get liquidity from each version
        uint256 v2Liquidity = getV2Liquidity(tokenIn, tokenOut);
        uint256 v3Liquidity = getV3Liquidity(tokenIn, tokenOut);
        uint256 v4Liquidity = getV4Liquidity(tokenIn, tokenOut);
        
        // For small swaps, prefer version with most liquidity
        if (amountIn < 10 ether) {
            if (v4Liquidity > v3Liquidity && v4Liquidity > v2Liquidity) {
                return (4, getV4Quote(tokenIn, tokenOut, amountIn));
            }
            // ...
        }
        
        // For large swaps, might want to split across versions
        // ...
    }
}
```

## 📊 Comparison with Direct V4Router

### Using Universal Router (This Exercise)

```solidity
// Pros:
// ✅ Single interface for V2/V3/V4
// ✅ Can combine operations (swap + liquidity)
// ✅ Future-proof (new versions can be added)
// ✅ Permit2 integration

// Cons:
// ❌ Additional routing overhead (~40k gas)
// ❌ More complex encoding
// ❌ Extra abstraction layer

router.execute(commands, inputs, deadline);
// Gas: ~180k
```

### Using Direct V4Router

```solidity
// Pros:
// ✅ More direct (less overhead)
// ✅ Simpler encoding
// ✅ ~40k gas savings

// Cons:
// ❌ Only works for V4
// ❌ Can't combine with V2/V3
// ❌ Separate interface for each version

v4Router.exactInputSingle(params, deadline);
// Gas: ~140k
```

### Recommendation

**Use Universal Router when**:
- Building multi-protocol applications
- Need flexibility for future versions
- Want unified interface
- Gas cost difference is acceptable

**Use Direct V4Router when**:
- Only using V4
- Every bit of gas matters
- Simpler code preferred
- Not combining protocols

## 🎓 Learning Outcomes

After completing this exercise, you should understand:

### Conceptual Understanding
- ✅ Command-based execution patterns
- ✅ How Universal Router unifies multiple protocols
- ✅ The role of Permit2 in modern DeFi
- ✅ SETTLE and TAKE patterns for delta management
- ✅ Trade-offs between routing layers

### Technical Skills
- ✅ Encoding commands and inputs for Universal Router
- ✅ Building action sequences for V4
- ✅ Using Permit2 for approvals
- ✅ Handling both ETH and ERC20 tokens
- ✅ Debugging multi-layered contract calls

### Practical Applications
- ✅ Building multi-protocol aggregators
- ✅ Implementing complex routing strategies
- ✅ Creating gas-efficient batch operations
- ✅ Integrating signature-based approvals

## 📚 Additional Resources

### Official Documentation
- [Universal Router GitHub](https://github.com/Uniswap/universal-router)
- [Permit2 Documentation](https://github.com/Uniswap/permit2)
- [V4 Router Implementation](https://github.com/Uniswap/v4-periphery/blob/main/src/V4Router.sol)
- [Commands Library](https://github.com/Uniswap/universal-router/blob/main/contracts/libraries/Commands.sol)

### Related Concepts
- EIP-2612 (Permit)
- EIP-712 (Typed Structured Data)
- Command pattern in smart contracts
- Multi-protocol routing strategies

### Code Examples
- [Universal Router Examples](https://github.com/Uniswap/universal-router/tree/main/test)
- [Integration Examples](https://docs.uniswap.org/contracts/universal-router/technical-reference)

## ✅ Exercise Checklist

Before moving to the next exercise, ensure you can:

- [ ] Explain the Universal Router architecture
- [ ] Describe the difference between commands and actions
- [ ] Implement token transfers via transferFrom
- [ ] Configure Permit2 approvals correctly
- [ ] Encode V4_SWAP command with proper actions
- [ ] Build SWAP_EXACT_IN_SINGLE parameters
- [ ] Use SETTLE_ALL and TAKE_ALL actions
- [ ] Handle both ETH and ERC20 tokens
- [ ] Withdraw tokens back to users
- [ ] Pass both test scenarios
- [ ] Debug common Universal Router errors
- [ ] Explain when to use Universal Router vs direct routers

## 🎯 Next Steps

After mastering Universal Router, consider exploring:

1. **Multi-Hop Swaps**: Swapping through multiple pools
2. **V2/V3 Integration**: Using other Uniswap versions
3. **Permit2 Signatures**: Implementing gasless approvals
4. **Batch Operations**: Combining multiple operations
5. **Custom Commands**: Building your own command extensions
6. **MEV Protection**: Protecting against sandwich attacks
7. **Flash Swaps**: Using flash accounting for arbitrage

---

**Exercise Complete!** 🎉

You now understand how to use Uniswap's Universal Router to execute V4 swaps through a unified interface. This knowledge enables you to build applications that seamlessly integrate multiple DeFi protocols and versions in a gas-efficient manner.

The Universal Router's command-based architecture represents the future of DeFi routing, providing flexibility and extensibility for protocols yet to be built.

