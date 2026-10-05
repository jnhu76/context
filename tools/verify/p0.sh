#!/usr/bin/env bash
# P0 unified verification entry: the single verification gate.
#
# GitHub Actions (.github/workflows/p0.yml) bootstraps checkout, submodules,
# Xmake and the inspection tools, then runs this script. The workflow must not
# re-implement any check below, otherwise it becomes a second, weaker definition
# of "verified" that can drift away from this one (issue #3).
#
# Checks, in order:
#   1. required tools present
#   2. platform is Linux x86-64
#   3. every submodule initialized, HEAD == superproject gitlink, clean tree
#   4. negative controls for the submodule identity oracle
#   5. the recorded Boost.Context pin agrees with the gitlink, the submodule HEAD,
#      docs/UPSTREAM.md and xmake.lua
#   6. debug build + correctness tests
#   7. release build + benchmark smoke run
#   8. symbol closure inspection for both modes
#   9. cross-mode comparison of the global defined-symbol closure
#  10. negative controls for the symbol closure oracle
#
# Fails loudly; never silently skips.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

EXPECTED_SHA="1b7bb3d6173032c592cbe82d43f4406e51c3653a"
SUBMODULE="third_party/boost-context"

fail() { echo "P0 VERIFY: FAIL: $*" >&2; exit 1; }

# The symbol negative controls redirect the oracle through P0_SYMBOLS_R*_LIB. The
# gate itself must always inspect the artifacts it just built, so an inherited
# override can neither substitute other files nor make the cross-mode comparison
# compare one artifact set with itself.
unset P0_SYMBOLS_ALLOW_OVERRIDE
unset P0_SYMBOLS_R0_LIB P0_SYMBOLS_R1_LIB P0_SYMBOLS_R1_BIN
step() { echo; echo "==> $*"; }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

step "checking required tools"
for tool in git xmake nm readelf objdump awk grep c++filt ar; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done

step "checking platform (Linux x86-64 SysV)"
[ "$(uname -s)" = "Linux" ] || fail "P0 requires Linux, got $(uname -s)"
[ "$(uname -m)" = "x86_64" ] || fail "P0 requires x86_64, got $(uname -m)"

step "checking submodule identity (all recorded submodules)"
bash tools/verify/submodules.sh

step "negative controls: submodule identity oracle"
bash tools/verify/tests/submodule_identity_negative.sh

step "checking the recorded Boost.Context pin"
gitlink="$(git ls-tree HEAD "$SUBMODULE" | awk '{print $3}')"
[ -n "$gitlink" ] || fail "no gitlink recorded for $SUBMODULE"
[ "$gitlink" = "$EXPECTED_SHA" ] || fail "gitlink $gitlink != expected $EXPECTED_SHA"
sub_sha="$(git -C "$SUBMODULE" rev-parse HEAD)"
[ "$sub_sha" = "$EXPECTED_SHA" ] || fail "submodule HEAD $sub_sha != expected $EXPECTED_SHA"
grep -q "$EXPECTED_SHA" docs/UPSTREAM.md || fail "docs/UPSTREAM.md does not record the pinned SHA"
grep -q "$EXPECTED_SHA" xmake.lua || fail "xmake.lua does not record the pinned SHA"
echo "   pinned SHA ok: $EXPECTED_SHA"
echo "   gitlink (superproject HEAD tree) == submodule HEAD == docs/UPSTREAM.md == xmake.lua"
echo "   all six gitlink/HEAD identities are enforced separately by tools/verify/submodules.sh"

step "debug build + correctness"
xmake f -m debug >/dev/null
xmake >/dev/null
xmake run test_reference
xmake run test_raw_fcontext

step "release build + benchmark smoke"
xmake f -m release >/dev/null
xmake >/dev/null
xmake run bench_context_switch 20000

step "symbol closure inspection (release)"
P0_SYMBOLS_CLOSURE_OUT="$workdir/closure.release" bash tools/verify/symbols.sh release

step "symbol closure inspection (debug)"
P0_SYMBOLS_CLOSURE_OUT="$workdir/closure.debug" bash tools/verify/symbols.sh debug

step "cross-mode global symbol closure comparison"
if ! diff -u "$workdir/closure.release" "$workdir/closure.debug"; then
  fail "the global defined-symbol closure differs between debug and release (diff above); that is a source-closure change, not a local-symbol artifact"
fi
echo "   global defined-symbol closure identical in debug and release: $(awk '!/^#/ { n++ } END { print n + 0 }' "$workdir/closure.release") entries of (archive member, symbol, nm class, ELF binding)"

step "negative controls: symbol closure oracle"
bash tools/verify/tests/symbol_oracle_negative.sh

echo
echo "P0 VERIFY: ALL CHECKS PASSED"
