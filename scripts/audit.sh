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

if grep -nE '\.html([^A-Za-z0-9_]|$)' examples/*.ores tests/*.ores 2>/dev/null; then
  fail "application code must render Markup through the public API"
fi

# A trusted HTMX expression must still be safely encoded as an HTML value.
if grep -nF 'html.attr_trusted(' src/htmx.ores; then
  fail "HTMX values must pass through the encoded attribute-value boundary"
fi

# Guard the new safe-by-construction API against accidental raw escape hatches
# or dynamic tag/name factories. This is a source guard, not compiler proof.
if grep -nE 'pub (static )?fnc (trusted_raw|attr_trusted|element_trusted|script_trusted|style_sheet|raw|unsafe|from_html|from_raw)\\(' src/safe_html.ores; then
  fail "safe_html must not expose raw constructors or promotions"
fi
if grep -nE 'pub static fnc (element|void_element|attr)\\(' src/safe_html.ores; then
  fail "safe_html must not expose dynamically named HTML"
fi
if [[ "$(grep -Fc 'markup.trusted_raw(render(node))' src/safe_html.ores)" -ne 1 ]]; then
  fail "safe_html must have one reviewed typed-to-Markup promotion boundary"
fi
if grep -nE '(^|[[:space:]])(script|style)[[:space:]]*\\(' src/safe_html.ores; then
  fail "safe_html cannot expose script/style node constructors"
fi

# Safe HTML must snapshot caller array arguments before exposing nodes.
# These source checks complement, but do not replace, compiler-backed tests.
for required in 'let Array<SafeAttr> attrs_copy = arr[];' 'let Array<HtmlNode> children_copy = arr[];' 'attrs_copy.add(attr as SafeAttr);' 'children_copy.add(child as HtmlNode);' 'self.attributes = attrs_copy;' 'self.children = children_copy;'; do
  if ! grep -Fq -- "$required" src/safe_html.ores; then
    fail "safe HTML node ownership copy is missing: $required"
  fi
done
if grep -nE 'self\\.(attributes|children)[[:space:]]*=[[:space:]]*(attributes|children);' src/safe_html.ores; then
  fail "safe HTML nodes must not retain caller array aliases"
fi

echo "audit: native SSR invariants passed"
