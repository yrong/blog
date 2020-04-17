---
author: Ron
catalog: true
date: 2018-12-12
tags:
- leetcode
title: leetcode-problems
---


# subarray-sum-equals-k
https://leetcode.com/problems/subarray-sum-equals-k/description/

## 题目描述
```
Given an array of integers and an integer k, you need to find the total number of continuous subarrays whose sum equals to k.

Example 1:
Input:nums = [1,1,1], k = 2
Output: 2
Note:
The length of the array is in range [1, 20,000].
The range of numbers in the array is [-1000, 1000] and the range of the integer k is [-1e7, 1e7].

```
## 思路
符合直觉的做法是暴力求解所有的子数组，然后分别计算和，如果等于k,count就+1.这种做法的时间复杂度为O(n^2).

这里有一种更加巧妙的方法，我们可以借助额外的空间，使用hashmap来简化时间复杂度，这种算法的时间复杂度可以达到O(n).

我们维护一个hashmap，hashmap的key为累加值acc，value为累加值acc出现的次数。
我们迭代数组，然后不断更新acc和hashmap，如果acc 等于k，那么很明显应该+1. 如果hashmap[acc - k] 存在，
我们就把它加到结果中去即可。

语言比较难以解释，我画了一个图来演示nums = [1,2,3,3,0,3,4,2], k = 6的情况。

![560.subarray-sum-equals-k](/blog/img/leetcode/560.subarray-sum-equals-k.jpg)

如图，当访问到nums[3]的时候，hashmap如图所示，这个时候count为2.
其中之一是[1,2,3],这个好理解。还有一个是[3,3].

这个[3,3]正是我们通过hashmap[acc - k]即hashmap[9 - 6]得到的。

## 关键点解析

- 可以利用hashmap记录和的累加值来避免重复计算

## 代码

* 语言支持：JS, Python

Javascript Code:

```js
/*
 * @lc app=leetcode id=560 lang=javascript
 *
 * [560] Subarray Sum Equals K
 */
/**
 * @param {number[]} nums
 * @param {number} k
 * @return {number}
 */
var subarraySum = function(nums, k) {
  const hashmap = {};
  let acc = 0;
  let count = 0;

  for (let i = 0; i < nums.length; i++) {
    acc += nums[i];

    if (acc === k) count++;

    if (hashmap[acc - k] !== void 0) {
      count += hashmap[acc - k];
    }

    if (hashmap[acc] === void 0) {
      hashmap[acc] = 1;
    } else {
      hashmap[acc] += 1;
    }
  }

  return count;
};
```

Python Code:

```python
class Solution:
    def subarraySum(self, nums: List[int], k: int) -> int:
        d = {}
        acc = count = 0
        for num in nums:
            acc += num
            if acc == k:
                count += 1
            if acc - k in d:
                count += d[acc-k]
            if acc in d:
                d[acc] += 1
            else:
                d[acc] = 1
        return count
```

# jump-game
https://leetcode.com/problems/jump-game/description/

## 题目描述
```
Given an array of non-negative integers, you are initially positioned at the first index of the array.

Each element in the array represents your maximum jump length at that position.

Determine if you are able to reach the last index.

Example 1:

Input: [2,3,1,1,4]
Output: true
Explanation: Jump 1 step from index 0 to 1, then 3 steps to the last index.
Example 2:

Input: [3,2,1,0,4]
Output: false
Explanation: You will always arrive at index 3 no matter what. Its maximum
             jump length is 0, which makes it impossible to reach the last index.

```

## 思路

这道题目是一道典型的`回溯`类型题目。
思路就是用一个变量记录当前能够到达的最大的索引，我们逐个遍历数组中的元素去更新这个索引。
变量完成判断这个索引是否大于数组下表即可。
## 关键点解析

- 建模 (记录和更新当前位置能够到达的最大的索引即可)

## 代码

* 语言支持: Javascript，Python3

```js

/*
 * @lc app=leetcode id=55 lang=javascript
 *
 * [55] Jump Game
 *
 * https://leetcode.com/problems/jump-game/description/
 *
 * algorithms
 * Medium (31.38%)
 * Total Accepted:    252.4K
 * Total Submissions: 797.2K
 * Testcase Example:  '[2,3,1,1,4]'
 *
 * Given an array of non-negative integers, you are initially positioned at the
 * first index of the array.
 *
 * Each element in the array represents your maximum jump length at that
 * position.
 *
 * Determine if you are able to reach the last index.
 *
 * Example 1:
 *
 *
 * Input: [2,3,1,1,4]
 * Output: true
 * Explanation: Jump 1 step from index 0 to 1, then 3 steps to the last
 * index.
 *
 *
 * Example 2:
 *
 *
 * Input: [3,2,1,0,4]
 * Output: false
 * Explanation: You will always arrive at index 3 no matter what. Its
 * maximum
 * jump length is 0, which makes it impossible to reach the last index.
 *
 *
 */
/**
 * @param {number[]} nums
 * @return {boolean}
 */
var canJump = function(nums) {
  let max = 0; // 能够走到的数组下标

  for(let i = 0; i < nums.length; i++) {
      if (max < i) return false; // 当前这一步都走不到，后面更走不到了
      max = Math.max(nums[i] + i, max);
  }

  return max >= nums.length - 1
};

```
Python3 Code:
```Python
class Solution:
    def canJump(self, nums: List[int]) -> bool:
        """思路同上"""
        _max = 0
        _len = len(nums)
        for i in range(_len-1):
            if _max < i:
                return False
            _max = max(_max, nums[i] + i)
            # 下面这个判断可有可无，但提交的时候数据会好看点
            if _max >= _len - 1:
                return True
        return _max >= _len - 1
```

# 1014. 最佳观光组合

https://leetcode-cn.com/problems/best-sightseeing-pair/description/

## 题目描述

给定正整数数组  A，A[i]  表示第 i 个观光景点的评分，并且两个景点  i 和  j  之间的距离为  j - i。

一对景点（i < j）组成的观光组合的得分为（A[i] + A[j] + i - j）：景点的评分之和减去它们两者之间的距离。

返回一对观光景点能取得的最高分。

示例：

输入：[8,1,5,2,6]
输出：11
解释：i = 0, j = 2, A[i] + A[j] + i - j = 8 + 5 + 0 - 2 = 11

提示：

2 <= A.length <= 50000
1 <= A[i] <= 1000

## 思路

最简单的思路就是两两组合，找出最大的，妥妥超时，我们来看下代码：

```python
class Solution:
    def maxScoreSightseeingPair(self, A: List[int]) -> int:
        n = len(A)
        res = 0
        for i in range(n - 1):
            for j in range(i + 1, n):
                res = max(res, A[i] + A[j] + i - j)
        return res
```

我们思考如何优化。 其实我们可以遍历一遍数组，对于数组的每一项`A[j] - j` 我们都去前面找`最大`的 A[i] + i （这样才能保证结果最大）。

我们考虑使用动态规划来解决, 我们使用 dp[i] 来表示 数组 A 前 i 项的`A[i] + i`的最大值。

```python
class Solution:
    def maxScoreSightseeingPair(self, A: List[int]) -> int:
        n = len(A)
        dp = [float('-inf')] * (n + 1)
        res = 0
        for i in range(n):
            dp[i + 1] = max(dp[i], A[i] + i)
            res = max(res, dp[i] + A[i] - i)
        return res
```

如上其实我们发现，dp[i + 1] 只和 dp[i] 有关，这是一个空间优化的信号。我们其实可以使用一个变量来记录，而不必要使用一个数组，代码见下方。

## 关键点解析

- 空间换时间
- dp 空间优化

## 代码

```python
class Solution:
    def maxScoreSightseeingPair(self, A: List[int]) -> int:
        n = len(A)
        pre = A[0] + 0
        res = 0
        for i in range(1, n):
            res = max(res, pre + A[i] - i)
            pre = max(pre, A[i] + i)
        return res
```

## 小技巧

Python 的代码如果不使用 max，而是使用 if else 效率目测会更高，大家可以试一下。

```python
class Solution:
    def maxScoreSightseeingPair(self, A: List[int]) -> int:
        n = len(A)
        pre = A[0] + 0
        res = 0
        for i in range(1, n):
            # res = max(res, pre + A[i] - i)
            # pre = max(pre, A[i] + i)
            res = res if res > pre + A[i] - i else pre + A[i] - i
            pre = pre if pre > A[i] + i else A[i] + i
        return res
```

# merge-intervals

https://leetcode.com/problems/merge-intervals/description/

## 题目描述
```
Given a collection of intervals, merge all overlapping intervals.

Example 1:

Input: [[1,3],[2,6],[8,10],[15,18]]
Output: [[1,6],[8,10],[15,18]]
Explanation: Since intervals [1,3] and [2,6] overlaps, merge them into [1,6].
Example 2:

Input: [[1,4],[4,5]]
Output: [[1,5]]
Explanation: Intervals [1,4] and [4,5] are considered overlapping.
NOTE: input types have been changed on April 15, 2019. Please reset to default code definition to get new method signature.

```

## 思路

- 先对数组进行排序，排序的依据就是每一项的第一个元素的大小。
- 然后我们对数组进行遍历，遍历的时候两两运算（具体运算逻辑见下）
- 判断是否相交，如果不相交，则跳过
- 如果相交，则合并两项
## 关键点解析

- 对数组进行排序简化操作
- 如果不排序，需要借助一些hack,这里不介绍了

## 代码

* 语言支持: Javascript，Python3

```js


/*
 * @lc app=leetcode id=56 lang=javascript
 *
 * [56] Merge Intervals
 */
/**
 * @param {number[][]} intervals
 * @return {number[][]}
 */

function intersected(a, b) {
  if (a[0] > b[1] || a[1] < b[0]) return false;
  return true;
}

function mergeTwo(a, b) {
  return [Math.min(a[0], b[0]), Math.max(a[1], b[1])];
}
var merge = function(intervals) {
  // 这种算法需要先排序
  intervals.sort((a, b) => a[0] - b[0]);
  for (let i = 0; i < intervals.length - 1; i++) {
    const cur = intervals[i];
    const next = intervals[i + 1];

    if (intersected(cur, next)) {
      intervals[i] = undefined;
      intervals[i + 1] = mergeTwo(cur, next);
    }
  }
  return intervals.filter(q => q);
};
```
Python3 Code:
```Python
class Solution:
    def merge(self, intervals: List[List[int]]) -> List[List[int]]:
        """先排序，后合并"""
        if len(intervals) <= 1:
            return intervals
        
        # 排序
        def get_first(a_list):
            return a_list[0]
        intervals.sort(key=get_first)
        
        # 合并
        res = [intervals[0]]
        for i in range(1, len(intervals)):
            if intervals[i][0] <= res[-1][1]:
                res[-1] = [res[-1][0], max(res[-1][1], intervals[i][1])]
            else:
                res.append(intervals[i])
        
        return res
```
