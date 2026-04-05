// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LPToken is ERC20 {
    address public amm;
    
    modifier onlyAmm() {
        require(msg.sender == amm, "Only AMM can mint/burn");
        _;
    }
    
    constructor() ERC20("AMM Liquidity Provider Token", "AMM-LP") {}
    
    function setAmm(address _amm) external {
        require(amm == address(0), "AMM already set");
        amm = _amm;
    }
    
    function mint(address to, uint256 amount) external onlyAmm {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external onlyAmm {
        _burn(from, amount);
    }
}