# AGENTS.md

`jnhu76/context` is an **independent research repo**, not a fork of `boostorg/context`
and not a Boost.Context replacement. It is a reproducible execution-mechanism research
harness. The current phase is **P0 (reproducible baseline only)** — do not build P1+ yet.

## Non-negotiable rules

**Upstream is immutable.**
- `third_party/boost-context` is a git submodule pinned to an exact commit SHA. Never
  edit, patch, or copy-and-modify anything under it: sources (`.cpp` / `.hpp` / `.S`),
  build files, tests, docs.
- P0 must never require a modified upstream file. If a test needs one, stop and report
  instead of patching.
- Verify cleanliness before and after changes:
  `git -C third_party/boost-context status --porcelain` must print nothing.
- Never track `develop` or any moving ref. Updating upstream is a reviewed SHA change:
  propose SHA → inspect diff → update submodule → run P0 correctness → run benchmark →
  review symbol set → commit the SHA change.

**Xmake is the only build entry.**
- Use `xmake f` / `xmake` / `xmake run`. Do not require Boost.Build, CMake, or Jam to
  build the experiment; they are reference only.
- Select upstream translation units explicitly per target. **Never** write
  `add_files("third_party/boost-context/src/**")` or otherwise glob the upstream tree.
- Keep R0 and R1 in separate targets — do not collapse the baseline into one big target.
- `xmake f -m debug` for correctness, `xmake f -m release` for benchmark. Do not enable
  LTO in P0 (it destroys P1 source/function attribution).

**Platform is Linux x86-64 SysV ABI only.** Do not add Windows / macOS / ARM / RISC-V /
PPC / other backends or their upstream sources.

## P0 scope

Two clearly separated reference layers:
- **R0** — `boost::context::fiber` public API, used as a behavior/reference oracle.
  Simplest deterministic ping-pong; no scheduler.
- **R1** — raw upstream `make_fcontext` + `jump_fcontext`. Add `ontop_fcontext` only if
  correctness demonstrably requires it, and document why.

For raw fcontext, compile only the translation units actually needed
(e.g. `src/asm/make_x86_64_sysv_elf_gas.S` and `src/asm/jump_x86_64_sysv_elf_gas.S`).
Any extra upstream TU must be justified: which symbol, and whether the dependency is
correctness, link, or convenience.

Correctness tests (few and strong) cover: basic transfer, local state preserved across
suspend/resume, suspend inside a nested call, normal termination (never resume a finished
context), and thousands+ of deterministic ping-pongs.

Benchmark: one release-mode ping-pong with warm-up, fixed iteration count, wall-clock,
mean per-transfer cost, and the raw iteration count. It establishes a reproducible
baseline; it does **not** prove optimization.

**P0 must NOT implement:** scheduler, user-space thread runtime, ready queue, wait/wakeup,
futex abstraction, multi-worker, work stealing, migration, `jump_fcontext`/register-save
changes, removal of MXCSR/x87/CET/TLS handling, custom context ABI, eBPF, sched_ext, BPF
loader, or kernel policy. Do not make minimality or "faster than Boost.Context" claims.
Do not add wake-before-park, external notification, multithread races, remote wake, or
shutdown protocols to the tests.

## Evidence and verification

- One verification entrypoint (`xmake run verify-p0` or `./tools/verify/p0.sh`) checks:
  pinned SHA, submodule clean, debug build, correctness tests, release build, benchmark
  runs, symbol inspection. Fail loudly on missing tools — never silently skip.
- Symbol inspection with `nm` / `readelf -Ws` / `objdump` must reveal which fcontext
  primitives are in the artifact and whether `ontop_fcontext` or unrelated Boost.Context
  code leaked in.
- Record experiment identity: OS, kernel, arch, compiler + version, Xmake version, build
  mode, upstream SHA, target ABI, optimization flags (and CPU model if cheap).

## Docs to keep in sync

- `docs/UPSTREAM.md` — upstream repo, pinned SHA, acquisition method, why no fork,
  immutability policy, update procedure and what must be re-verified after an update.
- `docs/P0-BASELINE.md` — scope, platform, R0/R1, actual compiled source set, actual
  symbols, correctness coverage, benchmark, known limitations.
- `README.md` — shortest path (`git clone --recurse-submodules`, `xmake f -m release`,
  `xmake`, `xmake run ...`). State that no minimality/runtime/kernel claims are made.

## Stop and report (do not work around)

- Pinned SHA missing or unreachable.
- Not Linux x86-64.
- Xmake cannot build the upstream x86-64 fcontext assembly (investigate the root cause;
  do not switch back to CMake/Jam and call it done).
- Raw fcontext would need an upstream edit to pass.
- R0 is blocked by missing Boost dependencies and cannot be satisfied within scope — do
  not vendor the whole Boost tree.
