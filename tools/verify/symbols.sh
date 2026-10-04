#!/usr/bin/env bash
# P0 symbol inspection.
#
# Proves what was actually compiled into each artifact: which fcontext
# primitives are present, whether ontop_fcontext leaked into the raw baseline,
# and whether unrelated Boost.Context implementation was linked.
#
# Usage: tools/verify/symbols.sh [debug|release]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

MODE="${1:-release}"
case "$MODE" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

fail() { echo "P0 SYMBOLS: FAIL: $*" >&2; exit 1; }

for tool in nm readelf objdump; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done

libdir="build/linux/x86_64/$MODE"
r0_lib="$libdir/libboost_context_reference.a"
r1_lib="$libdir/libraw_fcontext_reference.a"
r1_bin="$libdir/test_raw_fcontext"

[ -f "$r0_lib" ] || fail "missing $r0_lib (run: xmake f -m $MODE && xmake)"
[ -f "$r1_lib" ] || fail "missing $r1_lib"
[ -f "$r1_bin" ] || fail "missing $r1_bin"

defined_text() {
  nm --defined-only "$1" 2>/dev/null | awk '$2 == "T" { print $3 }' | sort -u
}

echo "P0 symbol inspection ($MODE)"

echo "-- R1 raw_fcontext_reference: defined text symbols --"
defined_text "$r1_lib" | sed 's/^/   /'

r1="$(defined_text "$r1_lib")"
grep -qx 'make_fcontext' <<<"$r1" || fail "R1 missing make_fcontext"
grep -qx 'jump_fcontext' <<<"$r1" || fail "R1 missing jump_fcontext"
if grep -qx 'ontop_fcontext' <<<"$r1"; then
  fail "R1 unexpectedly contains ontop_fcontext"
fi

echo "-- R0 boost_context_reference: defined text symbols --"
defined_text "$r0_lib" | sed 's/^/   /'

r0="$(defined_text "$r0_lib")"
grep -qx 'make_fcontext' <<<"$r0" || fail "R0 missing make_fcontext"
grep -qx 'jump_fcontext' <<<"$r0" || fail "R0 missing jump_fcontext"
grep -qx 'ontop_fcontext' <<<"$r0" || fail "R0 missing ontop_fcontext (link dependency of upstream fcontext.cpp)"
grep -q 'stack_traits' <<<"$r0" || fail "R0 missing stack_traits symbols"

if grep -Eq 'continuation|fiber' <<<"$r0"; then
  fail "R0 unexpectedly contains continuation/fiber implementation symbols"
fi

echo "-- R1 test_raw_fcontext: must not define or reference Boost symbols --"
# Inspect the complete symbol table (defined + undefined), demangled. Using
# --defined-only here would not prove the stated property because an unresolved
# or dynamically satisfied Boost reference would be invisible to that check.
if nm -C "$r1_bin" 2>/dev/null | grep -Fq 'boost::'; then
  fail "test_raw_fcontext unexpectedly defines or references Boost symbols"
fi

echo "P0 SYMBOLS: PASS"
