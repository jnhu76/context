# 研究基础：minimum sufficient execution closure

状态：项目 **长期研究权威（living document）**。
最后与代码对齐：2026-10-04（P0 baseline，见 `docs/P0-BASELINE.md`）。
来源：用户提供的《最小用户态执行：从 Boost.Context 到可证伪实验》v0.1，以及本轮
Repository-wide Research Foundation & Documentation Authority Audit 的修订。

本文件回答：我们研究什么；哪些已被证明；哪些仍是假设；user-space 与 kernel-space 分别如何
寻找 minimum sufficient closure；当前阶段在哪里；什么条件下进入下一阶段；文档/代码/实验
不一致时如何处理。**执行纪律与治理见 `AGENTS.md`；upstream policy 见 `docs/UPSTREAM.md`。**

---

## 0. 一句话

在明确 execution contract 下，通过可验证的 **closure construction** 与反例实验，寻找
minimum sufficient 的 execution semantics、mechanisms、kernel capabilities 与 cross-layer
information。任何 "minimum" 结论都是 **contract-relative + evidence-backed +
counterexample-supported + cost-attributed**。

---

## 1. 研究问题

对 stackful cooperative execution，在给定 observable execution contract 下：

1. user-space 最少必须保留哪些 **semantics**？
2. 哪些 **source/function/state** 足以实现这些 semantics？
3. kernel 最少需要提供哪些 **capabilities**？
4. kernel 最少需要知道多少 **runtime information**？
5. 为维持 correctness，这些状态与成本究竟位于哪一层？

形式化候选（不是已证明的数学下界）：

```text
U* = minimum sufficient user-space closure
K* = minimum sufficient kernel capability closure
I* = minimum sufficient cross-layer information
```

本文件只主张 **contract-relative、counterexample-supported 的 minimum candidate**，不主张
全局最小证明。

---

## 2. 三种必须分开的工作

| 工作 | 例子 | 能支持的结论 |
|---|---|---|
| 缩减语义（semantic narrowing） | 不支持 migration、forced cancellation | 更窄契约下可以更简单；**不等于**同功能更快 |
| 精简实现（implementation / closure simplification） | 相同契约下消除重复状态、缩小 source/hot-path closure | 存在实现或状态布局收益 |
| 跨层协作（cross-layer cooperation） | 向内核提供 worker 需求摘要，改变 carrier 调度 | 特定竞争条件下存在调度协作收益 |

"历史包袱"只是待核验分类，**不能作为删减理由**。每项能力需区分：必要语义、可选兼容承诺、
实现冗余、调试支持、平台正确性要求。最低语义不是固定的寄存器列表；语义描述**可观察行为**，
寄存器、队列、栈和原子变量是实现这些行为的状态。

---

## 3. 方法论：closure construction（不是 deletion fork）

**明确拒绝**以下方法：

```text
Boost.Context → delete → delete → 剩下的就是 minimum
```

正确 pipeline（与 `AGENTS.md` §1 一致）：

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

逐项删除（deletion）不是方法本身，只是 closure 的**反证手段**：

- 对每个**保留条款**，需要"删除后"的具体反例；
- 对每个**保留状态**，需要解释它实现哪个条款，以及是否可由别处推导。

由此得到相对当前契约、经反例支持的最小候选，而非绝对最小证明。删掉源码、模板或未编译的
平台文件，不必然减少每次切换的指令；必须同时观察反汇编、实际执行路径与测量结果。

---

## 4. 证据等级

- **A. VERIFIED FACT**：可由当前代码、build graph、test、CI、exact upstream source、实际
  symbol/source closure 直接验证。
- **B. CURRENT CONTRACT / PROJECT DECISION**：人为冻结的研究边界。
- **C. HYPOTHESIS / CANDIDATE**：待验证；必须写成 candidate / hypothesis / proposed protocol /
  to be validated。
- **D. FUTURE WORK**：尚未实现或验证。

规则：B/C/D 不得写成 A；research plan 中存在某物，不等于项目已支持该物。

---

## 5. Execution contract（当前冻结）

### 5.1 平台与构建（B）

- Linux x86-64 SysV ABI，固定编译器与构建配置；其他 ABI 后续单独验证。
- Xmake 为 build authority；upstream 以 pinned submodule 提供（见 `docs/UPSTREAM.md`）。

### 5.2 提供的承诺（B，第一版目标）

- 每个执行体具有自己的栈，支持普通嵌套函数调用。
- 只在显式 yield/wait 位置切换，不提供任意指令位置抢占。
- 执行体固定在所属 worker 上；worker 由正常 pthread/Linux task 承载。
- 可以正常返回并回收；不能恢复已结束执行体（terminal path 不得再次 resume）。
- 等待协议不丢失已登记的一次性事件通知。
- 多线程阶段允许外部线程发通知；外部线程不能直接恢复目标执行体。
- 完成事件的发布与消费有明确 happens-before 关系。

### 5.3 暂不提供的承诺（B）

- 跨 worker 迁移、工作窃取、抢占式公平性或硬实时期限。
- POSIX thread API 的透明替代。
- 每个执行体独立的 `thread_local`、`errno` 或 signal identity。
- 任意阻塞库调用自动转为异步操作。
- 强制取消、强制销毁尚未结束的栈、跨执行体隐式异常传播。
- 完整 I/O、定时器、future、channel、锁库或通用调度插件体系。

TLS 等状态继承 worker 的行为；"不虚拟化"不表示可以无视相关依赖。异常允许在同一执行体内
正常抛出并捕获，但第一版禁止在 catch/展开期间切换；不得让异常越过上下文切换边界。使用
Boost 后端时还必须遵守其 forced-unwind 要求。

不支持强制取消意味着：不能完成的执行体可能使正常关闭无法完成。第一版只承诺在所有任务与
事件源按约定结束时完成 shutdown，不伪造"任意程序均可有界关闭"的保证。

---

## 6. Closure 框架（统一 user / kernel / cross-layer）

### 6.1 User-space closure

从 R1（raw mechanism）出发，逐级构造：

```text
U0 = reference public abstraction   (boost::context::fiber，行为参照)
U1 = raw upstream mechanism          (make_fcontext + jump_fcontext)
U2 = exact upstream source/function closure
U3 = specialized mechanism           (仅当证据支持)
```

必须区分三种 closure，不能混为一谈：

- **source closure**：哪些 translation units 被取用。
- **symbol/function closure**：最终 artifact 实际依赖哪些 symbols/functions。
- **semantic closure**：这些 mechanism 支撑哪些 observable obligations。

**不得仅因 source 少就宣称 semantic minimum。**

### 6.2 Kernel-space closure（不是删 Linux）

Kernel 侧的研究对象**不是** "Linux source function deletion"。第一阶段 kernel 保持
**stock Linux**。kernel closure 定义为：

```text
kernel capability closure
+ hook closure
+ helper / kfunc closure
+ state closure
+ cross-layer information closure
```

以后 sched_ext 实验可研究：Ops closure、helpers/kfunc closure、BPF state closure、task scope。
用户态仍负责 fiber/context 的 resume、wait correctness 和 lifetime。

### 6.3 Cross-layer information closure

user-space → kernel 的候选信息级别：

```text
I0 = no runtime hint
I1 = runnable bit
I2 = nr_ready
I3 = oldest_ready timestamp
...
```

目标不是尽可能多地使用 eBPF，而是回答：**kernel 最少需要知道什么？**

### 6.4 三者关系

source/function/symbol closure 描述"实现由什么构成"；semantic closure 描述"支撑哪些承诺"；
kernel capability closure 描述"内核提供什么机制"；cross-layer information closure 描述
"内核需要知道什么"。四者共同回答 §1 的五个问题，缺一不可。

---

## 7. Boost.Context 的定位

Boost.Context 提供执行上下文转移，可作为协作式用户态线程的基础；它本身不是带完整调度策略
的线程运行时。因此本项目不能预设它已经包含 promise、通用 executor、完整等待图等"可删除层"。

Boost.Context 在本项目中的角色是 **upstream mechanism provider / immutable experimental
substrate**，不是我们自己的 runtime。upstream 以 pristine、pinned submodule 提供，禁止修改
（见 `docs/UPSTREAM.md`）。当前已存在两个 reference（P0 阶段证据）：

```text
R0: boost::context::fiber
R1: raw make_fcontext + jump_fcontext
```

P1 从 R1 出发构造 user-space closure。R1 的 terminal handoff 是 harness lifecycle 约定，
不是"raw fcontext 提供通用 termination/reclamation 抽象"的声明。

---

## 8. 执行状态与关键竞态（candidate protocol，未实现）

以下状态机是**研究候选**，不是已验证算法。实现可以合并编码，但必须解释各个转换。

| 起始状态 | 事件 | 结果与约束 |
|---|---|---|
| NEW | 所有者发布 | READY；栈与入口已经有效 |
| READY | worker 取出 | RUNNING；只能取出一次 |
| RUNNING | yield | 保存上下文后重新 READY |
| RUNNING | 准备等待 | PARKING；建立本轮等待身份 |
| PARKING | 通知先到 | 记录已通知，不能让另一线程提前恢复 |
| PARKING | 完成切出且尚未通知 | WAITING |
| WAITING | 通知被接受 | READY；一次等待至多入队一次 |
| RUNNING | 入口返回 | TERMINATED；切回调度栈后处理回收 |
| TERMINATED | 外部访问权全部撤销或排空 | RECLAIMED |

`PARKING` 特别重要：通知可能发生在等待登记完成、但寄存器与栈尚未完成切出的时候。唤醒方不能
因为看到"有人等待"就立即交给另一个执行者。第一版允许使用容易论证的互斥/序号协议作为
correctness reference，不强求 lock-free。

### 8.1 等待协议应明确的事项（proposed protocol）

1. 事件源先有持久状态，通知不是没有记忆的裸脉冲。
2. 每轮等待有独立身份；重复通知可以合并，但不能重复排队。
3. 定义登记、提交挂起、接受通知和撤销登记各自的线性化点。
4. 登记与条件复查共同覆盖 wake-before-park。
5. 数据发布使用与消费配对的同步关系，不能只将状态变量设为 READY。
6. 外部线程只投递通知；由 owner worker 完成状态转换与恢复。
7. worker 自身准备睡眠时，也需要单独处理"检查 inbox 与进入内核等待"之间的竞态。

### 8.2 回收协议应明确的事项（proposed protocol）

- 代际 ID 可以识别陈旧通知，但**不能单独保护**读取 generation 的那次内存访问；必须先保证
  token/索引表仍然有效，或使用受保护的间接访问。
- 结束后可先保留小型通知记录，待生产者释放通知权后再回收；其内存与同步开销必须计入总成本。
  不能把这些记录移出 Cell 后宣称开销已删除。

以上均为**协议要求**，不是已验证算法；实现阶段必须给出具体操作和内存序。

---

## 9. 成本模型与归因

至少分开记录：

- 用户态恢复和 runnable 队列成本；
- 等待登记、通知投递、同步与跨核一致性成本；
- worker 内核阻塞、唤醒及调度成本；
- 栈分配、页面实际触及和回收成本；
- tracing、BPF 程序及需求摘要传输成本；
- 事件发生后排队等待的时间。

事件到恢复的墙钟延迟 ≠ 内核 CPU 时间。syscall 变少、内核 CPU 变少、p99 变低不是同一件事。

BPF 收益按"减少的调度失配与通信成本，减去新增 BPF 执行、状态发布及同步成本"理解。该式只是
**归因框架，不是已量化模型**。端到端延迟和资源用量必须同时验证。

---

## 10. 阶段模型（修订旧 E0–E4 → P0–P5）

> 修订说明：附件旧 E1 直接进入 FIFO/wait runtime；本修订在 reference baseline 与 runtime
> 之间插入 **P1 user-space closure**。旧 E2"逐项删减 Boost"改为 closure construction。

### P0 — Reproducible Baseline（已完成）

- pinned pristine Boost.Context；Xmake；R0/R1；correctness baseline；switch benchmark；
  symbol/source visibility。
- **这是历史/阶段证据，不是整个项目的长期 scope。**
- 证据：`docs/P0-BASELINE.md`、`tools/verify/p0.sh`。

### P1 — User-space Closure（下一步，未开始）

- 目标：从 execution obligations 出发构造最小 source/function/symbol closure。
- 研究对象：`make_fcontext` / `jump_fcontext` / `ontop_fcontext?` / wrapper? / stack traits?
- 每个加入的 mechanism 必须回答：**哪个 contract obligation 要求它？**
- 每个移除必须有 correctness counterexample 或证据。
- 输出：closure ledger（候选，未来 `docs/CLOSURE-LEDGER.md`）+ correctness oracle。

**Exit criteria**：每个保留/移除项都有 obligation 说明或反例；closure 有 symbol/source 证据。

### P2 — Minimal User-space Runtime（未开始）

- owner worker、FIFO ready queue、lifecycle、explicit yield、wait registration、
  wake-before-park correctness、termination/reclaim、external notification。
- 不能提前假定复杂 scheduler。

**Exit criteria**：§8 的等待/回收协议在可控竞态下 correctness 成立。

### P3 — Multi-worker & Boundary Profiling（未开始）

- fixed ownership、remote notification、futex worker sleep/wake、CPU affinity、
  oversubscription、burst workload。
- 明确拆分：userspace queue cost / wait protocol cost / kernel block-wakeup cost /
  scheduler delay / CPU contention。

**Exit criteria**：成本按层归因；确认是否存在内核调度/唤醒瓶颈。

### P4 — eBPF Observability（未开始）

- 先观察，不改变调度策略。只有 profiling 已证明值得继续才进入。

**Exit criteria**：观测本身成本已测量，且不改变主性能结论。

### P5 — Conditional sched_ext Experiments（未开始）

对照至少：

```text
K0 = normal Linux scheduler
K1 = sched_ext without runtime demand information
K2 = same policy + minimum runtime demand information
```

若 `K2 ≈ K1`，**不能**声称 cross-layer information 有价值。

---

## 11. eBPF / sched_ext 的严格位置

eBPF 不是项目起点。必须保持以下纪律：

```text
user-space correctness
        ↓
user-space runtime
        ↓
boundary profiling
        ↓
confirm kernel scheduling/wakeup bottleneck
        ↓
eBPF observability
        ↓
sched_ext policy experiment
```

只有 profiling 证明 worker scheduling / wakeup / CPU allocation / oversubscription /
contention 确实形成重要成本后，才能进入 sched_ext。**不得为了"项目需要 kernel 创新"而人为
制造 sched_ext 工作。Negative result 是合法结果。**

eBPF 不把 C++ 栈恢复、对象析构、Cell 生命周期、完整等待图和逐 Cell 调度搬进内核；也不预设
BPF 可以无成本替代 futex 的原子等待协议或 I/O 完成传输。需求摘要只能影响策略，**不能成为
唯一唤醒事实**。

---

## 12. 测量：最小性能矩阵与纪律

### 12.1 最小性能矩阵

| workload | 变化轴 | 主要指标 |
|---|---|---|
| 双执行体切换 | 固定有效工作量 | 每次转移成本、指令数 |
| FIFO yield | runnable 数量 2/8/64/1024 | 调度成本、每任务等待 |
| 本地等待/通知 | 早到/正常/重复通知 | 登记与恢复成本、正确性 |
| 远程通知 | 批量 1/8/64；不同 CPU 放置 | 事件到恢复延迟、CPU 时间 |
| 大 population | 总数与 ready 数独立扫描 | 元数据、栈驻留、cache、排队延迟 |
| 突发完成 | 突发大小与队列压力 | p50/p95/p99、最长等待、吞吐 |
| CPU/等待混合 | yield 间隔与 worker 竞争 | 饥饿、尾延迟、上下文切换 |

population 初始可取 10²/10³/10⁴；确认内存预算后再扩展。百万有栈执行体不是起步条件。必须报告
每个栈的**虚拟保留、实际驻留和触及深度**，不能把未触及的虚拟栈当作完整内存成本。公平性比较
要控制每个任务的有效工作量和让出频率；显式协作模型不能对永不让出的计算承诺有界服务。

### 12.2 测量纪律与判定

- 初始每配置至少 5 次独立进程运行，随机化版本顺序，保存每次原始结果。
- 使用相同编译配置、栈策略、预热与有效工作量；特殊构建单列。
- correctness 构建与性能构建分开，二者功能边界一致。
- 同时报 throughput、CPU 时间、端到端延迟分布、内存及 syscall/context-switch 计数。
- p99 必须有足够样本；样本不足时不报告 p999。
- 外部事件负载记录计划发出时间与实际发出时间，避免系统变慢后生成器也变慢而掩盖排队。
- 通过跟踪或采样解释收益，但主性能结果另测观测工具关闭的版本。
- busy polling、额外 CPU 和减少公平性造成的收益，必须显式归因。

工程筛选阈值（起步建议，非冻结成功线）：目标指标改善至少 5% 且大于重复运行噪声；共同契约下
的关键尾延迟/CPU/内存不得发生超过预先声明容忍度的回退。先用不含优化候选的 pilot 确认测量
精度，再冻结阈值；**不得看过收益后调线**。

性能正向结果还不足以证明"最低语义"：对每个保留条款需要删除后的具体反例；对每个保留状态
需要解释它实现哪个条款，以及是否可由别处推导。

---

## 13. 停止与收缩条件

| 观察结果 | 决策 |
|---|---|
| Boost/raw 热路径已接近目标 ABI 所需，删改无稳定收益 | 停止切换层优化，保留原后端 |
| 性能收益仅来自放弃行为保证 | 报告契约取舍，不宣称同语义更快 |
| 热状态减少但总状态/同步成本增加且无端到端收益 | 撤回布局优化或缩小适用场景 |
| 大 population 的主要成本是栈，而非调度元数据 | 转向栈策略研究，重新定义问题 |
| direct wake 收益仅来自去掉自行添加的冗余层 | 归为工程简化，不包装成新模型 |
| BPF 只改善无竞争微基准，或增加总 CPU 消耗 | 不纳入默认方案 |
| K2 不优于 K1 | 停止需求摘要协作，保留对策略的独立结论 |
| active[K] 损害冷队列服务或收益被维护成本抵消 | 删除该结构，不继续补复杂策略 |
| 无法在既定兼容边界内保证生命周期/等待正确性 | 暂停性能实验，修订契约或实现 |

一个优化失败，不等于整个用户态执行方向失败。应停止的是被否定的假设；若所有候选都无优势，
合理终点是复用 Boost.Context 加薄适配层。

---

## 14. 已证明 / 未证明（关键）

### 14.1 已验证事实（A，P0 证据）

- upstream SHA 已 pin 且 pristine（submodule working tree clean）。
- Xmake 在 Linux x86-64 SysV 上独立构建 R0 与 R1。
- R0/R1 correctness C-01…C-05 通过。
- R0/R1 的 exact source set 与 symbol set 已知并可审计（`tools/verify/symbols.sh`）。
- 存在可复现的 ping-pong benchmark 与 environment manifest。
- **不存在** scheduler / runtime / wait / eBPF / sched_ext。

### 14.2 当前 contract / 项目决定（B）

平台、Xmake authority、upstream immutable、owner-worker、no migration、cooperative stackful、
第一版 FIFO、异常不得越过切换边界、shutdown 前提。

### 14.3 假设 / 候选（C，**不得写成结论**）

- `make_fcontext + jump_fcontext` 是否足以支撑最小 closure。
- `ontop_fcontext` 的必要性。
- Boost.Context wrapper 是否存在稳定可测的 overhead。
- `PARKING` 协议形态、generation token 必要性、`active[K]` 价值。
- runnable bit / nr_ready / oldest_ready 的充分性。
- sched_ext 是否有收益；specialized context ABI 是否能变快。

### 14.4 未来工作（D）

runtime wait protocol、multi-worker、remote wake、eBPF、sched_ext、cross-layer demand summary、
specialized context ABI。

---

## 15. 文档 authority 与产物

当前 authority 结构：

```text
AGENTS.md                    → agent 执行治理入口
docs/RESEARCH-FOUNDATION.md  → 长期研究权威（本文件）
docs/UPSTREAM.md             → upstream policy（pin / immutable / provenance / 更新）
docs/P0-BASELINE.md          → P0 阶段证据（不是项目总纲）
README.md                    → 导航 / 上手
```

未来按需增加，**不预建空文件**：

```text
docs/CONTRACT.md         → 精确的 provide / not-provide / error / shutdown 前提
docs/EXPERIMENT.md       → 共同契约、变量、指标与冻结判定线
docs/CLOSURE-LEDGER.md   → source/function/semantic/kernel/information closure 账本
```

### 文档/代码/实验冲突的处理

1. 先确认可执行事实（代码、build graph、test、symbol）。
2. 若文档与事实冲突：修文档，不改事实。
3. 若权威文档之间冲突：以更接近事实来源的文档为准，并消除另一处的错误表述。
4. 若 contract 变更：显式标记为 contract change，并传播到所有引用它的文档。

---

## 16. 一手资料与证据边界

以下资料支持**能力边界**，不支持本文提出的性能假设已经成立。链接中的 latest/develop 为移动
目标，正式实验必须固定版本（见 `docs/UPSTREAM.md`）。

- [S1] Boost.Context — Overview：上下文转移的用途与基础库定位。
- [S2] Boost.Context — Context switching with fibers：恢复、句柄、栈与异常相关 API 行为。
- [S3] Linux — eBPF verifier：验证器与受限执行接口；不据此假定任意内核功能都能被替代。
- [S4] Linux — Extensible Scheduler Class：BPF 调度接口、作用范围、回退与 ABI 不稳定性。
- [S5] Boost.Context — x86-64 SysV jump assembly：后续固定版本源码审计入口；未据此宣告任何
  寄存器可删。

本文件中的语义划分、状态机、closure 账本、实验矩阵与停止条件均为**研究方案**，需要实现、
反例分析与测量验证。**尚未声称正确性 PASS、性能改善、绝对语义下界或论文创新性。**
