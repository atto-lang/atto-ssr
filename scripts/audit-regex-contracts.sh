#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ssr-audit-regex.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/src" "$tmp/examples" "$tmp/tests"
cp "$root/scripts/audit.sh" "$tmp/scripts/audit.sh"
: > "$tmp/src/htmx.ores"

# Minimal source satisfying the mandatory invariants. The audit must pass
# before each adversarial injection. No Oreslang compiler or tokens required.
cat > "$tmp/src/safe_html.ores" <<'ORES'
let Array<SafeAttr> attrs_copy = arr[];
let Array<HtmlNode> children_copy = arr[];
attrs_copy.add(attr as SafeAttr);
children_copy.add(child as HtmlNode);
self.attributes = attrs_copy;
self.children = children_copy;
markup.trusted_raw(render(node))
pub fnc render_with_limits(HtmlNode node, int max_depth, int max_nodes)
max_depth > 64
max_nodes > 4096
remaining_nodes - consumed
return Ok(checked.render());
return render_with_limits(node, max_depth, 4096);
consumed = consumed + child_count.unwrap();
if remaining_depth < 1 then
if remaining_nodes < 1 then
ORES
cp "$tmp/src/safe_html.ores" "$tmp/baseline.ores"
bash "$tmp/scripts/audit.sh" > "$tmp/output" 2>&1 || {
  cat "$tmp/output" >&2
  echo "audit regex tests: baseline failed" >&2
  exit 1
}

check_rejection() {
  local name="$1" injection="$2" diagnostic="$3"
  cp "$tmp/baseline.ores" "$tmp/src/safe_html.ores"
  printf '%s\n' "$injection" >> "$tmp/src/safe_html.ores"
  if bash "$tmp/scripts/audit.sh" > "$tmp/output" 2>&1; then
    echo "audit regex tests: unsafe $name accepted" >&2
    exit 1
  fi
  if ! grep -Fq -- "$diagnostic" "$tmp/output"; then
    cat "$tmp/output" >&2
    echo "audit regex tests: unexpected rejection for $name" >&2
    exit 1
  fi
  echo "audit regex tests: $name rejected"
}

check_rejection "raw-factory" 'pub static fnc raw(string value): SafeAttr {' 'safe_html must not expose raw constructors or promotions'
check_rejection "dynamic-tag" 'pub static fnc element(string name): HtmlNode {' 'safe_html must not expose dynamically named HTML'
check_rejection "script" 'pub static fnc script(string code): HtmlNode {' 'safe_html cannot expose script/style node constructors'
check_rejection "style" 'pub static fnc style(string code): HtmlNode {' 'safe_html cannot expose script/style node constructors'
check_rejection "alias-attr" 'self.attributes = attributes;' 'safe HTML nodes must not retain caller array aliases'
check_rejection "alias-child" 'self.children = children;' 'safe HTML nodes must not retain caller array aliases'

echo "audit regex tests: 7/7 contract cases passed"
