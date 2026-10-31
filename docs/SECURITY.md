# Security

## Escaped data boundaries

`markup.text(value)` escapes ampersands, angle brackets and both quote characters
for HTML text context. Existing entities are treated as input data and encoded
again; the implementation never decodes entities. Non-delimiter Unicode is
preserved, including supplementary characters and combining sequences.

`html.attr(name, value)` escapes a double-quoted value and returns
`Result<Attrs, string>`. Accepted names are exactly:

`id`, `class`, `title`, `alt`, `value`, `placeholder`, `role`, `aria-label`,
`aria-description`, `aria-describedby`, and `aria-labelledby`.

Names are case-sensitive. Unknown names, empty names, whitespace, event
handlers, URLs, `style`, `srcdoc`, and HTMX attributes are rejected. `html.id`
and `html.class_name` provide fixed-name escaped helpers. Applications must
still enforce their own policies for IDs, classes and data later consumed by
JavaScript or another interpreter.

This follows the context separation described in the
[OWASP XSS prevention guidance](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html).
HTML encoding is not URL validation, HTML sanitization, JavaScript escaping,
CSS escaping, or a policy for executable HTMX expressions.

## Nominal wrappers

`Markup`, `Attrs` and `Stylesheet` are public nominal classes with private constructors and
immutable private string fields. Public rendering exposes an immutable string;
it does not grant permission to modify the stored representation. Negative
compiler/runtime tests reject external constructors, private field access, structural
record impersonation, callable impostors, same-name foreign classes, and subclass construction.

Imported function signatures are not yet fully typed by the compiler. Rendering
entry points therefore cast to the local nominal declaration before dispatching
on caller-supplied values. The pinned compiler compares declaration identity
and resolves inheritance in the object's defining unit; a same-name foreign
class or interface cannot pass these guards. These runtime checks are required
until imported-signature typing is complete.

This intentionally replaces the former structural aliases. Import them with
`import class`, compose through the module APIs, and render through the public
methods. Callers that fabricated or read `{html: string}` must migrate.

## Explicit trust

These APIs require trusted, context-correct inputs. Some are raw and bypass encoding; others encode HTML delimiters but still trust their URL, selector or executable semantics:

- `markup.trusted_raw` and `Markup.trusted_raw`
- `html.attr_trusted`, `Attrs.trusted_raw`, and `html.bool_attr_trusted` (raw attributes or names)
- `html.element_trusted` and `html.void_element_trusted`
- `css.trusted_raw`, `Stylesheet.trusted_raw`, and CSS `*_trusted` helpers
- HTMX `*_trusted` helpers (HTML-value-encoded, still policy-trusted)
- fixed-name HTML `*_trusted` helpers (HTML-value-encoded, still policy-trusted)
- `html.script_trusted`

The `html.attr_value_trusted(name, value)` boundary trusts the attribute
name and semantic context, but HTML-encodes its quoted value. All HTMX helpers
and the fixed-name `id_trusted`, `class_trusted`, `href_trusted`,
`action_trusted`, and `method_trusted` helpers now use it. Embedded quotes
cannot open an additional HTML attribute. **This does not validate URLs,
selectors, JavaScript or HTMX expressions.** Applications must still authorize
URLs and constrain executable semantics. This deliberately changes behavior
for previously pre-encoded trusted helper inputs; pass the original input
instead. `html.attr_trusted` remains the explicit raw escape hatch.

Do not pass untrusted data to them. In particular, HTML text must not be reused
as script or style source. Generic tag names remain trusted because tag choice
changes parsing context. URL helpers and safe HTMX JSON/expression handling
remain separate work.

## Typed same-origin path syntax and expression-free HTMX

`url.local_path(Array<string>)` produces an opaque nominal `LocalPath`
with a private constructor. A segment contains only ASCII letters, digits,
underscore and hyphen; no empty segments; at most 8 segments and 64 ASCII
bytes per segment. Zero segments produce `/`. There is no untrusted
authority, scheme, dot, slash, backslash, percent-encoding, fragment, query,
whitespace, control byte, or non-ASCII character in a segment. Validation
is deliberately conservative: it does NOT authorize HTTP routes, methods,
tenants, redirects, cookies, CSRF protections or downstream proxies.

`html.href_local`, `html.action_local`, and the seven HTMX `*_local`
helpers only accept `LocalPath`. They HTML-encode the value, although
the path grammar excludes HTML delimiter characters. Older `*_trusted`
APIs remain an explicit policy-bypass escape hatch and are not appropriate
for attacker-controlled values.

`htmx.swap`, `htmx.trigger`, and `htmx.target` accept a small
expression-free exact-value subset and return `Result<Attrs,string>`.
The helpers reject arbitrary selectors, trigger modifiers, event filters,
JavaScript expressions, and swap modifiers. `htmx.vals_empty()` produces
a fixed `{}` JSON value. Do not assemble JSON or JS-based `hx-vals`
through string concatenation: use a typed JSON serializer and an
application-level allowlist. Rejecting URL syntax does not prove application
authorization, and no URL parser or origin policy for general URLs is
claimed. Route normalization must agree with this restricted grammar.

## Safe HTML node path (opt-in, not yet default)

Prefer `SafeAttr.id/title/class_name/aria_label/value/placeholder/role`,
`SafeAttr.href_local/action_local`, and fixed methods such as
`HtmlNode.text/div/span/a/input/fragment` when constructing HTML from
untrusted data. `SafeAttr` stores unescaped values with private name and
value fields; the renderer performs HTML encoding at serialization rather
than trusting a pre-escaped string. `HtmlNode` constructors only select a
fixed set of ordinary and void tags; no public script/style/raw/dynamic tag
constructor exists. `safe_html.to_markup` is the **single reviewed bridge**
to legacy raw `Markup`, and must accept only a `HtmlNode`.

The older `markup.trusted_raw`, `html.attr_trusted`, and
`html.element_trusted` remain public. Therefore this does **not** enforce
global safe-by-default behavior, and cannot prevent callers from using the
legacy raw API. `HtmlNode` now copies caller-owned attribute and child arrays into private
arrays before publishing the node. This is a source-level ownership defense
with an authored late-mutation regression fixture, **not yet compiler/run
evidence**. It is not a proof of cross-actor heap isolation or safe recursive
depth. The opt-in `safe_html.render_with_depth_limit(node, max_depth)` now rejects
invalid and exceeded structural depth before producing a rendered string.
The unchecked legacy `safe_html.render()` remains for compatibility; neither
entrypoint enforces encoded UTF-8 bytes, output allocation, or node-count
limits. This policy remains unverified by compiler guest execution. No tenant/HTTP isolation is
implied. The safe-tree fixture and negative nominal-construction cases are
authored expected oracles, not executed guest proof until CI admission works.

## HTML response status boundary

`HtmlResponse` always contains an eagerly rendered body and
`text/html; charset=utf-8`. Consequently `response.with_status` rejects
1xx informational statuses and the no-body statuses 204, 205 and 304.
Render-able statuses otherwise remain 200–599. The HTTP adapter owns
header authorization (for example redirect `Location`, CSP and cookies)
and must represent no-body statuses separately. These checks are source-only
response semantics; they are not HTTP wire evidence.

## Implementation and validation

HTML policy is native Oreslang source. The compiler supplies a literal string
replacement storage primitive; it performs no regex or entity interpretation
and needs no Java interop permission. The SSR repository forbids Java source,
Java islands and host imports in source/examples/tests.

The pinned compiler is verified by exact Git tree before building. Tests compare
existing rendering output and adversarial escaping output byte for byte, and
require unsafe wrapper programs to fail with a matching diagnostic. The source
audit remains a supplementary check, not a substitute for those runtime and
compiler tests. Native-image and alternative backend proofs are separate work.

Rendering is eager and allocates intermediate strings. Native UTF-8 builders,
bounded/streamed response production and performance proofs remain pending.
