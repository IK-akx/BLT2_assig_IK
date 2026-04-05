// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./LPToken.sol";

contract AMM {
    using SafeERC20 for IERC20;

    IERC20 public tokenA;
    IERC20 public tokenB;
    LPToken public lpToken;

    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public totalLiquidity;

    uint256 public constant FEE = 30; // 0.3%
    uint256 public constant FEE_DENOMINATOR = 10000;

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpBurned);
    event Swap(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _tokenA, address _tokenB, address _lpToken) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        lpToken = LPToken(_lpToken);
        lpToken.setAmm(address(this));
    }

    function addLiquidity(uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin)
        external
        returns (uint256 lpMinted)
    {
        require(amountADesired > 0 && amountBDesired > 0, "Amounts must be > 0");

        if (reserveA == 0 && reserveB == 0) {
            lpMinted = _sqrt(amountADesired * amountBDesired);
        } else {
            uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Slippage B");
                lpMinted = (amountADesired * totalLiquidity) / reserveA;
            } else {
                uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal <= amountADesired, "Insufficient A");
                require(amountAOptimal >= amountAMin, "Slippage A");
                lpMinted = (amountBDesired * totalLiquidity) / reserveB;
            }
        }

        require(lpMinted > 0, "LP minted must be > 0");

        tokenA.safeTransferFrom(msg.sender, address(this), amountADesired);
        tokenB.safeTransferFrom(msg.sender, address(this), amountBDesired);

        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));
        totalLiquidity += lpMinted;

        lpToken.mint(msg.sender, lpMinted);

        emit LiquidityAdded(msg.sender, amountADesired, amountBDesired, lpMinted);
    }

    function removeLiquidity(uint256 lpAmount, uint256 amountAMin, uint256 amountBMin)
        external
        returns (uint256 amountA, uint256 amountB)
    {
        require(lpAmount > 0, "LP amount must be > 0");

        amountA = (lpAmount * reserveA) / totalLiquidity;
        amountB = (lpAmount * reserveB) / totalLiquidity;

        require(amountA >= amountAMin, "Slippage A");
        require(amountB >= amountBMin, "Slippage B");

        lpToken.burn(msg.sender, lpAmount);

        tokenA.safeTransfer(msg.sender, amountA);
        tokenB.safeTransfer(msg.sender, amountB);

        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));
        totalLiquidity -= lpAmount;

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpAmount);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 amountOutMin) external returns (uint256 amountOut) {
        require(amountIn > 0, "Amount in must be > 0");
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "Invalid token");

        bool isTokenA = tokenIn == address(tokenA);
        (uint256 reserveIn, uint256 reserveOut) = isTokenA ? (reserveA, reserveB) : (reserveB, reserveA);

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Slippage");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (isTokenA) {
            tokenB.safeTransfer(msg.sender, amountOut);
        } else {
            tokenA.safeTransfer(msg.sender, amountOut);
        }

        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));

        emit Swap(msg.sender, tokenIn, isTokenA ? address(tokenB) : address(tokenA), amountIn, amountOut);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "Amount in must be > 0");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _quote(uint256 amountA, uint256 reserveA_, uint256 reserveB_) internal pure returns (uint256) {
        require(amountA > 0, "Amount must be > 0");
        require(reserveA_ > 0 && reserveB_ > 0, "Reserves must be > 0");
        return (amountA * reserveB_) / reserveA_;
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
