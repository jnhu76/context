# P0 baseline

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

`boost::context::fiber` is used as a behavior/reference oracle, not as a
performance model. The harness runs a deterministic ping-pong between the main
context and one child fiber. No scheduler.

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

No `continuation` or `fiber` implementation symbols. `tools/verify/symbols.sh`
asserts all of the above.

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
upstream SHA, target ABI, optimization flags).

It establishes a reproducible baseline. It does **not** prove optimization and
deliberately reports no p99, throughput regime, million-fiber, multi-worker, or
kernel-scheduling numbers.

## Known limitations

- No source/function minimality claim has been proven; that is P1.
- No user-space runtime exists.
- No kernel/eBPF/sched_ext work has been introduced.
- No performance optimization has been attempted.
- No theoretical lower bound has been established.
- R1's terminal handoff is a harness lifecycle convention; it is not a claim
  that raw `fcontext` provides a general termination/reclamation abstraction.
- `ontop_fcontext` is compiled into R0 only because upstream `fcontext.cpp`
  references it; it is not exercised by the harness.
- Sanitizers are not enabled: custom stack switching produces misleading
  results under ASan's stack tracking, so P0 relies on explicit deterministic
  tests instead.
