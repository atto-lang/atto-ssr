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

HTML escaping is context-specific. `html.attr` rejects URL, event, CSS,
`srcdoc`, HTMX and unknown attributes. Do not treat escaping as URL validation,
JavaScript/CSS sanitization, or a policy for application code that reinterprets
an attribute value. See [docs/SECURITY.md](docs/SECURITY.md).

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

## Repository ownership and migration (2026-11-08)

The language is publicly **AttoLang** (formerly Oreslang), while the repository remains `ores-truffle-oreslang/oreslang-ssr`. Keep supported `.ores` source, historical import/package IDs and command names working unless a reviewed compatibility change proves replacements.

- **Belongs here:** server-side rendering modules and compiler-backed AttoLang view contracts.
- **Explicitly out of scope:** hosted SSR platform operations or cloud billing.
- **Organization split:** [atto-lang](https://github.com/atto-lang) maintains the compiler, portable language libraries and demo ecosystem; [atto-co](https://github.com/atto-co) handles independently governed commercial cloud hosting, tenant identity, billing, deployment control, networking and infrastructure. Related `atto-*` repos are not assumed transferred copies.
- **Proposed first move:** transfer this **same GitHub repository** to `atto-lang/oreslang-ssr`, preserving numeric ID, name and Git history, after individual authorizations. No direct old-org transfer to `atto-co` is authorized now. Future product spinouts need a separate decision.

**Migration and security checklist:** post ownership claim to [coordination issue #26](https://github.com/ores-truffle-oreslang/.github/issues/26); follow private [runbook draft #25](https://github.com/ores-truffle-oreslang/.github/pull/25). Record ID, exact head SHA/tree, PR/release/package consumers, Apps/webhooks, Pages, secrets, Actions/runners, branch/ruleset enforcement, target visibility/access, source/target admin approval, independent security review and rollback owner. Never mirror private source to evade a blocked transfer. Verify unchanged identity/history/tree and re-enable protections after the authorized GitHub transfer, then update external references and run exact-head CI. Jobs with zero executed steps (`steps=[]`/`null`) are `NOT_EXECUTED`, not success. Host-only and static tests do not prove native AttoLang guest or production networking capabilities.
