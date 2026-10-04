# Upstream authority

## Repository

- Upstream: <https://github.com/boostorg/context>
- Local path: `third_party/boost-context`
- Acquisition: `git submodule` (recorded in `.gitmodules`)
- Pinned commit: `1b7bb3d6173032c592cbe82d43f4406e51c3653a`

This repository is **not** a fork of `boostorg/context` and maintains no fork
relationship. It consumes upstream as a pinned, immutable submodule.

## Why no fork

A fork would let upstream code drift from the experiment and would blur the
question "which exact upstream revision produced this result?". A submodule
pinned to one commit keeps a single, auditable identity while leaving this
repository free to add only its own experiment code.

## Immutable substrate policy

`third_party/boost-context` must be treated as read-only:

- **U-01** No upstream file may be modified: `.cpp`, `.hpp`, `.S`, build files,
  tests, docs.
- **U-02** No local patch may be applied to the submodule.
- **U-03** Upstream sources may not be copied into this repository and modified,
  except for an explicitly provenance-recorded experimental copy that P0
  requires. P0 requires none.
- **U-04** A check must prove the working tree is clean. `tools/verify/p0.sh`
  runs `git -C third_party/boost-context status --porcelain` (and the same for
  every other submodule) and fails if the output is non-empty.

## Minimal Boost dependency submodules

The R0 (`boost::context::fiber`) path needs a small set of other Boost headers.
They are fetched as pinned submodules rather than by vendoring the whole Boost
tree. The audited closure is `config`, `assert`, `core`, `smart_ptr`
(`boost/intrusive_ptr.hpp`) and `mp11`. `predef` and `pool` are not on the
`fiber_fcontext` include path and are deliberately absent.

| Path | Upstream | Pinned commit |
| --- | --- | --- |
| `third_party/boost-context` | boostorg/context | `1b7bb3d6173032c592cbe82d43f4406e51c3653a` |
| `third_party/boost-config` | boostorg/config | `1a75a3e2ed18a49b3257fa0ce93cde590d1efac4` |
| `third_party/boost-assert` | boostorg/assert | `612d35df55376c6412f0477ed62d4d241f8861b7` |
| `third_party/boost-core` | boostorg/core | `177a1c61748a61a03aaa1d4ec696f81625e66cff` |
| `third_party/boost-smart_ptr` | boostorg/smart_ptr | `6e945160d788b8efdfc49ba4af1f8797cacd7c97` |
| `third_party/boost-mp11` | boostorg/mp11 | `0daffd6401724ddf473fd39d28f68e138d9a1303` |

## Updating upstream

Never track `develop` or any moving ref. An update is a reviewed commit:

1. Propose a new commit SHA.
2. Inspect the diff between the old and new SHA.
3. `git -C third_party/boost-context checkout <new-sha>` and stage the gitlink.
4. Update the pinned SHA here and in `xmake.lua`.
5. Run P0 correctness: `xmake f -m debug && xmake && xmake run test_reference && xmake run test_raw_fcontext`.
6. Run the benchmark: `xmake f -m release && xmake && xmake run bench_context_switch`.
7. Review the symbol set: `tools/verify/symbols.sh release`.
8. Commit the SHA change.

After an update, re-verify at minimum: the submodule is clean, P0 correctness
passes for R0 and R1, the benchmark runs, and the compiled source set and symbol
set in `docs/P0-BASELINE.md` still match reality.

## Verification

`tools/verify/p0.sh` asserts that the pinned SHA matches the gitlink recorded in
the repository, the checked-out submodule commit, and the SHA recorded in this
document and `xmake.lua`. Any drift fails the run.
