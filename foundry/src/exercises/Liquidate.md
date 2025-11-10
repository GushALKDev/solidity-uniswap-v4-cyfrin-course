# Aave V3 Liquidation with Flash Loans - Complete Technical Guide

## Introduction

This document provides comprehensive technical documentation for implementing an **Aave V3 liquidation bot** using flash loans and Uniswap V4 for collateral swaps. This advanced exercise combines multiple DeFi protocols to demonstrate real-world liquidation mechanics, flash loan patterns, and cross-protocol integration.

### What You'll Learn

- Flash loan mechanics and patterns
- Aave V3 liquidation system
- Under-collateralization detection
- Atomic liquidation execution
- Cross-protocol integration (Aave + Uniswap)
- WETH wrapping/unwrapping in complex flows
- Profit calculation and extraction
- Risk management in liquidations
- Gas optimization for profitable liquidations

### Key Concepts

**Flash Loan**: Borrow any amount without collateral, as long as you repay within the same transaction. Perfect for liquidations since you don't need upfront capital.

**Liquidation**: The process of repaying someone's debt in exchange for their collateral at a discount when they become under-collateralized.

**Under-Collateralization**: When the value of borrowed assets exceeds a certain percentage (liquidation threshold) of the collateral value.

**Health Factor**: Aave's metric for position safety. Below 1.0 = liquidatable. Formula: (Collateral × Liquidation Threshold) / Debt.

**Liquidation Bonus**: Extra collateral (discount) given to liquidators as incentive. Typically 5-10%.

**Flash Loan Fee**: Small fee (0.09% on Aave V3) charged for borrowing via flash loan.

**Atomic Execution**: All operations (loan → liquidate → swap → repay) must succeed in one transaction or all revert.

## Contract Overview

The `Liquidate.sol` contract performs a complete liquidation cycle:

1. **Get Flash Loan**: Borrow debt token from Aave V3
2. **Liquidate Position**: Repay user's debt, receive collateral
3. **Swap Collateral**: Convert collateral to debt token via Uniswap V4
4. **Repay Flash Loan**: Return borrowed amount + fee
5. **Extract Profit**: Send remaining tokens to caller

### Core Features

| Feature | Description |
|---------|-------------|
| **Flash Loan Integration** | Zero-capital liquidations |
| **Aave V3 Liquidation** | Repay debt, claim collateral |
| **Universal Router Swap** | Efficient collateral conversion |
| **Atomic Execution** | All-or-nothing transaction |
| **Profit Extraction** | Automatic profit calculation |
| **WETH Handling** | Seamless ETH ↔ WETH conversion |

### Technical Specifications

- **Solidity Version**: 0.8.28
- **Key Dependencies**: IFlash, ILiquidator, IUniversalRouter, IWETH
- **External Protocols**: Aave V3, Uniswap V4
- **Pattern**: Flash Loan Callback
- **Gas Cost**: ~300-400k (varies with collateral type)

## 🏗️ Architecture Overview

### Liquidation Flow Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                    LIQUIDATION CYCLE                               │
│                                                                    │
│  LIQUIDATOR                                                        │
│  (msg.sender)                                                      │
│      │                                                             │
│      │ 1. liquidate(tokenToRepay, user, poolKey)                   │
│      ↓                                                             │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                  Liquidate Contract                          │  │
│  │                                                              │  │
│  │  [Step 1: Get Debt Amount]                                   │  │
│  │  debt = liquidator.getDebt(tokenToRepay, user)               │  │
│  │  Example: 1000 USDC                                          │  │
│  │                                                              │  │
│  │  [Step 2: Request Flash Loan]                                │  │
│  │  flash.flash(tokenToRepay, debt, data)                       │  │
│  │  ────────────────────────────────────────────────────────>   │  │
│  │                                                              │  │
│  │                          Aave V3 Flash Loan                  │  │
│  │  <────────────────────────────────────────────────────────   │  │
│  │  Receives: 1000 USDC                                         │  │
│  │  Must Repay: 1000.9 USDC (1000 + 0.09% fee)                  │  │
│  │                                                              │  │
│  │  [Step 3: Flash Callback Triggered]                          │  │
│  │  flashCallback(tokenToRepay, amount, fee, data)              │  │
│  │  │                                                           │  │
│  │  │  [3a. Liquidate on Aave]                                  │  │
│  │  │  • Approve liquidator to spend 1000 USDC                  │  │
│  │  │  • liquidator.liquidate(collateral, debt, user)           │  │
│  │  │  • Repays user's 1000 USDC debt                           │  │
│  │  │  • Receives collateral (e.g., 0.5 ETH worth $550)         │  │
│  │  │                                                           │  │
│  │  │  [3b. Unwrap WETH if needed]                              │  │
│  │  │  If collateral is WETH:                                   │  │
│  │  │    WETH.withdraw(balance) → 0.5 ETH                       │  │
│  │  │                                                           │  │
│  │  │  [3c. Swap Collateral via Universal Router]               │  │
│  │  │  swap(key, 0.5 ETH, minOut, zeroForOne)                   │  │
│  │  │  ──────────────────────────────────────>                  │  │
│  │  │                 Universal Router                          │  │
│  │  │                       │                                   │  │
│  │  │                       │ V4_SWAP                           │  │
│  │  │                       ↓                                   │  │
│  │  │                 Uniswap V4 Pool                           │  │
│  │  │  <──────────────────────────────────                      │  │
│  │  │  Receives: 1050 USDC (swap output)                        │  │
│  │  │                                                           │  │
│  │  │  [3d. Wrap ETH if needed]                                 │  │
│  │  │  If output is ETH (address(0)):                           │  │
│  │  │    WETH.deposit{value: balance}() → WETH                  │  │
│  │  │                                                           │  │
│  │  │  [3e. Repay Flash Loan]                                   │  │
│  │  │  Transfer 1000.9 USDC to Aave                             │  │
│  │  │  Remaining: 49.1 USDC (profit)                            │  │
│  │  │                                                           │  │
│  │  └─ Return from flashCallback                                │  │
│  │                                                              │  │
│  │  [Step 4: Send Profit to Caller]                             │  │
│  │  Transfer 49.1 USDC to msg.sender                            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│      │                                                             │
│      │ Receive profit: 49.1 USDC                                   │
│      ↓                                                             │
│  LIQUIDATOR                                                        │
│  (msg.sender)                                                      │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### Token Flow Visualization

```
Initial State:
  User Position (Under-collateralized):
    Collateral: 0.5 ETH (worth $250 at current price)
    Debt: 1000 USDC
    Health Factor: 0.8 (< 1.0, liquidatable!)
    Liquidation Bonus: 10%

Step 1: Flash Loan
  ┌─────────────────────┐
  │   Aave V3 Flash     │
  ├─────────────────────┤
  │ Lend: 1000 USDC     │
  │ Fee: 0.9 USDC       │
  │ Must Repay: 1000.9  │
  └─────────────────────┘
       │
       ↓ (sends 1000 USDC)
  ┌─────────────────────┐
  │ Liquidate Contract  │
  ├─────────────────────┤
  │ Balance:            │
  │   1000 USDC ✅      │
  └─────────────────────┘

Step 2: Liquidate User
  ┌─────────────────────┐
  │ Liquidate Contract  │
  ├─────────────────────┤
  │ Approves 1000 USDC  │
  │ to Aave Liquidator  │
  └─────────────────────┘
       │
       ↓ liquidate(...)
  ┌─────────────────────┐
  │  Aave Liquidator    │
  ├─────────────────────┤
  │ Takes: 1000 USDC    │
  │ Repays user's debt  │
  │ Gives: 0.5 ETH      │
  │ + 10% bonus         │
  │ Total: 0.55 ETH     │
  └─────────────────────┘
       │
       ↓ (sends 0.55 ETH)
  ┌─────────────────────┐
  │ Liquidate Contract  │
  ├─────────────────────┤
  │ Balance:            │
  │   0 USDC            │
  │   0.55 ETH ✅       │
  └─────────────────────┘

Step 3: Swap Collateral
  ┌─────────────────────┐
  │ Liquidate Contract  │
  ├─────────────────────┤
  │ Approves ETH        │
  │ to Universal Router │
  └─────────────────────┘
       │
       ↓ swap(0.55 ETH, ...)
  ┌─────────────────────┐
  │ Uniswap V4 Pool     │
  ├─────────────────────┤
  │ Takes: 0.55 ETH     │
  │ Gives: 1050 USDC    │
  │ (Price: $500/ETH)   │
  │ * Note: Better than │
  │   oracle ($250/ETH) │
  └─────────────────────┘
       │
       ↓ (sends 1050 USDC)
  ┌─────────────────────┐
  │ Liquidate Contract  │
  ├─────────────────────┤
  │ Balance:            │
  │   1050 USDC ✅      │
  └─────────────────────┘

Step 4: Repay Flash Loan
  ┌─────────────────────┐
  │ Liquidate Contract  │
  ├─────────────────────┤
  │ Transfers 1000.9    │
  │ USDC to Flash       │
  └─────────────────────┘
       │
       ↓ (sends 1000.9 USDC)
  ┌─────────────────────┐
  │   Aave V3 Flash     │
  ├─────────────────────┤
  │ Received: 1000.9 ✅ │
  │ Flash loan repaid   │
  └─────────────────────┘

Final State:
  ┌─────────────────────┐
  │ Liquidate Contract  │
  ├─────────────────────┤
  │ Balance:            │
  │   49.1 USDC         │
  │ (profit) 🎉         │
  └─────────────────────┘
       │
       ↓ (sends to caller)
  ┌─────────────────────┐
  │    Liquidator       │
  │   (msg.sender)      │
  ├─────────────────────┤
  │ Profit: 49.1 USDC ✅│
  └─────────────────────┘

Profit Calculation:
  Collateral Value: 0.55 ETH × $500 = $1050
  Flash Loan Repayment: $1000.9
  Profit: $1050 - $1000.9 = $49.1
  Profit %: 4.9% of borrowed amount
```

### Why Flash Loans?

**Without Flash Loan**:
```
1. Need 1000 USDC upfront capital
2. Liquidate position
3. Swap collateral
4. Profit: 49.1 USDC (4.9% of capital)
Problem: Need large capital for meaningful profit
```

**With Flash Loan**:
```
1. Borrow 1000 USDC (0 capital)
2. Liquidate position
3. Swap collateral
4. Repay 1000.9 USDC
5. Keep profit: 49.1 USDC
Benefit: Zero capital required! Only pay gas
```

## 🔄 Complete Execution Flow

```
CALLER          LIQUIDATE        FLASH LOAN      AAVE            UNIVERSAL       UNISWAP V4
                CONTRACT                         LIQUIDATOR       ROUTER          POOL
  │                 │                │              │                │               │
  │ liquidate(      │                │              │                │               │
  │  token,user,key)│                │              │                │               │
  │────────────────>│                │              │                │               │
  │                 │                │              │                │               │
  │                 │ [1. Get debt]  │              │                │               │
  │                 │ getDebt(token, │              │                │               │
  │                 │   user)        │              │                │               │
  │                 │──────────────────────────────>│                │               │
  │                 │ returns: 1000  │              │                │               │
  │                 │<──────────────────────────────│                │               │
  │                 │                │              │                │               │
  │                 │ [2. Flash loan]│              │                │               │
  │                 │ flash(token,   │              │                │               │
  │                 │   1000, data)  │              │                │               │
  │                 │───────────────>│              │                │               │
  │                 │                │              │                │               │
  │                 │ Transfer 1000  │              │                │               │
  │                 │ USDC           │              │                │               │
  │                 │<───────────────│              │                │               │
  │                 │                │              │                │               │
  │                 │ flashCallback( │              │                │               │
  │                 │  token,1000,   │              │                │               │
  │                 │  0.9,data)     │              │                │               │
  │                 │<───────────────│              │                │               │
  │                 │                │              │                │               │
  │                 │ [3a. Liquidate]│              │                │               │
  │                 │ approve(1000)  │              │                │               │
  │                 │ liquidate(     │              │                │               │
  │                 │  collateral,   │              │                │               │
  │                 │  token, user)  │              │                │               │
  │                 │──────────────────────────────>│                │               │
  │                 │                │              │                │               │
  │                 │  Repays debt,  │              │                │               │
  │                 │  sends 0.55 ETH│              │                │               │
  │                 │<──────────────────────────────│                │               │
  │                 │                │              │                │               │
  │                 │ [3b. Unwrap]   │              │                │               │
  │                 │ WETH.withdraw( │              │                │               │
  │                 │  0.55 ether)   │              │                │               │
  │                 │ Now has 0.55ETH│              │                │               │
  │                 │                │              │                │               │
  │                 │ [3c. Swap]     │              │                │               │
  │                 │ approve Permit2│              │                │               │
  │                 │ router.execute(│              │                │               │
  │                 │  V4_SWAP, ...)│               │                │               │
  │                 │───────────────────────────────────────────────>│               │
  │                 │                │              │                │               │
  │                 │                │              │                │ unlock(...)   │
  │                 │                │              │                │──────────────>│
  │                 │                │              │                │               │
  │                 │                │              │                │  swap         │
  │                 │                │              │                │  0.55ETH for  │
  │                 │                │              │                │  1050 USDC    │
  │                 │                │              │                │<──────────────│
  │                 │                │              │                │               │
  │                 │  1050 USDC     │              │                │               │
  │                 │<───────────────────────────────────────────────│               │
  │                 │                │              │                │               │
  │                 │ [3d. Wrap ETH] │              │                │               │
  │                 │ (if needed)    │              │                │               │
  │                 │                │              │                │               │
  │                 │ [3e. Repay]    │              │                │               │
  │                 │ transfer(      │              │                │               │
  │                 │  1000.9 USDC)  │              │                │               │
  │                 │───────────────>│              │                │               │
  │                 │                │              │                │               │
  │                 │ Return from    │              │                │               │
  │                 │ callback       │              │                │               │
  │                 │───────────────>│              │                │               │
  │                 │                │              │                │               │
  │                 │ Flash loan     │              │                │               │
  │                 │ complete       │              │                │               │
  │                 │                │              │                │               │
  │                 │ [4. Profit]    │              │                │               │
  │                 │ transfer(49.1  │              │                │               │
  │                 │  USDC to user) │              │                │               │
  │                 │                │              │                │               │
  │  Profit: 49.1   │                │              │                │               │
  │<────────────────│                │              │                │               │
  │                 │                │              │                │               │
```

## 📝 Function Implementation Guide

### Function 1: `liquidate()`

**Purpose**: Initiate liquidation by obtaining a flash loan

**Signature**:
```solidity
function liquidate(
    address tokenToRepay,    // Token borrowed by user (debt token)
    address user,            // User to liquidate
    PoolKey calldata key     // V4 pool for swapping collateral
) external
```

**Parameters**:
- `tokenToRepay`: The token the user borrowed (e.g., USDC)
- `user`: Address of the under-collateralized position
- `key`: Uniswap V4 pool to use for collateral → debt token swap

### Implementation Steps

**Step 1: Map V4 Currencies**

```solidity
(address v4Token0, address v4Token1) = (key.currency0, key.currency1);
if (v4Token0 == address(0)) {
    v4Token0 = WETH;
}
```

**Why?**: V4 uses address(0) for ETH, but we need actual token addresses for validation.

**Step 2: Validate Pool**

```solidity
require(
    tokenToRepay == v4Token0 || tokenToRepay == v4Token1,
    "invalid pool key"
);
```

**Critical Check**: The debt token must be in the V4 pool so we can swap collateral back to it.

**Example**:
```solidity
// ✅ Valid
tokenToRepay = USDC
key = PoolKey(address(0), USDC, ...)  // ETH/USDC pool

// ❌ Invalid
tokenToRepay = DAI
key = PoolKey(address(0), USDC, ...)  // ETH/USDC pool (no DAI!)
```

**Step 3: Get Debt Amount**

```solidity
uint256 debt = liquidator.getDebt(tokenToRepay, user);
```

**What it does**: Queries Aave to determine how much debt can be liquidated.

**Implementation in Liquidator**:
```solidity
function getDebt(address token, address user) external view returns (uint256) {
    // Get user's debt from Aave
    (, uint256 totalDebtBase,,,, uint256 healthFactor) = 
        pool.getUserAccountData(user);
    
    // Must be liquidatable (health factor < 1)
    require(healthFactor < 1e18, "Cannot liquidate");
    
    // Get token price
    uint256 price = oracle.getAssetPrice(token);
    
    // Calculate max liquidatable amount (typically 50% of debt)
    uint256 maxLiquidatable = totalDebtBase / 2;
    
    // Convert to token amount
    return (maxLiquidatable * 10**decimals) / price;
}
```

**Step 4: Request Flash Loan**

```solidity
flash.flash(tokenToRepay, debt, abi.encode(user, key));
```

**Parameters**:
- `token`: What to borrow (debt token)
- `amount`: How much to borrow (debt amount)
- `data`: Encoded data passed to callback (user address + pool key)

**What happens**: Aave transfers `debt` amount of `tokenToRepay` to this contract, then calls `flashCallback`.

**Step 5: Send Profit to Caller**

```solidity
uint256 bal = IERC20(tokenToRepay).balanceOf(address(this));
if (bal > 0) {
    IERC20(tokenToRepay).transfer(msg.sender, bal);
}
```

**Why here?**: After `flashCallback` completes, any remaining balance is profit.

### Function 2: `flashCallback()`

**Purpose**: Execute liquidation and repay flash loan

**Signature**:
```solidity
function flashCallback(
    address tokenToRepay,    // Token borrowed via flash loan
    uint256 amount,          // Amount borrowed
    uint256 fee,             // Flash loan fee (0.09% on Aave)
    bytes calldata data      // Encoded (user, poolKey)
) external
```

**Called by**: Flash loan contract (Aave)

**Must complete**: Liquidation → Swap → Repayment

### Implementation Steps

**Step 1: Decode Callback Data**

```solidity
(address user, PoolKey memory key) = abi.decode(data, (address, PoolKey));
```

**Retrieve**: User to liquidate and pool for swapping.

**Step 2: Map Currencies Again**

```solidity
(address v4Token0, address v4Token1) = (key.currency0, key.currency1);
if (v4Token0 == address(0)) {
    v4Token0 = WETH;
}
```

**Step 3: Determine Collateral Token**

```solidity
address collateral = tokenToRepay == v4Token0 ? v4Token1 : v4Token0;
```

**Logic**:
- If debt is token0 → collateral is token1
- If debt is token1 → collateral is token0

**Example**:
```
Pool: ETH/USDC
tokenToRepay: USDC
→ collateral: ETH (we'll receive ETH, need to swap to USDC)
```

**Step 4: Approve and Liquidate**

```solidity
IERC20(tokenToRepay).approve(address(liquidator), amount);
liquidator.liquidate(collateral, tokenToRepay, user);
```

**What happens**:
1. Liquidator takes `amount` of `tokenToRepay` from us
2. Liquidator repays user's debt on Aave
3. Liquidator receives user's collateral from Aave
4. Liquidator sends collateral to us (with bonus!)

**Liquidation Bonus**:
```
User's collateral: 0.5 ETH
Debt repaid: 1000 USDC (worth 0.5 ETH at oracle price)
Liquidation bonus: 10%
Collateral received: 0.5 ETH + 10% = 0.55 ETH
```

**Step 5: Unwrap WETH if Needed**

```solidity
uint256 colBal = IERC20(collateral).balanceOf(address(this));

if (collateral == WETH) {
    weth.withdraw(colBal);
}
```

**Why?**: If collateral is WETH but V4 pool uses address(0) for ETH, must unwrap.

**Step 6: Swap Collateral**

```solidity
bool zeroForOne = collateral == v4Token0;

swap({
    key: key,
    amountIn: uint128(colBal),
    amountOutMin: 1,  // In production: calculate based on amount + fee
    zeroForOne: zeroForOne
});
```

**Direction**:
- If collateral is currency0 → swap token0 for token1
- If collateral is currency1 → swap token1 for token0

**Step 7: Wrap ETH if Needed**

```solidity
address currencyOut = zeroForOne ? key.currency1 : key.currency0;

if (currencyOut == address(0)) {
    weth.deposit{value: address(this).balance}();
}
```

**Why?**: If swap output is ETH (address(0)) but we need WETH to repay, must wrap.

**Step 8: Repay Flash Loan**

```solidity
uint256 bal = IERC20(tokenToRepay).balanceOf(address(this));
require(bal >= amount + fee, "insufficient amount to repay flash loan");
IERC20(tokenToRepay).transfer(address(flash), amount + fee);
```

**Critical**: Must repay `amount + fee` or transaction reverts.

**Profit Check**: If we have less than `amount + fee`, liquidation wasn't profitable.

### Function 3: `swap()` (Private)

**Purpose**: Swap collateral to debt token via Universal Router

**Signature**:
```solidity
function swap(
    PoolKey memory key,
    uint128 amountIn,
    uint128 amountOutMin,
    bool zeroForOne
) private
```

### Implementation

```solidity
function swap(
    PoolKey memory key,
    uint128 amountIn,
    uint128 amountOutMin,
    bool zeroForOne
) private {
    // 1. Determine swap direction
    (address currencyIn, address currencyOut) = zeroForOne
        ? (key.currency0, key.currency1)
        : (key.currency1, key.currency0);

    // 2. Approve if ERC20
    if (currencyIn != address(0)) {
        approve(currencyIn, uint160(amountIn), uint48(block.timestamp));
    }

    // 3. Build V4_SWAP command
    bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
    bytes[] memory inputs = new bytes[](1);

    // 4. Build actions
    bytes memory actions = abi.encodePacked(
        uint8(Actions.SWAP_EXACT_IN_SINGLE),
        uint8(Actions.SETTLE_ALL),
        uint8(Actions.TAKE_ALL)
    );

    bytes[] memory params = new bytes[](3);

    // 5. SWAP_EXACT_IN_SINGLE parameters
    params[0] = abi.encode(
        IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            hookData: bytes("")
        })
    );

    // 6. SETTLE_ALL parameters
    params[1] = abi.encode(currencyIn, uint256(amountIn));

    // 7. TAKE_ALL parameters
    params[2] = abi.encode(currencyOut, uint256(amountOutMin));

    // 8. Encode inputs
    inputs[0] = abi.encode(actions, params);

    // 9. Execute swap
    uint256 msgVal = currencyIn == address(0) ? address(this).balance : 0;
    router.execute{value: msgVal}(commands, inputs, block.timestamp);
}
```

**Pattern**: Same as UniversalRouter exercise (SWAP + SETTLE_ALL + TAKE_ALL).

### Complete Implementation

```solidity
contract Liquidate is IFlashReceiver {
    IUniversalRouter constant router = IUniversalRouter(UNIVERSAL_ROUTER);
    IPermit2 constant permit2 = IPermit2(PERMIT2);
    IWETH constant weth = IWETH(WETH);
    IFlash public immutable flash;
    ILiquidator public immutable liquidator;

    constructor(address _flash, address _liquidator) {
        flash = IFlash(_flash);
        liquidator = ILiquidator(_liquidator);
    }

    receive() external payable {}

    function liquidate(
        address tokenToRepay,
        address user,
        PoolKey calldata key
    ) external {
        // Map and validate
        (address v4Token0, address v4Token1) = (key.currency0, key.currency1);
        if (v4Token0 == address(0)) {
            v4Token0 = WETH;
        }
        require(
            tokenToRepay == v4Token0 || tokenToRepay == v4Token1,
            "invalid pool key"
        );

        // Get debt and flash loan
        uint256 debt = liquidator.getDebt(tokenToRepay, user);
        flash.flash(tokenToRepay, debt, abi.encode(user, key));

        // Send profit
        uint256 bal = IERC20(tokenToRepay).balanceOf(address(this));
        if (bal > 0) {
            IERC20(tokenToRepay).transfer(msg.sender, bal);
        }
    }

    function flashCallback(
        address tokenToRepay,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external {
        // Decode
        (address user, PoolKey memory key) = abi.decode(data, (address, PoolKey));

        // Map currencies
        (address v4Token0, address v4Token1) = (key.currency0, key.currency1);
        if (v4Token0 == address(0)) {
            v4Token0 = WETH;
        }

        // Determine collateral
        address collateral = tokenToRepay == v4Token0 ? v4Token1 : v4Token0;

        // Liquidate
        IERC20(tokenToRepay).approve(address(liquidator), amount);
        liquidator.liquidate(collateral, tokenToRepay, user);

        // Unwrap if WETH
        uint256 colBal = IERC20(collateral).balanceOf(address(this));
        if (collateral == WETH) {
            weth.withdraw(colBal);
        }

        // Swap
        bool zeroForOne = collateral == v4Token0;
        swap(key, uint128(colBal), 1, zeroForOne);

        // Wrap if ETH
        address currencyOut = zeroForOne ? key.currency1 : key.currency0;
        if (currencyOut == address(0)) {
            weth.deposit{value: address(this).balance}();
        }

        // Repay
        uint256 bal = IERC20(tokenToRepay).balanceOf(address(this));
        require(bal >= amount + fee, "insufficient amount to repay flash loan");
        IERC20(tokenToRepay).transfer(address(flash), amount + fee);
    }

    function swap(...) private {
        // Implementation shown above
    }

    function approve(address token, uint160 amount, uint48 expiration) private {
        IERC20(token).approve(address(permit2), uint256(amount));
        permit2.approve(token, address(router), amount, expiration);
    }
}
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "Cannot liquidate" | Health factor >= 1 | Wait for price movement or find different user |
| "invalid pool key" | Debt token not in pool | Use correct pool with debt token |
| "insufficient amount to repay" | Swap output too low | Check slippage, pool liquidity |
| "Flash loan not repaid" | Any error in callback | Debug liquidation/swap steps |
| "Insufficient funds" | Not enough collateral value | User not profitable to liquidate |

## 🧪 Testing Guide

### Test Scenario Overview

The test creates an under-collateralized Aave position and verifies liquidation:

```solidity
contract LiquidateTest is Test {
    // 1. Setup creates under-collateralized position
    function setUp() public {
        // Supply 1 ETH collateral
        // Borrow 1000 USDC at 2000 USD/ETH
        // Mock price drop to 500 USD/ETH
        // Health factor drops below 1.0
    }

    // 2. Test liquidation
    function test_liquidate() public {
        // Execute liquidation
        // Verify collateral decreased
        // Verify debt decreased
        // Verify liquidator profit
    }
}
```

### Understanding the Test Setup

**Initial Position**:
```solidity
// Mock ETH price at $2000
oracle.mock_getAssetPrice(WETH, 2000e8);

// User supplies 1 ETH collateral
vm.startPrank(user);
weth.deposit{value: 1 ether}();
weth.approve(address(pool), 1 ether);
pool.supply(WETH, 1 ether, user, 0);

// User borrows 1000 USDC
pool.borrow(USDC, 1000e6, 2, 0, user);
vm.stopPrank();

// Position at this point:
// Collateral: 1 ETH = $2000
// Debt: 1000 USDC = $1000
// Health Factor: ($2000 × 0.8) / $1000 = 1.6 ✅ (healthy)
```

**Creating Liquidation Opportunity**:
```solidity
// Mock ETH price crash to $500 (75% drop!)
oracle.mock_getAssetPrice(WETH, 500e8);

// Position now:
// Collateral: 1 ETH = $500
// Debt: 1000 USDC = $1000
// Health Factor: ($500 × 0.8) / $1000 = 0.4 ❌ (liquidatable!)
```

**Why 0.8?**: This is the liquidation threshold. If collateral value × 0.8 < debt, position is liquidatable.

### Running the Test

```bash
# Run liquidation test
forge test --match-test test_liquidate -vvv

# With detailed traces
forge test --match-test test_liquidate -vvvv

# Fork mainnet if needed
forge test --match-test test_liquidate --fork-url $MAINNET_RPC -vvv
```

### Test Execution Breakdown

```solidity
function test_liquidate() public {
    // 1. Record initial state
    uint256 colBefore = pool.getCollateralBalance(WETH, user);
    uint256 debtBefore = pool.getDebtBalance(USDC, user);
    uint256 liquidatorBalBefore = IERC20(USDC).balanceOf(address(this));

    console.log("Before Liquidation:");
    console.log("  Collateral:", colBefore);      // 1 ETH
    console.log("  Debt:", debtBefore);           // 1000 USDC
    console.log("  Liquidator:", liquidatorBalBefore); // 0

    // 2. Execute liquidation
    PoolKey memory key = PoolKey({
        currency0: Currency.wrap(address(0)),  // ETH
        currency1: Currency.wrap(USDC),        // USDC
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(address(0))
    });

    liquidate.liquidate(USDC, user, key);

    // 3. Verify results
    uint256 colAfter = pool.getCollateralBalance(WETH, user);
    uint256 debtAfter = pool.getDebtBalance(USDC, user);
    uint256 liquidatorBalAfter = IERC20(USDC).balanceOf(address(this));

    console.log("After Liquidation:");
    console.log("  Collateral:", colAfter);      // ~0.45 ETH
    console.log("  Debt:", debtAfter);           // ~500 USDC
    console.log("  Liquidator:", liquidatorBalAfter); // ~49 USDC

    // Assertions
    assertTrue(colAfter < colBefore, "Collateral should decrease");
    assertTrue(debtAfter < debtBefore, "Debt should decrease");
    assertTrue(liquidatorBalAfter > liquidatorBalBefore, "Should profit");
}
```

### Expected Results

```
Logs:
  Before Liquidation:
    Collateral: 1000000000000000000 (1 ETH)
    Debt: 1000000000 (1000 USDC)
    Liquidator: 0

  Flash Loan:
    Borrowed: 1000000000 USDC
    Fee: 900000 (0.9 USDC)

  Liquidation:
    Debt Repaid: 1000000000 USDC
    Collateral Seized: 550000000000000000 (0.55 ETH)
    Liquidation Bonus: 10%

  Swap:
    Input: 550000000000000000 (0.55 ETH)
    Output: 1049100000 (1049.1 USDC)

  Flash Loan Repayment:
    Amount: 1000900000 (1000.9 USDC)
    Remaining: 48200000 (48.2 USDC)

  After Liquidation:
    Collateral: 450000000000000000 (0.45 ETH)
    Debt: 500000000 (500 USDC)
    Liquidator: 48200000 (48.2 USDC profit)

Test result: ok. 1 passed
```

### Test Variations

**Test 1: Different Collateral Types**
```solidity
function test_liquidate_wbtc() public {
    // Setup WBTC as collateral
    // Borrow USDC
    // Price crash
    // Liquidate via WBTC/USDC pool
}
```

**Test 2: Partial Liquidation**
```solidity
function test_partial_liquidation() public {
    // Health factor = 0.95 (close to 1.0)
    // Liquidate only portion needed to restore health
    // Verify health factor > 1.0 after
}
```

**Test 3: Multiple Collateral**
```solidity
function test_liquidate_multi_collateral() public {
    // User has ETH + WBTC collateral
    // Choose most profitable collateral to seize
    // Liquidate and verify optimal path
}
```

**Test 4: Unprofitable Liquidation**
```solidity
function test_unprofitable_liquidation() public {
    // Low liquidity pool (high slippage)
    // Liquidation bonus < flash loan fee + gas
    // Expect revert: "insufficient amount to repay"
}
```

**Test 5: High Slippage**
```solidity
function test_high_slippage() public {
    // Large liquidation in small pool
    // Set realistic amountOutMin
    // May need to split into smaller liquidations
}
```

## 🔍 Deep Dive: Flash Loan Mechanics

### What Are Flash Loans?

Flash loans allow you to borrow **any amount** of tokens **without collateral**, as long as you repay within the **same transaction**.

```
Traditional Loan:
  Day 1: Deposit $1000 collateral → Borrow $500
  Day 30: Repay $500 + interest → Get collateral back
  Capital Required: $1000
  Time: 30 days

Flash Loan:
  Block N: Borrow $1,000,000 → Use → Repay + fee
  Capital Required: $0 (only gas)
  Time: 1 transaction (~12 seconds)
```

### Flash Loan Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Flash Loan Lifecycle                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Step 1: Request                                            │
│  ─────────────────                                          │
│  User calls: flash.flash(token, amount, data)               │
│                                                             │
│  Step 2: Lend                                               │
│  ──────────────                                             │
│  Flash contract transfers tokens to user                    │
│  Before:  Flash = 1M USDC, User = 0                         │
│  After:   Flash = 0,       User = 1M USDC                   │
│                                                             │
│  Step 3: Callback                                           │
│  ───────────────────                                        │
│  Flash contract calls: user.flashCallback(...)              │
│  User has 1M USDC to use however they want                  │
│                                                             │
│  Step 4: User Logic                                         │
│  ─────────────────────                                      │
│  • Execute trades                                           │
│  • Liquidations                                             │
│  • Arbitrage                                                │
│  • Refinancing                                              │
│  • Collateral swaps                                         │
│                                                             │
│  Step 5: Repay                                              │
│  ────────────────                                           │
│  User must transfer: amount + fee                           │
│  Fee = amount × 0.09% = 900 USDC                            │
│  Total repay = 1,000,900 USDC                               │
│                                                             │
│  Step 6: Verify                                             │
│  ─────────────────                                          │
│  Flash contract checks balance                              │
│  require(balance >= initialBalance + fee)                   │
│  If fails → entire transaction reverts                      │
│                                                             │
│  Step 7: Success                                            │
│  ──────────────────                                         │
│  Transaction completes                                      │
│  User keeps profit (if any)                                 │
│  Flash contract keeps fee                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Flash Loan Providers

| Provider | Fee | Max Amount | Notes |
|----------|-----|------------|-------|
| **Aave V3** | 0.09% | Pool reserves | Most popular, reliable |
| **Uniswap V4** | 0% | Pool reserves | **Can't use for liquidations!** (PoolManager locked) |
| **Balancer** | 0% | Vault balance | Good for arb |
| **dYdX** | 0% | Limited | Solo margin |

### Why Aave V3 Instead of Uniswap V4?

The exercise uses **Aave V3 flash loans** instead of **Uniswap V4 flash loans** for a critical reason:

```
❌ Uniswap V4 Flash Loan Problem:

PoolManager.unlock(callback) {
    // PoolManager is LOCKED during callback
    locker = msg.sender;
    isLocked = true;
    
    callback();  // Your code runs here
    
    // Problem: Universal Router needs to call PoolManager.unlock()
    // But PoolManager is already locked!
    // Result: Revert
}

✅ Aave V3 Flash Loan Solution:

AaveFlash.flash(callback) {
    // No PoolManager locking
    // Transfer tokens
    callback();  // Your code runs here
    // Universal Router can freely use V4 pools
    // Check repayment
}
```

**Code Comparison**:

```solidity
// ❌ Would fail with Uniswap V4 flash
IPoolManager(manager).unlock(
    abi.encodeCall(this.flashCallback, (...))
);
// Inside flashCallback:
//   router.execute() → needs to unlock PoolManager → REVERT!

// ✅ Works with Aave V3 flash
IFlash(aaveFlash).flash(token, amount, data);
// Inside flashCallback:
//   router.execute() → unlocks PoolManager → SUCCESS!
```

### Flash Loan Fee Calculation

```solidity
// Aave V3 flash loan fee
uint256 FEE_PERCENTAGE = 9;  // 0.09%
uint256 FEE_BASE = 10000;

function calculateFee(uint256 amount) pure returns (uint256) {
    return (amount * FEE_PERCENTAGE) / FEE_BASE;
}

// Examples
calculateFee(1000e6)  // 1000 USDC → 0.9 USDC fee
calculateFee(10000e6) // 10000 USDC → 9 USDC fee
calculateFee(1e18)    // 1 ETH → 0.0009 ETH fee
```

### Flash Loan Use Cases

**1. Liquidations** (this exercise)
```
Borrow debt token → Liquidate → Swap collateral → Repay → Profit
```

**2. Arbitrage**
```
Borrow token → Swap on DEX A → Swap on DEX B → Repay → Profit
```

**3. Collateral Swap**
```
Borrow token → Repay debt → Withdraw collateral → Swap → Deposit new collateral → Borrow → Repay flash loan
```

**4. Refinancing**
```
Borrow from Protocol A → Repay Protocol B debt → Withdraw collateral → Deposit to Protocol A → Repay flash loan
(Lower interest rate)
```

**5. Self-Liquidation**
```
Borrow → Liquidate yourself → Get collateral + bonus → Repay → Save 5% liquidation penalty
```

## 🏦 Deep Dive: Aave V3 Liquidation

### Liquidation Mechanics

Aave uses a **health factor** to determine if a position can be liquidated:

```
Health Factor = (Collateral Value × Liquidation Threshold) / Debt Value

If Health Factor < 1.0 → Liquidatable
If Health Factor >= 1.0 → Safe
```

### Health Factor Examples

**Example 1: Healthy Position**
```
Collateral: 1 ETH @ $2000 = $2000
Liquidation Threshold: 80%
Debt: 1000 USDC = $1000

Health Factor = ($2000 × 0.80) / $1000 = 1.6
Status: Healthy ✅
```

**Example 2: At Risk**
```
Collateral: 1 ETH @ $1300 = $1300
Liquidation Threshold: 80%
Debt: 1000 USDC = $1000

Health Factor = ($1300 × 0.80) / $1000 = 1.04
Status: Risky ⚠️ (close to liquidation)
```

**Example 3: Liquidatable**
```
Collateral: 1 ETH @ $1200 = $1200
Liquidation Threshold: 80%
Debt: 1000 USDC = $1000

Health Factor = ($1200 × 0.80) / $1000 = 0.96
Status: Liquidatable ❌
```

### Liquidation Parameters

```solidity
struct ReserveConfiguration {
    uint256 ltv;                    // 75% - Loan-to-Value (max borrow)
    uint256 liquidationThreshold;   // 80% - Liquidation trigger
    uint256 liquidationBonus;       // 10% - Extra collateral for liquidator
    uint256 decimals;               // Token decimals
    bool borrowingEnabled;          // Can borrow this asset
    bool usageAsCollateralEnabled;  // Can use as collateral
}
```

**Common Configurations**:

| Asset | LTV | Liquidation Threshold | Liquidation Bonus |
|-------|-----|----------------------|-------------------|
| **ETH** | 80% | 82.5% | 5% |
| **WBTC** | 70% | 75% | 10% |
| **USDC** | 80% | 85% | 5% |
| **DAI** | 75% | 80% | 5% |
| **LINK** | 50% | 65% | 10% |

### Liquidation Process

```
┌──────────────────────────────────────────────────────────────┐
│              Aave V3 Liquidation Process                     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Step 1: Check Health Factor                                 │
│  ────────────────────────────                                │
│  function liquidate(collateral, debt, user, amount) {        │
│      (,,,, healthFactor) = pool.getUserAccountData(user);    │
│      require(healthFactor < 1e18, "Cannot liquidate");       │
│  }                                                           │
│                                                              │
│  Step 2: Calculate Max Liquidatable                          │
│  ───────────────────────────────────                         │
│  • Can liquidate up to 50% of debt per transaction           │
│  • If health factor very low, can liquidate 100%             │
│                                                              │
│  maxLiquidatable = healthFactor < 0.95e18                    │
│      ? totalDebt                                             │
│      : totalDebt / 2                                         │
│                                                              │
│  Step 3: Transfer Debt Token                                 │
│  ──────────────────────────────                              │
│  IERC20(debtToken).transferFrom(                             │
│      liquidator,                                             │
│      address(pool),                                          │
│      amount                                                  │
│  );                                                          │
│                                                              │
│  Step 4: Repay User's Debt                                   │
│  ────────────────────────────                                │
│  userDebt[user][debtToken] -= amount;                        │
│                                                              │
│  Step 5: Calculate Collateral to Seize                       │
│  ───────────────────────────────────────                     │
│  debtPrice = oracle.getAssetPrice(debtToken);                │
│  collateralPrice = oracle.getAssetPrice(collateralToken);    │
│                                                              │
│  debtValue = amount × debtPrice;                             │
│  collateralAmount = debtValue / collateralPrice;             │
│  bonus = collateralAmount × liquidationBonus;                │
│  totalSeized = collateralAmount + bonus;                     │
│                                                              │
│  Step 6: Transfer Collateral                                 │
│  ──────────────────────────────                              │
│  userCollateral[user][collateralToken] -= totalSeized;       │
│  IERC20(collateralToken).transfer(liquidator, totalSeized);  │
│                                                              │
│  Step 7: Emit Event                                          │
│  ─────────────────────                                       │
│  emit Liquidated(user, collateral, debt, amount, bonus);     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Liquidation Bonus Calculation

```solidity
// User position
uint256 collateral = 1 ether;  // 1 ETH
uint256 debt = 1000e6;         // 1000 USDC

// Prices (from oracle)
uint256 ethPrice = 1200e8;     // $1200 per ETH
uint256 usdcPrice = 1e8;       // $1 per USDC

// Liquidation parameters
uint256 liquidationBonus = 1100;  // 110% (10% bonus)
uint256 BASE = 10000;

// Step 1: Calculate debt value in USD
uint256 debtValueUSD = (debt × usdcPrice) / 1e8;
// = (1000e6 × 1e8) / 1e8 = 1000e6 USD

// Step 2: Calculate collateral needed (at oracle price)
uint256 collateralNeeded = (debtValueUSD × 1e18) / ethPrice;
// = (1000e6 × 1e18) / 1200e8
// = 0.833... ETH

// Step 3: Add liquidation bonus
uint256 totalSeized = (collateralNeeded × liquidationBonus) / BASE;
// = (0.833... ETH × 1100) / 10000
// = 0.916... ETH

// Result:
// Liquidator pays: 1000 USDC
// Liquidator receives: 0.916 ETH
// At market price ($1200): 0.916 × $1200 = $1099.2
// Profit before costs: $99.2 (9.92%)
```

### Profitable Liquidation Math

For a liquidation to be profitable:

```
Collateral Value (market) > Debt Repaid + Flash Loan Fee + Gas Costs

Example:
  Collateral: 0.55 ETH @ $1000/ETH = $550
  Debt Repaid: $500
  Flash Loan Fee: $500 × 0.09% = $0.45
  Gas: ~400k gas @ 50 gwei × $3000/ETH = $60
  
  Profit = $550 - $500 - $0.45 - $60 = -$10.45
  ❌ Not profitable!

Better Example:
  Collateral: 0.55 ETH @ $2000/ETH = $1100
  Debt Repaid: $1000
  Flash Loan Fee: $1000 × 0.09% = $0.9
  Gas: ~400k gas @ 50 gwei × $2000/ETH = $40
  
  Profit = $1100 - $1000 - $0.9 - $40 = $59.1
  ✅ Profitable!
```

### Oracle Price vs Market Price

**Key Insight**: Liquidation bonus is calculated using **oracle price**, but you swap at **market price**.

```
Scenario: Oracle lags behind market

Oracle Price: ETH = $1000
Market Price: ETH = $1200 (market moved faster)
Debt: $1000 USDC

Liquidation (using oracle):
  Collateral to seize = $1000 / $1000 × 1.1 = 1.1 ETH
  
Swap (using market):
  1.1 ETH × $1200 = $1320
  
Profit:
  $1320 - $1000 (debt) - $0.9 (fee) = $319.1
  
🎉 Extra profit from oracle lag!
```

**Risk**: If market price < oracle price, liquidation may be unprofitable!

```
Oracle Price: ETH = $1200
Market Price: ETH = $1000 (crash!)
Debt: $1000 USDC

Liquidation (using oracle):
  Collateral to seize = $1000 / $1200 × 1.1 = 0.916 ETH
  
Swap (using market):
  0.916 ETH × $1000 = $916
  
Loss:
  $916 - $1000 (debt) - $0.9 (fee) = -$84.9
  
❌ Unprofitable! Transaction will revert.
```

## 💰 Profit Calculation and Optimization

### Profit Formula

```
Gross Profit = Collateral Value (market) - Debt Repaid

Net Profit = Gross Profit - Flash Loan Fee - Gas Costs - Slippage

Profit % = (Net Profit / Debt Repaid) × 100
```

### Example Calculations

**Scenario 1: Small Liquidation**
```
Debt: 1000 USDC
Collateral: 0.55 ETH @ $2000/ETH = $1100
Flash Loan Fee: $1000 × 0.09% = $0.90
Gas: 350k × 50 gwei × $2000/ETH = $35
Slippage: ~$5

Net Profit = $1100 - $1000 - $0.90 - $35 - $5 = $59.10
Profit % = ($59.10 / $1000) × 100 = 5.91%
```

**Scenario 2: Large Liquidation**
```
Debt: 100,000 USDC
Collateral: 55 ETH @ $2000/ETH = $110,000
Flash Loan Fee: $100,000 × 0.09% = $90
Gas: 350k × 50 gwei × $2000/ETH = $35
Slippage: ~$500

Net Profit = $110,000 - $100,000 - $90 - $35 - $500 = $9,375
Profit % = ($9,375 / $100,000) × 100 = 9.375%
```

**Key Insight**: Larger liquidations are more profitable (percentage-wise) because gas costs are fixed!

### Break-Even Analysis

```solidity
// Minimum profit needed to break even
function calculateBreakEven(
    uint256 debtAmount,
    uint256 gasPrice,
    uint256 ethPrice
) pure returns (uint256 minCollateralValue) {
    // Flash loan fee
    uint256 flashFee = (debtAmount × 9) / 10000;  // 0.09%
    
    // Gas cost in ETH
    uint256 gasETH = (350000 × gasPrice);  // 350k gas
    
    // Gas cost in USD
    uint256 gasUSD = (gasETH × ethPrice) / 1e18;
    
    // Total costs
    uint256 totalCosts = debtAmount + flashFee + gasUSD;
    
    return totalCosts;
}

// Example: Is this liquidation profitable?
uint256 debtAmount = 1000e6;  // 1000 USDC
uint256 gasPrice = 50 gwei;
uint256 ethPrice = 2000e8;

uint256 breakEven = calculateBreakEven(debtAmount, gasPrice, ethPrice);
// breakEven = 1000 + 0.9 + 35 = 1035.9 USDC

// If collateral worth > $1035.9 → Profitable ✅
// If collateral worth < $1035.9 → Unprofitable ❌
```

### Gas Optimization Strategies

**1. Batch Liquidations**
```solidity
function batchLiquidate(
    address[] calldata users,
    address[] calldata collaterals,
    address tokenToRepay,
    PoolKey calldata key
) external {
    // One flash loan for multiple liquidations
    // Amortize gas costs across liquidations
    // 500k gas for 5 liquidations = 100k per liquidation
}
```

**2. Optimize Swap Path**
```solidity
// ❌ Less efficient
ETH → USDC (single pool, might have slippage)

// ✅ More efficient
ETH → USDT → USDC (multi-hop, better pricing)
```

**3. Use Lower Gas Prices**
```solidity
// Monitor gas prices
// Only liquidate when gas < 50 gwei
// Use private mempools to avoid MEV

if (tx.gasprice > 50 gwei) {
    revert("Gas too high");
}
```

**4. Optimize Approvals**
```solidity
// ❌ Approve on every transaction
IERC20(token).approve(spender, amount);

// ✅ Approve once with max amount
IERC20(token).approve(spender, type(uint256).max);
```

### Slippage Protection

```solidity
function calculateMinOut(
    uint256 amountIn,
    uint256 poolPrice,
    uint256 slippageBps  // 50 = 0.5%
) pure returns (uint256) {
    uint256 expectedOut = amountIn × poolPrice;
    uint256 slippage = (expectedOut × slippageBps) / 10000;
    return expectedOut - slippage;
}

// Example
uint256 minOut = calculateMinOut(
    0.55 ether,     // ETH amount
    2000e6,         // $2000 per ETH
    50              // 0.5% slippage
);
// minOut = 1100 - 5.5 = 1094.5 USDC
```

### Profitability Checker

```solidity
function isProfitable(
    address user,
    address collateral,
    address debt,
    PoolKey calldata key
) external view returns (bool profitable, int256 expectedProfit) {
    // 1. Get liquidation data
    uint256 debtAmount = liquidator.getDebt(debt, user);
    uint256 collateralAmount = liquidator.getCollateralSeized(
        collateral,
        debt,
        user,
        debtAmount
    );
    
    // 2. Get market price for collateral
    uint256 collateralValue = quoter.quote(
        key,
        collateralAmount,
        true
    );
    
    // 3. Calculate costs
    uint256 flashFee = (debtAmount × 9) / 10000;
    uint256 gasCost = estimateGas() × tx.gasprice × ethPrice / 1e18;
    uint256 slippage = (collateralValue × 50) / 10000;  // 0.5%
    
    // 4. Calculate profit
    uint256 totalCosts = debtAmount + flashFee + gasCost + slippage;
    
    expectedProfit = int256(collateralValue) - int256(totalCosts);
    profitable = expectedProfit > 0;
}
```

## 🔄 WETH Wrapping/Unwrapping Logic

### Why Wrap/Unwrap?

Uniswap V4 uses `address(0)` for native ETH, but:
- Aave V3 uses WETH (ERC20)
- Flash loans are in WETH
- Need conversions between ETH ↔ WETH

### Wrapping Scenarios

**Scenario 1: Collateral is WETH, Pool uses ETH**
```
Liquidation gives: WETH
Pool expects: ETH
Action: Unwrap before swap

WETH.withdraw(balance);
// Now have ETH for V4 swap
```

**Scenario 2: Swap outputs ETH, Flash loan needs WETH**
```
Swap gives: ETH
Flash loan expects: WETH
Action: Wrap after swap

WETH.deposit{value: balance}();
// Now have WETH to repay flash loan
```

### Complete Wrapping Logic

```solidity
// After receiving collateral from liquidation
uint256 colBal = IERC20(collateral).balanceOf(address(this));

// Check if need to unwrap
if (collateral == WETH) {
    // Collateral is WETH but might need ETH for swap
    if (key.currency0 == address(0) || key.currency1 == address(0)) {
        // Pool uses address(0) for ETH, unwrap
        weth.withdraw(colBal);
        // Now have ETH
    }
}

// Perform swap
swap(key, amountIn, amountOutMin, zeroForOne);

// Check if need to wrap
address currencyOut = zeroForOne ? key.currency1 : key.currency0;
if (currencyOut == address(0)) {
    // Swap output is ETH but flash loan needs WETH
    weth.deposit{value: address(this).balance}();
    // Now have WETH
}

// Repay flash loan in WETH
IERC20(WETH).transfer(address(flash), amount + fee);
```

### WETH Interface

```solidity
interface IWETH {
    // Wrap: ETH → WETH
    function deposit() external payable;
    
    // Unwrap: WETH → ETH
    function withdraw(uint256 amount) external;
    
    // ERC20 functions
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}
```

### Usage Examples

**Wrap ETH to WETH**:
```solidity
// Have: 1 ETH
// Want: 1 WETH

IWETH(WETH).deposit{value: 1 ether}();

// Result:
// ETH balance: 0
// WETH balance: 1 ether
```

**Unwrap WETH to ETH**:
```solidity
// Have: 1 WETH
// Want: 1 ETH

IWETH(WETH).withdraw(1 ether);

// Result:
// WETH balance: 0
// ETH balance: 1 ether
```

**Receive ETH**:
```solidity
// Contract must have receive function
receive() external payable {}

// Or fallback
fallback() external payable {}
```

### Decision Tree

```
┌─────────────────────────────────────────────────────────┐
│         WETH Wrapping/Unwrapping Decision Tree          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  START: Received collateral from liquidation            │
│     │                                                   │
│     ├─ Is collateral WETH?                              │
│     │                                                   │
│     ├─ YES → Check pool currencies                      │
│     │   │                                               │
│     │   ├─ Does pool use address(0)?                    │
│     │   │                                               │
│     │   ├─ YES → Unwrap WETH to ETH                     │
│     │   │   │     weth.withdraw(balance)                │
│     │   │   │     Now have: ETH ✓                       │
│     │   │   │                                           │
│     │   │   └─ NO → Keep as WETH                        │
│     │   │         Now have: WETH ✓                      │
│     │   │                                               │
│     │   └─ Proceed to swap                              │
│     │                                                   │
│     └─ NO → Use collateral as-is                        │
│         │                                               │
│         └─ Proceed to swap                              │
│                                                         │
│  SWAP: Execute Universal Router swap                    │
│     │   swap(key, amountIn, amountOutMin, zeroForOne)   │
│     │                                                   │
│     └─ Swap complete, now check output                  │
│                                                         │
│  AFTER SWAP: Check swap output token                    │
│     │                                                   │
│     ├─ Is output address(0)?                            │
│     │                                                   │
│     ├─ YES → Received ETH, need WETH for flash loan     │
│     │   │     weth.deposit{value: balance}()            │
│     │   │     Now have: WETH ✓                          │
│     │   │                                               │
│     │   └─ NO → Already have correct token              │
│     │         Now have: Token ✓                         │
│     │                                                   │
│     └─ Proceed to repay flash loan                      │
│                                                         │
│  END: Repay flash loan                                  │
│       IERC20(tokenToRepay).transfer(flash, amt + fee)   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Edge Cases

**Case 1: Both tokens are wrapped/native versions**
```solidity
// Pool: WETH/USDC (both ERC20)
// No wrapping needed

collateral = WETH;
// Don't unwrap, swap WETH directly
```

**Case 2: Multiple wraps needed**
```solidity
// Rare: Collateral is token A, needs to wrap to B, then to C
// Solution: Use multi-hop swap instead
```

**Case 3: Contract receives ETH unexpectedly**
```solidity
// Always have receive() function
receive() external payable {
    // Optional: track unexpected ETH
    emit ReceivedETH(msg.sender, msg.value);
}
```

## 🐛 Debugging Guide

### Common Issues and Solutions

#### Issue 1: "Cannot liquidate"

**Error**:
```
Error: Cannot liquidate
  at Liquidator.getDebt()
```

**Causes**:
1. Health factor >= 1.0
2. User doesn't exist
3. User has no debt

**Debug**:
```solidity
function debugHealthFactor(address user) external view {
    (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) = pool.getUserAccountData(user);
    
    console.log("Collateral:", totalCollateralETH);
    console.log("Debt:", totalDebtETH);
    console.log("Health Factor:", healthFactor);
    console.log("Liquidatable:", healthFactor < 1e18);
}
```

**Solutions**:
- Wait for price change
- Find different user
- Verify oracle prices

#### Issue 2: "invalid pool key"

**Error**:
```
Error: invalid pool key
  at Liquidate.liquidate()
```

**Cause**: Debt token not in pool

**Debug**:
```solidity
console.log("tokenToRepay:", tokenToRepay);
console.log("pool.currency0:", key.currency0);
console.log("pool.currency1:", key.currency1);

// Map address(0) to WETH
address v4Token0 = key.currency0 == address(0) ? WETH : key.currency0;
address v4Token1 = key.currency1 == address(0) ? WETH : key.currency1;

console.log("Mapped token0:", v4Token0);
console.log("Mapped token1:", v4Token1);

bool valid = tokenToRepay == v4Token0 || tokenToRepay == v4Token1;
console.log("Valid:", valid);
```

**Solution**: Use correct pool
```solidity
// ❌ Wrong
PoolKey({
    currency0: Currency.wrap(WETH),
    currency1: Currency.wrap(USDC),
    ...
});
// tokenToRepay = DAI → not in pool!

// ✅ Correct
PoolKey({
    currency0: Currency.wrap(address(0)),  // ETH
    currency1: Currency.wrap(DAI),
    ...
});
// tokenToRepay = DAI → in pool ✓
```

#### Issue 3: "insufficient amount to repay flash loan"

**Error**:
```
Error: insufficient amount to repay flash loan
  at Liquidate.flashCallback()
```

**Causes**:
1. Swap output too low (slippage)
2. Liquidation not profitable
3. Low pool liquidity

**Debug**:
```solidity
// Before repayment
uint256 balance = IERC20(tokenToRepay).balanceOf(address(this));
uint256 required = amount + fee;

console.log("Balance:", balance);
console.log("Required:", required);
console.log("Shortfall:", required - balance);

// Check swap output
console.log("Collateral in:", collateralAmount);
console.log("Debt out:", balance);
console.log("Effective price:", (collateralAmount * 1e18) / balance);
```

**Solutions**:
1. Increase slippage tolerance
2. Use different pool (better liquidity)
3. Wait for better market conditions
4. Split into smaller liquidations

#### Issue 4: Swap Reverts

**Error**:
```
Error: V4_SWAP failed
  at UniversalRouter.execute()
```

**Causes**:
1. Insufficient approval
2. Wrong swap direction
3. Price out of range
4. Pool not initialized

**Debug**:
```solidity
// Check approvals
console.log("Token allowance to Permit2:", 
    IERC20(token).allowance(address(this), PERMIT2));
console.log("Token allowance to Router:",
    IPermit2(PERMIT2).allowance(address(this), token, UNIVERSAL_ROUTER));

// Check swap parameters
console.log("zeroForOne:", zeroForOne);
console.log("amountIn:", amountIn);
console.log("amountOutMin:", amountOutMin);

// Check pool
console.log("Pool initialized:", manager.isPoolInitialized(key));
console.log("Pool liquidity:", manager.getLiquidity(key));
```

**Solutions**:
```solidity
// Ensure proper approvals
IERC20(token).approve(PERMIT2, type(uint256).max);
IPermit2(PERMIT2).approve(token, UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);

// Verify swap direction
bool correctDirection = (collateral == v4Token0) ? true : false;

// Use realistic slippage
uint256 minOut = (expectedOut * 9950) / 10000;  // 0.5% slippage
```

#### Issue 5: Flash Loan Callback Not Called

**Error**:
```
Error: Flash loan completed but no callback
```

**Cause**: Wrong interface implementation

**Debug**:
```solidity
// Verify interface
console.log("Implements IFlashReceiver:",
    address(this).code.length > 0);

// Check callback selector
bytes4 selector = this.flashCallback.selector;
console.log("Callback selector:", selector);
// Should be: 0x...
```

**Solution**: Implement correct interface
```solidity
interface IFlashReceiver {
    function flashCallback(
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}

contract Liquidate is IFlashReceiver {
    function flashCallback(...) external override {
        // Implementation
    }
}
```

### Debugging Checklist

Before liquidation:
- [ ] User health factor < 1.0
- [ ] Debt token in V4 pool
- [ ] Pool has sufficient liquidity
- [ ] Gas price acceptable
- [ ] Estimated profit > costs

During execution:
- [ ] Flash loan received
- [ ] Liquidation executed
- [ ] Collateral received
- [ ] WETH wrapped/unwrapped correctly
- [ ] Swap executed successfully
- [ ] Sufficient balance for repayment

After execution:
- [ ] Flash loan repaid
- [ ] Profit transferred to caller
- [ ] No tokens left in contract
- [ ] Events emitted correctly

### Logging Template

```solidity
function flashCallback(...) external {
    console.log("=== Flash Callback Start ===");
    console.log("Token to repay:", tokenToRepay);
    console.log("Amount borrowed:", amount);
    console.log("Fee:", fee);
    
    // Decode
    (address user, PoolKey memory key) = abi.decode(data, (address, PoolKey));
    console.log("User:", user);
    console.log("Pool currency0:", key.currency0);
    console.log("Pool currency1:", key.currency1);
    
    // Map and determine collateral
    address collateral = ...;
    console.log("Collateral token:", collateral);
    
    // Liquidate
    console.log("=== Liquidation ===");
    liquidator.liquidate(...);
    uint256 colBal = IERC20(collateral).balanceOf(address(this));
    console.log("Collateral received:", colBal);
    
    // Unwrap if needed
    if (collateral == WETH && ...) {
        console.log("Unwrapping WETH");
        weth.withdraw(colBal);
        console.log("ETH balance:", address(this).balance);
    }
    
    // Swap
    console.log("=== Swap ===");
    console.log("Amount in:", colBal);
    console.log("Zero for one:", zeroForOne);
    swap(...);
    console.log("Balance after swap:", IERC20(tokenToRepay).balanceOf(address(this)));
    
    // Wrap if needed
    address currencyOut = ...;
    if (currencyOut == address(0)) {
        console.log("Wrapping ETH to WETH");
        weth.deposit{value: address(this).balance}();
    }
    
    // Repay
    console.log("=== Repayment ===");
    uint256 bal = IERC20(tokenToRepay).balanceOf(address(this));
    uint256 required = amount + fee;
    console.log("Balance:", bal);
    console.log("Required:", required);
    console.log("Excess (profit):", bal - required);
    
    IERC20(tokenToRepay).transfer(address(flash), required);
    console.log("=== Flash Callback End ===");
}
```

## 🌐 Real-World Applications

### 1. Liquidation Bots

**Purpose**: Monitor lending protocols 24/7 and automatically liquidate under-collateralized positions.

```solidity
contract LiquidationBot {
    // Monitor Aave positions
    function monitor() external {
        address[] memory users = getUsersAtRisk();
        
        for (uint i = 0; i < users.length; i++) {
            if (isProfitable(users[i])) {
                liquidate(users[i]);
            }
        }
    }
    
    // Get users with low health factors
    function getUsersAtRisk() internal view returns (address[] memory) {
        // Query subgraph or events
        // Filter by health factor < 1.05
        // Sort by profitability
    }
    
    // Check profitability before executing
    function isProfitable(address user) internal view returns (bool) {
        // Calculate expected profit
        // Consider gas costs, flash fees
        // Require minimum profit threshold (e.g., $50)
    }
}
```

**Architecture**:
```
┌───────────────────────────────────────────────────┐
│                 Liquidation Bot                   │
├───────────────────────────────────────────────────┤
│                                                   │
│  Off-Chain Component:                             │
│  ┌────────────────────────────────────────────┐   │
│  │ Monitor Service (Node.js)                  │   │
│  │ • Query The Graph every block              │   │
│  │ • Track health factors                     │   │
│  │ • Calculate profitability                  │   │
│  │ • Send transactions                        │   │
│  └────────────────────────────────────────────┘   │
│         │                                         │
│         ↓                                         │
│  On-Chain Component:                              │
│  ┌────────────────────────────────────────────┐   │
│  │ Liquidate Contract                         │   │
│  │ • Flash loan                               │   │
│  │ • Liquidate                                │   │
│  │ • Swap                                     │   │
│  │ • Profit extraction                        │   │
│  └────────────────────────────────────────────┘   │
│                                                   │
└───────────────────────────────────────────────────┘
```

**Monitoring Query** (The Graph):
```graphql
{
  users(
    where: {
      healthFactor_lt: "1000000000000000000"  # < 1.0
    }
    orderBy: borrowedValueUSD
    orderDirection: desc
  ) {
    id
    collateral {
      token
      amount
      valueUSD
    }
    borrows {
      token
      amount
      valueUSD
    }
    healthFactor
  }
}
```

### 2. MEV Protection

**Problem**: Liquidation transactions can be front-run by MEV bots.

**Solution**: Use private mempools (Flashbots, Eden Network)

```typescript
// Using Flashbots
import { FlashbotsBundleProvider } from '@flashbots/ethers-provider-bundle';

const flashbotsProvider = await FlashbotsBundleProvider.create(
    provider,
    authSigner,
    'https://relay.flashbots.net'
);

// Build liquidation transaction
const tx = await liquidate.populateTransaction.liquidate(
    tokenToRepay,
    user,
    poolKey
);

// Send as Flashbots bundle
const bundle = [
    {
        signer: wallet,
        transaction: tx
    }
];

const bundleSubmission = await flashbotsProvider.sendBundle(
    bundle,
    targetBlockNumber
);
```

**Benefits**:
- No front-running
- No failed transactions in public mempool
- Priority ordering
- Can bundle multiple operations

### 3. Cross-Protocol Liquidations

**Scenario**: Liquidate on multiple protocols atomically

```solidity
contract MultiProtocolLiquidator {
    function liquidateMultiple(
        LiquidationParams[] calldata liquidations
    ) external {
        // 1. Calculate total flash loan needed
        uint256 totalDebt;
        for (uint i = 0; i < liquidations.length; i++) {
            totalDebt += liquidations[i].debtAmount;
        }
        
        // 2. Get one large flash loan
        flash.flash(debtToken, totalDebt, abi.encode(liquidations));
    }
    
    function flashCallback(...) external {
        LiquidationParams[] memory liquidations = abi.decode(data, ...);
        
        // 3. Execute all liquidations
        for (uint i = 0; i < liquidations.length; i++) {
            // Liquidate on Aave
            // Liquidate on Compound
            // Liquidate on Spark
            // etc.
        }
        
        // 4. Aggregate collateral and swap
        
        // 5. Repay flash loan
    }
}
```

### 4. Liquidation Sniping

**Strategy**: Compete for the same liquidation opportunity

```solidity
contract LiquidationSniper {
    // Use higher gas price to be first
    function snipe(
        address user,
        uint256 gasPrice
    ) external {
        // Calculate max gas price that keeps liquidation profitable
        uint256 maxGasPrice = calculateMaxGasPrice(user);
        
        require(gasPrice <= maxGasPrice, "Too expensive");
        
        // Execute with specified gas price
        liquidate{gas: 400000, gasPrice: gasPrice}(user);
    }
    
    function calculateMaxGasPrice(address user) internal view returns (uint256) {
        uint256 expectedProfit = estimateProfit(user);
        uint256 gasUsed = 350000;
        
        // Max gas price where profit > 0
        return (expectedProfit * 1e18) / (gasUsed * ethPrice);
    }
}
```

### 5. Liquidation as a Service

**Business Model**: Provide liquidation services to protocols

```solidity
contract LiquidationService {
    mapping(address => uint256) public protocolFees;
    
    // Protocols register and set fees
    function registerProtocol(uint256 feePercent) external {
        protocolFees[msg.sender] = feePercent;
    }
    
    // Execute liquidation and share profit
    function liquidateForProtocol(
        address protocol,
        address user
    ) external {
        // Execute liquidation
        uint256 profit = liquidate(user);
        
        // Split profit
        uint256 protocolFee = (profit * protocolFees[protocol]) / 100;
        uint256 liquidatorProfit = profit - protocolFee;
        
        // Distribute
        IERC20(debtToken).transfer(protocol, protocolFee);
        IERC20(debtToken).transfer(msg.sender, liquidatorProfit);
    }
}
```

## 🚀 Advanced Concepts

### 1. Just-In-Time (JIT) Liquidations

**Concept**: Provide liquidity just before liquidation, remove after

```solidity
function jitLiquidate(address user, PoolKey memory key) external {
    // 1. Flash loan to add liquidity
    // 2. Add liquidity to pool (improves swap price)
    // 3. Execute liquidation
    // 4. Swap collateral (better price due to liquidity)
    // 5. Remove liquidity
    // 6. Repay flash loan
    // 7. Keep profit
}
```

**Benefits**:
- Better swap execution
- Higher profit margins
- Reduced slippage

**Risks**:
- Higher gas costs
- Complexity
- Timing sensitive

### 2. Partial Liquidations

**Strategy**: Liquidate just enough to restore health

```solidity
function partialLiquidate(address user) external {
    // Get current health factor
    uint256 hf = getHealthFactor(user);
    
    // Calculate minimum liquidation to reach HF = 1.05
    uint256 minDebt = calculateMinLiquidation(user, 1.05e18);
    
    // Liquidate only minimum amount
    liquidate(user, minDebt);
    
    // Benefits:
    // - Lower gas (smaller amounts)
    // - Less slippage
    // - User keeps more collateral
    // - Can liquidate same user again if prices continue falling
}
```

### 3. Self-Liquidation

**Use Case**: Liquidate your own position to avoid liquidation penalty

```solidity
contract SelfLiquidator {
    function selfLiquidate() external {
        // 1. Flash loan debt amount
        // 2. Repay your own debt
        // 3. Withdraw collateral
        // 4. Swap collateral to debt token
        // 5. Repay flash loan
        
        // Result: Avoid liquidation penalty (typically 5-10%)
        // Cost: Only flash loan fee (0.09%)
    }
}
```

**Math**:
```
Traditional Liquidation:
  Collateral: 1 ETH = $1100
  Debt: $1000
  Liquidation penalty: 10%
  Liquidator gets: $1100
  User loses: $100 (10%)

Self-Liquidation:
  Flash loan: $1000
  Repay debt: $1000
  Withdraw: 1 ETH = $1100
  Swap: $1100
  Repay: $1000.9 (flash fee)
  Keep: $99.1
  User loses: $0.9 (0.09%)
  
Savings: $100 - $0.9 = $99.1 🎉
```

### 4. Liquidation Aggregation

**Strategy**: Aggregate multiple small liquidations into one transaction

```solidity
function aggregateLiquidations(
    address[] calldata users,
    address[] calldata collaterals,
    address debtToken
) external {
    // 1. Calculate total flash loan needed
    uint256 totalDebt = 0;
    for (uint i = 0; i < users.length; i++) {
        totalDebt += getDebt(users[i]);
    }
    
    // 2. One flash loan for all
    flash.flash(debtToken, totalDebt, abi.encode(users, collaterals));
}

function flashCallback(...) external {
    (address[] memory users, address[] memory collaterals) = abi.decode(data, ...);
    
    // 3. Execute all liquidations
    uint256 totalCollateral = 0;
    for (uint i = 0; i < users.length; i++) {
        liquidate(collaterals[i], debtToken, users[i]);
        totalCollateral += IERC20(collaterals[i]).balanceOf(address(this));
    }
    
    // 4. Aggregate swap (better than individual swaps)
    swap(totalCollateral);
    
    // 5. Repay and profit
}
```

**Benefits**:
- Amortized gas costs
- Better swap pricing (larger amounts)
- Higher efficiency

### 5. Oracle Manipulation Protection

**Risk**: Attackers manipulate oracles to trigger false liquidations

**Protection**:
```solidity
function safeLiquidate(address user) external {
    // 1. Get prices from multiple oracles
    uint256 chainlinkPrice = chainlinkOracle.getPrice(token);
    uint256 uniswapV3Price = v3Oracle.getPrice(token);
    uint256 uniswapV4Price = v4Oracle.getPrice(token);
    
    // 2. Check price deviation
    uint256 maxDeviation = 5;  // 5%
    uint256 avgPrice = (chainlinkPrice + uniswapV3Price + uniswapV4Price) / 3;
    
    require(
        abs(chainlinkPrice - avgPrice) * 100 / avgPrice <= maxDeviation,
        "Price manipulation detected"
    );
    
    // 3. Use TWAP instead of spot price
    uint256 twapPrice = getTWAP(token, 30 minutes);
    
    // 4. Proceed with liquidation
    liquidate(user);
}
```

### 6. Multi-Hop Liquidations

**Scenario**: Collateral needs multiple swaps to reach debt token

```solidity
function multiHopLiquidate(
    address user,
    PoolKey[] memory swapPath  // e.g., WBTC → ETH → USDC
) external {
    // 1. Flash loan USDC
    flash.flash(USDC, debtAmount, data);
}

function flashCallback(...) external {
    // 2. Liquidate, receive WBTC
    liquidate(WBTC, USDC, user);
    
    // 3. Swap WBTC → ETH
    swap(poolWBTC_ETH, wbtcAmount, ...);
    
    // 4. Swap ETH → USDC
    swap(poolETH_USDC, ethAmount, ...);
    
    // 5. Repay flash loan in USDC
    repay();
}
```

### 7. Gas Token Optimization

**Strategy**: Use gas tokens (Chi, GST2) to reduce liquidation costs

```solidity
import "@1inch/chi/contracts/IGasToken.sol";

contract GasOptimizedLiquidator {
    IGasToken public immutable chi;
    
    function liquidate(address user) external {
        // 1. Mint gas tokens when gas is cheap
        // Done off-chain during low gas periods
        
        // 2. Use gas tokens during liquidation
        uint256 gasStart = gasleft();
        
        // Execute liquidation
        _liquidate(user);
        
        // 3. Free gas tokens
        uint256 gasUsed = gasStart - gasleft();
        uint256 tokensToFree = (gasUsed + 14154) / 41947;
        
        chi.freeUpTo(tokensToFree);
        
        // Result: ~50% gas refund
    }
}
```

### 8. Liquidation Insurance

**Concept**: Insure against failed liquidations

```solidity
contract LiquidationInsurance {
    // Users pay premium to protect against liquidation
    function buyInsurance(uint256 coverageAmount) external payable {
        // Premium = 1% of coverage per month
        uint256 premium = (coverageAmount * 100) / 10000;
        require(msg.value >= premium, "Insufficient premium");
        
        // Store coverage
        coverage[msg.sender] = Coverage({
            amount: coverageAmount,
            expiry: block.timestamp + 30 days
        });
    }
    
    // If user gets liquidated, they can claim insurance
    function claim() external {
        require(wasLiquidated(msg.sender), "Not liquidated");
        require(coverage[msg.sender].expiry > block.timestamp, "Expired");
        
        // Pay out coverage
        uint256 amount = coverage[msg.sender].amount;
        delete coverage[msg.sender];
        
        payable(msg.sender).transfer(amount);
    }
}
```

## 📚 Summary and Best Practices

### Key Takeaways

1. **Flash Loans Enable Zero-Capital Liquidations**
   - Borrow debt token without collateral
   - Execute liquidation atomically
   - Only pay small fee (0.09%)

2. **Aave V3 vs Uniswap V4 Flash Loans**
   - Use Aave V3 (PoolManager locking issue with V4)
   - Allows Universal Router to access V4 pools
   - Slightly higher fee but more flexible

3. **Health Factor < 1.0 = Liquidatable**
   - Monitor health factors continuously
   - Price movements trigger liquidations
   - Act fast - competition is fierce

4. **Liquidation Bonus = Profit Source**
   - Extra collateral as incentive (5-10%)
   - Must exceed flash fee + gas + slippage
   - Oracle lag can increase profit

5. **WETH Wrapping is Critical**
   - V4 uses address(0) for ETH
   - Aave uses WETH (ERC20)
   - Must wrap/unwrap correctly

### Best Practices Checklist

**Before Liquidation**:
- [ ] Verify health factor < 1.0
- [ ] Calculate expected profit
- [ ] Check gas prices
- [ ] Verify pool liquidity
- [ ] Test on fork first

**Implementation**:
- [ ] Handle address(0) ↔ WETH mapping
- [ ] Implement proper error handling
- [ ] Use realistic slippage protection
- [ ] Add profitability checks
- [ ] Optimize gas usage

**Testing**:
- [ ] Test with different collateral types
- [ ] Test price crash scenarios
- [ ] Test low liquidity cases
- [ ] Test unprofitable liquidations
- [ ] Test gas cost impacts

**Production**:
- [ ] Monitor positions 24/7
- [ ] Use private mempools (Flashbots)
- [ ] Set minimum profit thresholds
- [ ] Implement circuit breakers
- [ ] Track metrics and profitability

### Security Considerations

1. **Reentrancy Protection**
```solidity
bool private locked;

modifier nonReentrant() {
    require(!locked, "Reentrant call");
    locked = true;
    _;
    locked = false;
}

function liquidate(...) external nonReentrant {
    // Safe from reentrancy
}
```

2. **Access Control**
```solidity
address public owner;

modifier onlyOwner() {
    require(msg.sender == owner, "Not owner");
    _;
}

function emergencyWithdraw() external onlyOwner {
    // Only owner can recover funds
}
```

3. **Slippage Protection**
```solidity
function swap(..., uint256 minAmountOut) private {
    uint256 amountOut = router.execute(...);
    require(amountOut >= minAmountOut, "Slippage too high");
}
```

4. **Flash Loan Validation**
```solidity
function flashCallback(...) external {
    require(msg.sender == address(flash), "Invalid flash loan");
    // Prevent unauthorized callbacks
}
```

### Performance Optimization

1. **Gas Optimization**
   - Use `calldata` instead of `memory` for external functions
   - Cache storage variables in memory
   - Use unchecked math where safe
   - Batch approvals

2. **Capital Efficiency**
   - Reuse flash loans for multiple liquidations
   - Aggregate small liquidations
   - Optimize swap routes

3. **Timing Optimization**
   - Monitor mempool for opportunities
   - Use private mempools
   - Compete on gas price strategically

### Common Pitfalls to Avoid

❌ **Don't**:
- Assume all liquidations are profitable
- Ignore gas costs in calculations
- Use spot prices without TWAP
- Hardcode token addresses
- Skip error handling
- Test only happy paths

✅ **Do**:
- Calculate profitability before executing
- Include all costs (gas, fees, slippage)
- Use multiple price oracles
- Make contracts flexible
- Handle all error cases
- Test edge cases thoroughly

### Further Reading

- [Aave V3 Documentation](https://docs.aave.com/developers/core-contracts/pool)
- [Uniswap V4 Documentation](https://docs.uniswap.org/contracts/v4/overview)
- [Flash Loans Explained](https://docs.aave.com/developers/guides/flash-loans)
- [MEV and Liquidations](https://ethereum.org/en/developers/docs/mev/)
- [Liquidation Bot Strategies](https://github.com/makerdao/liquidation-keeper)

### Conclusion

Liquidations are a critical component of DeFi lending protocols, ensuring system solvency. By combining flash loans, liquidation mechanics, and efficient swaps, you can build profitable liquidation bots with zero upfront capital.

Key success factors:
- **Speed**: Be first to liquidate
- **Efficiency**: Minimize costs
- **Reliability**: Handle all edge cases
- **Profitability**: Only execute profitable liquidations

This exercise demonstrates real-world DeFi composability, combining Aave V3 flash loans with Uniswap V4 swaps to create a powerful liquidation system. The patterns learned here apply to arbitrage, refinancing, and many other DeFi strategies.

---

**Next Steps**:
1. Implement the contract
2. Test thoroughly on a fork
3. Deploy to testnet
4. Monitor real positions
5. Optimize based on real data
6. Consider building a full liquidation bot

Good luck with your liquidations! 🚀

