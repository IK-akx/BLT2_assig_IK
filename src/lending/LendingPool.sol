// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LendingPool is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateralToken;
    IERC20 public immutable borrowToken;

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant PRECISION = 1e18;

    uint256 public constant LTV = 7500; // 75%
    uint256 public constant LIQUIDATION_THRESHOLD = 8000; // 80%
    uint256 public constant LIQUIDATION_BONUS = 500; // 5%

    uint256 public baseRate = 200; // 2% annual in bps
    uint256 public slope = 500; // +5% max annual in bps
    uint256 public utilizationTarget = 8000; // 80%

    uint256 public totalCollateral;
    uint256 public totalBorrowed;

    // simple admin-controlled price for collateral in borrow-token units
    // 1e18 = 1 collateral token = 1 borrow token
    uint256 public collateralPrice = 1e18;

    struct Position {
        uint256 collateral;
        uint256 borrowed;
        uint256 lastAccrual;
    }

    mapping(address => Position) public positions;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        uint256 repaidDebt,
        uint256 seizedCollateral
    );
    event CollateralPriceUpdated(uint256 newPrice);

    constructor(address _collateralToken, address _borrowToken) Ownable(msg.sender) {
        require(_collateralToken != address(0), "Zero collateral token");
        require(_borrowToken != address(0), "Zero borrow token");

        collateralToken = IERC20(_collateralToken);
        borrowToken = IERC20(_borrowToken);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        _accrueUserInterest(msg.sender);

        positions[msg.sender].collateral += amount;
        totalCollateral += amount;

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        _accrueUserInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        require(pos.collateral > 0, "No collateral");

        uint256 collateralValue = _collateralValue(pos.collateral);
        uint256 maxBorrow = (collateralValue * LTV) / BASIS_POINTS;
        uint256 newDebt = pos.borrowed + amount;

        require(newDebt <= maxBorrow, "Exceeds LTV");
        require(borrowToken.balanceOf(address(this)) >= amount, "Insufficient pool liquidity");

        pos.borrowed = newDebt;
        totalBorrowed += amount;

        borrowToken.safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        _accrueUserInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        require(pos.borrowed > 0, "No debt");

        uint256 repayAmount = amount > pos.borrowed ? pos.borrowed : amount;

        pos.borrowed -= repayAmount;
        totalBorrowed -= repayAmount;

        borrowToken.safeTransferFrom(msg.sender, address(this), repayAmount);

        emit Repaid(msg.sender, repayAmount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        _accrueUserInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        require(pos.collateral >= amount, "Insufficient collateral");

        uint256 newCollateral = pos.collateral - amount;
        uint256 debt = pos.borrowed;

        if (debt > 0) {
            uint256 hfAfter = _healthFactorFrom(newCollateral, debt);
            require(hfAfter > PRECISION, "Health factor too low");
        }

        pos.collateral = newCollateral;
        totalCollateral -= amount;

        collateralToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function liquidate(address user) external {
        require(user != address(0), "Zero user");

        _accrueUserInterest(user);

        Position storage pos = positions[user];
        require(pos.borrowed > 0, "No debt");
        require(getHealthFactor(user) < PRECISION, "Not liquidatable");

        uint256 debtToRepay = pos.borrowed;

        // collateral to seize = debt value / price, plus liquidation bonus
        uint256 collateralEquivalent = (debtToRepay * PRECISION) / collateralPrice;
        uint256 bonusCollateral = (collateralEquivalent * LIQUIDATION_BONUS) / BASIS_POINTS;
        uint256 collateralToSeize = collateralEquivalent + bonusCollateral;

        if (collateralToSeize > pos.collateral) {
            collateralToSeize = pos.collateral;

            // if user has insufficient collateral, reduce debt repaid proportionally
            uint256 discountedCollateral = (collateralToSeize * BASIS_POINTS) / (BASIS_POINTS + LIQUIDATION_BONUS);
            debtToRepay = (discountedCollateral * collateralPrice) / PRECISION;
        }

        require(debtToRepay > 0, "Nothing to liquidate");

        pos.collateral -= collateralToSeize;
        pos.borrowed -= debtToRepay;

        totalCollateral -= collateralToSeize;
        totalBorrowed -= debtToRepay;

        borrowToken.safeTransferFrom(msg.sender, address(this), debtToRepay);
        collateralToken.safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(user, msg.sender, debtToRepay, collateralToSeize);
    }

    function updateInterest() external {
        _accrueUserInterest(msg.sender);
    }

    function setCollateralPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be > 0");
        collateralPrice = newPrice;
        emit CollateralPriceUpdated(newPrice);
    }

    function getCurrentDebt(address user) public view returns (uint256) {
        Position memory pos = positions[user];
        if (pos.borrowed == 0) return 0;
        if (pos.lastAccrual == 0) return pos.borrowed;

        uint256 timeDelta = block.timestamp - pos.lastAccrual;
        if (timeDelta == 0) return pos.borrowed;

        uint256 rate = getCurrentBorrowRate();
        uint256 interest = (pos.borrowed * rate * timeDelta) / (BASIS_POINTS * 365 days);

        return pos.borrowed + interest;
    }

    function getHealthFactor(address user) public view returns (uint256) {
        Position memory pos = positions[user];
        uint256 debt = getCurrentDebt(user);

        if (debt == 0) return type(uint256).max;

        return _healthFactorFrom(pos.collateral, debt);
    }

    function getCurrentBorrowRate() public view returns (uint256) {
        if (totalCollateral == 0) return baseRate;
        if (totalBorrowed == 0) return baseRate;

        uint256 utilization = (totalBorrowed * BASIS_POINTS) / _collateralValue(totalCollateral);

        if (utilization <= utilizationTarget) {
            return baseRate;
        }

        uint256 excess = utilization - utilizationTarget;
        uint256 variablePart = (slope * excess) / (BASIS_POINTS - utilizationTarget);

        return baseRate + variablePart;
    }

    function _accrueUserInterest(address user) internal {
        Position storage pos = positions[user];

        if (pos.lastAccrual == 0) {
            pos.lastAccrual = block.timestamp;
            return;
        }

        if (pos.borrowed == 0) {
            pos.lastAccrual = block.timestamp;
            return;
        }

        uint256 timeDelta = block.timestamp - pos.lastAccrual;
        if (timeDelta == 0) return;

        uint256 rate = getCurrentBorrowRate();
        uint256 interest = (pos.borrowed * rate * timeDelta) / (BASIS_POINTS * 365 days);

        if (interest > 0) {
            pos.borrowed += interest;
            totalBorrowed += interest;
        }

        pos.lastAccrual = block.timestamp;
    }

    function _collateralValue(uint256 collateralAmount) internal view returns (uint256) {
        return (collateralAmount * collateralPrice) / PRECISION;
    }

    function _healthFactorFrom(uint256 collateralAmount, uint256 debt) internal view returns (uint256) {
        if (debt == 0) return type(uint256).max;

        uint256 collateralValue = _collateralValue(collateralAmount);
        uint256 adjustedCollateral = (collateralValue * LIQUIDATION_THRESHOLD) / BASIS_POINTS;

        return (adjustedCollateral * PRECISION) / debt;
    }
}