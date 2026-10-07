# oreslang-ssr

Native server-side HTML/CSS rendering for Oreslang.

This repository is intentionally **Oreslang source only** for rendering semantics: no Java templates, no host reflection, and no client-side rendering runtime.

## Goal

Provide the Oreslang equivalent of the small, composable server-rendering layer you get from Maud plus the lightweight HTML response boundary you get from Axum:

- markup values compose with normal Oreslang functions;
- HTML documents and partial fragments use the same renderer;
- CSS can be generated from Oreslang source;
- HTTP integration receives a tiny `HtmlResponse` value;
- HTMX attributes make server-rendered interactivity useful before Oreslang has a JS/WASM target.

## Current modules

- `src/markup.ores` — `Markup`, composition, joining, conditional markup, rendering.
- `src/html.ores` — attributes, generic elements, void elements, documents, common tag helpers.
- `src/css.ores` — declarations, rules, media queries, stylesheet composition.
- `src/htmx.ores` — `hx-*` attribute helpers for requests, targets, triggers, swaps, selection, OOB swaps.
- `src/response.ores` — Axum-like HTML response value: status + content type + body.

## Example

```ores
import module markup from './src/markup';
import module html from './src/html';
import module htmx from './src/htmx';
import module response from './src/response';

pub fnc counter_fragment(): {status: int, content_type: string, body: string} {
  val body = html.div(
    html.attrs_join([
      html.attr_trusted("id", "counter"),
      htmx.post_trusted("/counter/increment"),
      htmx.target_trusted("#counter"),
      htmx.outer_html()
    ]),
    html.button(
      html.attrs_empty(),
      markup.trusted_raw("Increment")
    )
  );

  return response.fragment(body);
}
```

That is server-side HTML generation only. HTMX performs the browser request/swap; Oreslang does not need to ship a browser runtime.

## Security: dynamic escaping is intentionally gated

The desired API is escaped-by-default, Maud-style.

Current Oreslang cannot yet implement a correct arbitrary-string HTML escaper in native source because strings are not traversable/indexable and have no native transform/builder primitive.

The escaping primitive gap is tracked at **oreslang-source.java#246**. A second issue, **#248**, tracks the opaque/newtype boundary needed to make `Markup` unforgeable rather than merely a record convention.

Until it lands:

- string-to-HTML conversion is explicitly `markup.trusted_raw(...)`;
- HTML attributes are explicitly `html.attr_trusted(...)`;
- HTMX values use `*_trusted(...)`;
- CSS values/selectors use explicitly trusted helpers;
- these functions must not receive untrusted/user-controlled data.

We intentionally do **not** provide a fake `escape()` or misleading safe-looking `text(string)` API.

See [docs/SECURITY.md](docs/SECURITY.md).

## Design principles

1. **Native Oreslang semantics.** Rendering policy lives in `.ores` files.
2. **Escaped-by-default target.** Raw HTML remains an explicit escape hatch.
3. **No framework-owned DOM.** Markup is server output, not a browser VDOM.
4. **Functions over ceremony.** Components are ordinary functions returning `Markup`.
5. **Router-independent.** `HtmlResponse` can adapt to `oreslang-http-routing` or another server.
6. **HTMX-friendly.** Full pages and partial fragments are equally first-class.
7. **Streaming-compatible design.** The eager string implementation can later lower to a UTF-8 builder/writer.
8. **No client story yet.** JS/WASM rendering is deferred until Oreslang has a supported browser compilation target.

## Examples

```bash
oreslang check examples/basic-page.ores
oreslang check examples/htmx-fragment.ores
```

or:

```bash
bash scripts/check.sh
```

### Compiler compatibility note

These sources follow the current intended Oreslang syntax, including:

```ores
define module markup as
  ...
end
```

At the time this branch was created, the compiler's default `main` still had older module parsing without mandatory `as`. This repo follows the newer language contract rather than writing new library code in stale syntax.

## Roadmap

See:

- [docs/DESIGN.md](docs/DESIGN.md)
- [docs/SECURITY.md](docs/SECURITY.md)
- [docs/ROADMAP.md](docs/ROADMAP.md)

The next critical steps are safe dynamic string escaping via #246 and an opaque `Markup` representation via #248; after that, add native UTF-8 builder/streaming output and a direct adapter for `oreslang-http-routing`.

## Compiler PR checkpoint (2026-10-06)

A [repository-specific compiler compatibility matrix](docs/compiler-pr-sync.md) tracks the 10 newest `oreslang-source.java` PRs. They remain unmerged upstream; existing demos, build flags, and stable compiler references stay unchanged pending exact-SHA conformance testing.
