> **AI agent instructions (organization-wide):** Before working on code, issues, or pull requests, read and follow the [organization `AGENTS.md`](https://github.com/ores-truffle-oreslang/.github/blob/main/AGENTS.md), including its **merge-first stealth-development policy**. Honor any repository-local `AGENTS.md`, explicit holds, and GitHub-enforced rules.

# oreslang-ssr

## AttoLang migration and current specification (2026-11-18)

**AttoLang** is the current language name, formerly **Oreslang**. This `ores-truffle-oreslang/oreslang-ssr` checkout retains its historical name and documentation. The AttoLang-named destination for new related work is **[atto-lang/atto-ssr](https://github.com/atto-lang/atto-ssr)**. These are distinct GitHub repositories unless an exact verified migration establishes otherwise; do not assume identical code, issues, PRs, releases or test status.

**[atto-spec](https://github.com/atto-lang/atto-spec)** is the canonical normative language specification; old Oreslang-named specifications and examples are historical, not an independent authority. Use [atto-platform-conformance](https://github.com/atto-lang/atto-platform-conformance) for portable executable conformance, [atto-common-source](https://github.com/atto-lang/atto-common-source) for portable `.atto` libraries, and backend-specific `atto-source.*` for compiler/runtime implementations. The design direction includes `snake_case` methods, `borrow!`/`take!`/`share!`/`copy!`/`copy!!`, [implicit borrowing](https://github.com/atto-lang/atto-spec/blob/main/language/implicit-argument-borrow-v1.md), [file/module constants with one-time nonthrowing environment reads](https://github.com/atto-lang/atto-spec/blob/main/language/file-module-const-v1.md) and the [bitwise/stream operator proposal](https://github.com/atto-lang/atto-spec/blob/main/language/bitwise-and-stream-operators-v1.md). **These are targets, not proof that this checkout executes them.**

Existing `.ores`, `oreslang-*` tool commands, package/ABI names and fixture syntax below document legacy compatibility; only replace them after real target-specific compiler/runtime tests. Avoid Python tooling/tests in AttoLang projects; prefer Rust for supporting tooling. For backend feature claims, require exact source SHA/tree, target/toolchain, actual positive and negative guest execution, and explicit passed/failed/unsupported/not-executed status. Host-only and zero-step CI runs do not establish parity.

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
