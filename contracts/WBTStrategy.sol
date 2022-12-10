// SPDX-License-Identifier: Unlicense

pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "./WBTVault.sol";

contract WBTStrategy {
    WBTVault public immutable vault;
    IUniswapV3Pool public immutable pool;
    int24 public immutable tickSpacing;

    int24 public baseThreshold;
    int24 public limitThreshold;
    int24 public maxTwapDeviation;
    uint32 public twapDuration;
    address public keeper;

    uint256 public lastRebalance;
    int24 public lastTick;


    constructor(
        address _vault,
        int24 _baseThreshold,
        int24 _limitThreshold,
        int24 _maxTwapDeviation,
        uint32 _twapDuration,
        address _keeper
    ) {
        IUniswapV3Pool _pool = WBTVault(_vault).pool();
        int24 _tickSpacing = _pool.tickSpacing();

        vault = WBTVault(_vault);
        pool = _pool;
        tickSpacing = _tickSpacing;

        baseThreshold = _baseThreshold;
        limitThreshold = _limitThreshold;
        maxTwapDeviation = _maxTwapDeviation;
        twapDuration = _twapDuration;
        keeper = _keeper;

        _checkThreshold(_baseThreshold, _tickSpacing);
        _checkThreshold(_limitThreshold, _tickSpacing);
        require(_maxTwapDeviation > 0, "maxTwapDeviation");
        require(_twapDuration > 0, "twapDuration");

        (, lastTick, , , , , ) = _pool.slot0();
    }


    function rebalance() external {
        require(msg.sender == keeper, "keeper");

        int24 _baseThreshold = baseThreshold;
        int24 _limitThreshold = limitThreshold;

        int24 tick = getTick();
        int24 maxThreshold =
            _baseThreshold > _limitThreshold ? _baseThreshold : _limitThreshold;
        require(tick > TickMath.MIN_TICK + maxThreshold + tickSpacing, "tick too low");
        require(tick < TickMath.MAX_TICK - maxThreshold - tickSpacing, "tick too high");

        int24 twap = getTwap();
        int24 deviation = tick > twap ? tick - twap : twap - tick;
        require(deviation <= maxTwapDeviation, "maxTwapDeviation");

        int24 tickFloor = _floor(tick);
        int24 tickCeil = tickFloor + tickSpacing;

        vault.rebalance(
            0,
            0,
            tickFloor - _baseThreshold,
            tickCeil + _baseThreshold,
            tickFloor - _limitThreshold,
            tickFloor,
            tickCeil,
            tickCeil + _limitThreshold
        );

        lastRebalance = block.timestamp;
        lastTick = tick;
    }

    function getTick() public view returns (int24 tick) {
        (, tick, , , , , ) = pool.slot0();
    }


    function getTwap() public view returns (int24) {
        uint32 _twapDuration = twapDuration;
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _twapDuration;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgo);
        return int24((tickCumulatives[1] - tickCumulatives[0]) / _twapDuration);
    }

    function _floor(int24 tick) internal view returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--;
        return compressed * tickSpacing;
    }

    function _checkThreshold(int24 threshold, int24 _tickSpacing) internal pure {
        require(threshold > 0, "threshold > 0");
        require(threshold <= TickMath.MAX_TICK, "threshold too high");
        require(threshold % _tickSpacing == 0, "threshold % tickSpacing");
    }

    function setKeeper(address _keeper) external onlyGovernance {
        keeper = _keeper;
    }

    function setBaseThreshold(int24 _baseThreshold) external onlyGovernance {
        _checkThreshold(_baseThreshold, tickSpacing);
        baseThreshold = _baseThreshold;
    }

    function setLimitThreshold(int24 _limitThreshold) external onlyGovernance {
        _checkThreshold(_limitThreshold, tickSpacing);
        limitThreshold = _limitThreshold;
    }

    function setMaxTwapDeviation(int24 _maxTwapDeviation) external onlyGovernance {
        require(_maxTwapDeviation > 0, "maxTwapDeviation");
        maxTwapDeviation = _maxTwapDeviation;
    }

    function setTwapDuration(uint32 _twapDuration) external onlyGovernance {
        require(_twapDuration > 0, "twapDuration");
        twapDuration = _twapDuration;
    }


    modifier onlyGovernance {
        require(msg.sender == vault.governance(), "governance");
        _;
    }
}
