# context

An independent research repository for studying how much minimal sufficient
semantics, mechanism, and state are required for user-space, kernel-space, and
boundary-crossing execution under a given execution contract.

This project is **not** a `boostorg/context` fork and is **not** a Boost.Context
replacement. It consumes upstream Boost.Context as a pinned, immutable submodule
and uses it as a reference baseline.

Current phase: **P0 — a reproducible execution-mechanism research harness.**
It builds two reference layers (public `boost::context::fiber` and raw
`make_fcontext`/`jump_fcontext`), minimal correctness tests, and a context-switch
benchmark. No scheduler, runtime, kernel, or performance claim is made yet.

## Quick start

```sh
git clone --recurse-submodules <repo-url> context
cd context

# Correctness
xmake f -m debug
xmake
xmake run test_reference
xmake run test_raw_fcontext

# Benchmark (release)
xmake f -m release
xmake
xmake run bench_context_switch
```

## Verify the foundation

```sh
./tools/verify/p0.sh
```

Checks the pinned upstream SHA and submodule cleanliness, builds debug and
release, runs both correctness suites, smoke-runs the benchmark, and inspects the
compiled symbol set. It fails loudly on missing tools or drift.

## Documentation

- `docs/UPSTREAM.md` — upstream authority, pinning, immutable policy, updates.
- `docs/P0-BASELINE.md` — scope, source set, symbols, tests, benchmark, limits.
- `AGENTS.md` — the working contract for agents in this repository.

Platform: Linux x86-64 SysV ABI.
