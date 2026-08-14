#!/usr/bin/env bash
# necro-file-mtime-test.sh — necro_file_mtime returns ONE clean epoch integer
# on whatever platform it runs on.
#
# The bug this guards: `stat -f %m "$f" 2>/dev/null || stat -c %Y "$f"` looks
# like a portable pair, but GNU's -f is --file-system, so `%m` is read as a
# second operand. GNU stat prints the filesystem report for "$f" to stdout,
# exits non-zero because the file named `%m` is missing, and the `||` branch
# then appends the real mtime to that output. The caller gets a multi-word
# string, every `-lt` comparison against it errors under `set -u`, and the
# failure is silent: the min_epoch staleness filter (invariant 9) stops
# rejecting anything on Linux/WSL2 and the 60s lock-age recovery never fires.
#
# Asserting "digits, nothing else" catches that on both platforms, and catches
# a re-reordering of the two stat calls immediately rather than three layers
# down in a min-epoch assertion.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
. "$ROOT/lib/common.sh"

fail=0

f="$TMP/probe"
printf 'x\n' > "$f"

got="$(necro_file_mtime "$f")"
case "$got" in
  ''|*[!0-9]*) echo "FAIL: not a bare epoch integer: [$got]"; fail=1 ;;
esac

# Directories matter too — both lock-age checks stat a lock DIR, not a file.
got_dir="$(necro_file_mtime "$TMP")"
case "$got_dir" in
  ''|*[!0-9]*) echo "FAIL: directory mtime is not a bare integer: [$got_dir]"; fail=1 ;;
esac

# It must be usable in arithmetic directly — that is how every caller uses it.
now="$(date +%s)"
if ! [ "$(( now - got ))" -ge 0 ] 2>/dev/null; then
  echo "FAIL: result unusable in arithmetic: [$got]"; fail=1
fi

# A missing path yields empty, not garbage: callers guard on [ -n "$mtime" ].
missing="$(necro_file_mtime "$TMP/nope")"
[ -z "$missing" ] || { echo "FAIL: missing path should yield empty, got [$missing]"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS: necro_file_mtime returns one clean epoch integer"
exit "$fail"
