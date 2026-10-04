#!/usr/bin/env bash
# P0 unified verification entry.
#
# Checks, in order:
#   1. required tools present
#   2. platform is Linux x86-64
#   3. pinned upstream SHA matches the gitlink, the submodule and the docs
#   4. every submodule is initialized and its working tree is clean
#   5. debug build + correctness tests
#   6. release build + benchmark smoke run
#   7. symbol inspection for both modes
#
# Fails loudly; never silently skips.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

EXPECTED_SHA="1b7bb3d6173032c592cbe82d43f4406e51c3653a"
SUBMODULE="third_party/boost-context"

fail() { echo "P0 VERIFY: FAIL: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

step "checking required tools"
for tool in git xmake nm readelf objdump awk grep; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done

step "checking platform (Linux x86-64 SysV)"
[ "$(uname -s)" = "Linux" ] || fail "P0 requires Linux, got $(uname -s)"
[ "$(uname -m)" = "x86_64" ] || fail "P0 requires x86_64, got $(uname -m)"

step "checking pinned upstream SHA"
gitlink="$(git ls-tree HEAD "$SUBMODULE" | awk '{print $3}')"
[ -n "$gitlink" ] || fail "no gitlink recorded for $SUBMODULE"
[ "$gitlink" = "$EXPECTED_SHA" ] || fail "gitlink $gitlink != expected $EXPECTED_SHA"
sub_sha="$(git -C "$SUBMODULE" rev-parse HEAD)"
[ "$sub_sha" = "$EXPECTED_SHA" ] || fail "submodule HEAD $sub_sha != expected $EXPECTED_SHA"
grep -q "$EXPECTED_SHA" docs/UPSTREAM.md || fail "docs/UPSTREAM.md does not record the pinned SHA"
grep -q "$EXPECTED_SHA" xmake.lua || fail "xmake.lua does not record the pinned SHA"
echo "   pinned SHA ok: $EXPECTED_SHA"

step "checking submodule cleanliness"
if git submodule status --recursive | grep -q '^-'; then
  fail "a submodule is not initialized (run: git submodule update --init --recursive)"
fi
while read -r sm; do
  [ -n "$sm" ] || continue
  [ -d "$sm" ] || fail "submodule directory missing: $sm"
  dirty="$(git -C "$sm" status --porcelain)"
  [ -z "$dirty" ] || fail "submodule working tree not clean: $sm"
done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
echo "   all submodules clean"

step "debug build + correctness"
xmake f -m debug >/dev/null
xmake >/dev/null
xmake run test_reference
xmake run test_raw_fcontext

step "release build + benchmark smoke"
xmake f -m release >/dev/null
xmake >/dev/null
xmake run bench_context_switch 20000

step "symbol inspection (release)"
bash tools/verify/symbols.sh release

step "symbol inspection (debug)"
bash tools/verify/symbols.sh debug

echo
echo "P0 VERIFY: ALL CHECKS PASSED"
