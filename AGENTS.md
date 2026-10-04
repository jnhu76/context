# AGENTS.md

本仓库研究 **最小用户态执行（minimal userspace execution）**：在明确、可检验的执行契约下，寻找实现该契约所需的最小用户态机制闭包，并在证据支持时研究最小的用户态/内核协作边界。

本仓库不是 `boostorg/context` 的 fork，也不以“删薄 Boost.Context”为目标。Boost.Context 是参考实现与机制来源之一；上游必须保持 pristine、固定 SHA，实验只选择实际需要的 source/capability closure。

> P0 只是已完成的 reproducible baseline，不是本仓库长期 scope，也不是后续 agent 的行为边界。

## 1. 研究纪律

所有工作遵循：

```text
observable contract
      ↓
required state / mechanism
      ↓
exact source / capability closure
      ↓
correctness oracle
      ↓
measurement
```

- 先定义仍承诺什么、明确不承诺什么，再讨论实现。
- 优先“从空集向上选择所需闭包”，不要从完整上游向下删代码。
- 代码更少、API 更窄、symbol 更少，都不自动等于语义更低或性能更好。
- 同契约实现优化与缩减契约必须分开报告。
- 每个保留机制都应能对应到契约、反例或平台正确性要求。
- 每个性能结论都必须建立在正确性通过、实验变量可归因的前提上。

## 2. 三类工作不得混淆

1. **Semantic narrowing**：减少行为承诺，例如不支持 migration、forced cancellation。只能说明更窄契约下可以更简单。
2. **Implementation / closure simplification**：相同契约下缩小 source/state/hot-path closure。可以比较同契约实现成本。
3. **Cross-layer cooperation**：用户态向 kernel 提供有限信息并改变 carrier 调度。必须单独测量 kernel policy 本身与跨层信息的增量收益。

“历史包袱”只能作为待验证假设，不能作为删除理由。

## 3. 当前执行边界

初始研究目标为 **Linux x86-64 SysV ABI**。

当前候选契约包括：

- stackful execution，支持普通嵌套调用；
- 仅在显式 `yield` / `wait` 点切换；
- 一个执行体任一时刻最多一个执行者；
- 初始阶段固定 owner worker，worker 是普通 pthread/Linux task；
- 合法暂停点可恢复，局部程序状态保持；
- user body 正常返回后进入 terminal path，终态不得再次 resume；
- stack/control state 只能在安全生命周期点回收；
- wait/register/notify 竞态不能永久丢醒；
- 外部线程可以发布通知，但不能直接恢复目标执行体；
- 数据发布与恢复后的消费必须有明确 happens-before。

默认不承诺 migration、work stealing、抢占式公平、pthread 透明替代、每执行体独立 TLS/errno/signal identity、自动异步化任意阻塞调用、强制取消或完整 I/O/executor 框架。

## 4. 上游与构建

- `third_party/boost-context` 固定到 exact SHA；禁止直接修改、打补丁或在 submodule 中开发。
- Xmake 是本仓库实验代码的统一 build entry。
- 上游 source 必须显式选择，禁止用整树 glob 隐藏真实 closure。
- reference、raw mechanism、实验 closure 必须保持可区分；不要为了方便把它们合并成一个 target。
- 若需要修改底层 primitive，建立独立实验实现并记录 provenance，不修改 pristine upstream。

## 5. 文档也必须被审计

**文档不是事实本身。** Agent 既不能只审代码，也不能把已有文档当作天然正确的 authority。

每次进入一个阶段、issue 或 PR 时：

1. 先读取相关 `CONTRACT / AUDIT / EXPERIMENT / README / issue`；
2. 对照固定 upstream、当前代码、测试、构建产物和实际测量核验关键声明；
3. 标出 stale、重复 authority、与实现不一致、未经证据支持或把 hypothesis 写成 fact 的内容；
4. 修正文档，或显式标记为 draft / hypothesis / non-canonical；
5. 代码或实验改变语义、source closure、测试 oracle、测量方法后，必须反向审计受影响文档。

文档审计至少检查：

- scope 与当前阶段是否一致；
- “提供/不提供”的语义是否与实现和测试一致；
- upstream SHA、source/symbol set、ABI、flags 是否真实；
- benchmark 的计数、计时窗口和归因是否准确；
- 结论是否超出证据，例如把 microbenchmark 写成端到端收益；
- 是否存在多个相互冲突的 authority；
- 旧阶段文档是否错误限制后续阶段。

发现文档与代码冲突时，不得默认代码或文档任一方天然正确；先查证，再确定哪个需要修订。

## 6. 实验路线

总体路线是：

- **E0**：固定契约、upstream、环境和测量条件；
- **E1**：建立未修改 reference 与 correctness harness；
- **E2**：构造并验证最小 source/function/state closure；
- **E3**：加入 FIFO、wait/lifecycle、remote notification、multi-worker 等真实 runtime 语义并做压力实验；
- **E4**：只有 profiling 证明 carrier 的 kernel 调度/唤醒是重要瓶颈后，才进入 eBPF/sched_ext。

E4 中 kernel 的研究对象不是“裁剪 Linux 源码”，而是最小 **hook / helper / state / information closure**。用户态仍负责 fiber/context 的 resume、wait correctness 和 lifetime。

## 7. 测量与停止条件

- correctness build 与 performance build 分开；功能边界必须一致。
- 保存原始结果；控制编译配置、栈策略、CPU placement、warm-up 和有效工作量。
- throughput、CPU time、end-to-end latency、内存、syscall/context-switch 等指标不要互相代替。
- tracing/BPF 打开时的结果不能直接当主性能结果。
- 如果收益只来自放弃行为保证，报告 trade-off，不宣称同语义更快。
- 如果 Boost/raw hot path 已接近 ABI/platform floor 且修改无稳定收益，停止该方向。
- 如果 kernel cooperation 没有独立增量价值，停止增加跨层复杂度。
- correctness/lifetime/wait 无法证明时，暂停性能优化，先修契约或实现。

## 8. Agent 输出要求

每项工作最终必须说明：

- 本次研究/修改属于哪一类；
- 使用了什么 authority 与固定版本；
- 改变了哪些语义、机制或 source/capability closure；
- correctness evidence 是什么；
- 性能结果测量了什么、没有证明什么；
- 哪些文档经过审计并被修正；
- 是否触发停止条件或暴露新的 blocker。

保持 `AGENTS.md` 作为项目级研究治理入口；阶段细节应落在对应 authority 文档中，不要再次把本文件写成某一个 P0/P1 的任务说明。