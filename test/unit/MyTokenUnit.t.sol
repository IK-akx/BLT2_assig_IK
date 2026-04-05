// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MyToken} from "../../src/MyToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MyTokenUnitTest is Test {
    MyToken public token;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new MyToken();
        token.mint(owner, 1000 ether);
    }

    function testMint() public {
        assertEq(token.balanceOf(owner), 1000 ether);
    }

    function testTransfer() public {
        vm.prank(owner);
        token.transfer(user1, 100 ether);
        assertEq(token.balanceOf(owner), 900 ether);
        assertEq(token.balanceOf(user1), 100 ether);
    }

    function testApprove() public {
        vm.prank(owner);
        token.approve(user1, 200 ether);
        assertEq(token.allowance(owner, user1), 200 ether);
    }

    function testTransferFrom() public {
        vm.prank(owner);
        token.approve(user1, 200 ether);
        vm.prank(user1);
        token.transferFrom(owner, user2, 150 ether);
        assertEq(token.balanceOf(owner), 850 ether);
        assertEq(token.balanceOf(user2), 150 ether);
        assertEq(token.allowance(owner, user1), 50 ether);
    }

    function testTransferInsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 1 ether);
    }

    function testTransferFromInsufficientBalance() public {
        vm.prank(owner);
        token.approve(user1, 100 ether);
        vm.prank(user1);
        vm.expectRevert();
        token.transferFrom(owner, user2, 200 ether);
    }

    function testTransferFromInsufficientAllowance() public {
        vm.prank(owner);
        token.approve(user1, 50 ether);
        vm.prank(user1);
        vm.expectRevert();
        token.transferFrom(owner, user2, 100 ether);
    }

    function testApproveSelf() public {
        vm.prank(owner);
        token.approve(owner, 500 ether);
        assertEq(token.allowance(owner, owner), 500 ether);
    }

    function testZeroAddressTransfer() public {
        vm.prank(owner);
        vm.expectRevert();
        token.transfer(address(0), 100 ether);
    }

    function testMintToZeroAddress() public {
        vm.expectRevert();
        token.mint(address(0), 100 ether);
    }

    function testTransferEvent() public {
        vm.prank(owner);

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user1, 100 ether);

        token.transfer(user1, 100 ether);
    }
}
