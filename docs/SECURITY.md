# Security

HTML rendering is a security boundary.

## Current rule

Every API that converts an ordinary string directly into HTML, an HTML attribute, a tag name, or CSS is explicitly named `trusted*`.

Examples:

- `markup.trusted_raw(...)`
- `html.attr_trusted(...)`
- `html.element_trusted(...)`
- `css.declaration_trusted(...)`
- `htmx.get_trusted(...)`

These functions **must not receive untrusted/user-controlled strings**.

Oreslang currently lacks the native string traversal/transform primitive required to implement HTML escaping in Oreslang source. See `oreslang-source.java#246`.

## Provisional Markup representation

`Markup` is currently a record alias:

```ores
type Markup = {html: string};
```

That is useful for proving composition, but it is not yet an unforgeable security type because another source unit can construct the same record shape directly.

The required opaque/newtype/private-representation capability is tracked in `oreslang-source.java#248`.

Therefore the present security model is deliberately conservative:

- `trusted*` names are capability warnings to humans and static audits;
- the type checker does **not yet** prove that all `Markup` values passed through the system were escaped or explicitly trusted;
- production use with untrusted dynamic data should wait for #246 and #248.

## Required post-#246/#248 API

Once both language capabilities exist:

- `markup.text(dynamic_text)` escapes HTML text context and returns opaque `Markup`;
- `html.attr(name, dynamic_value)` escapes attribute context;
- trusted escape hatches retain explicit names such as `trusted_raw`;
- callers cannot directly forge a `Markup` from an arbitrary string;
- convenience element helpers should prefer safe APIs;
- examples should migrate away from trusted helpers except for literals/framework-owned constants.

## Contexts are distinct

Do not reuse HTML escaping as a universal sanitizer.

Separate policies are required for:

- HTML text;
- HTML quoted attributes;
- tag and attribute names;
- URLs;
- inline CSS values/selectors;
- script content;
- JSON embedded in attributes such as `hx-vals`.

The library should prefer structural APIs over trying to sanitize executable sublanguages.

That is why generic tag-name operations are named `element_trusted` / `void_element_trusted`, and script/style helpers remain explicitly trusted.

## No Java

This repository must not use:

- `java:` imports;
- `java { ... }`;
- `do java { ... }`;
- Java template engines;
- host reflection.

Rendering semantics belong to Oreslang source. Low-level string/buffer storage primitives may come from the native-first runtime/stdlib boundary, but policy remains in Oreslang.

`scripts/audit.sh` mechanically checks these repository-level invariants.
