# Uniswap V3 to V4 Multi-Hop Swap - Complete Technical Guide

## Introduction

This document provides comprehensive technical documentation for executing **multi-hop swaps** across Uniswap V3 and V4 protocols using the Universal Router. This exercise demonstrates the power of Universal Router's command-based architecture to seamlessly route trades across different protocol versions in a single atomic transaction.

### What You'll Learn

- Multi-hop swaps across different Uniswap versions
- Command chaining with Universal Router
- Handling WETH wrapping/unwrapping in routing
- Using CONTRACT_BALANCE for intermediate swaps
- SETTLE action in V4 for paying tokens
- OPEN_DELTA for using swap output as next input
- Cross-protocol token flow management
- Optimizing gas for complex routing scenarios

### Key Concepts

**Multi-Hop Swap**: A swap that goes through multiple pools to get from token A to token C via intermediate token B. Example: USDC → WETH (V3) → ETH (V4).

**Cross-Protocol Routing**: Executing swaps across different Uniswap versions (V2, V3, V4) in a single transaction.

**CONTRACT_BALANCE**: Special constant that tells Universal Router to use its entire balance of a token, useful for chaining operations.

**OPEN_DELTA**: Special constant in V4 that uses the current delta (debt/credit) as the swap amount, enabling seamless chaining.

**SETTLE vs SETTLE_ALL**: SETTLE pays a specific amount to PoolManager, while SETTLE_ALL pays all debt up to a maximum.

**WETH Handling**: Native ETH in V4 is represented as address(0), but V3 uses WETH. May need UNWRAP_WETH command between protocols.

## Contract Overview

The `SwapV3ToV4.sol` contract demonstrates:

1. Routing from V3 pool to V4 pool in one transaction
2. Handling WETH → ETH conversion when needed
3. Using CONTRACT_BALANCE for intermediate token amounts
4. Using SETTLE to pay tokens into V4 PoolManager
5. Using OPEN_DELTA to consume settlement debt
6. Atomic execution ensuring all-or-nothing trades

### Core Features

| Feature | Description |
|---------|-------------|
| **Cross-Protocol** | Seamlessly route V3 → V4 |
| **WETH Handling** | Automatic unwrapping when needed |
| **Atomic Execution** | Single transaction for entire route |
| **Gas Efficient** | No intermediate approvals or transfers |
| **Flexible Routing** | Support any V3 → V4 token combination |
| **Delta Management** | Efficient token accounting across hops |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Key Dependencies**: IUniversalRouter, IV4Router, Actions, Commands
- **Commands Used**: V3_SWAP_EXACT_IN, UNWRAP_WETH (conditional), V4_SWAP
- **V4 Actions**: SETTLE, SWAP_EXACT_IN_SINGLE, TAKE_ALL
- **Pattern**: V3 Swap → (Unwrap WETH) → V4 Settle → V4 Swap → Take

## 🏗️ Architecture Overview

### Multi-Hop Cross-Protocol Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    MULTI-HOP SWAP FLOW                           │
│                                                                  │
│  Token A (User)                                                  │
│      │                                                           │
│      ├─ Transfer to Universal Router                             │
│      │                                                           │
│      ↓                                                           │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │               Universal Router                             │  │
│  │                                                            │  │
│  │  Command 1: V3_SWAP_EXACT_IN                               │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  Uniswap V3 Pool (Token A → Token B)                 │  │  │
│  │  │                                                      │  │  │
│  │  │  Input:  Token A (from contract balance)             │  │  │
│  │  │  Output: Token B (stays in Universal Router)         │  │  │
│  │  │                                                      │  │  │
│  │  │  If Token B = WETH:                                  │  │  │
│  │  │    Balance: X WETH in Universal Router               │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  Command 2: UNWRAP_WETH (conditional)                      │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  Only if Token B = WETH                              │  │  │
│  │  │                                                      │  │  │
│  │  │  WETH.withdraw(X)                                    │  │  │
│  │  │  Result: X ETH in Universal Router                   │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  Command 3: V4_SWAP                                        │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  Action 1: SETTLE                                    │  │  │
│  │  │    - Pay Token B/ETH to PoolManager                  │  │  │
│  │  │    - Amount: CONTRACT_BALANCE                        │  │  │
│  │  │    - Creates debt in PoolManager                     │  │  │
│  │  │                                                      │  │  │
│  │  │  Action 2: SWAP_EXACT_IN_SINGLE                      │  │  │
│  │  │    - Uniswap V4 Pool (Token B → Token C)             │  │  │
│  │  │    - Amount: OPEN_DELTA (uses SETTLE debt)           │  │  │
│  │  │    - Creates credit in Token C                       │  │  │
│  │  │                                                      │  │  │
│  │  │  Action 3: TAKE_ALL                                  │  │  │
│  │  │    - Claim Token C from PoolManager                  │  │  │
│  │  │    - Sends to Universal Router                       │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  Result: Token C in Universal Router                       │  │
│  └────────────────────────────────────────────────────────────┘  │
│      │                                                           │
│      ├─ Withdraw Token C to User                                 │
│      ↓                                                           │
│  Token C (User)                                                  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Token Flow Visualization

#### Scenario 1: USDC → WETH (V3) → ETH (V4)

```
Step 1: User transfers USDC to Universal Router
  User:              1000 USDC
  Universal Router:  1000 USDC
  
Step 2: V3_SWAP_EXACT_IN (USDC → WETH)
  V3 Pool executes swap
  Universal Router:  0 USDC, 0.33 WETH
  
Step 3: UNWRAP_WETH (WETH → ETH)
  WETH.withdraw(0.33 ether)
  Universal Router:  0.33 ETH
  
Step 4: V4_SWAP
  
  Action 1 - SETTLE (pay ETH to PoolManager)
    Universal Router → PoolManager: 0.33 ETH
    PoolManager accounting:
      delta(ETH) = -0.33 (debt/negative)
    Universal Router: 0 ETH
    
  Action 2 - SWAP_EXACT_IN_SINGLE (use OPEN_DELTA)
    amountIn = OPEN_DELTA = 0.33 ETH
    Swap 0.33 ETH for USDC in V4 pool
    PoolManager accounting:
      delta(ETH) = -0.33 + 0.33 = 0 (settled)
      delta(USDC) = +1000 (credit/positive)
      
  Action 3 - TAKE_ALL (claim USDC)
    PoolManager → Universal Router: 1000 USDC
    PoolManager accounting:
      delta(USDC) = +1000 - 1000 = 0 (settled)
    Universal Router: 1000 USDC
    
Step 5: Withdraw to user
  Universal Router → User: 1000 USDC
  User: 1000 USDC ✅
```

#### Scenario 2: WETH → USDC (V3) → ETH (V4)

```
Step 1: User transfers WETH to Universal Router
  User:              1 WETH
  Universal Router:  1 WETH
  
Step 2: V3_SWAP_EXACT_IN (WETH → USDC)
  V3 Pool executes swap
  Universal Router:  0 WETH, 3000 USDC
  
Step 3: UNWRAP_WETH (skipped, output is USDC not WETH)

Step 4: V4_SWAP
  
  Action 1 - SETTLE (pay USDC to PoolManager)
    Universal Router → PoolManager: 3000 USDC
    PoolManager accounting:
      delta(USDC) = -3000 (debt)
    Universal Router: 0 USDC
    
  Action 2 - SWAP_EXACT_IN_SINGLE
    amountIn = OPEN_DELTA = 3000 USDC
    Swap 3000 USDC for ETH in V4 pool
    PoolManager accounting:
      delta(USDC) = -3000 + 3000 = 0 (settled)
      delta(ETH) = +1 (credit)
      
  Action 3 - TAKE_ALL (claim ETH)
    PoolManager → Universal Router: 1 ETH
    PoolManager accounting:
      delta(ETH) = +1 - 1 = 0 (settled)
    Universal Router: 1 ETH
    
Step 5: Withdraw to user
  Universal Router → User: 1 ETH
  User: 1 ETH ✅
```

### Why SETTLE + OPEN_DELTA Pattern?

This pattern is key to efficient V4 integration:

```
Traditional Approach (doesn't work well):
1. Take tokens from V3 swap
2. Approve V4 Router
3. Swap in V4
Problem: Requires approval, less gas efficient

SETTLE + OPEN_DELTA (optimal):
1. SETTLE: Pay tokens directly to PoolManager
   - Creates negative delta (debt)
2. SWAP with OPEN_DELTA: Use that debt as input
   - Swap consumes the debt
   - Creates positive delta (credit)
3. TAKE_ALL: Claim the credit

Benefit: No approvals, tokens stay in PoolManager accounting
```

## 🔄 Complete Execution Flow

```
USER                  CONTRACT        UNIVERSAL ROUTER    V3 POOL       V4 POOL MANAGER
 │                        │                   │              │               │
 │ swap(v3Params,v4Params)│                   │              │               │
 │───────────────────────>│                   │              │               │
 │                        │                   │              │               │
 │                        │ [1. Validate]     │              │               │
 │                        │ Check v3.tokenOut │              │               │
 │                        │ matches v4 pool   │              │               │
 │                        │                   │              │               │
 │                        │ [2. Transfer]     │              │               │
 │                        │ transferFrom(     │              │               │
 │                        │   user→router,    │              │               │
 │                        │   tokenIn)        │              │               │
 │                        │                   │              │               │
 │                        │ [3. Build commands]              │               │
 │                        │ If WETH output:   │              │               │
 │                        │   V3_SWAP +       │              │               │
 │                        │   UNWRAP_WETH +   │              │               │
 │                        │   V4_SWAP         │              │               │
 │                        │ Else:             │              │               │
 │                        │   V3_SWAP +       │              │               │
 │                        │   V4_SWAP         │              │               │
 │                        │                   │              │               │
 │                        │ [4. Encode inputs]│              │               │
 │                        │ V3_SWAP_EXACT_IN: │              │               │
 │                        │   recipient=router│              │               │
 │                        │   amountIn=       │              │               │
 │                        │     CONTRACT_BAL  │              │               │
 │                        │   path=encoded    │              │               │
 │                        │   payerIsUser=    │              │               │
 │                        │     false         │              │               │
 │                        │                   │              │               │
 │                        │ [5. Execute]      │              │               │
 │                        │ router.execute(   │              │               │
 │                        │   commands,inputs)│              │               │
 │                        │──────────────────>│              │               │
 │                        │                   │              │               │
 │                        │                   │ [6. CMD 1]   │               │
 │                        │                   │ V3_SWAP      │               │
 │                        │                   │─────────────>│               │
 │                        │                   │              │               │
 │                        │                   │  Swap A→B    │               │
 │                        │                   │  Send B to   │               │
 │                        │                   │  router      │               │
 │                        │                   │<─────────────│               │
 │                        │                   │              │               │
 │                        │                   │ Router has B │               │
 │                        │                   │              │               │
 │                        │                   │ [7. CMD 2]   │               │
 │                        │                   │ UNWRAP_WETH  │               │
 │                        │                   │ (if needed)  │               │
 │                        │                   │              │               │
 │                        │                   │ WETH.withdraw│               │
 │                        │                   │ Router now   │               │
 │                        │                   │ has ETH      │               │
 │                        │                   │              │               │
 │                        │                   │ [8. CMD 3]   │               │
 │                        │                   │ V4_SWAP      │               │
 │                        │                   │              │               │
 │                        │                   │ Action 1:    │               │
 │                        │                   │ SETTLE       │               │
 │                        │                   │─────────────────────────────>│
 │                        │                   │              │  Pay B/ETH    │
 │                        │                   │              │  delta=-X     │
 │                        │                   │<─────────────────────────────│
 │                        │                   │              │               │
 │                        │                   │ Action 2:    │               │
 │                        │                   │ SWAP (OPEN_  │               │
 │                        │                   │ DELTA)       │               │
 │                        │                   │─────────────────────────────>│
 │                        │                   │              │  unlock(...)  │
 │                        │                   │              │  swap X for Y │
 │                        │                   │              │  delta(B)=0   │
 │                        │                   │              │  delta(C)=+Y  │
 │                        │                   │<─────────────────────────────│
 │                        │                   │              │               │
 │                        │                   │ Action 3:    │               │
 │                        │                   │ TAKE_ALL     │               │
 │                        │                   │─────────────────────────────>│
 │                        │                   │              │  send C       │
 │                        │                   │              │  delta(C)=0   │
 │                        │                   │<─────────────────────────────│
 │                        │                   │              │               │
 │                        │                   │ Router has C │               │
 │                        │  Return           │              │               │
 │                        │<──────────────────│              │               │
 │                        │                   │              │               │
 │                        │ [9. Withdraw]     │              │               │
 │                        │ withdraw(C, user) │              │               │
 │                        │                   │              │               │
 │  Receive Token C       │                   │              │               │
 │<───────────────────────│                   │              │               │
 │                        │                   │              │               │
```

## 📝 Function Implementation Guide

### Function: `swap()`

**Purpose**: Execute a multi-hop swap from V3 to V4 in a single transaction

**Signature**:
```solidity
function swap(V3Params calldata v3, V4Params calldata v4) external
```

**Parameters**:

```solidity
struct V3Params {
    address tokenIn;        // Input token for V3 swap
    address tokenOut;       // Output token from V3 (input for V4)
    uint24 poolFee;         // V3 pool fee tier (500, 3000, 10000)
    uint256 amountIn;       // Amount of tokenIn to swap
}

struct V4Params {
    PoolKey key;            // V4 pool identifier
    uint128 amountOutMin;   // Minimum final output (slippage protection)
}
```

### Implementation Steps

**Step 1: Validate Pool Compatibility**

```solidity
// Disable WETH pools in V4 to keep code simple
require(
    v4.key.currency0 != WETH && v4.key.currency1 != WETH,
    "WETH pools disabled"
);
```

**Why?**: V4 uses address(0) for native ETH, not WETH. Supporting WETH pools would require additional logic.

**Step 2: Map V4 Currencies to Addresses**

```solidity
(address v4Token0, address v4Token1) = (v4.key.currency0, v4.key.currency1);

// Map address(0) to WETH for comparison
if (v4Token0 == address(0)) {
    v4Token0 = WETH;
}
```

**Why?**: V3 uses WETH, V4 uses address(0) for ETH. Need to compare them correctly.

**Step 3: Validate V3 Output Matches V4 Input**

```solidity
require(
    v3.tokenOut == v4Token0 || v3.tokenOut == v4Token1,
    "invalid pool key"
);
```

**Critical Check**: The output from V3 must be one of the tokens in the V4 pool.

**Step 4: Determine V4 Swap Direction**

```solidity
(address v4CurrencyIn, address v4CurrencyOut) = v3.tokenOut == v4Token0
    ? (v4.key.currency0, v4.key.currency1)
    : (v4.key.currency1, v4.key.currency0);
```

**Logic**:
- If V3 outputs token0 of V4 pool → swap token0 for token1
- If V3 outputs token1 of V4 pool → swap token1 for token0

**Step 5: Transfer Input Tokens to Universal Router**

```solidity
IERC20(v3.tokenIn).transferFrom(msg.sender, address(router), v3.amountIn);
```

**Why Universal Router?**: It needs custody of tokens to execute V3 swap.

**Step 6: Build Command Sequence**

```solidity
bytes memory commands;
bytes[] memory inputs;

if (v3.tokenOut == WETH) {
    // Need to unwrap WETH to ETH for V4
    commands = abi.encodePacked(
        uint8(Commands.V3_SWAP_EXACT_IN),
        uint8(Commands.UNWRAP_WETH),
        uint8(Commands.V4_SWAP)
    );
} else {
    // Direct token, no unwrapping needed
    commands = abi.encodePacked(
        uint8(Commands.V3_SWAP_EXACT_IN),
        uint8(Commands.V4_SWAP)
    );
}

inputs = new bytes[](commands.length);
```

**Decision Logic**:
- **V3 outputs WETH + V4 needs ETH**: Insert UNWRAP_WETH command
- **V3 outputs ERC20**: No unwrapping needed

**Step 7: Encode V3_SWAP_EXACT_IN Input**

```solidity
inputs[0] = abi.encode(
    address(router),                 // recipient: keep in router for next hop
    ActionConstants.CONTRACT_BALANCE, // amountIn: use entire balance
    uint256(1),                      // amountOutMin: accept any (for simplicity)
    abi.encodePacked(                // path: encoded V3 path
        v3.tokenIn,
        v3.poolFee,
        v3.tokenOut
    ),
    false                            // payerIsUser: false, pay from router balance
);
```

**Key Parameters**:

- **`recipient = address(router)`**: Output stays in Universal Router for next command
- **`ActionConstants.CONTRACT_BALANCE`**: Special value meaning "use entire balance"
  - Universal Router will use all tokenIn it holds
  - No need to specify exact amount
- **`amountOutMin = 1`**: Minimal slippage protection (for testing)
  - In production, calculate based on expected output
- **`path = abi.encodePacked(...)`**: V3's compact path encoding
  - Format: tokenIn, fee, tokenOut (for single hop)
  - For multi-hop: tokenIn, fee1, tokenMid, fee2, tokenOut
- **`payerIsUser = false`**: Tokens come from router, not user
  - Router already has tokens from Step 5

**Step 8: Encode UNWRAP_WETH Input (if needed)**

```solidity
if (v3.tokenOut == WETH) {
    inputs[1] = abi.encode(
        address(router),    // recipient: keep ETH in router
        uint256(1)          // amountMin: minimum to unwrap
    );
}
```

**Purpose**: Convert WETH to native ETH for V4 usage.

**Step 9: Build V4 Action Sequence**

```solidity
bytes memory actions = abi.encodePacked(
    uint8(Actions.SETTLE),
    uint8(Actions.SWAP_EXACT_IN_SINGLE),
    uint8(Actions.TAKE_ALL)
);
```

**Three-Step V4 Pattern**:
1. **SETTLE**: Pay tokens into PoolManager
2. **SWAP**: Use those tokens (via OPEN_DELTA)
3. **TAKE**: Claim swap output

**Step 10: Encode SETTLE Parameters**

```solidity
bytes[] memory params = new bytes[](3);

params[0] = abi.encode(
    v4CurrencyIn,                     // currency to settle
    uint256(ActionConstants.CONTRACT_BALANCE), // amount: all balance
    false                             // payerIsUser: false (router pays)
);
```

**SETTLE Parameters**:
- **`currency`**: Which token to pay (B from V3 output, or ETH after unwrap)
- **`amount = CONTRACT_BALANCE`**: Pay entire router balance
  - Automatically uses correct amount from previous hop
- **`payerIsUser = false`**: Router pays, not user
  - Router received tokens from V3/unwrap

**Why SETTLE before SWAP?**
- Creates debt in PoolManager that SWAP will consume
- More efficient than transferring tokens during swap

**Step 11: Encode SWAP_EXACT_IN_SINGLE Parameters**

```solidity
params[1] = abi.encode(
    IV4Router.ExactInputSingleParams({
        poolKey: v4.key,
        zeroForOne: v4CurrencyIn == v4.key.currency0,
        amountIn: ActionConstants.OPEN_DELTA,
        amountOutMinimum: v4.amountOutMin,
        hookData: bytes("")
    })
);
```

**Critical Parameter**: `amountIn = ActionConstants.OPEN_DELTA`

**What is OPEN_DELTA?**
```solidity
// Special constant
uint256 constant OPEN_DELTA = 0;

// When used as amountIn:
// "Use the current open delta (debt) for this currency"

// After SETTLE creates debt of X tokens:
//   delta = -X (negative = debt)
// SWAP with OPEN_DELTA:
//   amountIn = X (uses the debt)
//   After swap: delta(in) = 0, delta(out) = +Y
```

**Benefits**:
- No need to know exact amount in advance
- Automatically uses whatever SETTLE provided
- Seamless chaining of operations

**Step 12: Encode TAKE_ALL Parameters**

```solidity
params[2] = abi.encode(
    v4CurrencyOut,        // currency to take
    uint256(v4.amountOutMin) // minimum to receive
);
```

**TAKE_ALL**: Claims all credit (positive delta) for the currency, sending it to the router.

**Step 13: Encode V4_SWAP Input**

```solidity
inputs[inputs.length - 1] = abi.encode(actions, params);
```

**Structure**: V4_SWAP command takes encoded (actions, params) as its input.

**Step 14: Execute via Universal Router**

```solidity
router.execute(commands, inputs, block.timestamp);
```

**Atomic Execution**: All commands execute or entire transaction reverts.

**Step 15: Withdraw Output to User**

```solidity
withdraw(v4CurrencyOut, msg.sender);
```

**Implementation**:
```solidity
function withdraw(address currency, address receiver) private {
    if (currency == address(0)) {
        // Native ETH
        uint256 bal = address(this).balance;
        if (bal > 0) {
            (bool ok,) = receiver.call{value: bal}("");
            require(ok, "Transfer ETH failed");
        }
    } else {
        // ERC20
        uint256 bal = IERC20(currency).balanceOf(address(this));
        if (bal > 0) {
            IERC20(currency).transfer(receiver, bal);
        }
    }
}
```

### Complete Function

```solidity
function swap(V3Params calldata v3, V4Params calldata v4) external {
    // 1. Validate
    require(
        v4.key.currency0 != WETH && v4.key.currency1 != WETH,
        "WETH pools disabled"
    );

    // 2. Map currencies
    (address v4Token0, address v4Token1) = (v4.key.currency0, v4.key.currency1);
    if (v4Token0 == address(0)) {
        v4Token0 = WETH;
    }

    // 3. Validate connection
    require(
        v3.tokenOut == v4Token0 || v3.tokenOut == v4Token1,
        "invalid pool key"
    );

    // 4. Determine V4 direction
    (address v4CurrencyIn, address v4CurrencyOut) = v3.tokenOut == v4Token0
        ? (v4.key.currency0, v4.key.currency1)
        : (v4.key.currency1, v4.key.currency0);

    // 5. Transfer tokens to router
    IERC20(v3.tokenIn).transferFrom(msg.sender, address(router), v3.amountIn);

    // 6. Build commands
    bytes memory commands;
    bytes[] memory inputs;

    if (v3.tokenOut == WETH) {
        commands = abi.encodePacked(
            uint8(Commands.V3_SWAP_EXACT_IN),
            uint8(Commands.UNWRAP_WETH),
            uint8(Commands.V4_SWAP)
        );
    } else {
        commands = abi.encodePacked(
            uint8(Commands.V3_SWAP_EXACT_IN),
            uint8(Commands.V4_SWAP)
        );
    }

    inputs = new bytes[](commands.length);

    // 7. V3_SWAP_EXACT_IN
    inputs[0] = abi.encode(
        address(router),
        ActionConstants.CONTRACT_BALANCE,
        uint256(1),
        abi.encodePacked(v3.tokenIn, v3.poolFee, v3.tokenOut),
        false
    );

    // 8. UNWRAP_WETH (if needed)
    if (v3.tokenOut == WETH) {
        inputs[1] = abi.encode(address(router), uint256(1));
    }

    // 9. V4 actions
    bytes memory actions = abi.encodePacked(
        uint8(Actions.SETTLE),
        uint8(Actions.SWAP_EXACT_IN_SINGLE),
        uint8(Actions.TAKE_ALL)
    );
    bytes[] memory params = new bytes[](3);

    // 10. SETTLE
    params[0] = abi.encode(
        v4CurrencyIn,
        uint256(ActionConstants.CONTRACT_BALANCE),
        false
    );

    // 11. SWAP_EXACT_IN_SINGLE
    params[1] = abi.encode(
        IV4Router.ExactInputSingleParams({
            poolKey: v4.key,
            zeroForOne: v4CurrencyIn == v4.key.currency0,
            amountIn: ActionConstants.OPEN_DELTA,
            amountOutMinimum: v4.amountOutMin,
            hookData: bytes("")
        })
    );

    // 12. TAKE_ALL
    params[2] = abi.encode(v4CurrencyOut, uint256(v4.amountOutMin));

    // 13. V4_SWAP input
    inputs[inputs.length - 1] = abi.encode(actions, params);

    // 14. Execute
    router.execute(commands, inputs, block.timestamp);

    // 15. Withdraw
    withdraw(v4CurrencyOut, msg.sender);
}
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "WETH pools disabled" | V4 pool uses WETH directly | Use ETH (address(0)) in V4 pool |
| "invalid pool key" | V3 output doesn't match V4 pool | Ensure v3.tokenOut is in v4 pool |
| "STF" | Transfer failed | User must approve contract first |
| "Insufficient output" | Slippage too high | Increase amountOutMin tolerance |
| "OPEN_DELTA underflow" | No debt to consume | Ensure SETTLE happens before SWAP |

## 🧪 Testing Guide

### Test Setup

```solidity
contract SwapV3ToV4Test is Test, TestHelper {
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant usdc = IERC20(USDC);
    
    SwapV3ToV4 ex;
    PoolKey poolKey;
    
    receive() external payable {}
    
    function setUp() public {
        ex = new SwapV3ToV4();
        
        // Fund test contract
        deal(USDC, address(this), 1000 * 1e6);
        deal(WETH, address(this), 100 * 1e18);
        
        // Approve contract
        usdc.approve(address(ex), type(uint256).max);
        weth.approve(address(ex), type(uint256).max);
        
        // Define V4 pool (ETH/USDC)
        poolKey = PoolKey({
            currency0: address(0),      // ETH
            currency1: USDC,            // USDC
            fee: 500,
            tickSpacing: 10,
            hooks: address(0)
        });
    }
}
```

### Test Scenarios

#### Test 1: WETH → USDC (V3) → ETH (V4)

```solidity
function test_swap_weth_to_eth() public {
    // Track balances
    uint256 ethBefore = address(this).balance;
    uint256 wethBefore = weth.balanceOf(address(this));
    uint256 usdcBefore = usdc.balanceOf(address(this));
    
    // Execute multi-hop swap
    uint128 amountIn = 1e18; // 1 WETH
    ex.swap({
        v3: SwapV3ToV4.V3Params({
            tokenIn: WETH,
            tokenOut: USDC,
            poolFee: 3000,      // 0.3% V3 pool
            amountIn: amountIn
        }),
        v4: SwapV3ToV4.V4Params({
            key: poolKey,
            amountOutMin: 1     // Accept any output (for testing)
        })
    });
    
    // Check results
    uint256 ethAfter = address(this).balance;
    uint256 wethAfter = weth.balanceOf(address(this));
    uint256 usdcAfter = usdc.balanceOf(address(this));
    
    // Calculate deltas
    int256 ethDelta = int256(ethAfter) - int256(ethBefore);
    int256 wethDelta = int256(wethAfter) - int256(wethBefore);
    int256 usdcDelta = int256(usdcAfter) - int256(usdcBefore);
    
    console.log("ETH delta: %e", ethDelta);
    console.log("WETH delta: %e", wethDelta);
    console.log("USDC delta: %e", usdcDelta);
    
    // Assertions
    assertGt(ethDelta, 0, "Should receive ETH");
    assertLt(wethDelta, 0, "Should spend WETH");
    assertEq(usdcDelta, 0, "USDC should be intermediate only");
}
```

**What's Tested:**
- WETH spent (input)
- ETH received (output)
- USDC balance unchanged (fully used in intermediate hop)
- Multi-hop routing works correctly

**Flow**:
```
1 WETH → V3 → ~3000 USDC → unwrap WETH (N/A, output is USDC) 
                          → V4 → ~1 ETH
```

**Expected Output**:
```
ETH delta: +1000000000000000000 (1 ETH)
WETH delta: -1000000000000000000 (1 WETH)
USDC delta: 0 (intermediate token)
```

#### Test 2: USDC → WETH (V3) → ETH (V4)

```solidity
function test_swap_usdc_to_usdc() public {
    // Track balances
    uint256 ethBefore = address(this).balance;
    uint256 wethBefore = weth.balanceOf(address(this));
    uint256 usdcBefore = usdc.balanceOf(address(this));
    
    // Execute multi-hop swap
    uint128 amountIn = 1000 * 1e6; // 1000 USDC
    ex.swap({
        v3: SwapV3ToV4.V3Params({
            tokenIn: USDC,
            tokenOut: WETH,
            poolFee: 3000,
            amountIn: amountIn
        }),
        v4: SwapV3ToV4.V4Params({
            key: poolKey,
            amountOutMin: 1
        })
    });
    
    // Check results
    uint256 ethAfter = address(this).balance;
    uint256 wethAfter = weth.balanceOf(address(this));
    uint256 usdcAfter = usdc.balanceOf(address(this));
    
    int256 ethDelta = int256(ethAfter) - int256(ethBefore);
    int256 wethDelta = int256(wethAfter) - int256(wethBefore);
    int256 usdcDelta = int256(usdcAfter) - int256(usdcBefore);
    
    console.log("ETH delta: %e", ethDelta);
    console.log("WETH delta: %e", wethDelta);
    console.log("USDC delta: %e", usdcDelta);
    
    // Assertions
    assertGt(ethDelta, 0, "Should receive ETH");
    assertEq(wethDelta, 0, "WETH unwrapped to ETH");
    assertLt(usdcDelta, 0, "Should spend USDC");
}
```

**What's Tested:**
- USDC spent (input)
- ETH received (output, via unwrapped WETH)
- WETH balance unchanged (unwrapped to ETH immediately)
- UNWRAP_WETH command works correctly

**Flow**:
```
1000 USDC → V3 → ~0.33 WETH → UNWRAP_WETH → 0.33 ETH 
                              → V4 → ~1000 USDC
```

**Expected Output**:
```
ETH delta: +330000000000000000 (~0.33 ETH)
WETH delta: 0 (unwrapped immediately)
USDC delta: -1000000000 (1000 USDC spent)
```

### Running Tests

```bash
# Run all tests
forge test --fork-url $FORK_URL --match-contract SwapV3ToV4Test -vv

# Run specific test with detailed logs
forge test --fork-url $FORK_URL --match-test test_swap_weth_to_eth -vvv

# Run with gas report
forge test --fork-url $FORK_URL --match-contract SwapV3ToV4Test --gas-report

# Run with full traces
forge test --fork-url $FORK_URL --match-test test_swap_usdc_to_usdc -vvvv
```

### Expected Gas Costs

| Operation | Gas Cost | Notes |
|-----------|----------|-------|
| swap() - no unwrap | ~220,000 | V3 swap + V4 swap |
| swap() - with unwrap | ~240,000 | +20k for UNWRAP_WETH |
| V3_SWAP_EXACT_IN | ~100,000 | V3 pool swap |
| UNWRAP_WETH | ~20,000 | WETH.withdraw() |
| V4_SWAP (3 actions) | ~100,000 | SETTLE + SWAP + TAKE |

**Comparison**:
- Separate transactions: ~350k gas (approval + V3 + approval + V4)
- Unified router: ~220k gas (no intermediate approvals)
- **Savings**: ~130k gas (37% reduction)

## 🔍 Debugging Guide

### Debug Technique 1: Track Token Balances

```solidity
function swap(V3Params calldata v3, V4Params calldata v4) external {
    console.log("=== INITIAL STATE ===");
    console.log("User tokenIn:", IERC20(v3.tokenIn).balanceOf(msg.sender));
    console.log("Router tokenIn:", IERC20(v3.tokenIn).balanceOf(address(router)));
    
    // Transfer
    IERC20(v3.tokenIn).transferFrom(msg.sender, address(router), v3.amountIn);
    
    console.log("=== AFTER TRANSFER ===");
    console.log("User tokenIn:", IERC20(v3.tokenIn).balanceOf(msg.sender));
    console.log("Router tokenIn:", IERC20(v3.tokenIn).balanceOf(address(router)));
    
    // Execute
    router.execute(commands, inputs, block.timestamp);
    
    console.log("=== AFTER EXECUTE ===");
    console.log("Contract balance (out):", IERC20(v4CurrencyOut).balanceOf(address(this)));
    
    // Withdraw
    withdraw(v4CurrencyOut, msg.sender);
    
    console.log("=== AFTER WITHDRAW ===");
    console.log("User balance (out):", IERC20(v4CurrencyOut).balanceOf(msg.sender));
}
```

### Debug Technique 2: Verify Command Sequence

```solidity
function debugCommands(V3Params calldata v3) internal view {
    console.log("=== COMMAND SEQUENCE ===");
    
    if (v3.tokenOut == WETH) {
        console.log("Command 0:", uint8(Commands.V3_SWAP_EXACT_IN));
        console.log("Command 1:", uint8(Commands.UNWRAP_WETH));
        console.log("Command 2:", uint8(Commands.V4_SWAP));
        console.log("Total commands: 3");
    } else {
        console.log("Command 0:", uint8(Commands.V3_SWAP_EXACT_IN));
        console.log("Command 1:", uint8(Commands.V4_SWAP));
        console.log("Total commands: 2");
    }
}
```

### Debug Technique 3: Trace V4 Deltas

```solidity
// Add this in a test or hook
function traceDeltas() internal {
    console.log("=== V4 DELTAS ===");
    
    // After SETTLE
    console.log("After SETTLE:");
    console.log("  delta(in): negative (debt)");
    
    // After SWAP
    console.log("After SWAP:");
    console.log("  delta(in): 0 (consumed)");
    console.log("  delta(out): positive (credit)");
    
    // After TAKE_ALL
    console.log("After TAKE_ALL:");
    console.log("  delta(out): 0 (claimed)");
}
```

### Common Issues and Solutions

#### Issue 1: "WETH pools disabled"

**Symptom**: Transaction reverts immediately

**Cause**: V4 pool uses WETH instead of address(0) for ETH

**Debug**:
```solidity
console.log("V4 currency0:", v4.key.currency0);
console.log("V4 currency1:", v4.key.currency1);
console.log("WETH address:", WETH);
console.log("Uses WETH?", v4.key.currency0 == WETH || v4.key.currency1 == WETH);
```

**Solution**: Use address(0) in V4 pool key for ETH
```solidity
// Wrong
poolKey.currency0 = WETH;

// Correct
poolKey.currency0 = address(0);
```

#### Issue 2: "invalid pool key"

**Symptom**: Transaction reverts during validation

**Cause**: V3 output token not in V4 pool

**Debug**:
```solidity
console.log("V3 tokenOut:", v3.tokenOut);
console.log("V4 token0:", v4Token0);
console.log("V4 token1:", v4Token1);
console.log("Match token0?", v3.tokenOut == v4Token0);
console.log("Match token1?", v3.tokenOut == v4Token1);
```

**Solution**: Ensure proper token routing
```solidity
// V3 outputs USDC, V4 must have USDC
v3.tokenOut = USDC;
v4.key.currency0 = address(0); // ETH
v4.key.currency1 = USDC;       // ✅ Matches
```

#### Issue 3: UNWRAP_WETH Not Executing

**Symptom**: WETH remains in router, V4 swap fails

**Cause**: Conditional logic error

**Debug**:
```solidity
console.log("V3 tokenOut:", v3.tokenOut);
console.log("WETH address:", WETH);
console.log("Should unwrap?", v3.tokenOut == WETH);
console.log("Commands length:", commands.length);
```

**Solution**: Verify conditional
```solidity
if (v3.tokenOut == WETH) {
    // This branch should execute when V3 outputs WETH
    commands = abi.encodePacked(
        uint8(Commands.V3_SWAP_EXACT_IN),
        uint8(Commands.UNWRAP_WETH),     // ← This command
        uint8(Commands.V4_SWAP)
    );
}
```

#### Issue 4: OPEN_DELTA Underflow

**Symptom**: V4 swap reverts with arithmetic underflow

**Cause**: SETTLE didn't create debt, or wrong action order

**Debug**:
```solidity
// Verify action order
console.log("Action 0:", uint8(actions[0])); // Should be SETTLE
console.log("Action 1:", uint8(actions[1])); // Should be SWAP
console.log("Action 2:", uint8(actions[2])); // Should be TAKE_ALL

// Verify SETTLE parameters
console.log("SETTLE currency:", v4CurrencyIn);
console.log("SETTLE amount:", uint256(ActionConstants.CONTRACT_BALANCE));
```

**Solution**: Ensure correct order
```solidity
bytes memory actions = abi.encodePacked(
    uint8(Actions.SETTLE),              // 1. Create debt first
    uint8(Actions.SWAP_EXACT_IN_SINGLE), // 2. Use debt (OPEN_DELTA)
    uint8(Actions.TAKE_ALL)             // 3. Claim credit
);
```

#### Issue 5: No Output Received

**Symptom**: User receives nothing after swap

**Cause**: Withdraw function issue or wrong currency

**Debug**:
```solidity
console.log("Contract balance before withdraw:");
console.log("  ETH:", address(this).balance);
console.log("  Token:", IERC20(v4CurrencyOut).balanceOf(address(this)));

console.log("Withdrawing currency:", v4CurrencyOut);
console.log("Is ETH?", v4CurrencyOut == address(0));
```

**Solution**: Verify withdraw logic
```solidity
function withdraw(address currency, address receiver) private {
    if (currency == address(0)) {
        uint256 bal = address(this).balance;
        console.log("Withdrawing ETH:", bal);
        if (bal > 0) {
            (bool ok,) = receiver.call{value: bal}("");
            require(ok, "Transfer ETH failed");
        }
    } else {
        uint256 bal = IERC20(currency).balanceOf(address(this));
        console.log("Withdrawing token:", bal);
        if (bal > 0) {
            IERC20(currency).transfer(receiver, bal);
        }
    }
}
```

## 🎯 Real-World Applications

### Use Case 1: Liquidity Fragmentation Arbitrage

**Scenario**: Better prices split across V3 and V4

```solidity
contract LiquidityAggregator {
    function getBestRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (
        bool useV3ToV4,
        uint256 expectedOut
    ) {
        // Get quotes
        uint256 directV4 = quoteV4(tokenIn, tokenOut, amountIn);
        uint256 viaV3 = quoteV3ToV4(tokenIn, tokenOut, amountIn);
        
        // Route through better path
        if (viaV3 > directV4) {
            return (true, viaV3);
        }
        return (false, directV4);
    }
    
    function executeOptimalSwap(...) external {
        if (useV3ToV4) {
            // Use multi-hop
            swapV3ToV4.swap(...);
        } else {
            // Use direct V4
            v4Router.swap(...);
        }
    }
}
```

### Use Case 2: Migration Assistance

**Scenario**: Help users migrate positions from V3 to V4

```solidity
contract V3ToV4Migrator {
    function migratePosition(
        uint256 v3TokenId
    ) external {
        // 1. Withdraw from V3 position
        (uint256 amount0, uint256 amount1) = v3Position.withdraw(v3TokenId);
        
        // 2. Route one token through V3→V4 to rebalance
        swapV3ToV4.swap(
            V3Params({
                tokenIn: token0,
                tokenOut: token1,
                poolFee: 3000,
                amountIn: amount0 / 2
            }),
            V4Params({
                key: v4PoolKey,
                amountOutMin: calculateMin()
            })
        );
        
        // 3. Add balanced liquidity to V4
        v4PositionManager.mint(...);
    }
}
```

### Use Case 3: Cross-Protocol MEV Protection

**Scenario**: Split trades to avoid sandwich attacks

```solidity
contract MEVProtectedRouter {
    function protectedSwap(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external {
        // Split order across protocols
        uint256 half = amount / 2;
        
        // Part 1: V3 only
        v3Router.exactInputSingle(tokenIn, tokenOut, half);
        
        // Part 2: V3→V4 multi-hop (harder to sandwich)
        swapV3ToV4.swap(
            V3Params({tokenIn, intermediateToken, ...}),
            V4Params({...})
        );
    }
}
```

### Use Case 4: Automated Market Making

**Scenario**: Provide liquidity on V4, rebalance via V3

```solidity
contract HybridAMM {
    function rebalance() external {
        // Check V4 position skew
        (uint256 amount0, uint256 amount1) = getV4Position();
        
        if (amount0 > amount1 * 1.2) {
            // Too much token0, swap some to token1 via V3→V4
            swapV3ToV4.swap(
                V3Params({
                    tokenIn: token0,
                    tokenOut: intermediateToken,
                    ...
                }),
                V4Params({
                    // Ends in token1
                    ...
                })
            );
            
            // Add rebalanced liquidity back to V4
            v4PositionManager.increaseLiquidity(...);
        }
    }
}
```

### Use Case 5: Token Launch Strategy

**Scenario**: Launch on V4 but use V3 liquidity

```solidity
contract TokenLauncher {
    // New token has V4 pool but limited liquidity
    // Route through V3 ETH/USDC for better execution
    
    function buyNewToken(uint256 usdcAmount) external {
        // USDC → WETH (V3 deep liquidity) → NewToken (V4 new pool)
        swapV3ToV4.swap(
            V3Params({
                tokenIn: USDC,
                tokenOut: WETH,
                poolFee: 500,    // Stable pool
                amountIn: usdcAmount
            }),
            V4Params({
                key: PoolKey({
                    currency0: address(0),     // ETH
                    currency1: newToken,
                    fee: 10000,                // 1% for new token
                    tickSpacing: 200,
                    hooks: address(0)
                }),
                amountOutMin: calculateMin()
            })
        );
    }
}
```

## 🚀 Advanced Concepts

### Understanding CONTRACT_BALANCE

**Definition**: Special constant telling router to use entire token balance

```solidity
// From ActionConstants
uint256 constant CONTRACT_BALANCE = 0x8000000000000000000000000000000000000000000000000000000000000000;

// In UniversalRouter dispatch logic:
if (amount == ActionConstants.CONTRACT_BALANCE) {
    amount = ERC20(token).balanceOf(address(this));
}
```

**Why Useful?**
```solidity
// Without CONTRACT_BALANCE:
// Need to track exact amounts between commands
inputs[0] = abi.encode(..., exactAmount, ...);
// If V3 swap returns slightly different amount, next command fails

// With CONTRACT_BALANCE:
inputs[0] = abi.encode(..., CONTRACT_BALANCE, ...);
// Automatically uses whatever amount is available
// Perfect for command chaining
```

### Understanding OPEN_DELTA

**What is Delta?**

In V4, delta represents the PoolManager's debt/credit accounting:

```solidity
// Negative delta = You owe tokens to PoolManager (debt)
int256 delta = -1000; // Owe 1000 tokens

// Positive delta = PoolManager owes tokens to you (credit)
int256 delta = +1000; // Owed 1000 tokens

// Zero delta = All settled
int256 delta = 0;
```

**OPEN_DELTA Pattern**:

```solidity
// Step 1: SETTLE creates negative delta
SETTLE(currency, 1000, false)
// Result: delta = -1000 (PoolManager needs 1000 tokens)

// Step 2: SWAP with OPEN_DELTA uses that delta
SWAP_EXACT_IN_SINGLE(
    amountIn: OPEN_DELTA  // Uses the -1000 delta
)
// Swap internally:
//   Takes 1000 tokens (settles debt)
//   Executes swap
//   Creates credit in output token

// Result: 
//   delta(input) = 0 (debt settled)
//   delta(output) = +amount (credit created)
```

**Value of OPEN_DELTA**:
```solidity
uint128 constant OPEN_DELTA = 0;

// But has special meaning when used as amountIn
// Router interprets 0 as "use current delta"
```

### Multi-Hop Extensions

**Three-Way Hop**: V3 → V3 → V4

```solidity
function tripleHop(
    address tokenA,
    address tokenB,
    address tokenC,
    PoolKey calldata v4Key
) external {
    // Transfer tokenA to router
    IERC20(tokenA).transferFrom(msg.sender, address(router), amountIn);
    
    bytes memory commands = abi.encodePacked(
        uint8(Commands.V3_SWAP_EXACT_IN),  // A → B
        uint8(Commands.V3_SWAP_EXACT_IN),  // B → C
        uint8(Commands.V4_SWAP)             // C → D
    );
    
    bytes[] memory inputs = new bytes[](3);
    
    // First V3 hop
    inputs[0] = abi.encode(
        address(router),
        CONTRACT_BALANCE,
        1,
        abi.encodePacked(tokenA, uint24(3000), tokenB),
        false
    );
    
    // Second V3 hop
    inputs[1] = abi.encode(
        address(router),
        CONTRACT_BALANCE,  // Use output from first hop
        1,
        abi.encodePacked(tokenB, uint24(3000), tokenC),
        false
    );
    
    // V4 hop (same as before)
    inputs[2] = encodeV4Swap(tokenC, v4Key);
    
    router.execute(commands, inputs, deadline);
}
```

### Optimal Routing Algorithm

**Simple Router**:

```solidity
contract SimpleRouter {
    function getBestPath(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view returns (bytes memory commands, bytes[] memory inputs) {
        // Check all possible paths
        uint256 bestOutput = 0;
        uint8 bestPath = 0;
        
        // Path 1: Direct V4
        uint256 out1 = quoteV4(tokenIn, tokenOut, amountIn);
        if (out1 > bestOutput) {
            bestOutput = out1;
            bestPath = 1;
        }
        
        // Path 2: Direct V3
        uint256 out2 = quoteV3(tokenIn, tokenOut, amountIn);
        if (out2 > bestOutput) {
            bestOutput = out2;
            bestPath = 2;
        }
        
        // Path 3: V3 → V4 (via each intermediate)
        address[] memory intermediates = [WETH, USDC, USDT];
        for (uint i = 0; i < intermediates.length; i++) {
            uint256 out3 = quoteV3ToV4(tokenIn, intermediates[i], tokenOut, amountIn);
            if (out3 > bestOutput) {
                bestOutput = out3;
                bestPath = uint8(3 + i);
            }
        }
        
        // Build commands for best path
        return buildCommands(bestPath, tokenIn, tokenOut, amountIn);
    }
}
```

### Gas Optimization Techniques

#### 1. Conditional Command Building

```solidity
// Instead of always allocating for max commands
bytes memory commands;
if (needsUnwrap) {
    commands = abi.encodePacked(
        uint8(Commands.V3_SWAP_EXACT_IN),
        uint8(Commands.UNWRAP_WETH),
        uint8(Commands.V4_SWAP)
    );
} else {
    commands = abi.encodePacked(
        uint8(Commands.V3_SWAP_EXACT_IN),
        uint8(Commands.V4_SWAP)
    );
}
// Saves gas on encoding unused commands
```

#### 2. Reuse Router Approvals

```solidity
// Instead of transferring to router every time
function swapWithRouterBalance(
    V3Params calldata v3,
    V4Params calldata v4
) external {
    // Assume tokens already in router from previous operation
    // Skip transfer, directly execute
    router.execute(commands, inputs, deadline);
}
```

#### 3. Batch Multiple Swaps

```solidity
function batchSwaps(
    V3Params[] calldata v3Swaps,
    V4Params[] calldata v4Swaps
) external {
    // Build commands for all swaps
    bytes memory commands;
    for (uint i = 0; i < v3Swaps.length; i++) {
        commands = bytes.concat(
            commands,
            abi.encodePacked(
                uint8(Commands.V3_SWAP_EXACT_IN),
                uint8(Commands.V4_SWAP)
            )
        );
    }
    
    // Single execute call
    router.execute(commands, inputs, deadline);
}
```

### Error Recovery Patterns

**Graceful Degradation**:

```solidity
function swapWithFallback(
    V3Params calldata v3,
    V4Params calldata v4
) external returns (uint256 amountOut) {
    try this.swap(v3, v4) returns (uint256 amount) {
        return amount;
    } catch {
        // Fallback to direct V4 swap
        return v4Router.exactInputSingle(
            IV4Router.ExactInputSingleParams({
                poolKey: v4.key,
                zeroForOne: true,
                amountIn: v3.amountIn,
                amountOutMinimum: v4.amountOutMin,
                hookData: ""
            })
        );
    }
}
```

## 📊 Comparison with Alternative Approaches

### Method 1: SwapV3ToV4 (This Contract)

```solidity
swapV3ToV4.swap(v3Params, v4Params);
```

**Pros**:
- ✅ Single transaction (atomic)
- ✅ No intermediate approvals
- ✅ Automatic WETH handling
- ✅ Uses Universal Router

**Cons**:
- ❌ Limited to V3→V4 path
- ❌ Requires Universal Router
- ❌ Additional abstraction layer

**Gas**: ~220k

### Method 2: Separate Transactions

```solidity
// Transaction 1: V3 Swap
v3Router.exactInputSingle(params);

// Transaction 2: Approve V4
token.approve(v4Router, amount);

// Transaction 3: V4 Swap
v4Router.exactInputSingle(params);
```

**Pros**:
- ✅ Simple logic
- ✅ Direct control
- ✅ Can pause between steps

**Cons**:
- ❌ Three transactions (expensive)
- ❌ Not atomic (risk between txs)
- ❌ Manual approvals
- ❌ Price risk between swaps

**Gas**: ~350k total

### Method 3: Custom Aggregator

```solidity
// Build custom router
customRouter.multiHopSwap(path, amounts);
```

**Pros**:
- ✅ Optimized for specific use case
- ✅ Can include custom logic
- ✅ Potentially lowest gas

**Cons**:
- ❌ Must deploy and maintain
- ❌ Security auditing costs
- ❌ Less flexible

**Gas**: ~200k (if optimized)

### Recommendation

**Use SwapV3ToV4 when**:
- Need simple V3→V4 routing
- Want atomic execution
- Universal Router already available
- Gas cost acceptable

**Use Separate Transactions when**:
- Need granular control
- Can tolerate price risk
- Debugging/testing

**Use Custom Aggregator when**:
- High volume operations
- Specific routing requirements
- Gas optimization critical

## 🎓 Learning Outcomes

After completing this exercise, you should understand:

### Conceptual Understanding
- ✅ Multi-hop swap mechanics across protocols
- ✅ Command-based routing architecture
- ✅ WETH wrapping/unwrapping in routing
- ✅ Delta accounting in V4
- ✅ Cross-protocol token flow

### Technical Skills
- ✅ Using CONTRACT_BALANCE for chaining
- ✅ Using OPEN_DELTA in V4 swaps
- ✅ SETTLE action for paying tokens
- ✅ Conditional command building
- ✅ Handling ETH vs WETH

### Practical Applications
- ✅ Building cross-protocol routers
- ✅ Optimizing liquidity routing
- ✅ Implementing migration tools
- ✅ Creating arbitrage strategies

## 📚 Additional Resources

### Official Documentation
- [Universal Router](https://github.com/Uniswap/universal-router)
- [V3 Swap Router](https://docs.uniswap.org/contracts/v3/reference/periphery/SwapRouter)
- [V4 Core](https://github.com/Uniswap/v4-core)
- [V4 Periphery](https://github.com/Uniswap/v4-periphery)

### Related Concepts
- Multi-hop routing algorithms
- Cross-protocol composability
- MEV protection in multi-hop swaps
- Gas optimization strategies

### Further Reading
- [Optimal Routing in AMMs](https://uniswap.org/blog/auto-router)
- [Cross-Protocol Integration](https://docs.uniswap.org/sdk/v3/guides/routing)
- [Delta Accounting Patterns](https://github.com/Uniswap/v4-core/blob/main/docs/whitepaper-v4-draft.pdf)

## ✅ Exercise Checklist

Before moving to the next exercise, ensure you can:

- [ ] Explain why multi-hop routing is useful
- [ ] Describe the V3→V4 routing pattern
- [ ] Implement conditional UNWRAP_WETH logic
- [ ] Use CONTRACT_BALANCE for chaining commands
- [ ] Understand SETTLE + OPEN_DELTA pattern
- [ ] Handle both ETH and ERC20 outputs
- [ ] Pass both test scenarios
- [ ] Debug cross-protocol token flow
- [ ] Explain when to use multi-hop vs direct swap
- [ ] Describe gas trade-offs

## 🎯 Next Steps

After mastering V3→V4 routing, consider exploring:

1. **V4→V3 Routing**: Reverse direction routing
2. **Multi-Protocol Aggregators**: V2 + V3 + V4
3. **Smart Order Routing**: Dynamic path selection
4. **Flash Swaps**: Cross-protocol arbitrage
5. **MEV Protection**: Sandwich attack prevention
6. **Custom Hooks**: Protocol-specific optimizations

---

**Exercise Complete!** 🎉

You now understand how to route swaps across Uniswap V3 and V4 using Universal Router's command-based architecture. This knowledge enables you to build sophisticated routing systems that optimize for price, gas, and liquidity across multiple protocol versions.

The ability to seamlessly chain operations across protocols is a key innovation of Universal Router, unlocking new possibilities for DeFi composability and capital efficiency.

