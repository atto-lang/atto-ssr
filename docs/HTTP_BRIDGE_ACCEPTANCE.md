# SSR to HTTP routing: first executable contract

This branch adds **Oreslang source-level, eager response composition**. It does
NOT implement HTTP parsing/sockets, authentication, a stateful actor, an
`oreslang-http-routing` dependency, streaming, browser tests or native-image
proof. Keep the branches and runtime pins independent until the compiler-backed
combined build is executed.

## Modules and explicit boundaries

- `src/htmx_http.ores` accepts *normalized* values for HX-Request and
  HX-History-Restore-Request, with separate `present` and `duplicate` flags
  for each. It returns an error for duplicate fields, absent-but-nonempty
  values, or any present value other than exact `true` or `false`.
  It delegates page/fragment selection to `htmx_request.reply`, preserving
  history-restore precedence over ordinary htmx fragments.
- `src/counter_view.ores` is a **pure view**, not a counter implementation.
  It HTML-escapes an authorized actor snapshot and CSRF token field, sets
  a typed local `/counter/increment` action, and uses an ordinary
  `method="post"` form as the no-JavaScript fallback.
- The counter form's standalone fragment **and** its full page both mark
  CSRF-bearing markup with `hx-history="false"`. A fragment can be swapped
  into a previously unprotected page; guarding only the page wrapper is not
  sufficient. This controls htmx browser history snapshots, **not** HTTP
  network caching or form-token validation.
- The counter view/response guest fixtures assert boolean invariants instead
  of printing rendered CSRF-bearing HTML to test logs. Fixture oracles pin
  escaping, absence of unescaped markup, history embargo for standalone
  fragments, full-page restoration and HEAD suppression. A compiler-backed
  guest run is still required; a source-only model is not a passing guest test.
- `src/counter_response.ores` composes view and strict header handling
  for **GET or HEAD only** after routing and authorization. It must never
  be used as a POST handler. The POST mutation must be implemented in
  an actor-owned critical operation behind CSRF, method, and capability gates.

All source modules use Oreslang `.ores` rendering semantics, not host
templates or Java/Node server rendering.

## Responsibilities of the real HTTP adapter

The transport adapter, not SSR, must perform the following in order:

1. Bound raw request-line and header bytes/count, reject malformed HTTP
   framing and conflicting Content-Length/transfer encodings, and normalize
   header names case-insensitively. Reject duplicate HX header fields
   (including same-name values with different capitalization) instead of
   joining them.
2. Trim only HTTP optional whitespace (SP/HTAB) from the two HX field
   values **before** calling `htmx_http.reply_checked`. Do not treat a
   comma-separated list as one valid boolean. Supply `present=false`,
   `duplicate=false`, `value=""` when missing. A malformed header must
   produce an HTTP client error without invoking the handler.
3. Resolve canonical method and decoded path segments via the separately
   compiled `oreslang-http-routing` router. Use the router's pinned
   snapshot/generation, not a stale/caller-constructed Decision; PR #25
   hardening is a separate unmerged prerequisite.
4. Apply authentication, tenant capability checks, route-specific method
   policy and authorization. Obtain a scalar, immutable counter snapshot
   from an actor using a separately authorized request capability.
   Never send Router, Decision, or PathCapture objects to an isolated actor.
5. For GET/HEAD, supply `suppress_body` from the **validated router
   Decision** (HEAD) to `counter_response.get_or_head`. For POST, validate
   the form's CSRF token, invoke the actor's non-reentrant `critical`
   mutation once, then return either a fresh fragment to an authorized
   htmx request or an HTTP 303 redirect to the full counter page for a
   traditional form submission. Never mutate counter state on GET/HEAD.
6. Send the `status` and `content_type` as real HTTP status/header
   values. Merge, rather than overwrite, the `vary` metadata into a real
   `Vary` header with **both** HX-Request and
   HX-History-Restore-Request. Set real `Cache-Control: private, no-store`
   from the returned metadata. Until that wire behavior is verified, do
   not cache either representation.
7. Send **only** `body`. On HEAD it is empty, while
   `representation_body` remains the GET-equivalent output for the
   adapter to compute header semantics. Do not send duplicate bodies or
   infer byte Content-Length from character count. Compute byte lengths
   after UTF-8 encoding, or omit Content-Length when allowed.
8. Translate router 404, 405 (+ Allow), automatic OPTIONS (+ Allow),
   routing-limit rejection and no-body statuses separately. Never render
   HTML bodies for 204/205/304; prohibit body bytes on HEAD regardless
   of status. This source branch models only 200 HTML GET/HEAD variants.

## First integrated routes

| Method | Path | Gate | Response |
| --- | --- | --- | --- |
| GET | /counter | Authn + tenant capability + actor read | 200 full page for direct navigation, fragment for HX-Request |
| HEAD | /counter | Same read authorization; no write | Same representation metadata, zero transmitted body |
| POST | /counter/increment | CSRF + method/tenant capability + serialized actor mutation | 200 fresh fragment for HX or 303 redirect for no-JS form |
| GET | /counter/increment | No matching GET route | Method not allowed + correct Allow |
| OPTIONS | /counter/increment | Router auto-OPTIONS | No counter mutation; correct Allow |

Use the **existing** `oreslang-http-routing` segment trie, not a second
competing parser/router. Register handler IDs and explicit middleware pipeline
IDs in a pinned router snapshot.

## Exact-head verification plan

1. Source-free admission canary with nonzero job steps. Record exact workflow
   attempt, runner, SHA, tree, command and job-to-step binding.
2. Pinned `scripts/setup.sh` / `scripts/test.sh` in this SSR stack. Three
   new positive fixtures must match `.expected` byte-for-byte:
   `htmx-http-contract`, `counter-view-contract`,
   `counter-response-contract`, as well as all inherited fixtures and
   negative private-wrapper tests.
3. Resolve the **different compiler source pins and syntax** of SSR versus
   `oreslang-http-routing`. Demonstrate a single compiler-backed guest
   executable importing both modules; do not infer cross-repo parity from
   independent source-only checks.
4. Run real transport/wire tests: case-insensitive HX names, duplicates,
   whitespace, missing/false flags, invalid tokens, GET/HEAD/POST,
   404/405/OPTIONS, actual Vary and Cache-Control bytes, CSRF/capability
   failures and correct 303 fallback.
5. Run browser tests with htmx assets supplied by the application: no-JS
   POST, HTMX partial swap, direct GET, history-cache miss restoring a
   complete page, and sensitive-snapshot embargo.
6. Only after nonzero-step exact-head guest + native + wire receipts and
   independent review should this PR and its stacked prerequisites be
   considered for promotion. Check branch protection separately.

Source-only JS-model fixtures are **not** real Oreslang compiler, native or
wire results. Existing zero-step GitHub Actions failures indicate runner
admission, not a failing guest program.

## Offline exact-tree compiler admission (private CI mirror)

Before launching any guest code in an alternate private test organization,
provision **both** independent source trees, not only the SSR application tree:

1. Exact SSR candidate head/tree into the destination's private source branch.
2. Compiler snapshot into `.work/compiler` in that checkout, as its own clean
   Git repository with `HEAD^{tree}` exactly equal to `compiler-tree.txt`.
   `compiler.lock` identifies the upstream pinned revision; a new local mirror
   commit with identical Git tree is permitted and its actual commit SHA is
   printed in the compiler provenance line.
3. Execute `ORESLANG_OFFLINE=1 bash scripts/setup.sh`, followed by the
   complete positive/negative guest suite. The setup must **never** fall back
   to cloning a private source across organizations when the compiler checkout
   is absent. Invalid offline settings fail closed. Offline mode passes `-o`
   to Maven as well, so dependency/plugin resolution must succeed from the
   already-provisioned local Maven repository. This rejects missing artifacts
   rather than silently fetching them. It is not, by itself, an OS-level
   network sandbox or proof that arbitrary Maven plugins cannot open sockets.
   After Maven exits successfully, the setup also requires the actual
   `.work/classpath.txt` file to be nonempty and regular, plus the compiled
   `target/classes/dev/oreslang/launcher/OresMain.class` to exist and be
   nonempty and non-symlinked. Otherwise it fails without publishing
   `.work/ores`; Maven exit status alone is not a valid runnable-compiler
   receipt. The host tests mock these artifacts, so even a passing host test
   cannot substitute for a real GraalVM build and guest execution.
   To prevent a false-positive from **ignored build outputs** left by an earlier
   run, setup invalidates the prior classpath and `OresMain.class` before
   invoking Maven. It rejects symlinked intermediate class-output directories
   and the entrypoint itself **before** deleting artifacts or invoking Maven
   clean. This is an artifact freshness guard, not a cryptographic bytecode
   attestation; real guest execution is still required.
4. Capture the original head SHA/tree, mirrored head/tree, pinned compiler
   revision, actual compiler mirror commit/tree, workflow run attempt,
   job/step IDs, exit codes, and test outputs. Check the exact SHA again before
   treating the tests as evidence.

Never use the test organization's `GITHUB_TOKEN` to check out the private
origin from a different organization. A successful source-free runner canary
does **not** imply the application and compiler trees were mirrored or tested.
If GitHub rejects object writes or no admissible source path exists, stop and
retain the source-only classification. Do not bypass a failed transfer.

## Additional executable guest edge matrix

Each `tests/*.ores` file is paired with an exact `.expected` oracle and
is automatically included by `scripts/test.sh`. The following three **new,
independent** programs extend the existing contract set:

- `htmx-flag-adversarial.ores`: absent/duplicate/inconsistent values,
  noncanonical case, whitespace, comma combinations, accepted booleans
  (12 assertions).
- `htmx-head-history-adversarial.ores`: HEAD never transmits body bytes,
  selected full/fragment representation survives for headers, history restore
  wins over HX-Request, and invalid headers fail closed even for HEAD
  (9 assertions).
- `counter-token-fragment-adversarial.ores`: embedded CSRF-bearing
  fragments disable HTMX history snapshots, supplied text and attribute values
  are escaped, and POST action paths remain local (9 assertions).

These are guest *fixtures*, not claimed guest executions until the pinned
compiler runs them. They model normalized adapter flags and rendered strings,
not live HTTP parsing, real CSRF verification, or browser localStorage.
