# 研究基础：minimum sufficient execution closure

状态：项目 **长期研究权威（living document）**。

来源：用户提供的《最小用户态执行：从 Boost.Context 到可证伪实验》v0.1，以及后续对 closure construction、Xmake、kernel capability closure 与文档 authority 的修订。

本文件定义研究问题、目标 execution contract、closure 框架、实验阶段、测量纪律与停止条件。它不承担某个 PR/branch 的即时状态记录；阶段是否已完成，应由仓库历史、对应 phase evidence、CI 和实验记录共同证明。

执行治理见 `AGENTS.md`；upstream policy 见 `docs/UPSTREAM.md`；P0 证据见 `docs/P0-BASELINE.md`。

---

## 1. 研究问题

本项目研究 stackful cooperative execution，在给定 observable execution contract 下：

1. user-space 最少必须保留哪些 **semantics**？
2. 哪些 **source / function / state** 足以实现这些 semantics？
3. kernel 最少需要提供哪些 **capabilities**？
4. kernel 最少需要知道多少 **runtime information**？
5. 为维持 correctness，这些状态、同步与成本究竟位于哪一层？

形式化记号只是研究目标，不是已证明的数学下界：

```text
U* = minimum sufficient user-space closure
K* = minimum sufficient kernel capability closure
I* = minimum sufficient cross-layer information
```

任何 “minimum” 结论都必须是：

```text
contract-relative
+ evidence-backed
+ counterexample-supported
+ cost-attributed
```

本项目最多主张相对于当前 contract 的、经反例支持的 minimum candidate；不主张全局最小证明。

---

## 2. 证据等级与 authority 冲突

### 2.1 证据等级

- **A. VERIFIED FACT**：可由当前 revision 的代码、build graph、test、CI、exact upstream source、实际 source/symbol closure 或原始测量直接验证。
- **B. CURRENT CONTRACT / PROJECT DECISION**：人为冻结的研究边界与规范性决定。
- **C. HYPOTHESIS / CANDIDATE**：待验证设计、协议或性能假设。
- **D. FUTURE WORK**：尚未实现或验证的路线。

B/C/D 不得写成 A；research plan 中存在某项能力，不等于项目已经实现该能力。

### 2.2 冲突不是“代码永远赢”

先判断声明属于哪一类：

- **规范性声明**（contract / project decision）：代码不符合时，应判实现 non-conformant；若要改变规范，必须做显式 contract change，并传播到相关文档、test oracle 与实验设计。
- **描述性声明**（实际 source/symbol set、build flags、benchmark 计时窗口、测量结果）：以可复现证据为准，过期文档必须修正。
- **假设/候选**：保持 hypothesis/candidate 身份，直到 correctness 与实验给出足够证据。

文档和代码都不是天然正确。冲突必须先查证，再决定修实现、修描述，还是显式修改 contract。

---

## 3. 三类工作必须分开

| 工作 | 例子 | 能支持的结论 |
|---|---|---|
| 缩减语义（semantic narrowing） | 不支持 migration、forced cancellation | 更窄契约下可以更简单；**不等于**同功能更快 |
| 精简实现（implementation / closure simplification） | 相同契约下缩小 source/state/hot-path closure | 同契约实现成本可能降低 |
| 跨层协作（cross-layer cooperation） | 向 kernel 提供 worker 需求摘要，改变 carrier 调度 | 特定竞争条件下可能存在调度协作收益 |

“历史包袱”只能作为待核验分类，不能作为删除理由。每项能力必须区分：必要语义、可选兼容承诺、实现冗余、调试支持、平台正确性要求。

最低语义不是一张固定寄存器列表。语义描述可观察行为；寄存器、队列、栈、原子变量和 kernel hooks 是实现这些行为的机制与状态。

---

## 4. 方法论：closure construction，而不是 deletion fork

明确拒绝：

```text
Boost.Context
   ↓ delete
   ↓ delete
剩下的就是 minimum
```

统一 pipeline：

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

Boost.Context 是 pinned、pristine 的 upstream mechanism provider / reference substrate，不是项目自己的 runtime。

删除实验仍然有价值，但它只是**反证工具**：

- 对每个保留条款，尝试移除支撑机制并寻找具体 counterexample；
- 对每个保留状态，说明它实现哪个 contract obligation，以及能否由别处推导；
- 若删掉源码只减少未编译/未执行代码，而不改变 binary/hot path，就不能宣称运行时收益。

因此必须区分：

- **semantic closure**：哪些 observable obligations 必须保留；
- **source closure**：哪些 translation units 被选入；
- **symbol/function closure**：最终 artifact 实际依赖哪些 symbols/functions；
- **runtime/state closure**：为 scheduler、wait、lifetime 等新增哪些状态；
- **kernel capability closure**：内核需要提供哪些能力；
- **information closure**：user → kernel 最少要传什么信息。

这些 closure 不是同一个概念，不能互相替代。

---

## 5. 目标 execution contract（B；实现可以暂时落后）

本节是研究目标契约，不是“当前代码已经全部支持”的事实声明。

### 5.1 平台与构建

- Linux x86-64 SysV ABI；其他 ABI 后续单独验证。
- 固定 upstream revision、toolchain、build/link flags 与实验环境。
- Xmake 是项目实验 build entry；upstream source 必须显式选择，禁止整树 glob 隐藏真实 closure。

### 5.2 第一版提供的行为

- 每个执行体具有自己的栈，支持普通嵌套函数调用。
- 只在显式 `yield` / `wait` 位置切换，不提供任意指令位置抢占。
- 一个执行体任一时刻最多一个执行者。
- 初始阶段执行体固定在 owner worker；worker 是普通 pthread/Linux task。
- 从合法暂停点恢复，维持当前 ABI/contract 要求的程序状态。
- user body 可以正常返回；终态对象不得再次 resume；stack/control state 只能在安全生命周期点回收。
- wait/register/notify 竞态不能永久丢失已登记的一次性通知。
- 多线程阶段允许外部线程投递通知，但外部线程不能直接恢复目标执行体。
- 数据发布与恢复后的消费必须存在明确 happens-before。

### 5.3 暂不提供的行为

- 跨 worker migration、work stealing、抢占式公平或 hard realtime deadline。
- POSIX thread API 的透明替代。
- 每个执行体独立的 `thread_local`、`errno` 或 signal identity。
- 任意阻塞库调用自动转换为异步操作。
- 强制取消、强制销毁尚未结束的栈、跨执行体隐式异常传播。
- 完整 I/O、timer、future、channel、lock library 或通用 executor/plugin framework。

TLS 等状态继承 worker；“不虚拟化”不表示相关依赖可以忽略。

异常可以在同一执行体内正常抛出并捕获，但第一版禁止在 catch/stack-unwind 期间切换；不得让应用异常跨 context-switch 边界传播。使用 Boost 后端时还必须遵守其 forced-unwind / lifecycle 约束。

不支持 forced cancellation 意味着：无法按约定结束的执行体可能阻塞 shutdown。第一版只承诺在任务与事件源按约定结束时完成正常关闭。

---

## 6. User-space closure

P0 baseline 定义了两个 reference 层（事实细节见 `docs/P0-BASELINE.md`）：

```text
R0 = boost::context::fiber        # public behavior/reference
R1 = raw fcontext mechanism       # make_fcontext + jump_fcontext baseline
```

后续 user-space closure 应从 obligation 出发构造，而不是复制整个 public API：

```text
U0 = public reference
U1 = raw upstream mechanism
U2 = exact source/function/state closure
U3 = specialized mechanism, only if evidence justifies it
```

例如 `ontop_fcontext`、wrapper、stack traits、allocator policy 是否进入某个候选 closure，都必须回答：

> 哪个 contract obligation 要求它？

R1 的 terminal handoff 只是 harness lifecycle 约定，不代表 raw `fcontext` 已经提供通用 termination/reclamation abstraction。

如果后续需要修改底层 context primitive，不修改 `third_party/boost-context`；在项目侧建立独立 experimental implementation，并记录 upstream provenance、差异与适用 contract。

---

## 7. 执行状态、wait 与 lifetime（C：candidate protocol）

以下状态机来自研究设计，**不是已实现或已验证算法**：

| 起始状态 | 事件 | 结果与约束 |
|---|---|---|
| NEW | owner 发布 | READY；stack 与入口已经有效 |
| READY | worker 取出 | RUNNING；只能取出一次 |
| RUNNING | yield | 保存 context 后重新 READY |
| RUNNING | 准备等待 | PARKING；建立本轮等待身份 |
| PARKING | 通知先到 | 记录已通知，不能让另一线程提前 resume |
| PARKING | 完成切出且尚未通知 | WAITING |
| WAITING | 通知被接受 | READY；一次等待至多入队一次 |
| RUNNING | 入口返回 | TERMINATED；切回 scheduler/owner path 后处理回收 |
| TERMINATED | 外部访问权撤销或排空 | RECLAIMED |

`PARKING` 用来表达关键竞态：通知可能发生在 registration 已完成、但 context 尚未完全切出的窗口。看到“有人等待”不等于另一个线程可以直接 resume 该执行体。

### 7.1 Wait protocol 需要证明的事项

1. 事件源必须有持久状态，通知不能是无记忆的裸 pulse。
2. 每轮等待有独立 identity；重复通知可以合并，但不能重复 enqueue。
3. 定义 registration、commit-to-park、accept notification、cancel/unregister 的 linearization point。
4. registration 与 condition recheck 共同覆盖 wake-before-park。
5. 数据发布与消费使用配对的同步关系，不能只把 state 写成 READY。
6. 外部线程只发布通知；owner worker 完成状态转换与 resume。
7. worker 自身准备进入 kernel sleep 时，还必须处理“检查 inbox → 睡眠”之间的竞态。

第一版 reference protocol 可以使用容易论证的 mutex/sequence design，不强求 lock-free。

### 7.2 Reclamation 需要证明的事项

- generation ID 可以识别 stale notification，但不能单独保护“读取 generation 的那次内存访问”；必须先保证 token/index entry 的 lifetime。
- 可以在执行体结束后保留较小 notification record，等待 producer 撤销访问权后再回收；该内存与同步成本必须计入总成本。
- 把状态从主对象移到旁表，不等于成本消失。

具体实现必须给出操作顺序、内存序和反例测试。

---

## 8. Kernel closure 与 eBPF/sched_ext

Kernel 侧第一阶段保持 **stock Linux**。研究对象不是“删 Linux source”，而是：

```text
kernel capability closure
+ hook closure
+ helper / kfunc closure
+ state closure
+ task-scope closure
+ cross-layer information closure
```

sched_ext/eBPF 只能影响承载 runtime 的 Linux tasks/carrier workers；user-space 仍负责具体 fiber/context 的 resume、wait correctness 与 lifetime。

### 8.1 Cross-layer information ladder（C）

候选可从零信息开始：

```text
I0 = no runtime hint
I1 = runnable bit
I2 = nr_ready
I3 = oldest_ready_timestamp
...
```

问题不是“能传多少”，而是：

> kernel 最少需要知道什么，才能在目标 workload 下产生可重复、可归因的增量价值？

### 8.2 eBPF 的位置

```text
user-space correctness
        ↓
user-space runtime
        ↓
boundary profiling
        ↓
confirm kernel scheduling / wakeup bottleneck
        ↓
eBPF observability
        ↓
conditional sched_ext policy experiment
```

只有 profiling 证明 worker scheduling、wakeup、CPU allocation、oversubscription 或 contention 是重要成本，而且已排除更简单的 user-space/affinity/worker-count 原因后，才进入 sched_ext。

BPF 不负责 C++ stack resume、对象析构、execution-cell lifetime、完整 wait graph；也不预设 BPF 能替代 futex 的 atomic sleep/wake protocol 或 I/O completion transfer。

需求摘要只能影响 scheduling policy，不能成为唯一 wakeup fact。Negative result 是有效研究结果。

### 8.3 sched_ext 对照

至少需要：

```text
K0 = normal Linux scheduler + same userspace runtime
K1 = sched_ext policy without runtime demand information
K2 = same policy + runtime demand information
```

若 `K2` 只优于 `K0`、但与 `K1` 无可靠差异，不能声称 cross-layer information 有价值。

---

## 9. 成本模型与归因

至少分别记录：

- context resume 与 runnable queue 的 user-space cost；
- wait registration、notification publication、synchronization 与 cross-core coherence；
- worker kernel block/wakeup/scheduling；
- stack allocation、virtual reservation、实际 page touch 与 reclamation；
- tracing/BPF execution 与 runtime-summary publication；
- event arrival 到 resume 之间的 queueing delay。

事件到 resume 的 wall-clock latency 不等于 kernel CPU time。syscall 数减少、kernel CPU 减少、p99 降低也不是同一个结论。

BPF 收益按“减少的 scheduling mismatch/communication cost − 新增 BPF execution/state-publication/synchronization cost”理解；这只是 attribution framework，不是已量化模型。

---

## 10. 阶段模型

阶段模型定义工作依赖关系；**本文件不把某阶段写死为当前完成状态**。阶段状态必须由对应 evidence、repository history 与 CI/实验记录证明。

### P0 — Reproducible Baseline

目标：

- pinned pristine Boost.Context 与必要 reference dependencies；
- Xmake build authority；
- public/reference 与 raw mechanism baseline；
- deterministic correctness baseline；
- context-switch benchmark；
- source/symbol visibility。

阶段证据格式见 `docs/P0-BASELINE.md`。

### P1 — User-space Closure

目标：从 execution obligations 出发构造并验证 source/function/state closure。

要求：

- 每个保留 mechanism 对应明确 obligation / platform requirement；
- 每个删除/替换实验有 correctness counterexample 或证据；
- source 与 symbol closure 可审计；
- narrower contract 与 same-contract simplification 分开记录。

### P2 — Minimal User-space Runtime

在 P1 后加入：

- owner worker；
- FIFO ready queue；
- lifecycle；
- explicit yield；
- wait registration；
- wake-before-park correctness；
- termination/reclaim；
- external notification。

复杂 scheduler 不是起步条件。

### P3 — Multi-worker & Boundary Profiling

加入：

- fixed ownership；
- remote notification；
- worker idle park/wakeup（如 futex）；
- CPU affinity；
- oversubscription；
- burst workload。

明确拆分：user queue cost / wait protocol cost / kernel block-wakeup cost / scheduler delay / CPU contention。

### P4 — eBPF Observability

先观察，不改变 scheduler policy。必须量化 tracing 本身的成本，并在主性能结果中关闭观测工具。

### P5 — Conditional sched_ext Experiments

只有 P3/P4 证据证明 kernel scheduling/wakeup 值得干预时才进入。使用 K0/K1/K2 等对照分离 policy change 与 runtime-information cooperation 的收益。

---

## 11. 最小性能矩阵

| workload | 变化轴 | 主要指标 |
|---|---|---|
| 双执行体切换 | 固定有效工作量 | 每次 transfer 成本、指令数 |
| FIFO yield | runnable 数量 2/8/64/1024 | scheduler cost、每任务等待 |
| 本地 wait/notify | early/normal/duplicate notification | registration/resume cost、correctness |
| remote notification | batch 1/8/64；不同 CPU placement | event→resume latency、CPU time |
| large population | total 与 ready 数独立扫描 | metadata、stack RSS/touch、cache、queueing |
| burst completion | burst size 与 queue pressure | p50/p95/p99、最大等待、throughput |
| CPU/wait mix | yield interval 与 worker contention | starvation、tail latency、context switch |

population 初始可取 `10² / 10³ / 10⁴`；确认内存预算后再扩展。百万 stackful execution entities 不是起步条件。

必须区分每个 stack 的 virtual reservation、resident memory 与实际 touched depth；不能把未触及的虚拟地址空间当作完整物理内存成本。

公平性比较必须控制每个任务的有效工作量和让出频率；协作模型无法对永不 yield 的计算承诺有界服务。

---

## 12. 测量纪律

- pilot 阶段每配置至少 5 次独立进程运行；随机化版本顺序，保存每次原始结果。
- 同契约比较必须使用一致 toolchain、build flags、stack policy、warm-up 与有效工作量。
- correctness build 与 performance build 分开，但 observable contract 一致。
- 同时报 throughput、CPU time、end-to-end latency distribution、memory、syscall/context-switch 等；不能互相替代。
- p99 需要足够样本；样本不足时不报告 p999。
- 外部 event generator 同时记录 scheduled send time 与 actual send time，避免系统变慢时生成器同步变慢而掩盖 queueing。
- tracing/sampling 用于解释结果，主性能结果应另测观测关闭版本。
- busy polling、额外 CPU、降低 fairness 换来的收益必须明确归因。

“至少 5% 改善”只能作为早期工程筛选建议，不是理论成功线。应先用不包含优化候选的 pilot 测量 noise，再冻结 threshold；不得看完候选收益后再调门槛。

性能正向结果不足以证明 minimum semantics；仍需要 obligation→mechanism mapping 与 deletion/counterexample evidence。

---

## 13. 停止与收缩条件

| 观察结果 | 决策 |
|---|---|
| Boost/raw hot path 已接近目标 ABI/platform floor，修改无稳定收益 | 停止 context-switch 层优化，保留 upstream backend |
| 性能收益仅来自放弃行为保证 | 报告 contract trade-off，不宣称同语义更快 |
| hot state 减少但总状态/同步增加且无端到端收益 | 撤回或缩小适用场景 |
| large population 的主要成本是 stack 而非 scheduler metadata | 转向 stack strategy，重新定义问题 |
| direct wake 只消除了项目自己新增的冗余层 | 归为工程简化，不包装成新 execution model |
| BPF 只改善无竞争 microbenchmark，或增加总 CPU | 不纳入默认路线 |
| K2 不优于 K1 | 停止增加 runtime-demand information |
| active[K] 损害 cold-queue service 或维护成本抵消收益 | 删除该候选，不继续堆复杂策略 |
| lifecycle/wait correctness 无法在当前 contract 下成立 | 暂停性能实验，修 contract 或实现 |

一个候选失败，不等于整个研究方向失败。若所有 specialized candidate 都无稳定优势，合理终点可以是：复用 Boost.Context/raw mechanism + 薄 runtime adapter。

---

## 14. 文档 authority 与审计

长期职责分离：

```text
AGENTS.md                     -> agent 治理与审计纪律
docs/RESEARCH-FOUNDATION.md   -> 研究问题、目标契约、closure/phase/measurement/stop authority
docs/UPSTREAM.md              -> upstream pin / immutable / provenance / update policy
phase / experiment docs       -> 对应 revision/阶段的 evidence
README.md                     -> 导航与最短上手路径
code/tests/build/raw results  -> 可执行与经验事实
```

未来按需增加，不预建空 authority：

```text
docs/CONTRACT.md       -> 当目标 contract 需要比本文件更精确时建立
docs/EXPERIMENT.md     -> 冻结某一实验的变量、oracle、metric、threshold
docs/CLOSURE-LEDGER.md -> obligation ↔ mechanism ↔ source/symbol/capability evidence
```

每个 issue/phase/PR 开始和结束都要做文档审计：

1. 核对相关 contract、phase evidence、upstream identity 与实验定义；
2. 标出 stale statement、重复 authority、hypothesis-as-fact、未传播的 contract change；
3. 对描述性漂移按事实修文档；
4. 对规范性冲突判定实现 non-conformance 或提出显式 contract change；
5. 代码/实验改变 source closure、test oracle 或 measurement window 后，反向审计所有引用文档。

---

## 15. 一手资料与证据边界

以下资料只支持 capability/behavior boundary，不支持本文性能假设已经成立。正式实验必须固定具体 revision；`latest` / `develop` 只用于定位。

- [S1] Boost.Context — Overview: <https://www.boost.org/doc/libs/latest/libs/context/doc/html/context/overview.html>
- [S2] Boost.Context — Context switching with fibers: <https://www.boost.org/doc/libs/latest/libs/context/doc/html/context/ff.html>
- [S3] Linux — eBPF verifier: <https://docs.kernel.org/bpf/verifier.html>
- [S4] Linux — Extensible Scheduler Class: <https://docs.kernel.org/scheduler/sched-ext.html>
- [S5] Boost.Context x86-64 SysV jump assembly: <https://github.com/boostorg/context/blob/develop/src/asm/jump_x86_64_sysv_elf_gas.S>

本文件中的状态机、wait/lifetime protocol、information ladder、specialized ABI、eBPF/sched_ext 路线与性能 matrix 都属于研究设计或候选，除非对应 phase evidence 明确证明，否则不得升级为 VERIFIED FACT。
