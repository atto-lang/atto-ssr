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

Blocked on `oreslang-source.java#246` for escaping and `oreslang-source.java#248` for an unforgeable safe-markup representation.

- escaped `markup.text(string)`
- escaped `html.attr(name, value)`
- URL-aware helpers
- safer HTMX JSON/value helpers
- tests for `& < > " '` and mixed Unicode input

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
