// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract ForkTestingTest is Test {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC_WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;
    address constant WETH_WHALE = 0x2F0b23f53734252Bda2277357e97e1517d6B042A;

    uint256 constant FORK_BLOCK = 18500000;
    
    IERC20 public usdc = IERC20(USDC);
    IERC20 public weth = IERC20(WETH);
    IERC20 public dai = IERC20(DAI);
    IUniswapV2Router public router = IUniswapV2Router(UNISWAP_V2_ROUTER);
    
    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createSelectFork(MAINNET_RPC_URL, FORK_BLOCK);
        
        console.log("Fork created with ID:", forkId);
        console.log("Fork block number:", FORK_BLOCK);
        console.log("Current block number:", block.number);
    }
    
    function test_ReadUSDCRealTotalSupply() public {
        uint256 totalSupply = usdc.totalSupply();
        
        console.log("Real USDC total supply on mainnet:");
        console.log("Total supply:", totalSupply);
        console.log("Total supply (formatted):", totalSupply / 1e6, "USDC");
        
        assertGt(totalSupply, 0);
        assertTrue(totalSupply > 10_000_000e6);
    }
    
    function test_SimulateUniswapSwap_USDCtoWETH() public {
        uint256 whaleBalance = usdc.balanceOf(USDC_WHALE);
        console.log("USDC Whale balance:", whaleBalance / 1e6, "USDC");
        assertGt(whaleBalance, 100_000e6);
        
        uint256 amountIn = 1000e6;
        
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;
        
        uint256[] memory expectedAmounts = router.getAmountsOut(amountIn, path);
        uint256 expectedWeth = expectedAmounts[1];
        
        console.log("Swapping 1000 USDC for WETH on Uniswap V2:");
        console.log("Expected WETH out:", expectedWeth / 1e18, "ETH");
        console.log("Expected WETH out (wei):", expectedWeth);
        
        assertGt(expectedWeth, 0, "Expected output should be > 0");
        
        vm.startPrank(USDC_WHALE);
        
        usdc.approve(UNISWAP_V2_ROUTER, amountIn);
        
        uint256 deadline = block.timestamp + 120;
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            1,
            path,
            USDC_WHALE,
            deadline
        );
        
        vm.stopPrank();
        
        assertEq(amounts.length, 2, "Swap should return 2 amounts");
        assertEq(amounts[0], amountIn, "Amount in should match");
        assertGt(amounts[1], 0, "Amount out should be > 0");
        
        console.log("Actual WETH received:", amounts[1] / 1e18, "ETH");
        console.log("Actual WETH received (wei):", amounts[1]);
        console.log("Swap successful!");
    }
    
    function test_SimulateUniswapSwap_WETHtoDAI() public {
        uint256 whaleBalance = weth.balanceOf(WETH_WHALE);
        console.log("WETH Whale balance:", whaleBalance / 1e18, "WETH");
        assertGt(whaleBalance, 100 ether);
        
        uint256 amountIn = 1 ether;
        
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;
        
        uint256[] memory expectedAmounts = router.getAmountsOut(amountIn, path);
        uint256 expectedDai = expectedAmounts[1];
        
        console.log("Swapping 1 WETH for DAI on Uniswap V2:");
        console.log("Expected DAI out:", expectedDai / 1e18, "DAI");
        
        assertGt(expectedDai, 0, "Expected output should be > 0");
        
        vm.startPrank(WETH_WHALE);
        
        weth.approve(UNISWAP_V2_ROUTER, amountIn);
        
        uint256 deadline = block.timestamp + 120;
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            1,
            path,
            WETH_WHALE,
            deadline
        );
        
        vm.stopPrank();
        
        assertEq(amounts.length, 2, "Swap should return 2 amounts");
        assertEq(amounts[0], amountIn, "Amount in should match");
        assertGt(amounts[1], 0, "Amount out should be > 0");
        
        console.log("Actual DAI received:", amounts[1] / 1e18, "DAI");
        console.log("Swap successful!");
    }
    
    function test_ReadUniswapV2Reserves() public {
        address pair = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        
        IUniswapV2Pair uniswapPair = IUniswapV2Pair(pair);
        
        (uint112 reserve0, uint112 reserve1, ) = uniswapPair.getReserves();
        address token0 = uniswapPair.token0();
        address token1 = uniswapPair.token1();
        
        console.log("Uniswap V2 USDC/WETH Pair Reserves at block", FORK_BLOCK);
        
        if (token0 == USDC) {
            console.log("USDC reserve:", reserve0 / 1e6, "USDC");
            console.log("WETH reserve:", uint256(reserve1) / 1e18, "WETH");
            assertGt(reserve0, 0);
            assertGt(reserve1, 0);
        } else {
            console.log("WETH reserve:", uint256(reserve0) / 1e18, "WETH");
            console.log("USDC reserve:", reserve1 / 1e6, "USDC");
            assertGt(reserve0, 0);
            assertGt(reserve1, 0);
        }
    }
    
    function test_ReadRealAddressBalance() public {
        address vitalik = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
        
        uint256 ethBalance = vitalik.balance;
        uint256 usdcBalance = usdc.balanceOf(vitalik);
        
        console.log("Vitalik's ETH balance:", ethBalance / 1e18, "ETH");
        console.log("Vitalik's USDC balance:", usdcBalance / 1e6, "USDC");
    }
}