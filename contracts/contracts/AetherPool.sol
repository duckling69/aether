// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

interface IERC20Metadata {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
}

contract AetherPool is Initializable, OwnableUpgradeable, PausableUpgradeable {
    uint256 public constant BPS_DENOM = 10_000;
    uint256 public constant HEALTH_FACTOR_DECIMALS = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant BASE_CURRENCY_DECIMALS = 8;
    uint256 public constant CLOSE_FACTOR_BPS = 5_000;
    uint256 public constant FULL_LIQUIDATION_HF_THRESHOLD = 0.95e18;
    uint256 public constant MIN_BORROW_AMOUNT = 1e4; // small floor for borrows in demo

    struct AssetConfig {
        bool initialized;
        bool borrowingEnabled;
        bool collateralEnabled;
        uint16 ltv;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        uint16 supplyRateBps;
        uint16 borrowRateBps;
        uint8 decimals;
        uint128 priceUsd;
    }

    struct AggregatedReserveData {
        address asset;
        string name;
        string symbol;
        uint8 decimals;
        bool borrowingEnabled;
        bool collateralEnabled;
        uint16 ltv;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        uint16 supplyRateBps;
        uint16 borrowRateBps;
        uint128 priceUsd;
        uint256 totalSupplied;
        uint256 totalBorrowed;
        uint256 availableLiquidity;
    }

    struct UserReserveData {
        address asset;
        uint256 supplied;
        uint256 currentDebt;
        bool usageAsCollateralEnabled;
    }

    address[] internal reserveList;
    mapping(address => AssetConfig) public reserveConfigs;
    mapping(address => uint256) public totalSupplied;
    mapping(address => uint256) public totalBorrowed;
    mapping(address => mapping(address => uint256)) public userSupplies;
    mapping(address => mapping(address => uint256)) public userDebt;
    mapping(address => mapping(address => uint256)) public debtTimestamp;
    mapping(address => mapping(address => bool)) public collateralDisabled;

    event ReserveInitialized(address indexed asset);
    event PriceUpdated(address indexed asset, uint256 priceUsd);
    event Supply(
        address indexed reserve, address user, address indexed onBehalfOf,
        uint256 amount, uint16 referralCode
    );
    event Withdraw(
        address indexed reserve, address indexed user, address indexed to, uint256 amount
    );
    event Borrow(
        address indexed reserve, address user, address indexed onBehalfOf,
        uint256 amount, uint256 interestRateMode, uint256 borrowRate, uint16 referralCode
    );
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer,
        uint256 amount, bool useATokens
    );
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);
    event LiquidationCall(
        address indexed collateralAsset, address indexed debtAsset, address indexed user,
        uint256 debtToCover, uint256 liquidatedCollateralAmount,
        address liquidator, bool receiveAToken
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
    }

    function initReserve(
        address asset,
        bool borrowingEnabled,
        bool collateralEnabled,
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationBonus,
        uint16 supplyRateBps,
        uint16 borrowRateBps,
        uint128 priceUsd
    ) external onlyOwner {
        require(!reserveConfigs[asset].initialized, "already initialized");
        require(liquidationThreshold >= ltv, "threshold < ltv");
        require(priceUsd > 0, "price required");

        reserveConfigs[asset] = AssetConfig({
            initialized: true,
            borrowingEnabled: borrowingEnabled,
            collateralEnabled: collateralEnabled,
            ltv: ltv,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus,
            supplyRateBps: supplyRateBps,
            borrowRateBps: borrowRateBps,
            decimals: IERC20Metadata(asset).decimals(),
            priceUsd: priceUsd
        });
        reserveList.push(asset);
        emit ReserveInitialized(asset);
    }

    function setAssetPrice(address asset, uint128 priceUsd) external onlyOwner {
        require(reserveConfigs[asset].initialized, "unknown asset");
        require(priceUsd > 0, "price required");
        reserveConfigs[asset].priceUsd = priceUsd;
        emit PriceUpdated(asset, priceUsd);
    }

    function rescue(address asset, uint256 amount, address to) external onlyOwner {
        IERC20Metadata(asset).transfer(to, amount);
    }

    // === Pause controls (added modification) ===
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external whenNotPaused {
        require(reserveConfigs[asset].initialized, "unknown asset");
        require(amount > 0, "zero amount");

        require(
            IERC20Metadata(asset).transferFrom(msg.sender, address(this), amount),
            "transfer failed"
        );
        userSupplies[onBehalfOf][asset] += amount;
        totalSupplied[asset] += amount;

        emit Supply(asset, msg.sender, onBehalfOf, amount, referralCode);
    }

    function withdraw(address asset, uint256 amount, address to) external whenNotPaused returns (uint256) {
        require(reserveConfigs[asset].initialized, "unknown asset");
        uint256 userBalance = userSupplies[msg.sender][asset];
        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;
        require(amountToWithdraw > 0 && amountToWithdraw <= userBalance, "invalid amount");

        userSupplies[msg.sender][asset] = userBalance - amountToWithdraw;
        totalSupplied[asset] -= amountToWithdraw;

        (, uint256 totalDebtBase, , , , uint256 healthFactor) = getUserAccountData(msg.sender);
        require(
            totalDebtBase == 0 || healthFactor >= HEALTH_FACTOR_DECIMALS,
            "HF too low after withdraw"
        );

        require(IERC20Metadata(asset).transfer(to, amountToWithdraw), "transfer failed");
        emit Withdraw(asset, msg.sender, to, amountToWithdraw);
        return amountToWithdraw;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external whenNotPaused {
        AssetConfig storage cfg = reserveConfigs[asset];
        require(cfg.initialized, "unknown asset");
        require(cfg.borrowingEnabled, "borrowing disabled");
        require(amount > 0, "zero amount");
        require(amount >= MIN_BORROW_AMOUNT, "amount below min");
        require(onBehalfOf == msg.sender, "credit delegation unsupported");
        require(IERC20Metadata(asset).balanceOf(address(this)) >= amount, "insufficient liquidity");

        _accrue(msg.sender, asset);
        userDebt[msg.sender][asset] += amount;
        totalBorrowed[asset] += amount;

        (uint256 collateralBase, uint256 debtBase, , , uint256 avgLtv, ) = getUserAccountData(msg.sender);
        require(debtBase * BPS_DENOM <= collateralBase * avgLtv, "exceeds LTV");

        require(IERC20Metadata(asset).transfer(msg.sender, amount), "transfer failed");
        emit Borrow(asset, msg.sender, onBehalfOf, amount, interestRateMode, cfg.borrowRateBps, referralCode);
    }

    function repay(
        address asset,
        uint256 amount,
        uint256,
        address onBehalfOf
    ) external whenNotPaused returns (uint256) {
        require(reserveConfigs[asset].initialized, "unknown asset");

        _accrue(onBehalfOf, asset);
        uint256 debt = userDebt[onBehalfOf][asset];
        require(debt > 0, "no debt");

        uint256 paybackAmount = (amount == type(uint256).max || amount > debt) ? debt : amount;
        require(
            IERC20Metadata(asset).transferFrom(msg.sender, address(this), paybackAmount),
            "transfer failed"
        );

        userDebt[onBehalfOf][asset] = debt - paybackAmount;
        totalBorrowed[asset] = totalBorrowed[asset] >= paybackAmount
            ? totalBorrowed[asset] - paybackAmount
            : 0;

        emit Repay(asset, onBehalfOf, msg.sender, paybackAmount, false);
        return paybackAmount;
    }

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external whenNotPaused returns (uint256, uint256) {
        require(reserveConfigs[collateralAsset].initialized && reserveConfigs[debtAsset].initialized, "unknown asset");
        require(reserveConfigs[collateralAsset].collateralEnabled, "asset not collateral");
        require(!collateralDisabled[user][collateralAsset], "collateral not active");
        require(debtToCover > 0, "zero amount");

        (, uint256 totalDebtBase, , , , uint256 healthFactor) = getUserAccountData(user);
        require(totalDebtBase > 0 && healthFactor < HEALTH_FACTOR_DECIMALS, "HF not below 1");

        _accrue(user, debtAsset);
        uint256 currentDebt = userDebt[user][debtAsset];
        require(currentDebt > 0, "no debt in asset");
        uint256 maxLiquidatable = healthFactor < FULL_LIQUIDATION_HF_THRESHOLD
            ? currentDebt
            : (currentDebt * CLOSE_FACTOR_BPS) / BPS_DENOM;
        uint256 actualDebtToCover = debtToCover > maxLiquidatable ? maxLiquidatable : debtToCover;

        return _executeSeizure(collateralAsset, debtAsset, user, actualDebtToCover, currentDebt, receiveAToken);
    }

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external {
        require(reserveConfigs[asset].initialized, "unknown asset");
        collateralDisabled[msg.sender][asset] = !useAsCollateral;

        if (!useAsCollateral) {
            (, uint256 totalDebtBase, , , , uint256 healthFactor) = getUserAccountData(msg.sender);
            require(totalDebtBase == 0 || healthFactor >= HEALTH_FACTOR_DECIMALS, "HF too low");
            emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
        } else {
            emit ReserveUsedAsCollateralEnabled(asset, msg.sender);
        }
    }

    function getUserAccountData(address user)
        public
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        uint256 weightedLtv;
        uint256 weightedThreshold;

        for (uint256 i = 0; i < reserveList.length; i++) {
            address asset = reserveList[i];
            AssetConfig storage cfg = reserveConfigs[asset];

            uint256 userSupply = userSupplies[user][asset];
            if (userSupply > 0 && cfg.collateralEnabled && !collateralDisabled[user][asset]) {
                uint256 value = (userSupply * cfg.priceUsd) / (10 ** cfg.decimals);
                totalCollateralBase += value;
                weightedLtv += value * cfg.ltv;
                weightedThreshold += value * cfg.liquidationThreshold;
            }

            uint256 debt = _currentDebt(user, asset);
            if (debt > 0) {
                totalDebtBase += (debt * cfg.priceUsd) / (10 ** cfg.decimals);
            }
        }

        if (totalCollateralBase > 0) {
            ltv = weightedLtv / totalCollateralBase;
            currentLiquidationThreshold = weightedThreshold / totalCollateralBase;
        }

        uint256 borrowingPower = (totalCollateralBase * ltv) / BPS_DENOM;
        availableBorrowsBase = borrowingPower > totalDebtBase ? borrowingPower - totalDebtBase : 0;

        if (totalDebtBase == 0) {
            healthFactor = type(uint256).max;
        } else {
            healthFactor =
                (totalCollateralBase * currentLiquidationThreshold * HEALTH_FACTOR_DECIMALS)
                / (totalDebtBase * BPS_DENOM);
        }
    }

    function getReservesList() external view returns (address[] memory) {
        return reserveList;
    }

    function getAllReservesData() external view returns (AggregatedReserveData[] memory data) {
        data = new AggregatedReserveData[](reserveList.length);
        for (uint256 i = 0; i < reserveList.length; i++) {
            address asset = reserveList[i];
            AssetConfig storage cfg = reserveConfigs[asset];
            data[i] = AggregatedReserveData({
                asset: asset,
                name: IERC20Metadata(asset).name(),
                symbol: IERC20Metadata(asset).symbol(),
                decimals: cfg.decimals,
                borrowingEnabled: cfg.borrowingEnabled,
                collateralEnabled: cfg.collateralEnabled,
                ltv: cfg.ltv,
                liquidationThreshold: cfg.liquidationThreshold,
                liquidationBonus: cfg.liquidationBonus,
                supplyRateBps: cfg.supplyRateBps,
                borrowRateBps: cfg.borrowRateBps,
                priceUsd: cfg.priceUsd,
                totalSupplied: totalSupplied[asset],
                totalBorrowed: totalBorrowed[asset],
                availableLiquidity: IERC20Metadata(asset).balanceOf(address(this))
            });
        }
    }

    function getUserReservesData(address user) external view returns (UserReserveData[] memory data) {
        data = new UserReserveData[](reserveList.length);
        for (uint256 i = 0; i < reserveList.length; i++) {
            address asset = reserveList[i];
            data[i] = UserReserveData({
                asset: asset,
                supplied: userSupplies[user][asset],
                currentDebt: _currentDebt(user, asset),
                usageAsCollateralEnabled: !collateralDisabled[user][asset]
            });
        }
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return reserveConfigs[asset].priceUsd;
    }

    function _executeSeizure(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 actualDebtToCover,
        uint256 originalDebt,
        bool receiveAToken
    ) internal returns (uint256, uint256) {
        AssetConfig storage collCfg = reserveConfigs[collateralAsset];
        AssetConfig storage debtCfg = reserveConfigs[debtAsset];

        uint256 debtValueBase = (actualDebtToCover * debtCfg.priceUsd) / (10 ** debtCfg.decimals);
        uint256 collateralToSeize = (debtValueBase * (BPS_DENOM + collCfg.liquidationBonus) * (10 ** collCfg.decimals))
            / (collCfg.priceUsd * BPS_DENOM);

        uint256 userCollateral_ = userSupplies[user][collateralAsset];
        require(userCollateral_ > 0, "no collateral in asset");
        if (collateralToSeize > userCollateral_) {
            collateralToSeize = userCollateral_;
            uint256 seizedValueBase = (collateralToSeize * collCfg.priceUsd) / (10 ** collCfg.decimals);
            actualDebtToCover =
                (seizedValueBase * BPS_DENOM * (10 ** debtCfg.decimals))
                / ((BPS_DENOM + collCfg.liquidationBonus) * debtCfg.priceUsd);
        }

        require(
            IERC20Metadata(debtAsset).transferFrom(msg.sender, address(this), actualDebtToCover),
            "transfer failed"
        );
        userDebt[user][debtAsset] = originalDebt - actualDebtToCover;
        totalBorrowed[debtAsset] = totalBorrowed[debtAsset] >= actualDebtToCover
            ? totalBorrowed[debtAsset] - actualDebtToCover
            : 0;

        userSupplies[user][collateralAsset] = userCollateral_ - collateralToSeize;
        totalSupplied[collateralAsset] -= collateralToSeize;
        require(IERC20Metadata(collateralAsset).transfer(msg.sender, collateralToSeize), "transfer failed");

        emit LiquidationCall(
            collateralAsset, debtAsset, user,
            actualDebtToCover, collateralToSeize, msg.sender, receiveAToken
        );
        return (actualDebtToCover, collateralToSeize);
    }

    function _currentDebt(address user, address asset) internal view returns (uint256) {
        uint256 principal = userDebt[user][asset];
        if (principal == 0) return 0;
        uint256 dt = block.timestamp - debtTimestamp[user][asset];
        uint256 interest = (principal * reserveConfigs[asset].borrowRateBps * dt) / (BPS_DENOM * SECONDS_PER_YEAR);
        return principal + interest;
    }

    function _accrue(address user, address asset) internal {
        uint256 current = _currentDebt(user, asset);
        uint256 principal = userDebt[user][asset];
        if (current > principal) {
            userDebt[user][asset] = current;
            totalBorrowed[asset] += current - principal;
        }
        debtTimestamp[user][asset] = block.timestamp;
    }

    uint256[50] private __gap;
}
