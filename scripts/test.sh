#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
oreslang_bin="${ORESLANG_BIN:-$root/.work/ores}"

# This test inventory is trusted input to the compiler runner. Reject
# symlinked/out-of-tree and unpaired fixtures *before* executing any guest.
fail_inventory() { echo "fixture inventory: $*" >&2; exit 65; }
shopt -s nullglob
for dir in "$root/examples" "$root/tests" "$root/tests/reject"; do
  [[ -d "$dir" && ! -L "$dir" ]] || fail_inventory "unsafe fixture directory: $dir"
done
# The post-inventory checks are executable inputs, too. Fail before any
# guest dispatch rather than trusting a redirected or absent helper script.
for helper in "$root/scripts/audit.sh" "$root/scripts/check.sh"; do
  [[ -f "$helper" && ! -L "$helper" ]] || fail_inventory "missing or unsafe runner helper: $helper"
done
positive=("$root"/tests/*.ores)
positive_expected=("$root"/tests/*.expected)
negative=("$root"/tests/reject/*.ores)
negative_expected=("$root"/tests/reject/*.err)
(( ${#positive[@]} > 0 && ${#negative[@]} > 0 )) || fail_inventory "empty positive or negative inventory"
for source in "$root"/examples/*.ores "${positive[@]}" "${negative[@]}"; do
  [[ -f "$source" && ! -L "$source" ]] || fail_inventory "unsafe fixture source: $source"
done
for source in "${positive[@]}"; do
  expected="${source%.ores}.expected"
  [[ -f "$expected" && ! -L "$expected" && -s "$expected" ]] || fail_inventory "missing, empty or unsafe positive expectation: $expected"
done
for expected in "${positive_expected[@]}"; do
  source="${expected%.expected}.ores"
  [[ -f "$source" && ! -L "$source" ]] || fail_inventory "orphan positive expectation: $expected"
done
for source in "${negative[@]}"; do
  expected="${source%.ores}.err"
  [[ -f "$expected" && ! -L "$expected" && -s "$expected" ]] || fail_inventory "missing, empty or unsafe negative expectation: $expected"
done
for expected in "${negative_expected[@]}"; do
  source="${expected%.err}.ores"
  [[ -f "$source" && ! -L "$source" ]] || fail_inventory "orphan negative expectation: $expected"
done
# Pair checks above identify the exact missing/orphaned source. Keep a
# count invariant as a final defense without masking the actionable path.
(( ${#positive[@]} == ${#positive_expected[@]} )) || fail_inventory "positive fixture/expectation count mismatch"
(( ${#negative[@]} == ${#negative_expected[@]} )) || fail_inventory "negative fixture/expectation count mismatch"

# Permit inexpensive CI admission to verify the exact fixture inventory
# before downloading GraalVM or compiling the pinned Oreslang compiler.
# This mode MUST NEVER invoke a guest, audit command, or compiler.
if [[ "$#" -gt 1 || ( "$#" -eq 1 && "$1" != "--inventory-only" ) ]]; then
  echo "usage: scripts/test.sh [--inventory-only]" >&2
  exit 64
fi
if [[ "$#" -eq 1 ]]; then
  printf 'fixture inventory: %s positive and %s negative pairs verified\n' "${#positive[@]}" "${#negative[@]}"
  exit 0
fi

bash "$root/scripts/audit.sh"
bash "$root/scripts/check.sh"

cd "$root"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ores-ssr.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

for expected in "$root"/tests/*.expected; do
  source="${expected%.expected}.ores"
  "$oreslang_bin" "$source" > "$tmp/actual"
  diff -u "$expected" "$tmp/actual"
  echo "test: $(basename "$source") passed"
done

for source in "$root"/tests/reject/*.ores; do
  expected="$(cat "${source%.ores}.err")"
  if "$oreslang_bin" "$source" > "$tmp/rejected" 2>&1; then
    echo "unsafe program accepted: $source" >&2
    exit 1
  fi
  if ! grep -Fq -- "$expected" "$tmp/rejected"; then
    echo "unexpected diagnostic for $source" >&2
    cat "$tmp/rejected" >&2
    exit 1
  fi
  echo "test: reject/$(basename "$source") passed"
done
