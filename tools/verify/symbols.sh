#!/usr/bin/env bash
# P0 symbol closure inspection.
#
# Answers, from the real artifacts, what each reference layer actually contains:
#
#   1. the complete defined-symbol inventory of every archive, as
#      (archive member, symbol, nm class, ELF binding) entries with multiplicity
#      preserved;
#   2. an exact global defined-symbol closure per archive: multiset equality over
#      those entries, so a missing symbol, an extra symbol in any nm class, a
#      duplicated definition, and a required definition replaced by a same-name
#      definition of another class all fail; which side of the global/local
#      bucket an entry belongs to is decided by the ELF binding, not by the case
#      of the nm class letter;
#   3. forbidden-implementation-family assertions over every defined symbol of
#      every class (mangled and demangled names), and over undefined references;
#   4. classification of every local (STB_LOCAL) defined symbol: either a label of
#      a pinned upstream assembly source compiled into that target, or a
#      compiler-generated internal-linkage name (mangled '_Z...'). This is a
#      classification of the complete observed local set, not an allowlist of
#      local names -- a local symbol whose name already has that shape is accepted
#      without being enumerated. Unclassified local symbols fail.
#
#   5. the R1 test binary: its complete symbol table (defined and undefined,
#      demangled) must be free of Boost symbols, and every nm entry in it must
#      be classifiable.
#
# The complete defined-symbol set (all classes) is what the assertions run on.
# Three earlier revisions were weaker, and all three are why this file looks the
# way it does: one filtered 'nm --defined-only' down to class 'T' (blind to a
# defined symbol appearing as W/t/D/B/R); the next kept the (class, name) pairs
# but then compared only the *set of names* -- which loses the class, the
# defining archive member and the multiplicity, so a duplicated definition, or a
# strong definition replaced by a same-name weak one, stayed invisible; and the
# third bucketed global vs local by the nm letter case -- but the letter case is
# a display rendering, not a binding: GNU indirect functions render as lowercase
# 'i' and GNU unique objects as lowercase 'u' whatever their ELF binding is, so
# a globally bound definition could pass as a compiler-generated local. The ELF
# symbol table is the binding authority; the nm class remains part of the
# closure identity only.
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
# "archive[member.o]:" lines. The nm class letter is a display rendering of the
# symbol table entry, not a binding: readelf -Ws reports the ELF binding
# (LOCAL/GLOBAL/WEAK/UNIQUE) of every symbol, per archive member, and that
# report decides which bucket an entry belongs to.
#
# symbol_entries is the single extraction every defined-symbol assertion below
# runs on: every nm entry joined to its ELF symbol-table row on
# (archive member, name, value), emitted as
# "archive member, symbol, nm class, ELF binding" with multiplicity preserved.
# It fails instead of dropping anything it cannot parse or join: a dropped
# entry would silently shrink the closure that the assertions then compare
# against.

# nm layer: "archive member, symbol, nm class, value". The value becomes part of
# the join key; nm prints it as unpadded lowercase hex, so it is zero-stripped
# here (readelf pads it to the machine word width -- the same rule is applied on
# the readelf side). It fails instead of dropping anything it cannot parse: a
# dropped entry would silently shrink the closure that the assertions then
# compare against.
closure_entries() {
  local art="$1" label="$2" raw
  if ! raw="$(nm --format=posix --defined-only "$art" 2>/dev/null)"; then
    fail "$label: nm failed on $art"
  fi
  awk -v label="$label" '
    {
      if (substr($0, length($0), 1) == ":") {
        if ($0 !~ /^.*\[.*\]:$/) {
          printf "%s: nm output line ends with a colon but is not an archive member header: %s\n", label, $0 > "/dev/stderr"
          bad = 1
          next
        }
        member = $0
        sub(/^.*\[/, "", member)
        sub(/\]:$/, "", member)
        next
      }
      if (NF >= 3 && $2 ~ /^[A-Za-z]$/) {
        if ($2 == "U") {
          printf "%s: an undefined (U) entry appeared in nm --defined-only output: %s\n", label, $0 > "/dev/stderr"
          bad = 1
          next
        }
        if (member == "") {
          printf "%s: defined symbol %s appeared before any archive member header, so this artifact is not a static archive and member identity cannot be checked\n", label, $1 > "/dev/stderr"
          bad = 1
          next
        }
        value = tolower($3)
        sub(/^0+/, "", value)
        if (value == "") value = "0"
        printf "%s\t%s\t%s\t%s\n", member, $1, $2, value
        next
      }
      printf "%s: nm line that is neither an archive member header nor a symbol entry, so it would be dropped from the closure: %s\n", label, $0 > "/dev/stderr"
      bad = 1
    }
    END { if (bad) exit 3 }
  ' <<<"$raw"
}

# ELF layer: the authoritative defined-symbol rows of the symbol table, per
# archive member, as "archive member, name, value, binding". readelf also prints
# FILE and SECTION rows nm never lists, and UND rows carry no definition; those
# are not part of the nm inventory and are dropped here. A symbol row before any
# member header, or a row with fewer fields than the documented layout
# (value size type bind vis ndx name), fails instead of being attributed to the
# wrong member.
elf_bind_rows() {
  local art="$1" label="$2" raw
  if ! raw="$(readelf -Ws "$art" 2>/dev/null)"; then
    fail "$label: readelf failed on $art"
  fi
  awk -v label="$label" '
    /^File: .*\(.*\)/ {
      member = $0
      sub(/^.*\(/, "", member)
      sub(/\)[[:space:]]*$/, "", member)
      next
    }
    /^[[:space:]]*[0-9]+:/ {
      if (member == "") {
        printf "%s: readelf symbol row appeared before any archive member header: %s\n", label, $0 > "/dev/stderr"
        bad = 1
        next
      }
      line = $0
      sub(/^[[:space:]]*[0-9]+:[[:space:]]*/, "", line)
      n = split(line, f, /[[:space:]]+/)
      if (n < 6) {
        printf "%s: readelf symbol row with fewer fields than the documented layout: %s\n", label, $0 > "/dev/stderr"
        bad = 1
        next
      }
      if (f[3] == "FILE" || f[3] == "SECTION" || f[6] == "UND") next
      name = f[7]
      if (name == "") next
      for (i = 8; i <= n; i++) name = name " " f[i]
      value = tolower(f[1])
      sub(/^0+/, "", value)
      if (value == "") value = "0"
      printf "%s\t%s\t%s\t%s\n", member, name, value, f[4]
      next
    }
    END { if (bad) exit 3 }
  ' <<<"$raw"
}

# Join layer: appends the authoritative ELF binding to every nm entry, one output
# line per nm occurrence. The join itself is part of the oracle: the nm inventory
# and the readelf inventory must agree as multisets over
# (archive member, name, value). An nm entry with no symbol-table row, a
# symbol-table row the nm inventory does not list, a multiplicity mismatch, one
# position reporting two different bindings or nm classes, and a binding outside
# the set the oracle buckets on all fail instead of being resolved silently.
join_bindings() {
  local label="$1" nm_data="$2" elf_data="$3"
  awk -F'\t' -v label="$label" '
    NR == FNR {
      if ($0 == "") next
      k = $1 SUBSEP $2 SUBSEP $4
      if (!(k in seen)) { seen[k] = 1; keys[++nkeys] = k }
      nmcnt[k]++
      nmmem[k] = $1; nmname[k] = $2; nmval[k] = $4
      nmcls[k, $3] = 1
      next
    }
    {
      if ($0 == "") next
      k = $1 SUBSEP $2 SUBSEP $3
      if (!(k in seen)) { seen[k] = 1; keys[++nkeys] = k }
      elfcnt[k]++
      elfmem[k] = $1; elfname[k] = $2; elfval[k] = $3
      elfbind[k, $4] = 1
    }
    END {
      bad = 0
      for (ki = 1; ki <= nkeys; ki++) {
        k = keys[ki]
        if ((k in nmcnt) && !(k in elfcnt)) {
          printf "%s: nm lists defined symbol %s (archive member %s, value %s) but the ELF symbol table has no row at that position, so no binding can be joined\n", label, nmname[k], nmmem[k], nmval[k] > "/dev/stderr"
          bad = 1
          continue
        }
        if ((k in elfcnt) && !(k in nmcnt)) {
          printf "%s: the ELF symbol table defines %s (archive member %s, value %s) but the nm inventory does not list it; the inventory would silently shrink\n", label, elfname[k], elfmem[k], elfval[k] > "/dev/stderr"
          bad = 1
          continue
        }
        if (nmcnt[k] != elfcnt[k]) {
          printf "%s: (archive member %s, symbol %s, value %s) appears %d times in the nm inventory but %d times in the ELF symbol table\n", label, nmmem[k], nmname[k], nmval[k], nmcnt[k], elfcnt[k] > "/dev/stderr"
          bad = 1
          continue
        }
        ncls = 0; cls = ""
        for (ck in nmcls) if (index(ck, k SUBSEP) == 1) { ncls++; cls = substr(ck, length(k) + 2) }
        if (ncls != 1) {
          printf "%s: (archive member %s, symbol %s, value %s) carries %d distinct nm classes; the nm output cannot be classified unambiguously\n", label, nmmem[k], nmname[k], nmval[k], ncls > "/dev/stderr"
          bad = 1
          continue
        }
        nbind = 0; bind = ""
        for (bk in elfbind) if (index(bk, k SUBSEP) == 1) { nbind++; bind = substr(bk, length(k) + 2) }
        if (nbind != 1) {
          printf "%s: (archive member %s, symbol %s, value %s) reports %d distinct ELF bindings; the binding join is ambiguous\n", label, nmmem[k], nmname[k], nmval[k], nbind > "/dev/stderr"
          bad = 1
          continue
        }
        if (bind !~ /^(LOCAL|GLOBAL|WEAK|UNIQUE)$/) {
          printf "%s: ELF binding %s of symbol %s (archive member %s) is not a binding the oracle buckets on\n", label, bind, nmname[k], nmmem[k] > "/dev/stderr"
          bad = 1
          continue
        }
        joined[k] = nmmem[k] "\t" nmname[k] "\t" cls "\t" bind
      }
      if (bad) exit 3
      for (ki = 1; ki <= nkeys; ki++) {
        k = keys[ki]
        if (k in joined) for (c = 0; c < nmcnt[k]; c++) print joined[k]
      }
    }
  ' <(printf "%s\n" "$nm_data") <(printf "%s\n" "$elf_data")
}

symbol_entries() {
  local art="$1" label="$2" nm_data elf_data
  nm_data="$(closure_entries "$art" "$label")" || fail "$label: could not extract the nm defined-symbol inventory"
  elf_data="$(elf_bind_rows "$art" "$label")" || fail "$label: could not extract the ELF symbol-table bindings"
  join_bindings "$label" "$nm_data" "$elf_data"
}

# The ELF binding decides which closure bucket an entry belongs to; the nm class
# letter never does. GLOBAL and WEAK are bindings a linker resolves across
# objects, and UNIQUE (STB_GNU_UNIQUE) is a global binding with uniqueness
# semantics: all three are definitions the global closure must account for.
# Everything else (LOCAL) is classified by assert_locals_classified; an unknown
# binding already failed the join.
global_entries() { awk -F'\t' '$4 == "GLOBAL" || $4 == "WEAK" || $4 == "UNIQUE"'; }
local_entries()  { awk -F'\t' '$4 == "LOCAL"'; }

# Undefined entries keep their nm class: an undefined reference can be weak ('w',
# 'v'), and those omit the value field exactly like 'U' does. Filtering on
# "class == U" would hide a weakly referenced forbidden symbol.
undefined_entries() {
  nm --format=posix "$1" 2>/dev/null \
    | awk 'NF == 2 && $2 ~ /^[A-Za-z]$/ { printf "%s\t%s\n", $2, $1 }' | sort -u
}
undefined_names() { undefined_entries "$1" | awk -F'\t' '{ print $2 }' | sort -u; }
demangle() { c++filt <<<"$1"; }

# Expected closure entries are written as "<archive member>|<symbol>|<nm class>"
# (pipe-separated so the source stays readable) and converted to tabs here. The
# archive member is part of the closure: for a static archive, which member
# provides a definition is as much a property of the artifact as the name is.
expected_entries() {
  awk -F'|' '/^[[:space:]]*$/ { next }
               { if (NF == 3) printf "%s\t%s\t%s\n", $1, $2, $3; else print }'
}

assert_expected_entries_wellformed() {
  local label="$1" expected="$2" bad
  bad="$(awk -F'\t' 'NF != 3 || $1 == "" || $2 == "" || $3 == "" { print }' <<<"$expected")"
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" | head -5 | sed 's/^/     /' >&2
    fail "$label: expected-closure entry is not '<archive member>|<symbol>|<nm class>'"
  fi
}

inventory() {
  local label="$1" art="$2" entries
  if ! entries="$(symbol_entries "$art" "$label")"; then
    fail "$label: could not derive the defined-symbol inventory from the nm/ELF join (see above)"
  fi
  echo "-- $label complete defined-symbol inventory: $art"
  echo "   defined entries by nm class:"
  awk -F'\t' '{ print $3 }' <<<"$entries" | sort | uniq -c | awk '{ printf "     %s x %s\n", $2, $1 }'
  echo "   defined entries by ELF binding:"
  awk -F'\t' '{ print $4 }' <<<"$entries" | sort | uniq -c | awk '{ printf "     %s x %s\n", $2, $1 }'
  echo "   defined entries (nm class, symbol, archive member, ELF binding), multiplicity preserved:"
  awk -F'\t' '{ printf "     %s %s   [%s] bind %s\n", $3, $2, $1, $4 }' <<<"$entries" | sort
  echo "   undefined entries:"
  while IFS=$'\t' read -r cls name; do
    [ -n "$name" ] && printf '     %s %s\n' "$cls" "$name"
  done < <(undefined_entries "$art")
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

# Multiset equality over (archive member, symbol, nm class). Comparing the *set
# of names* instead would accept a duplicate definition, a definition that moved
# to another member, and a strong definition replaced by a same-name weak one --
# all three leave the name set unchanged while the artifact changed.
assert_global_closure() {
  local art="$1" label="$2" expected="$3"
  local entries report kind count member name cls n_entries
  assert_expected_entries_wellformed "$label" "$expected"
  if ! entries="$(symbol_entries "$art" "$label")"; then
    fail "$label: could not derive the global closure entries from the nm/ELF join (see above)"
  fi
  entries="$(global_entries <<<"$entries" | cut -f1-3 | sort)"
  report="$(awk -v expected="$expected" '
    BEGIN {
      n = split(expected, line, "\n")
      for (i = 1; i <= n; i++) if (line[i] != "") want[line[i]]++
    }
    { got[$0]++ }
    END {
      for (e in want) if (got[e] < want[e]) printf "MISSING\t%d\t%s\n", want[e] - got[e], e
      for (a in got) if (want[a] < got[a]) printf "EXTRA\t%d\t%s\n", got[a] - want[a], a
    }
  ' <<<"$entries" | sort)"
  while IFS=$'\t' read -r kind count member name cls; do
    [ -n "$kind" ] || continue
    printf '     %s x%s: class %s, symbol %s, archive member %s (%s)\n' \
      "$kind" "$count" "$cls" "$name" "$member" "$(demangle "$name")" >&2
  done <<<"$report"
  if grep -q '^MISSING' <<<"$report"; then
    fail "$label: required global definition missing (closure entry = archive member + symbol + nm class, multiplicity included)"
  fi
  if grep -q '^EXTRA' <<<"$report"; then
    fail "$label: unexpected extra global definition (any nm class counts, not only T; a duplicate definition or a same-name definition in another archive member counts too)"
  fi
  n_entries="$(awk 'NF { n++ } END { print n + 0 }' <<<"$entries")"
  echo "   exact global defined-symbol closure verified: $n_entries entries of (archive member, symbol, nm class), multiset equality"
}

assert_no_forbidden_defined() {
  local art="$1" label="$2" pattern="$3" entries member name cls bind d
  if ! entries="$(symbol_entries "$art" "$label")"; then
    fail "$label: could not derive the defined-symbol inventory from the nm/ELF join (see above)"
  fi
  while IFS=$'\t' read -r member name cls bind; do
    [ -n "$name" ] || continue
    d="$(demangle "$name")"
    if grep -Eq "$pattern" <<<"$name" || grep -Eq "$pattern" <<<"$d"; then
      fail "$label: forbidden implementation symbol present: $cls $name in archive member $member ($d)"
    fi
  done < <(printf '%s\n' "$entries")
}

assert_no_forbidden_undefined() {
  local art="$1" label="$2" pattern="$3" cls n d
  while IFS=$'\t' read -r cls n; do
    [ -n "$n" ] || continue
    d="$(demangle "$n")"
    if grep -Eq "$pattern" <<<"$n" || grep -Eq "$pattern" <<<"$d"; then
      fail "$label: forbidden symbol referenced but not defined: $cls $n ($d)"
    fi
  done < <(undefined_entries "$art")
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

# Classifies the complete observed local set; it does not enumerate an allowlist,
# so a local symbol whose name already looks compiler-generated is accepted by
# shape. The guarantee is "observed and classified", not "exactly listed".
assert_locals_classified() {
  local art="$1" label="$2" entries member name cls bind asm_labels=0 compiler_names=0
  shift 2
  if ! entries="$(symbol_entries "$art" "$label")"; then
    fail "$label: could not derive the local-symbol inventory from the nm/ELF join (see above)"
  fi
  while IFS=$'\t' read -r member name cls bind; do
    [ -n "$name" ] || continue
    if local_asm_label "$name" "$@"; then
      echo "   local symbol: $name -- label of a pinned upstream assembly source compiled into this target [$member]"
      asm_labels=$((asm_labels + 1))
    elif [[ "$name" == _Z* ]]; then
      echo "   local symbol: $name -- compiler-generated internal-linkage name [$member]"
      compiler_names=$((compiler_names + 1))
    else
      fail "$label: unclassified local defined symbol: $cls $name in archive member $member (neither a label of the pinned upstream assembly sources compiled into this target nor a compiler-generated '_Z' name)"
    fi
  done < <(local_entries <<<"$entries")
  echo "   local defined symbols observed and classified: $asm_labels upstream asm label(s), $compiler_names compiler-generated (classification of the complete observed local set, not an allowlist of local names)"
}

echo "P0 symbol closure inspection ($MODE)"

echo
echo "== complete defined-symbol inventory =="
# The nm-only guards run before any extraction so that an artifact nm itself
# cannot read fails on the nm report rather than deeper in the join.
assert_nm_reports_no_errors "$r1_lib" "R1 raw_fcontext_reference"
assert_nm_entries_classified "$r1_lib" "R1 raw_fcontext_reference"
inventory "R1" "$r1_lib"

echo
assert_nm_reports_no_errors "$r0_lib" "R0 boost_context_reference"
assert_nm_entries_classified "$r0_lib" "R0 boost_context_reference"
inventory "R0" "$r0_lib"

echo
echo "== R1 raw_fcontext_reference closure =="
r1_expected="$(expected_entries <<'SYMEOF'
make_x86_64_sysv_elf_gas.S.o|make_fcontext|T
jump_x86_64_sysv_elf_gas.S.o|jump_fcontext|T
SYMEOF
)"
assert_global_closure "$r1_lib" "R1 raw_fcontext_reference" "$r1_expected"
assert_no_forbidden_defined "$r1_lib" "R1 raw_fcontext_reference" 'ontop_fcontext'
assert_no_forbidden_undefined "$r1_lib" "R1 raw_fcontext_reference" 'ontop_fcontext'
assert_locals_classified "$r1_lib" "R1 raw_fcontext_reference" "$asm_make" "$asm_jump"

echo
echo "== R0 boost_context_reference closure =="
r0_expected="$(expected_entries <<'SYMEOF'
make_x86_64_sysv_elf_gas.S.o|make_fcontext|T
jump_x86_64_sysv_elf_gas.S.o|jump_fcontext|T
ontop_x86_64_sysv_elf_gas.S.o|ontop_fcontext|T
fcontext.cpp.o|_ZN5boost7context6detail13jump_fcontextEPvS2_|T
fcontext.cpp.o|_ZN5boost7context6detail13make_fcontextEPvmPFvNS1_10transfer_tEE|T
fcontext.cpp.o|_ZN5boost7context6detail14ontop_fcontextEPvS2_PFNS1_10transfer_tES3_E|T
stack_traits.cpp.o|_ZN5boost7context12stack_traits12default_sizeEv|T
stack_traits.cpp.o|_ZN5boost7context12stack_traits12is_unboundedEv|T
stack_traits.cpp.o|_ZN5boost7context12stack_traits12maximum_sizeEv|T
stack_traits.cpp.o|_ZN5boost7context12stack_traits12minimum_sizeEv|T
stack_traits.cpp.o|_ZN5boost7context12stack_traits9page_sizeEv|T
SYMEOF
)"
echo "   required global definitions (archive member | demangled symbol | nm class):"
while IFS=$'\t' read -r m n c; do
  [ -n "$n" ] && printf '     %s | %s | %s\n' "$m" "$(demangle "$n")" "$c"
done <<<"$r0_expected"
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
    printf '# libboost_context_reference.a global defined entries: <archive member>\t<symbol>\t<nm class>\t<ELF binding>\n'
    symbol_entries "$r0_lib" "R0 boost_context_reference" | global_entries | sort
    printf '# libraw_fcontext_reference.a global defined entries: <archive member>\t<symbol>\t<nm class>\t<ELF binding>\n'
    symbol_entries "$r1_lib" "R1 raw_fcontext_reference" | global_entries | sort
  } > "$P0_SYMBOLS_CLOSURE_OUT"
  echo
  echo "   global closure digest written to $P0_SYMBOLS_CLOSURE_OUT"
fi

echo
echo "P0 SYMBOLS: PASS"
