#!/usr/bin/env bash
# Negative controls for tools/verify/symbols.sh.
#
# Each control mutates a copy of a real release artifact and asserts that the
# oracle fails *for the expected reason*. Controls 1-3 inject a defined symbol
# whose nm class is not T -- exactly what the previous oracle
# (nm --defined-only | awk '$2 == "T"') could not see -- and the harness also
# proves mechanically that the injected name is invisible to that T-only filter,
# so "the previous oracle would have passed this" is demonstrated, not asserted.

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

# The pre-#3 oracle: defined symbols whose nm class is exactly T.
old_t_only() { nm --defined-only "$1" 2>/dev/null | awk '$2 == "T" { print $3 }' | sort -u; }

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

cc -c -O0 -fno-inline -o "$tmp/inject_weak.o"  "$tmp/inject_weak.c"
cc -c -O0 -fno-inline -o "$tmp/inject_fiber.o" "$tmp/inject_fiber.c"
cc -c -O0 -fno-inline -o "$tmp/inject_local.o" "$tmp/inject_local.c"
cc -c -O0 -o "$tmp/inject_unique.o" "$tmp/inject_unique.c"

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
cp "$libdir/libraw_fcontext_reference.a" "$tmp/r1_weak.a"
ar r "$tmp/r1_weak.a" "$tmp/inject_weak.o" 2>/dev/null
control_setup "$tmp/r1_weak.a" p0_injected_weak_symbol
expect_fail "R1 archive + unexpected defined weak (W) global symbol" \
  'unexpected extra global definition' P0_SYMBOLS_R1_LIB="$tmp/r1_weak.a"

# 2. R0 archive + local symbol in the forbidden continuation/fiber family.
cp "$libdir/libboost_context_reference.a" "$tmp/r0_fiber.a"
ar r "$tmp/r0_fiber.a" "$tmp/inject_fiber.o" 2>/dev/null
control_setup "$tmp/r0_fiber.a" p0_injected_fiber_probe
expect_fail "R0 archive + forbidden family symbol in a non-T class" \
  'forbidden implementation symbol' P0_SYMBOLS_R0_LIB="$tmp/r0_fiber.a"

# 3. R1 archive + unexpected local (t) symbol that is not in any known family.
cp "$libdir/libraw_fcontext_reference.a" "$tmp/r1_local.a"
ar r "$tmp/r1_local.a" "$tmp/inject_local.o" 2>/dev/null
control_setup "$tmp/r1_local.a" p0_injected_local_helper
expect_fail "R1 archive + unexpected local (t) symbol" \
  'unclassified local defined symbol' P0_SYMBOLS_R1_LIB="$tmp/r1_local.a"

# 4. R1 archive with a required primitive removed.
cp "$libdir/libraw_fcontext_reference.a" "$tmp/r1_missing.a"
member="$(ar t "$tmp/r1_missing.a" | grep 'make_x86_64_sysv_elf_gas' | head -1)"
[ -n "$member" ] || { echo "control setup error: make member not found" >&2; exit 1; }
ar d "$tmp/r1_missing.a" "$member"
expect_fail "R1 archive with the make_fcontext member removed" \
  'required global definition missing' P0_SYMBOLS_R1_LIB="$tmp/r1_missing.a"

# 5. Archive with a member nm cannot parse. nm reports this on stderr and keeps
#    going, so without the stderr assertion the member would silently vanish from
#    the inventory while every other assertion still passed.
cp "$libdir/libraw_fcontext_reference.a" "$tmp/r1_bogus.a"
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
cp "$libdir/libboost_context_reference.a" "$tmp/r0_unique.a"
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

echo "P0 SYMBOL ORACLE CONTROLS: PASS"
