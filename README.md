# context

An independent research repository for studying the **minimum sufficient execution closure** required by an explicit execution contract: first in user space, and later—only when evidence justifies it—at the user/kernel boundary.

This project is **not** a `boostorg/context` fork and is **not** a Boost.Context replacement. It consumes upstream Boost.Context as a pinned, immutable mechanism/reference source and selects only the source/capability closure required by each experiment.

## Current state

**P0 — reproducible baseline** is established in this branch: public `boost::context::fiber` (R0), raw `make_fcontext`/`jump_fcontext` (R1), deterministic correctness tests, a context-switch benchmark, symbol inspection, and pinned upstream identities.

P0 is a baseline, not the project scope. Subsequent work derives and tests smaller user-space source/function/state closures, then adds runtime semantics such as lifecycle, wait/wakeup, remote notification, and multi-worker execution. eBPF/sched_ext is considered only if profiling shows carrier scheduling or wakeup is an important bottleneck.

See `AGENTS.md` for project-wide research discipline. Phase-specific facts remain in their corresponding documents.

## Quick start

```sh
git clone --recurse-submodules <repo-url> context
cd context

# Correctness baseline
xmake f -m debug
xmake
xmake run test_reference
xmake run test_raw_fcontext

# Baseline benchmark
xmake f -m release
xmake
xmake run bench_context_switch
```

## Verify the P0 baseline

```sh
./tools/verify/p0.sh
```

This regression check validates pinned upstream identities and cleanliness, debug/release builds, both correctness suites, benchmark smoke, and the compiled symbol set. It remains useful after P0 as a guard against baseline drift.

## Documentation authority

Read in this order:

1. `AGENTS.md` — project-wide research/governance rules, including document-audit discipline.
2. `docs/RESEARCH-FOUNDATION.md` — long-term research authority: questions, execution contract,
   closure framework, phase model (P0–P5), evidence levels, and the proven/hypothesis ledger.
3. `docs/UPSTREAM.md` — upstream identity, immutability, provenance, and update policy.
4. `docs/P0-BASELINE.md` — P0 phase evidence (source/symbol set, tests, benchmark, limitations).
5. Code and verification scripts (`xmake.lua`, `tools/verify/`, `tests/`, `bench/`).

When documents disagree with code or experiments, the executable facts win and the documents are
corrected — never the reverse.

Platform currently under study: Linux x86-64 SysV ABI. Next phase: **P1 — User-space Closure**
(not started).
