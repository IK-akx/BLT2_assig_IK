// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TestToken} from "../../src/tokens/TestToken.sol";
import {LendingPool} from "../../src/lending/LendingPool.sol";

contract LendingPoolTest is Test {
    TestToken public collateral;
    TestToken public borrow;
    LendingPool public pool;

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public liquidator = address(0x3);
    address public lender = address(0x4);

    function setUp() public {
        collateral = new TestToken("Collateral", "COL");
        borrow = new TestToken("Borrow", "BRW");
        pool = new LendingPool(address(collateral), address(borrow));

        collateral.mint(user1, 10_000 ether);
        collateral.mint(user2, 10_000 ether);

        borrow.mint(user1, 10_000 ether);
        borrow.mint(user2, 10_000 ether);
        borrow.mint(liquidator, 10_000 ether);
        borrow.mint(lender, 100_000 ether);

        vm.startPrank(user1);
        collateral.approve(address(pool), type(uint256).max);
        borrow.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        collateral.approve(address(pool), type(uint256).max);
        borrow.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
        collateral.approve(address(pool), type(uint256).max);
        borrow.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(lender);
        borrow.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.prank(lender);
        borrow.transfer(address(pool), 50_000 ether);
    }

    function test_DepositFlow() public {
        vm.prank(user1);
        pool.deposit(1000 ether);

        (uint256 collateralAmt, uint256 borrowedAmt, ) = pool.positions(user1);
        assertEq(collateralAmt, 1000 ether);
        assertEq(borrowedAmt, 0);
        assertEq(collateral.balanceOf(address(pool)), 1000 ether);
    }

    function test_WithdrawFlow() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.withdraw(400 ether);
        vm.stopPrank();

        (uint256 collateralAmt, , ) = pool.positions(user1);
        assertEq(collateralAmt, 600 ether);
        assertEq(collateral.balanceOf(user1), 9400 ether);
    }

    function test_BorrowWithinLTV() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(750 ether);
        vm.stopPrank();

        (, uint256 borrowedAmt, ) = pool.positions(user1);
        assertEq(borrowedAmt, 750 ether);
        assertEq(borrow.balanceOf(user1), 10_750 ether);
    }

    function test_BorrowExceedingLTVReverts() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        vm.expectRevert("Exceeds LTV");
        pool.borrow(751 ether);
        vm.stopPrank();
    }

    function test_BorrowWithZeroCollateralReverts() public {
        vm.prank(user1);
        vm.expectRevert("No collateral");
        pool.borrow(100 ether);
    }

    function test_PartialRepay() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(500 ether);
        pool.repay(200 ether);
        vm.stopPrank();

        (, uint256 borrowedAmt, ) = pool.positions(user1);
        assertEq(borrowedAmt, 300 ether);
    }

    function test_FullRepay() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(500 ether);
        pool.repay(500 ether);
        vm.stopPrank();

        (, uint256 borrowedAmt, ) = pool.positions(user1);
        assertEq(borrowedAmt, 0);
    }

    function test_WithdrawWhileDebtOutstandingReverts() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(700 ether);

        vm.expectRevert("Health factor too low");
        pool.withdraw(200 ether);
        vm.stopPrank();
    }

    function test_WithdrawAfterRepay() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(500 ether);
        pool.repay(500 ether);
        pool.withdraw(1000 ether);
        vm.stopPrank();

        (uint256 collateralAmt, uint256 borrowedAmt, ) = pool.positions(user1);
        assertEq(collateralAmt, 0);
        assertEq(borrowedAmt, 0);
        assertEq(collateral.balanceOf(user1), 10_000 ether);
    }

    function test_InterestAccrualOverTime() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(500 ether);
        vm.stopPrank();

        uint256 debtBefore = pool.getCurrentDebt(user1);

        vm.warp(block.timestamp + 365 days);

        vm.prank(user1);
        pool.updateInterest();

        uint256 debtAfter = pool.getCurrentDebt(user1);

        assertGt(debtAfter, debtBefore);

        (, uint256 borrowedAmt, ) = pool.positions(user1);
        assertGt(borrowedAmt, 500 ether);
    }

    function test_HealthFactorCalculation() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(500 ether);
        vm.stopPrank();

        uint256 hf = pool.getHealthFactor(user1);

        // HF = (1000 * 0.8) / 500 = 1.6
        assertEq(hf, 1.6e18);
    }

    function test_LiquidationAfterPriceDrop() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(750 ether);
        vm.stopPrank();

        uint256 hfBefore = pool.getHealthFactor(user1);
        assertGt(hfBefore, 1e18); // 800/750 = 1.0666...

        // price drops from 1.0 to 0.9
        pool.setCollateralPrice(0.9e18);

        uint256 hfAfter = pool.getHealthFactor(user1);
        assertLt(hfAfter, 1e18); // 720/750 = 0.96

        uint256 liquidatorBorrowBalanceBefore = borrow.balanceOf(liquidator);
        uint256 liquidatorCollateralBefore = collateral.balanceOf(liquidator);

        vm.prank(liquidator);
        pool.liquidate(user1);

        (, uint256 borrowedAmt, ) = pool.positions(user1);
        assertEq(borrowedAmt, 0);

        assertLt(borrow.balanceOf(liquidator), liquidatorBorrowBalanceBefore);
        assertGt(collateral.balanceOf(liquidator), liquidatorCollateralBefore);
    }

    function test_LiquidationAfterInterestAccrual() public {
        vm.startPrank(user1);
        pool.deposit(1000 ether);
        pool.borrow(750 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 4 * 365 days);

        uint256 hfBeforeAccrual = pool.getHealthFactor(user1);
        assertLt(hfBeforeAccrual, 1e18);

        vm.prank(liquidator);
        pool.liquidate(user1);

        (, uint256 borrowedAmt, ) = pool.positions(user1);
        assertEq(borrowedAmt, 0);
    }
}