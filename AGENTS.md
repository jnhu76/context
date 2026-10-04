# AGENTS.md

本仓库是独立的执行机制研究仓库，不是 `boostorg/context` 的 fork，也不修改上游。当前阶段仅做 **P0：可复现实验基线**。

## 硬约束

- `third_party/boost-context` 必须固定到明确 SHA；禁止修改、补丁化或复制后改写上游源码。
- Xmake 是唯一实验构建入口；上游源文件必须按 target 显式列出，禁止 glob。
- 仅支持 **Linux x86-64 SysV ABI**。
- R0 与 R1 必须保持独立 target：
  - **R0**：`boost::context::fiber`，作为公共 API / 行为参考。
  - **R1**：原始 `make_fcontext` + `jump_fcontext`；除非正确性明确需要，否则不得引入 `ontop_fcontext`。
- correctness 使用 debug；benchmark 使用 release；P0 禁止 LTO。

## P0 要证明什么

测试应覆盖少量但强的事实：

1. 基本 context transfer；
2. suspend/resume 后局部状态保持；
3. suspend 发生在真实的嵌套调用栈中；
4. context 正常结束后不会再次 resume，且生命周期处理明确；
5. 数千次以上确定性 ping-pong。

Benchmark 只建立可复现基线：warm-up、固定迭代数、wall-clock、每次 transfer 平均成本。**不得据此声称最小语义或优于 Boost.Context。**

## P0 禁止扩展

不要实现 scheduler、ready queue、wait/wakeup、futex、multi-worker、work stealing、migration、自定义 context ABI、寄存器保存集修改、MXCSR/x87/CET/TLS 删除、eBPF、sched_ext 或任何内核调度策略。

## 验证

统一入口：

```sh
./tools/verify/p0.sh
```

必须验证：上游 SHA 与 submodule cleanliness、debug correctness、release benchmark smoke、实际链接到的 fcontext symbols。缺少工具或证据时应失败，不得静默跳过。

## 文档职责

详细事实放在对应 authority 文档，不在本文件重复：

- `docs/UPSTREAM.md`：上游来源、固定 SHA、更新规则；
- `docs/P0-BASELINE.md`：P0 范围、实际 source/symbol、测试与 benchmark；
- `README.md`：最短构建与运行路径。

## 停止条件

遇到以下情况不要绕过：上游 SHA 不可获取、平台不是 Linux x86-64、Xmake 无法构建目标汇编、R1 需要修改上游源码、或 R0 只能通过 vendoring 整个 Boost 才能继续。先报告根因，再决定是否调整 P0。
