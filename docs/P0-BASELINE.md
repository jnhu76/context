# P0 baseline

This document is **P0 phase evidence**, not project-level authority. Project scope, research
questions, the closure framework, and the phase model (P0–P5) live in
`docs/RESEARCH-FOUNDATION.md`. Keep this document P0-specific.

## Scope

P0 establishes a reproducible, auditable research foundation:

- Xmake is the sole primary build entry.
- Boost.Context is a pinned, immutable submodule (see `docs/UPSTREAM.md`).
- Two reference layers exist: R0 (public API) and R1 (raw fcontext).
- Minimal correctness tests and one context-switch ping-pong benchmark exist.

P0 explicitly does **not** include: a scheduler, a user-space thread runtime, a
ready queue, wait/wakeup, a futex abstraction, multi-worker, work stealing,
migration, `jump_fcontext`/register-save changes, removal of MXCSR/x87/CET/TLS
handling, a custom context ABI, eBPF, sched_ext, a BPF loader, or kernel policy.
It makes no source/function minimality claim and no performance claim.

## Platform

Linux x86-64 SysV ABI (`x86_64-sysv-elf`) only. No other Boost.Context backend
is built or referenced.

## Reference layers

### R0 — Boost.Context public/reference baseline

`boost::context::fiber` is used as a behavior/reference oracle. It is not a
performance model: it is not a bar to beat, and no claim about achievable
performance follows from measuring it. The harness runs a deterministic
ping-pong between the main context and one child fiber. No scheduler.

### R1 — raw fcontext baseline

Uses upstream `make_fcontext` and `jump_fcontext` directly. `ontop_fcontext` is
available upstream but is not required by this harness and is deliberately not
compiled into R1.

R1 distinguishes user-body completion from raw-context return. On the pinned
x86-64 SysV backend, returning from the `make_fcontext` entry reaches upstream's
`finish` path, which exits the process. Therefore the harness lets the user body
return normally to its local trampoline, then performs an explicit terminal
handoff to the resumer. After that handoff the raw context is dead by harness
contract, is never resumed, and only then is its backing stack reclaimed.

## Actual source set

Xmake compiles exactly the following upstream translation units. No
`third_party/boost-context/src/**` glob is used.

R0 `boost_context_reference` (static library):

| Source | Reason |
| --- | --- |
| `src/asm/make_x86_64_sysv_elf_gas.S` | primitive |
| `src/asm/jump_x86_64_sysv_elf_gas.S` | primitive |
| `src/asm/ontop_x86_64_sysv_elf_gas.S` | link dependency: upstream `fcontext.cpp` references `::ontop_fcontext` unconditionally |
| `src/fcontext.cpp` | wraps the C asm symbols into the namespaced C++ symbols used by `fiber_fcontext.hpp` |
| `src/posix/stack_traits.cpp` | correctness dependency: the default fiber constructor calls `stack_traits::default_size()` |

R1 `raw_fcontext_reference` (static library):

| Source | Reason |
| --- | --- |
| `src/asm/make_x86_64_sysv_elf_gas.S` | primitive |
| `src/asm/jump_x86_64_sysv_elf_gas.S` | primitive |

Header dependencies come from the pinned Boost submodules listed in
`docs/UPSTREAM.md`. `predef` and `pool` are not included and not fetched.

## Actual symbols

R1 `libraw_fcontext_reference.a` defines only:

- `make_fcontext`
- `jump_fcontext`

No `ontop_fcontext`. `test_raw_fcontext` defines or references no Boost symbols.

R0 `libboost_context_reference.a` defines:

- `make_fcontext`, `jump_fcontext`, `ontop_fcontext`
- `boost::context::detail::{make,jump,ontop}_fcontext`
- `boost::context::stack_traits::{default_size,is_unbounded,maximum_size,minimum_size,page_size}`

No `continuation` or `fiber` implementation symbols.

`tools/verify/symbols.sh` asserts less than the lists above, and its checks are
narrower than they look. Its `defined_text()` helper runs `nm --defined-only`
and keeps only entries whose type letter is `T` (defined global text symbols),
deduplicated per archive; every archive check runs against that filtered set:

- R1 defines `make_fcontext` and `jump_fcontext`, and does not define
  `ontop_fcontext`.
- R0 defines all three primitives, and defines at least one symbol whose name
  contains `stack_traits`.
- R0's `continuation`/`fiber` absence check runs against the same `T`-only set,
  so it would not exclude such code appearing under another symbol class (`W`,
  `t`, `D`, `B`, `R`, or an undefined entry). This is not a complete
  symbol-closure oracle.
- The one check that does cover the complete symbol table is the R1 binary:
  `nm -C test_raw_fcontext` (defined and undefined, demangled) must contain no
  `boost::` name.

The `boost::context::detail::{make,jump,ontop}_fcontext` wrappers and the
individual `stack_traits` members are stated from the pinned upstream sources
and the build graph, and are not machine-checked at all. The
`continuation`/`fiber` exclusion, the R1 "defines only" list and the R0 "defines"
list above are checked only to the extent and within the `T`-only set described
here; they are otherwise source-derived.

## Correctness coverage

| ID | Property | R0 | R1 |
| --- | --- | --- | --- |
| C-01 | basic deterministic transfer | yes | yes |
| C-02 | ordinary local state preserved across suspend/resume | yes | yes |
| C-03 | suspend from inside a real nested call; nested frame continues after resume | yes | yes |
| C-04 | completion/lifetime boundary | fiber returns normally and becomes invalid | user body returns, terminal handoff occurs, raw context is never resumed, backing stack is then reclaimed |
| C-05 | repeated deterministic switching (20,000 round-trips) | yes | yes |

Not covered in P0: wake-before-park, external notification, multithread races,
remote wake, shutdown protocol.

## Benchmark

`bench/context_switch` runs a release-mode ping-pong against
`boost::context::fiber`:

```sh
xmake f -m release
xmake
xmake run bench_context_switch [rounds]   # default 200000
```

It performs a warm-up, then constructs and primes the measured fiber before the
timed interval. The timer covers exactly the requested steady-state ping-pong
rounds (`2 * rounds` context transfers); final termination and destruction occur
after the timer. It reports elapsed wall-clock, mean cost per round-trip and per
transfer, plus the raw iteration/transfer counts. It also prints an environment
manifest (OS, kernel, arch, CPU, compiler and version, Xmake version, build mode,
upstream SHA, target ABI, optimization flags). `target_abi` and
`optimization_flags` are build-time constants defined in `xmake.lua`, not a
verbatim compiler command line: `optimization_flags` reports the intended
effective setting for the build mode, and other flags such as `-std=c++17` and
`-Wall -Wextra` are not listed.

It establishes a reproducible baseline. It does **not** prove optimization and
deliberately reports no p99, throughput regime, million-fiber, multi-worker, or
kernel-scheduling numbers.

## Known limitations

- No source/function minimality claim has been proven; that is P1.
- No user-space runtime exists.
- No kernel/eBPF/sched_ext work has been introduced.
- No performance optimization has been attempted.
- No theoretical lower bound is claimed or pursued. The project only claims a
  contract-relative, counterexample-supported minimum candidate
  (`docs/RESEARCH-FOUNDATION.md`, section 1); a global minimality proof is out of
  scope rather than a pending P0 item.
- R1's terminal handoff is a harness lifecycle convention; it is not a claim
  that raw `fcontext` provides a general termination/reclamation abstraction.
- `ontop_fcontext` is compiled into R0 only because upstream `fcontext.cpp`
  references it; it is not exercised by the harness.
- Sanitizers are not enabled: custom stack switching produces misleading
  results under ASan's stack tracking, so P0 relies on explicit deterministic
  tests instead.
- The benchmark manifest records toolchain, ABI, flags and warm-up, but neither
  the stack policy/size nor the CPU placement, and no raw benchmark output is
  committed to the repository. The pilot measurement discipline of
  `docs/RESEARCH-FOUNDATION.md` section 12 (at least five independent process
  runs per configuration, randomized order, saved raw results) has not been
  applied to this baseline, which makes no performance claim in the first place.
