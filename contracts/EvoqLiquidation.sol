// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEvoqPositionManager {
    function liquidate(
        address _poolTokenBorrowed,
        address _poolTokenCollateral,
        address _borrower,
        uint256 _amount
    ) external returns (uint256 repaidAmount, uint256 seizedCollateral);
}

contract FlashLoanWithPairAddress {
    // Avoid Stack too deep
    // Struct to store data required for flash loan and liquidation
    struct LiquidationData {
        address borrower;
        address debtToken;
        uint256 debtAmount;
        address debtVToken;
        address collateralToken;
        address collateralVToken;
    }

    // Avoid Stack too deep
    // Struct to store swap-related reserves and calculated values
    struct SwapDetails {
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amountIn;
        uint256 amountOutMin;
    }

    // Contract state variables
    IEvoqPositionManager private immutable evoq; // Evoq Position Manager address
    address private immutable pancakeFactory; // Biswap Factory address for Avoid reentrancy guard
    address private immutable owner; // Contract owner
    IPool private immutable aavePool;

    constructor(
        address _owner,
        address _pancakeFactory,
        address _evoq,
        address _aavePool
    ) {
        owner = _owner;
        pancakeFactory = _pancakeFactory;
        evoq = IEvoqPositionManager(_evoq);
        aavePool = IPool(_aavePool);
    }

    /**
     * @dev Initiates a flash loan to perform liquidation.
     * @param debtToken The token to borrow for liquidation.
     * @param debtVToken The vToken of the borrowed token.
     * @param debtAmount The amount of debt token to borrow.
     * @param collateralToken The collateral token to seize.
     * @param collateralVToken The vToken of the collateral token.
     * @param borrower The address of the borrower to liquidate.
     */
    function initiateFlashLoan(
        address debtToken,
        address debtVToken,
        uint256 debtAmount,
        address collateralToken,
        address collateralVToken,
        address borrower
    ) external {
        // Encode data needed for the flash loan
        bytes memory data = abi.encode(
            LiquidationData(
                borrower,
                debtToken,
                debtAmount,
                debtVToken,
                collateralToken,
                collateralVToken
            )
        );

        aavePool.flashLoanSimple(
            address(this),
            debtToken,
            debtAmount,
            data,
            0 // referral code
        );
    }

    /**
     * @dev Callback function for flash loan; performs liquidation and repayment.
     * @param asset The address of the asset borrowed.
     * @param amount The amount of asset borrowed.
     * @param premium The premium amount.
     * @param initiator The address that initiated the flash loan.
     * @param params Encoded data for liquidation.
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        LiquidationData memory ld = abi.decode(params, (LiquidationData));

        // Approve the debt token and execute liquidation
        IERC20(ld.debtToken).approve(address(evoq), ld.debtAmount);
        evoq.liquidate(
            ld.debtVToken,
            ld.collateralVToken,
            ld.borrower,
            ld.debtAmount
        );

        // Retrieve the Pancake liquidity pool address
        address pancakePair = IUniswapV2Factory(pancakeFactory).getPair(
            ld.debtToken,
            ld.collateralToken
        );

        // Retrieve reserve information from the Pancake liquidity pool
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pancakePair)
            .getReserves();
        SwapDetails memory sd = ld.collateralToken ==
            IUniswapV2Pair(pancakePair).token0()
            ? SwapDetails(reserve0, reserve1, 0, 0)
            : SwapDetails(reserve1, reserve0, 0, 0);

        // Calculate minimum output amount and input amount
        sd.amountOutMin = ld.debtAmount + premium;
        sd.amountIn = getAmountIn(sd.amountOutMin, sd.reserveIn, sd.reserveOut);

        // Transfer collateral token to Pancake pool and execute swap
        IERC20(ld.collateralToken).transfer(pancakePair, sd.amountIn);
        IUniswapV2Pair(pancakePair).swap(
            ld.debtToken == IUniswapV2Pair(pancakePair).token0()
                ? sd.amountOutMin
                : 0,
            ld.debtToken == IUniswapV2Pair(pancakePair).token1()
                ? sd.amountOutMin
                : 0,
            address(this),
            new bytes(0)
        );

        // Repay the flash loan
        uint256 repaymentAmount = ld.debtAmount + premium;
        IERC20(ld.debtToken).approve(msg.sender, repaymentAmount);

        // Transfer remaining collateral to the contract owner
        uint256 collateralBalance = IERC20(ld.collateralToken).balanceOf(
            address(this)
        );
        if (collateralBalance > 0) {
            IERC20(ld.collateralToken).transfer(owner, collateralBalance);
        }

        return true;
    }

    /**
     * @dev Calculates the required input amount for a given output.
     * @param amountOut The desired output token amount.
     * @param reserveIn The reserve of the input token.
     * @param reserveOut The reserve of the output token.
     * @return amountIn The calculated input token amount.
     */
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountIn) {
        require(amountOut > 0, "TokenSwap: INVALID_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "TokenSwap: INSUFFICIENT_LIQUIDITY"
        );

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    fallback() external {}
}