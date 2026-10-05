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

This regression check is the single verification gate; GitHub Actions only bootstraps the environment and then runs it, so there is no second, weaker definition of "verified". It cross-checks the Boost.Context pin against the gitlink, the submodule HEAD, `docs/UPSTREAM.md` and `xmake.lua`; requires **every** submodule recorded in `.gitmodules` to be initialized with its `HEAD` equal to the superproject gitlink, its git worktree at the recorded path, and a clean working tree; then runs the debug/release builds, both correctness suites, a benchmark smoke run, and the symbol closure inspection in both modes. It is a baseline-drift guard, not a statement that later phases are complete.

Only the Boost.Context pin is compared against a recorded SHA, because it is the mechanism under study and is deliberately duplicated for cross-checking. For the other five reference dependencies no SHA is duplicated: their expected identity is the superproject gitlink in the HEAD tree, so a checkout at any other commit is rejected even when its working tree is clean, and `docs/UPSTREAM.md`'s dependency table stays a record rather than a second assertion. Both oracles are exercised by negative controls in the same run: `p0.sh` fails unless the submodule identity oracle rejects a wrong-but-clean checkout and the symbol closure oracle rejects an unexpected, duplicated or re-classed defined symbol outside the declared closure. A closure entry is (archive member, symbol, `nm` class) with its multiplicity, so an artifact that keeps the same symbol names but changes a class, moves a definition to another member or duplicates it is still rejected.

## Documentation authority

Read only the authorities relevant to the task, starting with:

1. `AGENTS.md` — project-wide governance and document-audit discipline.
2. `docs/RESEARCH-FOUNDATION.md` — research questions, target contract, closure framework, phase model, measurement and stop conditions.
3. `docs/UPSTREAM.md` — upstream identity, immutability, provenance, and update policy.
4. Phase/experiment evidence such as `docs/P0-BASELINE.md`.
5. Code, build graph, tests, CI, benchmark implementation, and raw results.

Conflicts are not resolved by a blanket “code wins” rule. Normative contract/project decisions and descriptive implementation/measurement claims have different authority; see `AGENTS.md` and `docs/RESEARCH-FOUNDATION.md`.

Platform currently under study: Linux x86-64 SysV ABI.
