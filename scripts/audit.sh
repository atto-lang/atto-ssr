#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail() {
  echo "audit: $*" >&2
  exit 1
}

if find src examples tests -type f -name '*.java' -print -quit | grep -q .; then
  fail "Java source is forbidden in the SSR repository"
fi

if grep -R -nE --include='*.ores' 'java:|(^|[[:space:]])java[[:space:]]*\{|do[[:space:]]+java[[:space:]]*\{' src examples tests 2>/dev/null; then
  fail "Java interop/source islands are forbidden in native SSR code"
fi

if grep -R -n --include='*.ores' 'DynamicStruct' src examples tests 2>/dev/null; then
  fail "DynamicStruct is not part of the SSR representation model"
fi

# New code follows the canonical module declaration even while validation
# temporarily runs against a compatibility parser.
if grep -R -nE --include='*.ores' '^[[:space:]]*define module [A-Za-z_][A-Za-z0-9_]*[[:space:]]*$' src examples tests 2>/dev/null; then
  fail "module declarations must use 'define module <name> as'"
fi

# Dynamic names and executable contexts still require explicit trust.
if grep -R -nE --include='*.ores' 'pub fnc (element|void_element|bool_attr)\(' src 2>/dev/null; then
  fail "dynamic tag and attribute names must remain explicitly trusted"
fi

if grep -R -nE --include='*.ores' 'pub fnc (style|script)\(' src 2>/dev/null; then
  fail "style/script contexts must remain explicit"
fi

# Positive examples/tests must use public APIs. Intentional negative fixtures
# under tests/reject are compiled separately and must fail.
if grep -R -nE --include='*.ores' 'obj[[:space:]]*\{[[:space:]]*html[[:space:]]*:' examples tests 2>/dev/null; then
  fail "application code must not forge the provisional Markup representation"
fi

if grep -RnE --include='*.ores' --include='*.atto' --exclude-dir=reject '\.html([^A-Za-z0-9_]|$)' examples tests; then
  fail "application code must render Markup through the public API"
fi

echo "audit: native SSR invariants passed"
