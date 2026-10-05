#!/usr/bin/env bash
# Negative controls for tools/verify/submodules.sh.
#
# Builds a throwaway superproject in a temp directory with one submodule pinned
# at a recorded gitlink, then asserts that the identity oracle
#
#   * passes  when HEAD == gitlink and the working tree is clean;
#   * fails   when HEAD != gitlink and the working tree is clean ("wrong but
#             clean", the state issue #3 is about) -- and fails with the
#             identity-mismatch reason, not merely because of a status prefix;
#   * fails   when HEAD == gitlink but the working tree is dirty.
#
# No network access and no writes to the real submodules: the submodule origin is
# a local repository created inside the temp directory.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

ORACLE="tools/verify/submodules.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

gitq() {
  git -c user.name=p0-verify -c user.email=p0-verify@invalid \
      -c protocol.file.allow=always -c commit.gpgsign=false "$@"
}

origin="$tmp/origin"
super="$tmp/super"
mkdir -p "$origin" "$super"

gitq -C "$origin" init -q -b main
echo "one" > "$origin/file.txt"
gitq -C "$origin" add file.txt
gitq -C "$origin" commit -q -m "commit A"
commit_a="$(gitq -C "$origin" rev-parse HEAD)"
echo "two" >> "$origin/file.txt"
gitq -C "$origin" add file.txt
gitq -C "$origin" commit -q -m "commit B"
commit_b="$(gitq -C "$origin" rev-parse HEAD)"

make_super() {  # <superproject-dir>: pin 'sub' at commit B
  mkdir -p "$1"
  gitq -C "$1" init -q -b main
  gitq -C "$1" submodule add -q "$origin" sub
  gitq -C "$1" commit -q -m "pin sub at commit B"
}

make_super "$super"

expect_pass() {
  local desc="$1" out
  if ! out="$(bash "$ORACLE" "$super" 2>&1)"; then
    echo "NEGATIVE CONTROL FAILED (oracle rejected a valid superproject): $desc" >&2
    echo "$out" >&2
    exit 1
  fi
  echo "   ok (oracle passes): $desc"
}

expect_fail() {
  local desc="$1" pattern="$2" out status
  set +e
  out="$(bash "$ORACLE" "$super" 2>&1)"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "NEGATIVE CONTROL FAILED (oracle accepted an invalid superproject): $desc" >&2
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
  echo "      $(grep -m1 'P0 SUBMODULES: FAIL' <<<"$out" | cut -c1-150)"
}

expect_pass "submodule HEAD == gitlink, clean working tree"

if [ "$(gitq -C "$super/sub" rev-parse HEAD)" != "$commit_b" ]; then
  echo "control setup error: submodule is not at commit B" >&2
  exit 1
fi

gitq -C "$super/sub" checkout -q "$commit_a"
if [ -n "$(gitq -C "$super/sub" status --porcelain)" ]; then
  echo "control setup error: the wrong-commit checkout is not clean" >&2
  exit 1
fi
expect_fail "submodule HEAD != gitlink with a clean working tree" 'identity mismatch'

gitq -C "$super/sub" checkout -q "$commit_b"
echo "local edit" >> "$super/sub/file.txt"
expect_fail "submodule HEAD == gitlink but the working tree is dirty" 'not clean'

# 4. Staged gitlink change: the superproject index records a different commit
#    than the HEAD tree while the submodule itself matches the HEAD tree and is
#    clean. The gitlink/HEAD comparison cannot see this by construction; the '+'
#    diagnostic has to, otherwise a commit identity change could sit staged
#    while the gate stays green.
gitq -C "$super/sub" checkout -q -- .
gitq -C "$super/sub" checkout -q "$commit_b"
gitq -C "$super/sub" checkout -q "$commit_a"
gitq -C "$super" add sub
gitq -C "$super/sub" checkout -q "$commit_b"
if [ -n "$(gitq -C "$super/sub" status --porcelain)" ]; then
  echo "control setup error: the staged-change checkout is not clean" >&2
  exit 1
fi
expect_fail "staged gitlink change (index != HEAD tree), matching clean checkout" 'superproject index'

# 5. Forged worktree redirection: the recorded path holds only a .git file whose
#    worktree is a second clone of the same commit elsewhere on disk. HEAD equals
#    the gitlink and git reports a clean tree, so only the path-level check can
#    see that the recorded directory contains none of the files.
gitq clone -q --no-checkout "$origin" "$tmp/elsewhere"
gitq -C "$tmp/elsewhere" checkout -q "$commit_b"
gitq -C "$super/.git/modules/sub" config core.worktree "$tmp/elsewhere"
rm -rf "$super/sub"
mkdir -p "$super/sub"
printf 'gitdir: ../.git/modules/sub\n' > "$super/sub/.git"
if [ "$(gitq -C "$super/sub" rev-parse HEAD)" != "$commit_b" ]; then
  echo "control setup error: the forged redirect does not resolve to commit B" >&2
  exit 1
fi
if [ -n "$(gitq -C "$super/sub" status --porcelain)" ]; then
  echo "control setup error: the forged redirect does not report a clean tree" >&2
  exit 1
fi
expect_fail "forged worktree redirection: clean tree and matching HEAD outside the recorded path" \
  'worktree path mismatch'

echo "P0 SUBMODULE ORACLE CONTROLS: PASS"
