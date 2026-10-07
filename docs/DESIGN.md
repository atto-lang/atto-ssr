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

- nominal `Markup` with immutable private string storage
- nominal `Attrs` with immutable private string storage
- nominal `Stylesheet` with immutable private string storage
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

The pinned compiler provides literal replacement and private class construction.
Escaping is implemented in Oreslang with ampersands replaced first. It does not
interpret existing entities or recursively process replacement text. `Markup`
and `Attrs` reject record-shaped impostors and direct external construction.

`html.attr` only accepts inert names; executable and URL contexts retain
explicitly trusted APIs until dedicated policy is implemented. The private
classes replace the old structural aliases and are an intentional type-level
API change. Rendering remains eager; a native UTF-8 builder is still pending.

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
