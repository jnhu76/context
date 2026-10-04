# context

An independent research repository for studying the **minimum sufficient execution closure** required by an explicit execution contract: first in user space, and later—only when evidence justifies it—at the user/kernel boundary.

This project is **not** a `boostorg/context` fork and is **not** a Boost.Context replacement. It consumes upstream Boost.Context as a pinned, immutable mechanism/reference source and selects only the source/capability closure required by each experiment.

## Repository role

The repository contains phase-specific evidence as well as long-lived research authority. A reproducible Boost.Context/raw-fcontext baseline is documented in `docs/P0-BASELINE.md`; later work may derive smaller user-space closures, add runtime semantics, profile the user/kernel boundary, and only then consider eBPF/sched_ext when evidence warrants it.

Do not infer the active phase from this README alone. Phase status must be supported by the repository/PR history and the corresponding phase evidence.

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

## Verify the baseline

```sh
./tools/verify/p0.sh
```

This regression check cross-checks the Boost.Context pin against the gitlink, the submodule HEAD, `docs/UPSTREAM.md` and `xmake.lua`, requires every submodule to be initialized with a clean working tree, then runs the debug/release builds, both correctness suites, a benchmark smoke run, and the release/debug symbol inspection. It is a baseline-drift guard, not a statement that later phases are complete. Only the Boost.Context pin is compared by SHA. The other five reference dependencies have their identity **completely unverified** by this script: it checks only that they are initialized and that their working trees are clean, and it does not reject a submodule checked out at a commit other than the one recorded in the superproject gitlink.

## Documentation authority

Read only the authorities relevant to the task, starting with:

1. `AGENTS.md` — project-wide governance and document-audit discipline.
2. `docs/RESEARCH-FOUNDATION.md` — research questions, target contract, closure framework, phase model, measurement and stop conditions.
3. `docs/UPSTREAM.md` — upstream identity, immutability, provenance, and update policy.
4. Phase/experiment evidence such as `docs/P0-BASELINE.md`.
5. Code, build graph, tests, CI, benchmark implementation, and raw results.

Conflicts are not resolved by a blanket “code wins” rule. Normative contract/project decisions and descriptive implementation/measurement claims have different authority; see `AGENTS.md` and `docs/RESEARCH-FOUNDATION.md`.

Platform currently under study: Linux x86-64 SysV ABI.
