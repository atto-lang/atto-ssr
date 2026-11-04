# Lessons from Maud, Axum, and htmx (Oreslang SSR)

This is a design and source-level integration contract, not a claim that the
Oreslang HTTP router, native transport, streaming renderer, or browser has
executed these cases. The native SSR semantics remain in `.ores`; there
is no Java, Node, Rust runtime renderer, or JS server.

## What to adopt

| Source | Valuable idea | Oreslang SSR status / boundary |
| --- | --- | --- |
| [Maud](https://maud.lambda.xyz/) | Composable typed markup, escaped data by default, explicit trusted raw markup, ordinary control flow. | `Markup`, `Attrs`, functions, `markup.text`, and `markup.join/when` already provide the value model. A compile-time HTML literal/macro DSL and incremental builder are **future work**. |
| [Axum](https://docs.rs/axum/latest/axum/) | Small handler response types; explicit extractors; router/middleware separate from HTML. | `response.ok/with_status` are eager HTML response values. This change adds `htmx_request.reply` with variant metadata. Actual request extraction, normalization, admission, middleware, and HTTP response conversion belong to `oreslang-http-routing`. |
| [htmx](https://htmx.org/docs/) | Hypermedia-driven interactions, full-page fallback, fragment swaps, browser history restoration and correct HTTP caching. | Existing `htmx.*` markup helpers remain. `htmx_request.reply` selects full pages or fragments; fixed `no_history_snapshot` / `disable_subtree` helpers were added. SSE, swaps and history need browser/wire checks. |

Do **not** port Maud's Rust macro expansion or Axum's Tokio/Tower
implementation to Oreslang. Adopt the contracts while preserving Oreslang's
native actor ownership, async-only transport, compile-time types, no reflection,
and explicit trust boundaries.

## Full page vs. partial response

Import modules and use the same escaped markup for both response variants:

```ores
import module htmx_request from './src/htmx_request';

// Header flags come from a trusted HTTP adapter, NOT the HTMX client.
val selected = htmx_request.reply(
  hx_request,
  history_restore_request,
  page_markup,
  fragment_markup
);
// selected.status == 200
// selected.content_type == "text/html; charset=utf-8"
// selected.body contains fully rendered HTML
// selected.vary == "HX-Request, HX-History-Restore-Request"
```

Truth table (request headers are normalized to booleans by the adapter):

| HX-Request | HX-History-Restore-Request | Result |
| --- | --- | --- |
| absent / false | absent / false | full HTML document |
| true | absent / false | HTML fragment |
| absent / false | true | full HTML document |
| true | true | full HTML document |

A history-cache miss **must** receive full HTML even if the client sends
both true flags. Ensure every URL pushed with `hx-push-url` also serves an
independently navigable full HTML document. Prefer configuring htmx with
`historyRestoreAsHxRequest: false`, but still honor the restore flag.

## HTTP adapter obligations (unimplemented)

The proposed Oreslang router adapter should:

1. Bound incoming header count and bytes **before** extraction. Compare header
   names case-insensitively; validate each flag as an exact `true` or
   `false` token after protocol-defined whitespace trimming; reject
   duplicates/conflicts/invalid values instead of choosing arbitrarily.
   Missing headers are false. Header flags never authorize routes or users.
2. Keep body extraction, authentication, tenant/actor capability checks, method
   authorization and CSRF checks in router middleware. Unsafe methods like
   `hx-post` still require server-side protections. HTMX headers are
   untrusted client input.
3. Convert `reply` into the existing HTML status and Content-Type fields;
   **merge**, do not overwrite, the `vary` names into the actual HTTP
   `Vary` response header on every cacheable negotiated representation.
   Since the response varies on two header flags, both names are required.
   Generate representation-specific ETags and appropriate Cache-Control.
4. Treat `htmx.no_history_snapshot()` (`hx-history="false"`) as a browser
   localStorage snapshot control, not a substitute for `Cache-Control:
   private, no-store`, session invalidation, sensitive-data redaction, or
   cross-tenant cache separation. `htmx.disable_subtree()` prevents HTMX
   interpretation of descendants, but does not sanitize unsafe HTML.
5. Enforce response limits, streaming backpressure, cancellation and actor
   generation fencing before sending bytes. The current implementation
   eagerly joins strings: it does not claim bounded memory or wire behavior.

`reply` intentionally returns a record with a `vary` metadata field, **not**
a serialized HTTP header. Until the router adapter honors that field,
application servers must add `Vary: HX-Request, HX-History-Restore-Request`
themselves, or prohibit caching of negotiated pages and fragments.

## Acceptance gates

- **Exact guest:** execute `tests/htmx-negotiation-contract.ores` at the
  pinned compiler tree; compare its output byte-for-byte with `.expected`.
  Cover all four flag combinations, escaping, status, MIME, `vary`, and the
  two fixed htmx HTML attributes. Existing rejection tests must still pass.
- **Real HTTP wire:** full HTML for a direct GET and history restore; fragment
  only for ordinary HX-Request GET; duplicate/malformed header rejection;
  correct `Vary` propagation and variant-specific cache behavior.
- **Browser:** boosted navigation, back/forward after cache miss, ordinary
  no-JS full-page fallback, and no history snapshot for sensitive regions.
- **Security:** real route authorization and CSRF negative cases, tenant cache
  isolation, untrusted HTMX header spoofing, CSP and XSS coverage.
- **Operations:** nonzero-step exact-head CI, compiler and guest receipts,
  then native image and HTTP transport tests; independent review and
  branch-protection controls remain separate merge gates.

The first bullet has source fixtures here; none of these gates is claimed to
have executed in this PR. The existing draft PR #13 and draft PR #16 are
stacked prerequisites, and their zero-step Actions runs are runner admission
failures, not failing guest semantics.
