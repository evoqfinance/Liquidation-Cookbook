﻿# OverView

Liquidation can occur when a user's Borrow Limit used exceeds 100%.

> Due to the Close Factor, the amount that can be processed in one transaction is **up to** 50% of the user's Borrowed Amount.

> The liquidation penalty is 10%.

# Use Case

**The liquidation of the ecosystem**

Liquidation in Evoq plays a vital role in maintaining a healthy and secure financial ecosystem by:

- **Mitigating Default Risk**: It allows for the recovery of assets from accounts that fail to meet collateral requirements, reducing the risk of insolvency.
- **Ensuring Market Stability**: By efficiently handling bad debt, liquidation helps sustain long-term market integrity and resilience.
- **Encouraging Liquidator Participation**: The LI mechanism provides incentives for liquidators to actively engage in the process, ensuring continuous liquidity and market efficiency.

# Example

The [Liquidation Contract](https://github.com/evoqfinance/Liquidation-Cookbook/blob/main/contracts/EvoqLiquidation.sol) below performs five key actions.

> The example contract is a capital-free liquidation using Aave flashloan. Therefore, you will pay a fee to Aave flashloan and receive a smaller amount of incentive than you expected. If you want to maximize your incentive, you should not use the contract below.

1. Borrow a borrower's loan asset using Aave Flashloan.
2. proceed to liquidate in Evoq Contract.
3. Swap the Reward (the borrower's deposit asset) received in step 2 for the flashloan asset via Pancake Swap V3.
4. repayment to Aave Flashloan.
5. Send the remaining Liquidate Reward to the liquidator.
