# Design

`oreslang-ssr` is a server-rendering library, not a browser runtime.

## Scope

The library owns:

- HTML markup composition;
- HTML document and fragment rendering;
- CSS string generation;
- small HTML response values;
- HTMX attribute helpers and fragment-oriented composition.

It does **not** own:

- sockets or HTTP listener primitives;
- routing;
- database access;
- client-side hydration;
- virtual DOM diffing;
- JavaScript generation;
- WASM generation.

Those boundaries keep rendering reusable with `oreslang-http-routing` or another Oreslang HTTP server.

## Model

The first implementation uses a tiny eager value model:

- `Markup = { html: string }`
- `Attrs = { html: string }`
- `Stylesheet = { css: string }`
- `HtmlResponse = { status, content_type, body }`

The API composes these values with ordinary Oreslang functions. There is no Java template engine and no hidden host callback layer.

This is intentionally closer to Maud's small `Markup`/rendering model than to a browser DOM. The response boundary is similarly small: an HTML response is just status, HTML content type, and rendered body.

## Escaping contract

The target contract is Maud-like:

1. arbitrary dynamic text is escaped by default;
2. arbitrary dynamic attribute values are escaped by default;
3. trusted/raw HTML is explicit;
4. trusted/raw CSS is explicit;
5. rendering never gains Java interop authority.

Current Oreslang cannot implement rule 1 or 2 correctly in native source because strings are not traversable and expose no native transform primitive. That language gap is tracked in `oreslang-source.java#246`.

A second gap is representation hiding: the current record-shaped `Markup` value is structurally forgeable. An opaque/newtype/private-representation facility is tracked in `oreslang-source.java#248`.

Until #246 and #248 land, this repo intentionally exposes only names containing `trusted` or `trusted_raw` for string-to-markup/string-to-attribute/tag conversion. This is less convenient but does not disguise an injection risk.

## Why not a template DSL first?

Oreslang already has:

- ordinary functions;
- typed records;
- arrays and iteration;
- modules;
- first-class functions.

Those are enough to prove the SSR composition model before adding dedicated syntax. If a future HTML literal/macro syntax is added, it should lower to the same `Markup`/attribute operations so the language does not gain a second rendering runtime.

## Rendering direction

The eager-string implementation is deliberately replaceable.

The desired optimization path is:

`Markup composition -> owned UTF-8 builder -> chunk writer / HTTP body`

That permits streaming and fewer intermediate allocations without changing application component code.

## HTMX

HTMX fits the SSR-only stage well because interaction remains HTML-driven:

- `hx-get`, `hx-post`, `hx-put`, `hx-patch`, `hx-delete`;
- `hx-target`;
- `hx-trigger`;
- `hx-swap`;
- `hx-select`;
- out-of-band swaps.

Handlers can return HTML fragments instead of booting a client Oreslang runtime.

When Oreslang eventually targets JS/WASM, client rendering can be designed separately rather than forcing hydration semantics into this server library.
