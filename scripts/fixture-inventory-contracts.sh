#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ssr-inventory.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fake="$tmp/repo"
checks=0

new_fixture() {
  rm -rf "$fake"
  mkdir -p "$fake/scripts" "$fake/examples" "$fake/tests/reject" "$fake/bin"
  cp "$root/scripts/test.sh" "$fake/scripts/test.sh"
  printf '#!/bin/bash\nexit 0\n' > "$fake/scripts/audit.sh"
  printf '#!/bin/bash\nexit 0\n' > "$fake/scripts/check.sh"
  printf 'example\n' > "$fake/examples/demo.ores"
  printf 'positive\n' > "$fake/tests/good.ores"
  printf 'OK\n' > "$fake/tests/good.expected"
  printf 'negative\n' > "$fake/tests/reject/bad.ores"
  printf 'EXPECTED_ERROR\n' > "$fake/tests/reject/bad.err"
  cat > "$fake/bin/ores" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'called\n' >> "$CALL_LOG"
if [[ "$1" == */reject/* ]]; then
  printf 'EXPECTED_ERROR\n' >&2
  exit 7
fi
printf 'OK\n'
MOCK
  chmod +x "$fake/bin/ores"
}

assert_rejected_before_guest() {
  local label="$1" status=0
  rm -f "$fake/calls"
  ORESLANG_BIN="$fake/bin/ores" CALL_LOG="$fake/calls" \
    bash "$fake/scripts/test.sh" >"$tmp/stdout" 2>"$tmp/stderr" || status=$?
  if [[ "$status" -ne 65 || -e "$fake/calls" ]]; then
    echo "inventory self-test failed: $label: status=$status" >&2
    cat "$tmp/stderr" >&2
    exit 1
  fi
  checks=$((checks + 1))
}

new_fixture
ORESLANG_BIN="$fake/bin/ores" CALL_LOG="$fake/calls" bash "$fake/scripts/test.sh" >"$tmp/stdout" 2>"$tmp/stderr"
[[ "$(wc -l < "$fake/calls")" -eq 2 ]] || { echo "happy fixture did not execute both cases" >&2; exit 1; }
checks=$((checks + 1))

new_fixture
rm "$fake/tests/good.expected"
assert_rejected_before_guest "missing positive expectation"

new_fixture
printf 'orphan\n' > "$fake/tests/orphan.expected"
assert_rejected_before_guest "orphan positive expectation"

new_fixture
mv "$fake/tests/good.ores" "$fake/saved.ores"
ln -s "$fake/saved.ores" "$fake/tests/good.ores"
assert_rejected_before_guest "symlinked positive source"

new_fixture
mv "$fake/tests/good.expected" "$fake/saved.expected"
ln -s "$fake/saved.expected" "$fake/tests/good.expected"
assert_rejected_before_guest "symlinked positive expectation"

new_fixture
rm "$fake/tests/good.ores"
mkdir "$fake/tests/good.ores"
assert_rejected_before_guest "source directory masquerade"

new_fixture
rm "$fake/tests/reject/bad.err"
assert_rejected_before_guest "missing negative diagnostic"

new_fixture
: > "$fake/tests/reject/bad.err"
assert_rejected_before_guest "empty negative diagnostic"

new_fixture
mv "$fake/examples/demo.ores" "$fake/saved-example.ores"
ln -s "$fake/saved-example.ores" "$fake/examples/demo.ores"
assert_rejected_before_guest "symlinked example"

new_fixture
mv "$fake/tests/reject" "$fake/reject-saved"
ln -s "$fake/reject-saved" "$fake/tests/reject"
assert_rejected_before_guest "symlinked negative directory"

# The real CI must gate the expensive compiler job on this mode. Check both
# success and negative inventories WITHOUT invoking any mock guest.
new_fixture
rm -f "$fake/calls"
ORESLANG_BIN="$fake/bin/ores" CALL_LOG="$fake/calls" \
  bash "$fake/scripts/test.sh" --inventory-only >"$tmp/stdout" 2>"$tmp/stderr"
grep -q '1 positive and 1 negative pairs verified' "$tmp/stdout"
[[ ! -e "$fake/calls" ]] || { echo "inventory-only executed guest" >&2; exit 1; }
checks=$((checks + 1))

new_fixture
rm "$fake/tests/good.expected"
rm -f "$fake/calls"
status=0
ORESLANG_BIN="$fake/bin/ores" CALL_LOG="$fake/calls" \
  bash "$fake/scripts/test.sh" --inventory-only >"$tmp/stdout" 2>"$tmp/stderr" || status=$?
[[ "$status" -eq 65 && ! -e "$fake/calls" ]] || { echo "inventory-only accepted absent expectation" >&2; exit 1; }
checks=$((checks + 1))

new_fixture
printf 'orphan\n' > "$fake/tests/orphan.expected"
rm -f "$fake/calls"
status=0
ORESLANG_BIN="$fake/bin/ores" CALL_LOG="$fake/calls" \
  bash "$fake/scripts/test.sh" --inventory-only >"$tmp/stdout" 2>"$tmp/stderr" || status=$?
[[ "$status" -eq 65 && ! -e "$fake/calls" ]] || { echo "inventory-only accepted orphan" >&2; exit 1; }
checks=$((checks + 1))

new_fixture
mv "$fake/tests/good.ores" "$fake/guest-source"
ln -s "$fake/guest-source" "$fake/tests/good.ores"
rm -f "$fake/calls"
status=0
ORESLANG_BIN="$fake/bin/ores" CALL_LOG="$fake/calls" \
  bash "$fake/scripts/test.sh" --inventory-only >"$tmp/stdout" 2>"$tmp/stderr" || status=$?
[[ "$status" -eq 65 && ! -e "$fake/calls" ]] || { echo "inventory-only accepted symlink" >&2; exit 1; }
checks=$((checks + 1))

echo "fixture inventory: $checks source-only contract cases passed"
