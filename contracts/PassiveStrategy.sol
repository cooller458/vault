// SPDX-License-Identifier: Unlicense

pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "./WBTVault.sol";
import "../interfaces/IStrategy.sol";

contract PassiveStrategy is IStrategy {
    using SafeMath for uint256;

    WBTVault public immutable vault;
    IUniswapV3Pool public immutable pool;
    int24 public immutable tickSpacing;

    int24 public baseThreshold;
    int24 public limitThreshold;
    uint256 public period;
    int24 public minTickMove;
    int24 public maxTwapDeviation;
    uint32 public twapDuration;
    address public keeper;

    uint256 public lastTimestamp;
    int24 public lastTick;

    constructor(
        address _vault,
        int24 _baseThreshold,
        int24 _limitThreshold,
        uint256 _period,
        int24 _minTickMove,
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
        period = _period;
        minTickMove = _minTickMove;
        maxTwapDeviation = _maxTwapDeviation;
        twapDuration = _twapDuration;
        keeper = _keeper;

        _checkThreshold(_baseThreshold, _tickSpacing);
        _checkThreshold(_limitThreshold, _tickSpacing);
        require(_minTickMove >= 0, "minTickMove must be >= 0");
        require(_maxTwapDeviation >= 0, "maxTwapDeviation must be >= 0");
        require(_twapDuration > 0, "twapDuration must be > 0");

        (, lastTick, , , , , ) = _pool.slot0();
/
    function rebalance() external override {
        require(shouldRebalance(), "cannot rebalance");

        (, int24 tick, , , , , ) = pool.slot0();
        int24 tickFloor = _floor(tick);
        int24 tickCeil = tickFloor + tickSpacing;

        vault.rebalance(
            0,
            0,
            tickFloor - baseThreshold,
            tickCeil + baseThreshold,
            tickFloor - limitThreshold,
            tickFloor,
            tickCeil,
            tickCeil + limitThreshold
        );

        lastTimestamp = block.timestamp;
        lastTick = tick;
    }

    function shouldRebalance() public view override returns (bool) {
        // check called by keeper
        if (msg.sender != keeper) {
            return false;
        }

        // check enough time has passed
        if (block.timestamp < lastTimestamp.add(period)) {
            return false;
        }

        // check price has moved enough
        (, int24 tick, , , , , ) = pool.slot0();
        int24 tickMove = tick > lastTick ? tick - lastTick : lastTick - tick;
        if (tickMove < minTickMove) {
            return false;
        }

        // check price near twap
        int24 twap = getTwap();
        int24 twapDeviation = tick > twap ? tick - twap : twap - tick;
        if (twapDeviation > maxTwapDeviation) {
            return false;
        }

        // check price not too close to boundary
        int24 maxThreshold = baseThreshold > limitThreshold ? baseThreshold : limitThreshold;
        if (
            tick < TickMath.MIN_TICK + maxThreshold + tickSpacing ||
            tick > TickMath.MAX_TICK - maxThreshold - tickSpacing
        ) {
            return false;
        }

        return true;
    }

    /// @dev Fetches time-weighted average price in ticks from Uniswap pool.
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
        require(threshold > 0, "threshold must be > 0");
        require(threshold <= TickMath.MAX_TICK, "threshold too high");
        require(threshold % _tickSpacing == 0, "threshold must be multiple of tickSpacing");
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

    function setPeriod(uint256 _period) external onlyGovernance {
        period = _period;
    }

    function setMinTickMove(int24 _minTickMove) external onlyGovernance {
        require(_minTickMove >= 0, "minTickMove must be >= 0");
        minTickMove = _minTickMove;
    }

    function setMaxTwapDeviation(int24 _maxTwapDeviation) external onlyGovernance {
        require(_maxTwapDeviation >= 0, "maxTwapDeviation must be >= 0");
        maxTwapDeviation = _maxTwapDeviation;
    }

    function setTwapDuration(uint32 _twapDuration) external onlyGovernance {
        require(_twapDuration > 0, "twapDuration must be > 0");
        twapDuration = _twapDuration;
    }

    modifier onlyGovernance {
        require(msg.sender == vault.governance(), "governance");
        _;
    }
}
