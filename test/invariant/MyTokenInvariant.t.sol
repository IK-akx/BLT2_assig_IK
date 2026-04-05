// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MyToken} from "../../src/MyToken.sol";

contract MyTokenInvariantTest is Test {
    MyToken public token;
    address[] public users;

    function setUp() public {
        token = new MyToken();
        
        for(uint i = 0; i < 5; i++) {
            address user = address(uint160(i + 1));
            users.push(user);
            token.mint(user, 1000 ether);
        }
    }

    function invariant_totalSupplyNeverChangesAfterTransfers() public {
        uint256 totalSupplyBefore = token.totalSupply();
        
        for(uint i = 0; i < users.length; i++) {
            for(uint j = 0; j < users.length; j++) {
                if(i != j && token.balanceOf(users[i]) > 0) {
                    uint256 amount = token.balanceOf(users[i]) / 2;
                    if(amount > 0) {
                        vm.prank(users[i]);
                        token.transfer(users[j], amount);
                    }
                }
            }
        }
        
        assertEq(token.totalSupply(), totalSupplyBefore);
    }

    function invariant_noAddressHasMoreThanTotalSupply() public view {
        for(uint i = 0; i < users.length; i++) {
            assertLe(token.balanceOf(users[i]), token.totalSupply());
        }
        assertLe(token.balanceOf(address(this)), token.totalSupply());
        assertLe(token.balanceOf(address(0)), token.totalSupply());
    }
}