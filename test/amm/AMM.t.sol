// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TokenA} from "../../src/tokens/TokenA.sol";
import {TokenB} from "../../src/tokens/TokenB.sol";
import {LPToken} from "../../src/amm/LPToken.sol";
import {AMM} from "../../src/amm/AMM.sol";

contract AMMTest is Test {
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpBurned);
    event Swap(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);



    TokenA public tokenA;
    TokenB public tokenB;
    LPToken public lpToken;
    AMM public amm;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    
    function setUp() public {
        tokenA = new TokenA();
        tokenB = new TokenB();
        lpToken = new LPToken();
        amm = new AMM(address(tokenA), address(tokenB), address(lpToken));
        
        tokenA.mint(user1, 10000 ether);
        tokenB.mint(user1, 10000 ether);
        tokenA.mint(user2, 10000 ether);
        tokenB.mint(user2, 10000 ether);
        
        vm.startPrank(user1);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }
    
    function test_AddLiquidityFirst() public {
        vm.prank(user1);
        uint256 lpMinted = amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        assertGt(lpMinted, 0);
        assertEq(lpToken.balanceOf(user1), lpMinted);
        assertEq(amm.totalLiquidity(), lpMinted);
    }
    
    function test_AddLiquiditySubsequent() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        vm.prank(user2);
        uint256 lpMinted = amm.addLiquidity(500 ether, 500 ether, 0, 0);
        
        assertGt(lpMinted, 0);
        assertEq(lpToken.balanceOf(user2), lpMinted);
    }
    
    function test_RemoveLiquidityPartial() public {
        vm.prank(user1);
        uint256 lpMinted = amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        vm.prank(user1);
        (uint256 amountA, uint256 amountB) = amm.removeLiquidity(lpMinted / 2, 0, 0);
        
        assertGt(amountA, 0);
        assertGt(amountB, 0);
        assertEq(lpToken.balanceOf(user1), lpMinted / 2);
    }
    
    function test_RemoveLiquidityFull() public {
        vm.prank(user1);
        uint256 lpMinted = amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        vm.prank(user1);
        (uint256 amountA, uint256 amountB) = amm.removeLiquidity(lpMinted, 0, 0);
        
        assertEq(amountA, 1000 ether);
        assertEq(amountB, 1000 ether);
        assertEq(lpToken.balanceOf(user1), 0);
        assertEq(amm.totalLiquidity(), 0);
    }
    
    function test_SwapTokenAToB() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        uint256 amountIn = 100 ether;
        uint256 expectedOut = amm.getAmountOut(amountIn, 1000 ether, 1000 ether);
        
        vm.prank(user1);
        uint256 amountOut = amm.swap(address(tokenA), amountIn, 0);
        
        assertEq(amountOut, expectedOut);
        assertGt(amountOut, 0);
    }
    
    function test_SwapTokenBToA() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        uint256 amountIn = 100 ether;
        uint256 expectedOut = amm.getAmountOut(amountIn, 1000 ether, 1000 ether);
        
        vm.prank(user1);
        uint256 amountOut = amm.swap(address(tokenB), amountIn, 0);
        
        assertEq(amountOut, expectedOut);
        assertGt(amountOut, 0);
    }
    
    function test_InvariantKIncreasesAfterSwap() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        uint256 kBefore = amm.reserveA() * amm.reserveB();
        
        vm.prank(user1);
        amm.swap(address(tokenA), 100 ether, 0);
        
        uint256 kAfter = amm.reserveA() * amm.reserveB();
        
        assertGt(kAfter, kBefore);
    }
    
    function test_SlippageProtectionReverts() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        uint256 amountOut = amm.getAmountOut(100 ether, 1000 ether, 1000 ether);
        
        vm.prank(user1);
        vm.expectRevert("Slippage");
        amm.swap(address(tokenA), 100 ether, amountOut + 1);
    }
    
    function test_ZeroAmountReverts() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        vm.prank(user1);
        vm.expectRevert("Amount in must be > 0");
        amm.swap(address(tokenA), 0, 0);
    }
    
    function test_AddLiquidityZeroAmountReverts() public {
        vm.prank(user1);
        vm.expectRevert("Amounts must be > 0");
        amm.addLiquidity(0, 1000 ether, 0, 0);
    }
    
    function test_RemoveLiquidityZeroAmountReverts() public {
        vm.prank(user1);
        vm.expectRevert("LP amount must be > 0");
        amm.removeLiquidity(0, 0, 0);
    }
    
    function test_LargeSwapHighPriceImpact() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        uint256 amountIn = 800 ether;
        uint256 amountOut = amm.getAmountOut(amountIn, 1000 ether, 1000 ether);
        
        assertLt(amountOut, 500 ether);
        
        vm.prank(user1);
        amm.swap(address(tokenA), amountIn, 0);
    }
    
    function test_InvalidTokenReverts() public {
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        vm.prank(user1);
        vm.expectRevert("Invalid token");
        amm.swap(address(0x123), 100 ether, 0);
    }
    
    function testFuzz_Swap(uint256 amountIn) public {
        vm.assume(amountIn > 0 && amountIn < 1000 ether);
        
        vm.prank(user1);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
        
        uint256 reserveABefore = amm.reserveA();
        uint256 reserveBBefore = amm.reserveB();
        
        uint256 amountOut = amm.getAmountOut(amountIn, reserveABefore, reserveBBefore);
        
        if (amountOut > 0) {
            vm.prank(user1);
            uint256 actualOut = amm.swap(address(tokenA), amountIn, 0);
            
            assertEq(actualOut, amountOut);
            assertEq(amm.reserveA(), reserveABefore + amountIn);
            assertEq(amm.reserveB(), reserveBBefore - actualOut);
        }
    }
    
    function test_EventEmitted() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit LiquidityAdded(user1, 1000 ether, 1000 ether, 1000 ether);
        amm.addLiquidity(1000 ether, 1000 ether, 0, 0);
    }
}