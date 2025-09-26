// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Math
/// @notice 基础数学运算库
/// @dev 提供常用的数学函数，如最小值、最大值、绝对差值等
library Math {
    /// @notice 返回两个数中的较小值
    /// @param a 第一个数
    /// @param b 第二个数
    /// @return 较小的数
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;  // 如果a小于b，返回a，否则返回b
    }

    /// @notice 返回两个数中的较大值
    /// @param a 第一个数
    /// @param b 第二个数
    /// @return 较大的数
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;  // 如果a大于b，返回a，否则返回b
    }

    /// @notice 返回两个数的绝对差值
    /// @param a 第一个数
    /// @param b 第二个数
    /// @return 绝对差值
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;  // 返回|a - b|
    }

    /// @notice 检查点是否在模N的闭区间内
    /// @dev 这个函数处理环形区间的情况，用于快速通道成员选择
    /// @param point 要检查的点
    /// @param left 区间左端点
    /// @param right 区间右端点
    /// @param n 模数
    /// @return 是否在区间内
    function pointInClosedIntervalModN(uint256 point, uint256 left, uint256 right, uint256 n)
        internal pure returns (bool)
    {
        // 将所有值规范化到[0, n)范围内
        point = point % n;
        left = left % n;
        right = right % n;
        
        if (left <= right) {
            // 正常情况：区间不跨越边界
            return left <= point && point <= right;
        } else {
            // 环形情况：区间跨越边界
            return point >= left || point <= right;
        }
    }
} 