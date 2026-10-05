#!/usr/bin/env bash
# Negative controls for tools/verify/symbols.sh.
#
# Each control mutates a copy of a real release artifact and asserts that the
# oracle fails *for the expected reason*.
#
# Three removed blind spots are demonstrated mechanically here rather than
# asserted:
#
#   * controls 1-3 inject a defined symbol whose nm class is not T -- exactly what
#     the first oracle (nm --defined-only | awk '$2 == "T"') could not see -- and
#     the harness proves the injected name is invisible to that T-only filter;
#   * controls 7-10 change the artifact while leaving the *set of global defined
#     symbol names* byte-identical to the real archive -- exactly the projection
#     the second oracle compared -- and the harness proves that invariance. So
#     "the previous oracle would have accepted this artifact" is demonstrated, not
#     claimed. These four are what a name-set projection cannot see: an extra weak
#     definition of an allowed name, an extra strong definition of an allowed name
#     in a second archive member, a duplicate definition under the same member
#     name, and a required strong definition replaced by a same-name weak one.
#   * controls 11-12 compile two GNU indirect functions with the same nm class
#     letter but opposite ELF bindings -- exactly what the third oracle (global =
#     'u' or uppercase class) could not distinguish. The GLOBAL one has a
#     compiler-generated '_Z' name and leaves the letter-case projection
#     byte-identical to the real archive, so it had to pass as
#     "compiler-generated"; the LOCAL one must be classified like any other
#     local. The ELF binding is what tells them apart.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

MODE=release
libdir="build/linux/x86_64/$MODE"
ORACLE="tools/verify/symbols.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for tool in ar cc nm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "required tool not found: $tool" >&2; exit 1; }
done
for f in "$libdir/libraw_fcontext_reference.a" "$libdir/libboost_context_reference.a"; do
  [ -f "$f" ] || { echo "missing $f (run: xmake f -m $MODE && xmake)" >&2; exit 1; }
done

r1_real="$libdir/libraw_fcontext_reference.a"
r0_real="$libdir/libboost_context_reference.a"
r1_make_member="make_x86_64_sysv_elf_gas.S.o"

# The first oracle: defined symbols whose nm class is exactly T.
old_t_only() { nm --defined-only "$1" 2>/dev/null | awk '$2 == "T" { print $3 }' | sort -u; }

# The projection the second oracle compared: the *set* of global defined symbol
# names, with the nm class, the defining archive member and the multiplicity all
# dropped. Reimplemented here (a few lines of nm + awk) only so the controls can
# show that a mutated artifact leaves it unchanged; the oracle no longer computes
# it at all.
old_name_set() {
  nm --format=posix --defined-only "$1" 2>/dev/null \
    | awk 'NF >= 3 && $2 ~ /^[A-Za-z]$/ { print $2 "\t" $1 }' | sort -u \
    | awk -F'\t' '$1 == "u" || ($1 ~ /^[A-Z]$/ && $1 != "U") { print $2 }' | sort -u
}

# (archive member, symbol, nm class) occurrence count: proves the mutation landed
# before the oracle is asked to reject it.
count_member_entries() {
  local art="$1" member="$2" sym="$3" cls="$4"
  nm --format=posix --defined-only "$art" 2>/dev/null | awk -v m="$member" -v s="$sym" -v c="$cls" '
    substr($0, length($0), 1) == ":" { mm = $0; sub(/^.*\[/, "", mm); sub(/\]:$/, "", mm); next }
    NF >= 3 && mm == m && $1 == s && $2 == c { n++ }
    END { print n + 0 }'
}

cat > "$tmp/inject_weak.c" <<'CEOF'
/* Defined weak symbol: nm class W. Invisible to a T-only filter. */
__attribute__((weak)) int p0_injected_weak_symbol(void) { return 1; }
CEOF

cat > "$tmp/inject_fiber.c" <<'CEOF'
/* Defined local symbol in the forbidden family: nm class t. Invisible to a T-only filter. */
__attribute__((used, noinline)) static int p0_injected_fiber_probe(void) { return 2; }
CEOF

cat > "$tmp/inject_local.c" <<'CEOF'
/* Defined local symbol outside the forbidden family: nm class t. Invisible to a T-only filter. */
__attribute__((used, noinline)) static int p0_injected_local_helper(void) { return 3; }
CEOF

cat > "$tmp/inject_unique.c" <<'CEOF'
/* One GNU-unique global object: readelf reports its binding as UNIQUE (not
   LOCAL), while its name looks like a compiler-generated internal-linkage entity.
   Bucketing the lowercase 'u' with the local symbols would let this globally
   bound symbol pass as "compiler-generated". */
__asm__(
    ".globl _ZZ24p0_injected_unique_probeE5value\n"
    ".type _ZZ24p0_injected_unique_probeE5value, @gnu_unique_object\n"
    ".size _ZZ24p0_injected_unique_probeE5value, 4\n"
    "_ZZ24p0_injected_unique_probeE5value:\n"
    "  .long 7\n");
CEOF

cat > "$tmp/weak_make.c" <<'CEOF'
/* Same name as a required definition, but weak: nm class W instead of T. */
__attribute__((weak)) void make_fcontext(void) {}
CEOF

cat > "$tmp/strong_make.c" <<'CEOF'
/* Same name as a required definition, also strong (T), in a second member. */
void make_fcontext(void) {}
CEOF

cc -c -O0 -fno-inline -o "$tmp/inject_weak.o"  "$tmp/inject_weak.c"
cc -c -O0 -fno-inline -o "$tmp/inject_fiber.o" "$tmp/inject_fiber.c"
cc -c -O0 -fno-inline -o "$tmp/inject_local.o" "$tmp/inject_local.c"
cc -c -O0 -o "$tmp/inject_unique.o" "$tmp/inject_unique.c"
cc -c -o "$tmp/weak_make.o" "$tmp/weak_make.c"
cc -c -o "$tmp/strong_make.o" "$tmp/strong_make.c"

# Fails the harness if the injected symbol is not actually defined, or if the
# T-only filter *can* see it (which would make the control meaningless).
control_setup() {
  local art="$1" name="$2"
  if ! nm --format=posix --defined-only "$art" | grep -q "^$name "; then
    echo "control setup error: $name is not defined in $art" >&2
    exit 1
  fi
  if old_t_only "$art" | grep -qx "$name"; then
    echo "control setup error: $name is visible to the T-only filter, so this control does not exercise the blind spot" >&2
    exit 1
  fi
  echo "   (control setup: $name is defined, nm class != T, invisible to the T-only filter)"
}

# Fails the harness unless the mutated artifact has exactly the same global
# defined-symbol *name set* as the real archive. That projection is what the
# previous oracle compared, so this is the mechanical proof that the previous
# oracle could not distinguish the artifact from the real one.
control_setup_name_invariant() {
  local real="$1" art="$2"
  if ! diff <(old_name_set "$real") <(old_name_set "$art") >/dev/null; then
    echo "control setup error: the global name-set projection of $art differs from the real archive, so this control does not exercise the name-set blind spot" >&2
    diff <(old_name_set "$real") <(old_name_set "$art") >&2
    exit 1
  fi
  echo "   (control setup: global name-set projection byte-identical to the real archive; only class/member/multiplicity changed)"
}

# The projection the third oracle bucketed on: global defined names by nm letter
# case ('u' or uppercase). Reimplemented here only so the controls can show that
# the GLOBAL IFUNC leaves it byte-identical -- the blind spot the binding join
# removes.
old_case_global_names() {
  nm --format=posix --defined-only "$1" 2>/dev/null \
    | awk 'NF >= 3 && $2 ~ /^[A-Za-z]$/ { print $2 "\t" $1 }' | sort -u \
    | awk -F'\t' '$1 == "u" || ($1 ~ /^[A-Z]$/ && $1 != "U") { print $2 }' | sort -u
}

# Fails the harness unless the mutated archive has exactly the same letter-case
# global defined-name projection as the real archive -- what the case-based
# oracle compared, so this is the mechanical proof that it could not distinguish
# the artifact from the real one.
control_setup_case_invariant() {
  local real="$1" art="$2"
  if ! diff <(old_case_global_names "$real") <(old_case_global_names "$art") >/dev/null; then
    echo "control setup error: the letter-case global-name projection of $art differs from the real archive, so this control does not exercise the letter-case blind spot" >&2
    diff <(old_case_global_names "$real") <(old_case_global_names "$art") >&2
    exit 1
  fi
  echo "   (control setup: letter-case global-name projection byte-identical to the real archive)"
}

# Fails the harness unless the archive defines `name` with nm class `cls` and
# readelf reports it as IFUNC with binding `bind` -- the exact (class, binding)
# pair the control is about.
control_setup_ifunc_binding() {
  local art="$1" name="$2" cls="$3" bind="$4"
  if ! nm --format=posix --defined-only "$art" 2>/dev/null | awk -v n="$name" -v c="$cls" '$1 == n && $2 == c { found = 1 } END { exit !found }'; then
    echo "control setup error: $name is not defined with nm class $cls in $art" >&2
    exit 1
  fi
  if ! readelf -Ws "$art" 2>/dev/null | awk -v n="$name" -v b="$bind" '$4 == "IFUNC" && $5 == b && $8 == n { found = 1 } END { exit !found }'; then
    echo "control setup error: readelf does not report IFUNC $bind for $name in $art" >&2
    exit 1
  fi
  echo "   (control setup: $name is nm class $cls, readelf IFUNC $bind)"
}

# The mirror image of expect_fail: a control artifact the oracle must ACCEPT, and
# the classification line that proves the injected symbol went down the expected
# path -- not silently.
expect_pass() {
  local desc="$1" pattern="$2"
  shift 2
  local out status
  set +e
  out="$(env P0_SYMBOLS_ALLOW_OVERRIDE=1 "$@" bash "$ORACLE" "$MODE" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    echo "NEGATIVE CONTROL FAILED (oracle rejected a good artifact): $desc" >&2
    echo "$out" >&2
    exit 1
  fi
  if ! grep -Eq "$pattern" <<<"$out"; then
    echo "NEGATIVE CONTROL FAILED (expected classification line missing): $desc" >&2
    echo "   expected to match: $pattern" >&2
    echo "$out" >&2
    exit 1
  fi
  echo "   ok (oracle passes): $desc"
}

control_expect_count() {
  local art="$1" member="$2" sym="$3" cls="$4" want="$5" got
  got="$(count_member_entries "$art" "$member" "$sym" "$cls")"
  if [ "$got" != "$want" ]; then
    echo "control setup error: expected $want x ($member, $sym, $cls) in $art, found $got" >&2
    exit 1
  fi
  echo "   (control setup: $got x ($member, $sym, $cls))"
}

expect_fail() {
  local desc="$1" pattern="$2"
  shift 2
  local out status
  set +e
  # The oracle refuses redirected artifacts unless the opt-in is explicit, so the
  # controls cannot silently become the gate's own configuration.
  out="$(env P0_SYMBOLS_ALLOW_OVERRIDE=1 "$@" bash "$ORACLE" "$MODE" 2>&1)"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "NEGATIVE CONTROL FAILED (oracle accepted a bad artifact): $desc" >&2
    echo "$out" >&2
    exit 1
  fi
  if ! grep -Eq "$pattern" <<<"$out"; then
    echo "NEGATIVE CONTROL FAILED (wrong failure reason): $desc" >&2
    echo "   expected to match: $pattern" >&2
    echo "$out" >&2
    exit 1
  fi
  echo "   ok (oracle fails): $desc"
  echo "      $(grep -m1 'P0 SYMBOLS: FAIL' <<<"$out" | cut -c1-150)"
}

echo "P0 symbol closure oracle negative controls"

# 1. R1 archive + unexpected defined weak (W) global symbol.
cp "$r1_real" "$tmp/r1_weak.a"
ar r "$tmp/r1_weak.a" "$tmp/inject_weak.o" 2>/dev/null
control_setup "$tmp/r1_weak.a" p0_injected_weak_symbol
expect_fail "R1 archive + unexpected defined weak (W) global symbol" \
  'unexpected extra global definition' P0_SYMBOLS_R1_LIB="$tmp/r1_weak.a"

# 2. R0 archive + local symbol in the forbidden continuation/fiber family.
cp "$r0_real" "$tmp/r0_fiber.a"
ar r "$tmp/r0_fiber.a" "$tmp/inject_fiber.o" 2>/dev/null
control_setup "$tmp/r0_fiber.a" p0_injected_fiber_probe
expect_fail "R0 archive + forbidden family symbol in a non-T class" \
  'forbidden implementation symbol' P0_SYMBOLS_R0_LIB="$tmp/r0_fiber.a"

# 3. R1 archive + unexpected local (t) symbol that is not in any known family.
cp "$r1_real" "$tmp/r1_local.a"
ar r "$tmp/r1_local.a" "$tmp/inject_local.o" 2>/dev/null
control_setup "$tmp/r1_local.a" p0_injected_local_helper
expect_fail "R1 archive + unexpected local (t) symbol" \
  'unclassified local defined symbol' P0_SYMBOLS_R1_LIB="$tmp/r1_local.a"

# 4. R1 archive with a required primitive removed.
cp "$r1_real" "$tmp/r1_missing.a"
member="$(ar t "$tmp/r1_missing.a" | grep 'make_x86_64_sysv_elf_gas' | head -1)"
[ -n "$member" ] || { echo "control setup error: make member not found" >&2; exit 1; }
ar d "$tmp/r1_missing.a" "$member"
expect_fail "R1 archive with the make_fcontext member removed" \
  'required global definition missing' P0_SYMBOLS_R1_LIB="$tmp/r1_missing.a"

# 5. Archive with a member nm cannot parse. nm reports this on stderr and keeps
#    going, so without the stderr assertion the member would silently vanish from
#    the inventory while every other assertion still passed.
cp "$r1_real" "$tmp/r1_bogus.a"
printf 'this is not an object file\n' > "$tmp/not-an-object.txt"
ar r "$tmp/r1_bogus.a" "$tmp/not-an-object.txt" 2>/dev/null
if ! nm --format=posix "$tmp/r1_bogus.a" 2>&1 >/dev/null | grep -q 'file format not recognized'; then
  echo "control setup error: nm did not report the bogus member" >&2
  exit 1
fi
expect_fail "R1 archive with a member nm cannot parse" \
  'nm reported an error' P0_SYMBOLS_R1_LIB="$tmp/r1_bogus.a"

# 6. GNU-unique global symbol (nm class u, readelf binding UNIQUE). Treating the
#    lowercase 'u' as a local symbol would let an extra globally bound symbol pass
#    as "compiler-generated".
cp "$r0_real" "$tmp/r0_unique.a"
ar r "$tmp/r0_unique.a" "$tmp/inject_unique.o" 2>/dev/null
if ! nm --format=posix --defined-only "$tmp/inject_unique.o" | awk '$2 == "u" { print $1 }' | grep -q '^_ZZ'; then
  echo "control setup error: the injected object defines no unique (u) symbol" >&2
  exit 1
fi
if ! readelf -Ws "$tmp/inject_unique.o" 2>/dev/null | grep -q 'OBJECT  *UNIQUE'; then
  echo "control setup error: readelf does not report a UNIQUE binding" >&2
  exit 1
fi
expect_fail "R0 archive + GNU-unique (u) global symbol outside the closure" \
  'unexpected extra global definition' P0_SYMBOLS_R0_LIB="$tmp/r0_unique.a"

# --- controls 7-10: artifacts the name-set projection cannot distinguish -------

# 7. An allowed name gains a *weak* definition in a second member. The name set is
#    unchanged; the class of the extra definition is W, so a comparison that keeps
#    only names accepts it.
mkdir -p "$tmp/inj7"
cp "$tmp/weak_make.o" "$tmp/inj7/inject_weak_make.o"
cp "$r1_real" "$tmp/r1_dup_weak.a"
ar r "$tmp/r1_dup_weak.a" "$tmp/inj7/inject_weak_make.o" 2>/dev/null
control_setup_name_invariant "$r1_real" "$tmp/r1_dup_weak.a"
control_expect_count "$tmp/r1_dup_weak.a" inject_weak_make.o make_fcontext W 1
control_expect_count "$tmp/r1_dup_weak.a" "$r1_make_member" make_fcontext T 1
expect_fail "R1 archive + allowed name make_fcontext also defined weak (W) in a second member" \
  'unexpected extra global definition' P0_SYMBOLS_R1_LIB="$tmp/r1_dup_weak.a"

# 8. An allowed name gains a *strong* definition in a second member: two different
#    archive members both define T make_fcontext. The name set is unchanged again.
mkdir -p "$tmp/inj8"
cp "$tmp/strong_make.o" "$tmp/inj8/inject_strong_make.o"
cp "$r1_real" "$tmp/r1_dup_strong.a"
ar r "$tmp/r1_dup_strong.a" "$tmp/inj8/inject_strong_make.o" 2>/dev/null
control_setup_name_invariant "$r1_real" "$tmp/r1_dup_strong.a"
control_expect_count "$tmp/r1_dup_strong.a" inject_strong_make.o make_fcontext T 1
control_expect_count "$tmp/r1_dup_strong.a" "$r1_make_member" make_fcontext T 1
expect_fail "R1 archive + two different members defining T make_fcontext" \
  'unexpected extra global definition' P0_SYMBOLS_R1_LIB="$tmp/r1_dup_strong.a"

# 9. The duplicate lands under the *same* archive member name, so even an oracle
#    that keeps the member dimension must fall back on multiplicity to see it.
#    ar q is used because ar r would replace the member instead of adding it.
mkdir -p "$tmp/inj9"
cp "$tmp/strong_make.o" "$tmp/inj9/$r1_make_member"
cp "$r1_real" "$tmp/r1_dup_member.a"
ar q "$tmp/r1_dup_member.a" "$tmp/inj9/$r1_make_member" 2>/dev/null
if [ "$(ar t "$tmp/r1_dup_member.a" | grep -cx "$r1_make_member")" != "2" ]; then
  echo "control setup error: expected two members named $r1_make_member" >&2
  exit 1
fi
control_setup_name_invariant "$r1_real" "$tmp/r1_dup_member.a"
control_expect_count "$tmp/r1_dup_member.a" "$r1_make_member" make_fcontext T 2
expect_fail "R1 archive + duplicate T make_fcontext under the same member name" \
  'unexpected extra global definition' P0_SYMBOLS_R1_LIB="$tmp/r1_dup_member.a"

# 10. A required strong definition is *replaced* by a same-name weak one in the
#     same member. Nothing is added and nothing is renamed: only the nm class of
#     an existing entry changed, which a name-set projection cannot represent.
mkdir -p "$tmp/inj10"
cp "$tmp/weak_make.o" "$tmp/inj10/$r1_make_member"
cp "$r1_real" "$tmp/r1_weak_replace.a"
member="$(ar t "$tmp/r1_weak_replace.a" | grep -cx "$r1_make_member")"
[ "$member" = "1" ] || { echo "control setup error: expected one $r1_make_member member" >&2; exit 1; }
ar d "$tmp/r1_weak_replace.a" "$r1_make_member"
ar r "$tmp/r1_weak_replace.a" "$tmp/inj10/$r1_make_member" 2>/dev/null
control_setup_name_invariant "$r1_real" "$tmp/r1_weak_replace.a"
control_expect_count "$tmp/r1_weak_replace.a" "$r1_make_member" make_fcontext T 0
control_expect_count "$tmp/r1_weak_replace.a" "$r1_make_member" make_fcontext W 1
expect_fail "R1 archive + required T make_fcontext replaced by a same-name weak definition" \
  'required global definition missing' P0_SYMBOLS_R1_LIB="$tmp/r1_weak_replace.a"

# 11. A GLOBAL GNU indirect function whose name has the compiler-generated '_Z'
#     shape: nm renders it lowercase 'i', so bucketing by letter case passes it
#     as a compiler-generated local and the extra global definition stays
#     invisible to the closure. readelf reports it as IFUNC GLOBAL.
cat > "$tmp/inject_ifunc_global.c" <<'CEOF'
/* GLOBAL GNU indirect function: nm class 'i' (lowercase), readelf binding
   GLOBAL. Every name in this object has the compiler-generated '_Z' shape that
   letter-case bucketing accepts as a local. */
static void _Zp0_ifunc_impl(void) {}
static void *_Zp0_ifunc_resolve(void) { return (void *)_Zp0_ifunc_impl; }
void _Zp0_global_ifunc(void) __attribute__((ifunc("_Zp0_ifunc_resolve")));
CEOF
cc -c -O0 -o "$tmp/inject_ifunc_global.o" "$tmp/inject_ifunc_global.c"
cp "$r1_real" "$tmp/r1_ifunc_global.a"
ar r "$tmp/r1_ifunc_global.a" "$tmp/inject_ifunc_global.o" 2>/dev/null
control_setup_case_invariant "$r1_real" "$tmp/r1_ifunc_global.a"
control_setup_ifunc_binding "$tmp/r1_ifunc_global.a" _Zp0_global_ifunc i GLOBAL
expect_fail "R1 archive + GLOBAL IFUNC with a compiler-generated (_Z) name outside the closure" \
  'unexpected extra global definition' P0_SYMBOLS_R1_LIB="$tmp/r1_ifunc_global.a"

# 12. A LOCAL GNU indirect function: the same nm class letter as control 11 with
#     the opposite ELF binding. A discriminator that only read "class i means
#     global" would reject this artifact; the binding join classifies it like any
#     other compiler-generated local and the whole oracle must still pass.
cat > "$tmp/inject_ifunc_local.c" <<'CEOF'
/* LOCAL GNU indirect function: nm class 'i' (the same letter as the GLOBAL one
   in control 11), readelf binding LOCAL. */
static void _Zp0_ifunc_limpl(void) {}
static void *_Zp0_ifunc_lresolve(void) { return (void *)_Zp0_ifunc_limpl; }
__attribute__((ifunc("_Zp0_ifunc_lresolve"), used)) static void _Zp0_local_ifunc(void);
CEOF
cc -c -O0 -o "$tmp/inject_ifunc_local.o" "$tmp/inject_ifunc_local.c"
cp "$r1_real" "$tmp/r1_ifunc_local.a"
ar r "$tmp/r1_ifunc_local.a" "$tmp/inject_ifunc_local.o" 2>/dev/null
control_setup_ifunc_binding "$tmp/r1_ifunc_local.a" _Zp0_local_ifunc i LOCAL
expect_pass "R1 archive + LOCAL IFUNC classified as a compiler-generated local" \
  '_Zp0_local_ifunc -- compiler-generated' P0_SYMBOLS_R1_LIB="$tmp/r1_ifunc_local.a"

echo "P0 SYMBOL ORACLE CONTROLS: PASS"
