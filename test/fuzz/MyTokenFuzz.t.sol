// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MyToken} from "../../src/MyToken.sol";

contract MyTokenFuzzTest is Test {
    MyToken public token;
    address public owner = address(0x123);

    function setUp() public {
        token = new MyToken();
        token.mint(owner, 10000 ether);
    }

    function testFuzz_Transfer(address to, uint96 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != owner);
        vm.assume(amount <= token.balanceOf(owner));
        vm.assume(amount > 0);

        uint256 balanceBefore = token.balanceOf(owner);
        uint256 toBalanceBefore = token.balanceOf(to);

        vm.prank(owner);
        token.transfer(to, amount);

        assertEq(token.balanceOf(owner), balanceBefore - amount);
        assertEq(token.balanceOf(to), toBalanceBefore + amount);
    }

    function testFuzz_TransferFrom(address from, address to, uint96 amount, uint96 allowanceAmount) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);
        vm.assume(amount > 0);
        vm.assume(allowanceAmount > 0);
        
        token.mint(from, 10000 ether);
        
        vm.prank(from);
        token.approve(address(this), allowanceAmount);
        
        vm.assume(amount <= token.balanceOf(from));
        vm.assume(amount <= token.allowance(from, address(this)));
        
        uint256 fromBalanceBefore = token.balanceOf(from);
        uint256 toBalanceBefore = token.balanceOf(to);
        
        token.transferFrom(from, to, amount);
        
        assertEq(token.balanceOf(from), fromBalanceBefore - amount);
        assertEq(token.balanceOf(to), toBalanceBefore + amount);
    }
}