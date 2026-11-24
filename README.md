> **AI agent instructions (organization-wide):** Before working on code, issues, or pull requests, read and follow the [organization `AGENTS.md`](https://github.com/atto-lang/.github/blob/main/AGENTS.md), including its **merge-first stealth-development policy**. Honor any repository-local `AGENTS.md`, explicit holds, and GitHub-enforced rules.

# atto-ssr

Server-side rendering infrastructure for AttoLang web applications.

## Naming migration and language authority

This repository is maintained at [atto-lang/atto-ssr](https://github.com/atto-lang/atto-ssr); use `https://github.com/atto-lang/atto-ssr.git` for Git remotes and canonical `.atto` source examples. The normative language contract is [atto-spec](https://github.com/atto-lang/atto-spec), with executable guest evidence tracked by [atto-platform-conformance](https://github.com/atto-lang/atto-platform-conformance). Follow current ownership, borrowing, effects, actor, and syntax rules there; do not infer implemented features from a README or unexecuted CI.

## Responsibilities

Rendering entry points, application integration, and server/client handoff.

## Design guidelines

- Keep application-facing contracts separate from hosted Atto services.
- Explicitly specify error, cancellation, concurrency, and resource-lifecycle behavior where applicable.
- Document supported compiler backends, host restrictions, wire formats, and compatibility constraints.

## Development and verification

Use the source tree and CI for verified build/test commands. Tests should cover positive cases, invalid inputs, lifecycle behavior, and cross-backend interoperability where relevant.

## Status

This README describes the project's intended role. It does not imply that the listed APIs or platforms are already implemented or supported.

## Related

- [AttoLang](https://github.com/atto-lang)
- [Language specification](https://github.com/atto-lang/atto-spec)
- [Platform conformance](https://github.com/atto-lang/atto-platform-conformance)

## Repository ownership and contribution routing

**Belongs here:** Server-side template/rendering pipeline, hydration handoff, HTML response framing and typed view-model contracts for AttoLang.

**Belongs elsewhere:** Browser host APIs in atto-browser; HTTP route matching in atto-http-routing; specific SSR example applications in demo repos.

**Security and portability boundary:** Context-aware escaping and safe HTML construction are required; disallow implicit trust of user content, unbounded rendering or unsafe script injection.

AttoLang is the canonical project name; new source, examples and documentation use `.atto` and the `atto-lang` repository organization. This README defines scope, not feature readiness.

**Acceptance:** name exact source SHA/tree, runtime/toolchain, positive and negative checks and execution receipt before claiming support. Host-only tests and empty CI steps do not prove guest execution.

## Restricted HTML escaping reference (host-only)

`reference/safe_html.py` now implements bounded HTML text escaping and a tightly allowlisted quoted-attribute emitter. It rejects control characters, lone surrogate code points, URL/event/style attributes and unbounded node lists. Run `python3 -m unittest discover -s tests -v` for injection-shaped and boundary checks.

**Security scope:** These functions are safe only for ordinary HTML text and the specific allowed attributes, **not** JavaScript, CSS, HTML templates, URL schemes, inline scripts, raw HTML fragments or CSP decisions. This is not AttoLang SSR runtime implementation or proof of frontend sanitization across browsers. Production SSR must use context-aware rendering and browser E2E security tests.
