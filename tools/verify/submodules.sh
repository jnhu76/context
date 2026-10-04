#!/usr/bin/env bash
# P0 submodule identity oracle.
#
# For every direct submodule recorded in .gitmodules, requires
#
#     initialized  AND  submodule HEAD == superproject gitlink  AND  clean tree
#
# The superproject gitlink (the SHA recorded in the superproject HEAD tree) is
# the single authority for the expected identity. No submodule SHA is duplicated
# here, so this checks the git object graph instead of a copy of itself. The
# Boost.Context pin additionally has to agree with docs/UPSTREAM.md, xmake.lua
# and the recorded constant in tools/verify/p0.sh; that cross-check lives in
# p0.sh and is not repeated here.
#
# "initialized + clean working tree" is NOT identity: gitlink = A, HEAD = B with
# a clean tree is exactly the state this oracle has to reject.
#
# git submodule status prefixes are diagnostics only:
#   ' ' matches the gitlink, '-' is not initialized, '+' is a checkout that does
#   not match the gitlink recorded in the superproject index.
# Both '-' and '+' fail, but the direct gitlink/HEAD comparison above is what
# establishes identity; the prefix is never the correctness mechanism.
#
# Usage: tools/verify/submodules.sh [<superproject-root>]

set -euo pipefail

TARGET="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT="$(cd "$TARGET" && pwd)"
cd "$ROOT"

fail() { echo "P0 SUBMODULES: FAIL: $*" >&2; exit 1; }

[ -f .gitmodules ] || fail "no .gitmodules under $ROOT"

paths=()
while IFS= read -r -d '' record; do
  # --null emits "<key>\n<value>\0" per match. The submodule name defaults to the
  # path and may contain spaces, so the value is taken as everything after the
  # first newline rather than field-split.
  path="${record#*$'\n'}"
  [ -n "$path" ] && paths+=("$path")
done < <(git config --file .gitmodules --get-regexp --null '^submodule\..*\.path$')
[ "${#paths[@]}" -gt 0 ] || fail ".gitmodules records no submodule paths"

for sm in "${paths[@]}"; do
  [ -e "$sm/.git" ] || fail "$sm is not initialized (run: git submodule update --init --recursive)"

  # The recorded path must be the git worktree of that checkout. A .git file with
  # a redirected core.worktree can report HEAD == gitlink and a clean tree while
  # the recorded directory holds none of the files.
  if ! toplevel_raw="$(git -C "$sm" rev-parse --show-toplevel 2>/dev/null)"; then
    fail "$sm: cannot resolve the git worktree root of the submodule"
  fi
  toplevel="$(cd "$toplevel_raw" && pwd -P)"
  recorded_toplevel="$(cd "$sm" && pwd -P)"
  [ "$toplevel" = "$recorded_toplevel" ] \
    || fail "$sm worktree path mismatch: git reports '$toplevel', the recorded submodule path is '$recorded_toplevel'"

  entry="$(git ls-tree HEAD -- "$sm")"
  [ -n "$entry" ] || fail "$sm has no entry in the superproject HEAD tree"
  mode="$(awk 'NR == 1 { print $1 }' <<<"$entry")"
  kind="$(awk 'NR == 1 { print $2 }' <<<"$entry")"
  gitlink="$(awk 'NR == 1 { print $3 }' <<<"$entry")"
  [ "$mode" = "160000" ] && [ "$kind" = "commit" ] \
    || fail "$sm HEAD tree entry is '$mode $kind', not a 160000 commit gitlink"

  head_sha="$(git -C "$sm" rev-parse HEAD 2>/dev/null)" || fail "$sm: cannot resolve submodule HEAD"
  [ "$head_sha" = "$gitlink" ] \
    || fail "$sm identity mismatch: submodule HEAD $head_sha != superproject gitlink $gitlink"

  dirty="$(git -C "$sm" status --porcelain)"
  [ -z "$dirty" ] || fail "$sm working tree is not clean:
$dirty"

  echo "   ok: $sm gitlink == HEAD == $gitlink, clean"
done

status_out="$(git submodule status --recursive)"
if grep -q '^-' <<<"$status_out"; then
  fail "git submodule status reports an uninitialized submodule ('-' prefix):
$status_out"
fi
if grep -q '^+' <<<"$status_out"; then
  fail "git submodule status reports a checkout that does not match the gitlink recorded in the superproject index ('+' prefix):
$status_out"
fi

echo "   submodule identities verified: ${#paths[@]} (initialized, gitlink == HEAD, clean)"
