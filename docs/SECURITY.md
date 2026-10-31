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

These APIs bypass data encoding and require trusted, context-correct input:

- `markup.trusted_raw` and `Markup.trusted_raw`
- `html.attr_trusted`, `Attrs.trusted_raw`, and `*_trusted` attribute helpers
- `html.element_trusted` and `html.void_element_trusted`
- `css.trusted_raw`, `Stylesheet.trusted_raw`, and CSS/HTMX `*_trusted` helpers
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
