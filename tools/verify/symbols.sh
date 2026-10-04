#!/usr/bin/env bash
# P0 symbol closure inspection.
#
# Answers, from the real artifacts, what each reference layer actually contains:
#
#   1. the complete defined-symbol inventory of every artifact, by nm class;
#   2. an exact global defined-symbol closure per archive -- set equality, so a
#      missing symbol and an unexpected extra symbol in *any* nm class fail;
#   3. forbidden-implementation-family assertions over every defined symbol of
#      every class (mangled and demangled names), and over undefined entries;
#   4. classification of every local (STB_LOCAL) defined symbol: either a label
#      of a pinned upstream assembly source compiled into that target, or a
#      compiler-generated internal-linkage name (mangled '_Z...'). Unclassified
#      local symbols fail; they are never wildcarded away or silently ignored.
#
# The complete defined-symbol set (all classes) is what the assertions run on.
# The previous revision of this script filtered 'nm --defined-only' down to class
# 'T' first, which cannot see a defined symbol appearing as W/t/D/B/R.
#
# Local symbols legitimately differ between debug and release: optimization
# inlines or removes internal-linkage entities. The *global* closure must not
# differ, and tools/verify/p0.sh proves that by comparing the closure files
# written via P0_SYMBOLS_CLOSURE_OUT.
#
# Usage: tools/verify/symbols.sh [debug|release]
#
# Environment overrides (defaults are the real build artifacts; the negative
# controls in tools/verify/tests/symbol_oracle_negative.sh point these at mutated
# copies of the real artifacts):
#   P0_SYMBOLS_R0_LIB, P0_SYMBOLS_R1_LIB, P0_SYMBOLS_R1_BIN
#   P0_SYMBOLS_CLOSURE_OUT

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

MODE="${1:-release}"
case "$MODE" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

fail() { echo "P0 SYMBOLS: FAIL: $*" >&2; exit 1; }

# The artifact paths below can be redirected for the negative controls, but only
# with an explicit opt-in. An inherited P0_SYMBOLS_R* override would let the gate
# inspect different files than the ones just built -- and, in p0.sh, would make
# the cross-mode comparison compare one artifact set with itself.
if [ "${P0_SYMBOLS_ALLOW_OVERRIDE:-}" != "1" ] \
   && { [ -n "${P0_SYMBOLS_R0_LIB:-}" ] || [ -n "${P0_SYMBOLS_R1_LIB:-}" ] || [ -n "${P0_SYMBOLS_R1_BIN:-}" ]; }; then
  fail "P0_SYMBOLS_R0_LIB/P0_SYMBOLS_R1_LIB/P0_SYMBOLS_R1_BIN are set but P0_SYMBOLS_ALLOW_OVERRIDE is not 1; refusing to inspect redirected artifacts"
fi

for tool in nm c++filt readelf objdump; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done

libdir="build/linux/x86_64/$MODE"
r0_lib="${P0_SYMBOLS_R0_LIB:-$libdir/libboost_context_reference.a}"
r1_lib="${P0_SYMBOLS_R1_LIB:-$libdir/libraw_fcontext_reference.a}"
r1_bin="${P0_SYMBOLS_R1_BIN:-$libdir/test_raw_fcontext}"

for f in "$r0_lib" "$r1_lib" "$r1_bin"; do
  [ -f "$f" ] || fail "missing $f (run: xmake f -m $MODE && xmake)"
done

asm_dir="third_party/boost-context/src/asm"
asm_make="$asm_dir/make_x86_64_sysv_elf_gas.S"
asm_jump="$asm_dir/jump_x86_64_sysv_elf_gas.S"
asm_ontop="$asm_dir/ontop_x86_64_sysv_elf_gas.S"

# --- symbol extraction -------------------------------------------------------
#
# nm --format=posix prints "<name> <type> <value> [<size>]" per symbol and omits
# the value for undefined entries; archive members are introduced by
# "archive[member.o]:" lines. The type letter case is the binding: uppercase is
# global, lowercase is local, U is undefined.
defined_pairs() {
  nm --format=posix --defined-only "$1" 2>/dev/null \
    | awk 'NF >= 3 && $2 ~ /^[A-Za-z]$/ { print $2 "\t" $1 }' | sort -u
}
# 'u' is a GNU unique symbol: readelf reports its binding as UNIQUE, not LOCAL, so
# it belongs to the global closure. Bucketing it with the locals would let an
# extra globally bound symbol pass as "compiler-generated". 'v'/'w' are
# undefined-weak and cannot appear under --defined-only; if one ever did, the
# local bucket would fail it loudly rather than drop it.
global_defined() { defined_pairs "$1" | awk -F'\t' '$1 == "u" || ($1 ~ /^[A-Z]$/ && $1 != "U")'; }
local_defined()  { defined_pairs "$1" | awk -F'\t' '$1 ~ /^[a-z]$/ && $1 != "u"'; }
undefined_names() {
  nm --format=posix "$1" 2>/dev/null \
    | awk 'NF == 2 && $2 ~ /^[A-Za-z]$/ { print $1 }' | sort -u
}
demangle() { c++filt <<<"$1"; }

inventory() {
  local label="$1" art="$2" t n
  echo "-- $label complete defined-symbol inventory: $art"
  echo "   by nm class:"
  defined_pairs "$art" | awk -F'\t' '{ print $1 }' | sort | uniq -c \
    | awk '{ printf "     %s x %s\n", $2, $1 }'
  while IFS=$'\t' read -r t n; do
    [ -n "$n" ] || continue
    printf '     %s %s\n' "$t" "$n"
  done < <(defined_pairs "$art")
  echo "   undefined entries:"
  while read -r n; do
    [ -n "$n" ] && printf '     U %s\n' "$n"
  done < <(undefined_names "$art")
}

# Every nm entry must be classifiable. An entry whose type field is not a single
# letter (and that is not an archive member header) would otherwise be dropped by
# the filters above and disappear from the inventory -- the same kind of blind
# spot this oracle exists to remove, one layer down.
# nm keeps going after it cannot parse a member and reports that on stderr, so a
# suppressed stderr would let an unreadable member disappear from the inventory
# without any assertion noticing.
assert_nm_reports_no_errors() {
  local art="$1" label="$2" err status
  set +e
  err="$(nm --format=posix "$art" 2>&1 >/dev/null)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] || [ -n "$err" ]; then
    printf '%s\n' "$err" | head -5 | sed 's/^/     /' >&2
    fail "$label: nm reported an error while reading the artifact (exit $status); the inventory would be incomplete"
  fi
}

assert_nm_entries_classified() {
  local art="$1" label="$2" offending
  offending="$(nm --format=posix "$art" 2>/dev/null \
    | awk 'NF == 0 { next } substr($0, length($0), 1) == ":" { next } $2 !~ /^[A-Za-z]$/ { print }')"
  if [ -n "$offending" ]; then
    printf '%s\n' "$offending" | head -5 | sed 's/^/     /' >&2
    fail "$label: nm entry that is neither a symbol with a single-letter type nor an archive member header; it would be dropped from the inventory"
  fi
}

assert_global_closure() {
  local art="$1" label="$2" expected="$3"
  local pairs names missing unexpected n cls
  pairs="$(global_defined "$art")"
  names="$(awk -F'\t' '{ print $2 }' <<<"$pairs" | sort -u)"
  missing="$(comm -23 <(printf '%s\n' "$expected" | sort -u) <(printf '%s\n' "$names"))"
  unexpected="$(comm -13 <(printf '%s\n' "$expected" | sort -u) <(printf '%s\n' "$names"))"
  if [ -n "$missing" ]; then
    while read -r n; do
      [ -n "$n" ] && echo "     missing: $n ($(demangle "$n"))" >&2
    done <<<"$missing"
    fail "$label: required global definition missing"
  fi
  if [ -n "$unexpected" ]; then
    while read -r n; do
      [ -n "$n" ] || continue
      cls="$(awk -F'\t' -v n="$n" '$2 == n { print $1; exit }' <<<"$pairs")"
      echo "     unexpected: $cls $n ($(demangle "$n"))" >&2
    done <<<"$unexpected"
    fail "$label: unexpected extra global definition (any nm class counts, not only T)"
  fi
  echo "   exact global defined-symbol closure verified ($(wc -l <<<"$names") symbols)"
}

assert_no_forbidden_defined() {
  local art="$1" label="$2" pattern="$3" t n d
  while IFS=$'\t' read -r t n; do
    [ -n "$n" ] || continue
    d="$(demangle "$n")"
    if grep -Eq "$pattern" <<<"$n" || grep -Eq "$pattern" <<<"$d"; then
      fail "$label: forbidden implementation symbol present: $t $n ($d)"
    fi
  done < <(defined_pairs "$art")
}

assert_no_forbidden_undefined() {
  local art="$1" label="$2" pattern="$3" n d
  while read -r n; do
    [ -n "$n" ] || continue
    d="$(demangle "$n")"
    if grep -Eq "$pattern" <<<"$n" || grep -Eq "$pattern" <<<"$d"; then
      fail "$label: forbidden symbol referenced but not defined: U $n ($d)"
    fi
  done < <(undefined_names "$art")
}

local_asm_label() {
  local name="$1" src
  shift
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  for src in "$@"; do
    [ -f "$src" ] || fail "pinned upstream assembly source not found: $src"
    grep -qE "^[[:space:]]*$name:" "$src" && return 0
  done
  return 1
}

assert_locals_classified() {
  local art="$1" label="$2" t n asm_labels=0 compiler_names=0
  shift 2
  while IFS=$'\t' read -r t n; do
    [ -n "$n" ] || continue
    if local_asm_label "$n" "$@"; then
      echo "   local symbol: $n -- label of a pinned upstream assembly source compiled into this target"
      asm_labels=$((asm_labels + 1))
    elif [[ "$n" == _Z* ]]; then
      echo "   local symbol: $n -- compiler-generated internal-linkage name"
      compiler_names=$((compiler_names + 1))
    else
      fail "$label: unclassified local defined symbol: $t $n (neither a label of the pinned upstream assembly sources compiled into this target nor a compiler-generated '_Z' name)"
    fi
  done < <(local_defined "$art")
  echo "   local defined symbols classified: $asm_labels upstream asm label(s), $compiler_names compiler-generated"
}

echo "P0 symbol closure inspection ($MODE)"

echo
echo "== complete defined-symbol inventory =="
inventory "R1" "$r1_lib"
echo
inventory "R0" "$r0_lib"

echo
echo "== R1 raw_fcontext_reference closure =="
r1_expected="$(cat <<'SYMEOF'
make_fcontext
jump_fcontext
SYMEOF
)"
assert_nm_reports_no_errors "$r1_lib" "R1 raw_fcontext_reference"
assert_nm_entries_classified "$r1_lib" "R1 raw_fcontext_reference"
assert_global_closure "$r1_lib" "R1 raw_fcontext_reference" "$r1_expected"
assert_no_forbidden_defined "$r1_lib" "R1 raw_fcontext_reference" 'ontop_fcontext'
assert_no_forbidden_undefined "$r1_lib" "R1 raw_fcontext_reference" 'ontop_fcontext'
assert_locals_classified "$r1_lib" "R1 raw_fcontext_reference" "$asm_make" "$asm_jump"

echo
echo "== R0 boost_context_reference closure =="
r0_expected="$(cat <<'SYMEOF'
make_fcontext
jump_fcontext
ontop_fcontext
_ZN5boost7context6detail13jump_fcontextEPvS2_
_ZN5boost7context6detail13make_fcontextEPvmPFvNS1_10transfer_tEE
_ZN5boost7context6detail14ontop_fcontextEPvS2_PFNS1_10transfer_tES3_E
_ZN5boost7context12stack_traits12default_sizeEv
_ZN5boost7context12stack_traits12is_unboundedEv
_ZN5boost7context12stack_traits12maximum_sizeEv
_ZN5boost7context12stack_traits12minimum_sizeEv
_ZN5boost7context12stack_traits9page_sizeEv
SYMEOF
)"
echo "   required global definitions (demangled):"
while read -r n; do
  [ -n "$n" ] && printf '     %s\n' "$(demangle "$n")"
done <<<"$r0_expected"
assert_nm_reports_no_errors "$r0_lib" "R0 boost_context_reference"
assert_nm_entries_classified "$r0_lib" "R0 boost_context_reference"
assert_global_closure "$r0_lib" "R0 boost_context_reference" "$r0_expected"
assert_no_forbidden_defined "$r0_lib" "R0 boost_context_reference" 'continuation|fiber'
assert_no_forbidden_undefined "$r0_lib" "R0 boost_context_reference" 'continuation|fiber'
assert_locals_classified "$r0_lib" "R0 boost_context_reference" "$asm_make" "$asm_jump" "$asm_ontop"

echo
echo "== R1 test binary: no Boost symbol defined or referenced =="
assert_nm_reports_no_errors "$r1_bin" "R1 test_raw_fcontext"
assert_nm_entries_classified "$r1_bin" "R1 test_raw_fcontext"
# The complete symbol table (defined + undefined), demangled. --defined-only would
# not prove this: an undefined Boost reference would be invisible to it. Do not
# pipe into grep -q: with pipefail an early grep exit can SIGPIPE nm and turn a
# real match into a false-negative pipeline status, so match a captured copy.
if ! r1_bin_syms="$(nm -C "$r1_bin" 2>/dev/null)"; then
  fail "nm failed on $r1_bin"
fi
if grep -E 'boost::|_ZN?5boost' <<<"$r1_bin_syms" >/dev/null; then
  grep -E 'boost::|_ZN?5boost' <<<"$r1_bin_syms" | head -3 | sed 's/^/     /' >&2
  fail "test_raw_fcontext defines or references Boost symbols"
fi
echo "   complete symbol table is Boost-free"

if [ -n "${P0_SYMBOLS_CLOSURE_OUT:-}" ]; then
  {
    echo "# libboost_context_reference.a global defined symbols"
    global_defined "$r0_lib"
    echo "# libraw_fcontext_reference.a global defined symbols"
    global_defined "$r1_lib"
  } > "$P0_SYMBOLS_CLOSURE_OUT"
  echo
  echo "   global closure digest written to $P0_SYMBOLS_CLOSURE_OUT"
fi

echo
echo "P0 SYMBOLS: PASS"
