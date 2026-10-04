# AGENTS.md

本仓库研究 **minimum sufficient execution closure**：在明确 execution contract 下，寻找满足该契约所需的最小用户态语义、机制与状态，并在证据支持时研究最小 kernel capability 与跨层信息。

本仓库不是 `boostorg/context` 的 fork，也不以“删薄 Boost.Context”为目标。Boost.Context 是 pinned、pristine 的参考实现与机制来源；实验从契约出发向上构造所需 closure。

## Authority

开工前按任务范围读取：

1. `AGENTS.md`：执行治理与审计纪律；
2. `docs/RESEARCH-FOUNDATION.md`：长期研究问题、目标契约、closure 框架、阶段与停止条件；
3. `docs/UPSTREAM.md`：upstream pin / immutable / provenance；
4. 对应阶段或实验文档（如 `docs/P0-BASELINE.md`）；
5. 代码、build graph、tests、bench、CI 与原始测量结果。

不要把阶段证据文档当成项目总纲，也不要把 research plan 写成已实现能力。

### Authority 冲突

先区分声明类型：

- **规范性声明**（contract / project decision）：实现不符合时，先判实现 non-conformant；只能通过显式 contract change 修改 authority，不能为了迁就代码静默改文档。
- **描述性声明**（实际 source/symbol、build、benchmark window、测量结果）：以可复现证据为准，修正过期描述。
- **假设/候选**：保持 hypothesis/candidate 身份，直到 correctness 与实验给出证据。

任何冲突都先查证，不默认“代码天然正确”或“文档天然正确”。

## 研究纪律

统一顺序：

```text
observable contract
      ↓
required state / mechanism
      ↓
source / symbol / capability closure
      ↓
correctness oracle
      ↓
measurement
```

- 先定义提供与不提供的行为，再讨论实现。
- 优先从空集向上选择所需 closure，不从完整 upstream 向下删到“看起来最小”。
- source 少、symbol 少、API 窄都不等于 semantic minimum。
- **semantic narrowing**、**same-contract implementation simplification**、**cross-layer cooperation** 必须分开报告。
- 每个保留机制都应对应契约义务、反例或平台正确性要求。
- correctness 先于 performance；microbenchmark 不自动支持端到端结论。

## User / kernel 边界

- User-space 研究 source/function/state/semantic closure；当前目标平台为 Linux x86-64 SysV。
- `third_party/boost-context` 必须保持 pinned、clean、未 patch；需要改 primitive 时，在项目侧建立有 provenance 的独立实验实现。
- Xmake 是实验 build entry；upstream source 显式选择，禁止整树 glob 隐藏 closure。
- Kernel 第一阶段保持 stock Linux。研究对象是 capability / hook / helper(kfunc) / state / information closure，不是裁剪 Linux 源码。
- eBPF/sched_ext 只有在 profiling 证明 carrier scheduling/wakeup 是重要瓶颈后才进入；negative result 是有效结果。

## 文档审计

每个 issue / phase / PR 开始前和结束后都审计相关文档。

至少检查：

- scope、contract、阶段状态是否与当前 revision 一致；
- VERIFIED FACT / CONTRACT / HYPOTHESIS / FUTURE WORK 是否混淆；
- upstream SHA、ABI、source/symbol set、flags 是否真实；
- tests 是否真的证明文档声称的 correctness；
- benchmark 的计数、计时窗口、指标与归因是否准确；
- contract 变更是否传播到所有引用文档；
- 是否存在重复或冲突 authority；
- 旧阶段文档是否错误限制后续工作。

发现漂移时：修正描述、标记 non-conformance / hypothesis，或显式提出 contract change；不要通过改措辞掩盖真实冲突。

## 测量与停止

- correctness build 与 performance build 分开，但行为边界必须一致。
- 固定并记录 upstream、toolchain、ABI、flags、stack policy、CPU placement、warm-up 与 workload。
- 保存原始结果；throughput、CPU time、wall latency、memory、syscall/context-switch 不互相替代。
- tracing/BPF 开启时的成本单独记账。
- 收益若来自放弃保证，只能报告 trade-off。
- ABI/platform floor 已经主导、优化无稳定收益时停止该方向。
- wait/lifetime correctness 无法证明时暂停性能优化。
- cross-layer information 没有独立增量价值时停止增加 kernel 协作复杂度。

## Agent 交付

最终报告至少说明：

- 使用的 authority、revision 与实验身份；
- 修改属于 semantic narrowing、implementation simplification 还是 cross-layer cooperation；
- 改变的 contract / mechanism / closure；
- correctness 与 measurement evidence；
- 文档审计发现与修正；
- 未证明的内容、blocker 与触发的停止条件。

阶段细节放在对应 authority / evidence 文档；**不要再次把 `AGENTS.md` 改写成某个 P0/P1 的任务说明。**