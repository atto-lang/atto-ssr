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
      html.id("counter"),
      htmx.post_trusted("/counter/increment"),
      htmx.target_trusted("#counter"),
      htmx.outer_html()
    ]),
    html.button(
      html.attrs_empty(),
      markup.text("Increment")
    )
  );

  return response.fragment(body);
}
```

That is server-side HTML generation only. HTMX performs the browser request/swap; Oreslang does not need to ship a browser runtime.

## Escaped dynamic data

`markup.text(value)` escapes `& < > " '` and returns a nominal `Markup` value.
`html.attr(name, value)` returns `Result<Attrs, string>`: it escapes the value
and accepts only an explicit allowlist of inert attribute names. `html.id` and
`html.class_name` are fixed-name escaped helpers.

```ores
val card = html.div(
  html.attr("title", user_title).unwrap(),
  markup.text(user_message)
);
```

`Markup`, `Attrs` and `Stylesheet` have private constructors and immutable private storage.
Ordinary records cannot impersonate them. Trusted conversions remain explicit:
`markup.trusted_raw`, `html.attr_trusted`, and the `*_trusted` CSS/HTMX helpers.
This changes the former record aliases to nominal classes; callers importing
these names must use `import class`, and must render through the public API.

Fixed-name `*_trusted` attribute helpers and `htmx.*_trusted` now
encode HTML attribute values to prevent quote-breakout; they still trust URL,
selector, and HTMX expression semantics. Supply unescaped values. Only the
explicit low-level `html.attr_trusted` API retains raw-attribute behavior.

HTML escaping is context-specific. `html.attr` rejects URL, event, CSS,
`srcdoc`, HTMX and unknown attributes. Do not treat escaping as URL validation,
JavaScript/CSS sanitization, or a policy for application code that reinterprets
an attribute value. See [docs/SECURITY.md](docs/SECURITY.md).

## Safe local URL and HTMX option subset

`url.local_path(["workflows", "run_7"]).unwrap()` yields an opaque
`LocalPath` equal to `/workflows/run_7`. Its strict ASCII segment
grammar prevents unsafe authority, scheme, percent-decoding, traversal,
query and fragment syntax. Use `html.href_local(path)`,
`html.action_local(path)`, or `htmx.get_local(path)` and corresponding
HTMX mutation/SSE helpers. For basic HTMX options use
`htmx.swap("outerHTML")`, `htmx.trigger("click")`, or
`htmx.target("this")` which return `Result<Attrs,string>`.
The older `*_trusted` helpers remain explicit escape hatches.

These are syntax boundaries, not route authorization, CSRF protection,
or guarantees about actual HTTP transport. See `docs/SECURITY.md`.

## Closed, typed HTML tree (opt-in)

For safe data-first HTML composition without manual escaping:

```oreslang
import module safe_html from './src/safe_html';
import class HtmlNode from './src/safe_html';
import class SafeAttr from './src/safe_html';

val page = HtmlNode.div(
  [SafeAttr.id("app"), SafeAttr.title("a\" onclick=\"bad()")],
  [HtmlNode.text("<script>alert(1)</script>")]
);
val string html = safe_html.render(page);
```

The ordinary text is encoded **during serialization**, and the attribute
cannot escape its quoted context. Fixed tag factories and a private
constructor keep arbitrary tags and raw code out of this opt-in path.
The default legacy `Markup` API still supports explicit raw trust.
`HtmlNode` is currently eager, unbounded, and not proven transitively
immutable: see `docs/DESIGN.md` and `docs/STREAMING_CONTRACT.md`.

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

### Compiler compatibility and tests

`compiler.lock` identifies the compiler commit; `compiler-tree.txt` identifies
its exact source contents. CI checks out an identical compiler snapshot from
this private repository and verifies its tree before building. No cross-repo
secret is required. `bash scripts/setup.sh` builds the verified checkout in
`.work/compiler`; then `bash scripts/test.sh` uses the generated launcher.

The suite checks both examples, compares rendering and adversarial escaping
fixtures byte for byte, and requires unsafe constructor/field/struct/subclass
programs to fail with the expected diagnostic. The runtime storage primitive
is literal string replacement; all HTML policy stays in Oreslang.

## Roadmap

See:

- [docs/DESIGN.md](docs/DESIGN.md)
- [docs/SECURITY.md](docs/SECURITY.md)
- [docs/ROADMAP.md](docs/ROADMAP.md)

Next: native UTF-8 builder/streaming output, URL-aware helpers, and a direct adapter for `oreslang-http-routing`. The generic compiler issues #246/#248 still include broader performance/backend and type-system work; this library proves its own private-class boundary with rejection tests.

## Compiler PR checkpoint (2026-10-06)

A [repository-specific compiler compatibility matrix](docs/compiler-pr-sync.md) tracks the 10 newest `oreslang-source.java` PRs. They remain unmerged upstream; existing demos, build flags, and stable compiler references stay unchanged pending exact-SHA conformance testing.
