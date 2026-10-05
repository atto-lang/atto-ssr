# Security

HTML rendering is a security boundary.

## Current rule

Every API that converts an ordinary string directly into HTML, an HTML attribute, or CSS is explicitly named `trusted*`.

Examples:

- `markup.trusted_raw(...)`
- `html.attr_trusted(...)`
- `css.declaration_trusted(...)`
- `htmx.get_trusted(...)`

These functions **must not receive untrusted/user-controlled strings**.

This naming is temporary but intentional. Oreslang currently lacks the native string traversal/transform primitive required to implement HTML escaping in Oreslang source. See `oreslang-source.java#246`.

## Required post-#246 API

Once the string primitive exists:

- `markup.text(dynamic_text)` escapes HTML text context;
- `html.attr(name, dynamic_value)` escapes attribute context;
- trusted escape hatches retain explicit names such as `trusted_raw`;
- convenience element helpers should prefer safe APIs;
- examples should migrate away from trusted helpers except for literals/framework-owned constants.

## Contexts are distinct

Do not reuse HTML escaping as a universal sanitizer.

Separate policies are required for:

- HTML text;
- HTML quoted attributes;
- URLs;
- inline CSS values/selectors;
- script content;
- JSON embedded in attributes such as `hx-vals`.

The library should prefer structural APIs over trying to sanitize executable sublanguages.

## No Java

This repository must not use:

- `java:` imports;
- `java { ... }`;
- `do java { ... }`;
- Java template engines;
- host reflection.

Rendering semantics belong to Oreslang source. Low-level string/buffer storage primitives may come from the native-first runtime/stdlib boundary, but policy remains in Oreslang.
