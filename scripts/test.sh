#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
oreslang_bin="${ORESLANG_BIN:-$root/.work/ores}"

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
