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

This regression check validates pinned upstream identities and cleanliness, debug/release builds, both correctness suites, benchmark smoke, and the compiled symbol set. It is a baseline-drift guard, not a statement that later phases are complete.

## Documentation authority

Read only the authorities relevant to the task, starting with:

1. `AGENTS.md` — project-wide governance and document-audit discipline.
2. `docs/RESEARCH-FOUNDATION.md` — research questions, target contract, closure framework, phase model, measurement and stop conditions.
3. `docs/UPSTREAM.md` — upstream identity, immutability, provenance, and update policy.
4. Phase/experiment evidence such as `docs/P0-BASELINE.md`.
5. Code, build graph, tests, CI, benchmark implementation, and raw results.

Conflicts are not resolved by a blanket “code wins” rule. Normative contract/project decisions and descriptive implementation/measurement claims have different authority; see `AGENTS.md` and `docs/RESEARCH-FOUNDATION.md`.

Platform currently under study: Linux x86-64 SysV ABI.
