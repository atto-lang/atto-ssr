# Roadmap

## Phase 0 — native SSR core

- Markup composition
- generic HTML elements
- common element helpers
- trusted/static attributes
- CSS generation
- HTML response values
- HTMX helpers and fragment examples
- no Java

## Phase 1 — safe dynamic data

Implemented with the pinned literal replacement primitive and nominal classes with private immutable storage. URL/HTMX policy and streaming remain open.

- [x] escaped `markup.text(string)`
- [x] allowlisted, escaped `html.attr(name, value)`
- [x] narrow same-origin `LocalPath` syntax and HTMX enum-like option subset (guest validation pending)
- [ ] general URL/query builder, origin/redirect authorization and router normalization tests
- safer HTMX JSON/value helpers
- [x] tests for `& < > " '`, mixed Unicode, injection payloads and forged wrappers

## Phase 2 — rendering performance

- Oreslang/native UTF-8 builder
- append-oriented rendering
- render-to-writer
- chunked/streaming HTTP bodies
- allocation benchmarks
- deterministic output snapshots

## Phase 3 — HTTP integration

- adapters for `oreslang-http-routing`
- typed handler result / `IntoResponse`-like contract
- redirects, headers, cache control
- [x] body-forbidden status gate for `HtmlResponse` (pending pinned guest test)
- [ ] bounded actor-native rendering/transport: [streaming contract](STREAMING_CONTRACT.md)
- HTMX response headers
- content negotiation where useful

## Phase 4 — syntax ergonomics

Only after the function API is stable:

- optional HTML literal/macro syntax
- compile-time tag/attribute validation
- compile-time detection of void-element misuse
- generated convenience functions for the HTML standard

Any syntax sugar should lower to the same SSR value model.

## Explicitly deferred

Client-side Oreslang rendering/hydration is deferred until Oreslang has a supported JS or WASM compilation target.
