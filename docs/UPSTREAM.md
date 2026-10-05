# Upstream authority

## Repository

- Upstream: <https://github.com/boostorg/context>
- Local path: `third_party/boost-context`
- Acquisition: `git submodule` (recorded in `.gitmodules`)
- Pinned commit: recorded in the dependency table below, and mirrored in `xmake.lua` and `tools/verify/p0.sh` so the pin can be cross-checked rather than trusted

This repository is **not** a fork of `boostorg/context` and maintains no fork relationship. It consumes upstream as a pinned, immutable submodule and treats that tree as experimental input/reference material rather than project-owned implementation.

## Why no fork

A fork would blur the identity of the upstream mechanism under test and encourage experiment-specific edits to become mixed with upstream history. A pinned submodule keeps the upstream revision auditable while allowing this repository to build only the source closure required by each experiment.

## Immutable substrate policy

`third_party/boost-context` must be treated as read-only:

- **U-01** No upstream file may be modified: `.cpp`, `.hpp`, `.S`, build files, tests, or docs.
- **U-02** No local patch may be applied inside the submodule.
- **U-03** If an experiment must change a primitive or ABI, create a separate project-owned experimental implementation outside the submodule and record its upstream provenance. Do not overwrite or patch the pristine reference tree.
- **U-04** Verification must prove the upstream working tree is clean.

This distinction is intentional: **selecting a smaller source closure** and **modifying the mechanism itself** are different experiments and must remain separately attributable.

## Minimal Boost dependency submodules

The R0 (`boost::context::fiber`) reference path needs a small set of other Boost headers. They are fetched as pinned submodules rather than by vendoring the whole Boost tree. The audited P0 dependency closure is `config`, `assert`, `core`, `smart_ptr` (`boost/intrusive_ptr.hpp`) and `mp11`. `predef` and `pool` are not on the `fiber_fcontext` include path and are deliberately absent.

| Path | Upstream | Pinned commit |
| --- | --- | --- |
| `third_party/boost-context` | boostorg/context | `1b7bb3d6173032c592cbe82d43f4406e51c3653a` |
| `third_party/boost-config` | boostorg/config | `1a75a3e2ed18a49b3257fa0ce93cde590d1efac4` |
| `third_party/boost-assert` | boostorg/assert | `612d35df55376c6412f0477ed62d4d241f8861b7` |
| `third_party/boost-core` | boostorg/core | `177a1c61748a61a03aaa1d4ec696f81625e66cff` |
| `third_party/boost-smart_ptr` | boostorg/smart_ptr | `6e945160d788b8efdfc49ba4af1f8797cacd7c97` |
| `third_party/boost-mp11` | boostorg/mp11 | `0daffd6401724ddf473fd39d28f68e138d9a1303` |

These additional repositories are reference dependencies, not a claim that they are part of the eventual minimum runtime closure. Future experiments must distinguish reference-only dependencies from mechanisms actually required by the candidate runtime.

## Updating upstream

Never track `develop` or any moving ref. An upstream change is a reviewed experiment-input change:

1. Propose a new exact commit SHA.
2. Inspect the diff between the old and new revision.
3. Update the relevant submodule gitlink.
4. Update every recorded identity that is intentionally duplicated for verification.
5. Re-run the baseline regression suite.
6. Re-run symbol/source inspection.
7. Audit affected documentation and experiments for assumptions invalidated by the update.
8. Commit the identity change with the resulting evidence.

At minimum, the existing P0 regression remains a required guard while it exists:

```sh
./tools/verify/p0.sh
```

An upstream update must not silently change the source closure, ABI assumptions, symbol set, correctness behavior, or benchmark interpretation of an existing experiment. If it does, update or retire the affected experiment explicitly rather than rewriting history.

## Verification

`tools/verify/p0.sh` is the single verification gate, and CI (`.github/workflows/p0.yml`) bootstraps the environment and runs it rather than re-implementing any check. It cross-checks the Boost.Context pin against the gitlink, the submodule HEAD, this document and `xmake.lua`; enforces, for **every** submodule recorded in `.gitmodules`, that it is initialized, that its `HEAD` equals the gitlink recorded in the superproject HEAD tree, that the git worktree of that checkout is the recorded path, and that its working tree is clean (`tools/verify/submodules.sh`); and then checks the correctness baselines, a benchmark smoke run and the symbol closure of both artifacts in both build modes, comparing (archive member, symbol, `nm` class) entries with multiplicity.

For the five reference dependencies no SHA is duplicated anywhere: the superproject gitlink is the authority for their expected identity, so a wrong-but-clean checkout is rejected while the table above remains a record rather than a re-verified assertion. The Boost.Context pin keeps its duplicated four-way cross-check (`gitlink`, submodule `HEAD`, this document, `xmake.lua`) because it is the mechanism under study.

Every oracle in the gate is exercised by negative controls during the same run: `p0.sh` fails if the submodule identity oracle accepts a wrong-but-clean checkout or a dirty working tree, or if the symbol closure oracle accepts an unexpected, duplicated or re-classed defined symbol in any symbol class, or an archive with a required symbol removed. Closure entries are (archive member, symbol, `nm` class) with multiplicity, not a set of names. Later phases may add additional verification, but must not weaken these existing reproducibility checks without an explicit reviewed reason.
