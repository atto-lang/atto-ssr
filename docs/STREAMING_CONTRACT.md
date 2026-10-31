# Bounded actor-native SSR streaming contract

**Design only.** No streamed render, HTTP wire integration, resource bound,
scheduler proof or native Oreslang guest receipt exists in this PR. Current
`Markup` and `HtmlResponse` eagerly allocate complete output strings.

## Current typed-tree stepping stone

A closed `HtmlNode` / `SafeAttr` tree now exists in `src/safe_html.ores`.
It provides serializer-side escaping for fixed tag/attribute contexts,
without exposing raw node constructors. The **implementation still renders
eagerly to a string**. Its constructor now copies input child and attribute arrays, with
unexecuted source-level mutation-isolation fixtures. The opt-in `render_with_limits` preflight checks depth (up to 64) and the count of rendered node occurrences (up to 4096). The depth-only helper now delegates to that capped preflight. This is **not** a UTF-8 byte, allocation or overall memory quota; a single text node may contain arbitrarily large data. The serializer still
does not implement backpressure, tenant/actor ownership or cancellation. No native
guest evidence or transport proof has been recorded. The streaming API must
solve ownership and resource accounting before claiming these properties.

## API and ownership (planned)

A render request must explicitly carry a tenant-owned render capability, an
output-byte limit (encoded UTF-8), maximum render depth, maximum chunk size,
bounded in-flight queue capacity, cancellation scope and deadline. Admission
rejects missing or invalid limits before headers or bytes are emitted.

The renderer owns a single mutable encoder and its output buffer. Inputs may
be immutable/borrowed only for the duration allowed by the compiler's borrow
rules; no borrowed actor-local value crosses a suspension point. A producer
emits to an owned, bounded channel and suspends (not blocks a carrier) when
the queue is full. User code must not execute inside runtime timer callbacks.

Each render is identified by tenant, actor generation and unique operation
identity. Runtime-owned tickets gate producer writes; stale tickets from
actor retirement/hot reload are rejected before mutating the transport.
Actor handlers remain non-reentrant across suspension, even when a producer
waits for channel capacity. A stalled tenant must not pin other tenants'
carriers or buffer quotas.

## Output semantics

- Text and attribute values apply their existing context-specific Oreslang
  encoding **before emission**. Untrusted URLs, CSS, script, HTMX expressions
  and raw markup remain rejected or explicitly trusted as appropriate.
- Concatenated chunks must be byte-identical to the eager renderer for the
  supported subset. UTF-8 code points and HTML escapes must not be split in
  a way that exposes partial unencoded content to a consumer.
- Exceeding output byte/depth/chunk limits fails closed without truncating a
  syntactically valid page to appear successful.
- A pending output write is cancelled on client disconnect, deadline expiry
  or generation retirement. Exactly one terminal outcome wins.
- Before committing response headers, failures return a typed error. Once
  headers are committed, failure aborts the response stream rather than
  writing a second status or a misleading success page.
- The renderer never authorizes `Location`, cookies, CSP, cache or other
  headers. An HTTP adapter owns those independent capabilities.
- Informational and body-forbidden statuses (1xx, 204, 205, 304) cannot
  carry an SSR HTML body, whether eager or streaming.

## Minimum conformance matrix (all pending guest/native evidence)

| Class | Adversarial case | Oracle |
| --- | --- | --- |
| Equivalence | nested HTML, escaped attributes, Unicode | identical concatenated eager bytes |
| Chunk boundary | `&`, `<`, quote, multi-byte UTF-8 at boundary | no malformed encoding, no partial escape |
| Admission | absent or exceeded byte/depth/queue quota | typed failure, no output emitted |
| Backpressure | consumer stalls on a full bounded channel | producer suspends; bounded memory/carriers |
| Cancellation | disconnect while producer awaits capacity | one terminal outcome; no writes after cancel |
| Timer races | cancellation/deadline/channel readiness simultaneous | single winner; no leaked continuation |
| Tenant isolation | tenant A stalled; tenant B still serving | B progresses, no cross-tenant data |
| Hot reload | old-generation write after retirement | stale producer rejected |
| HTTP | body-forbidden statuses and post-commit failure | correct status/header/wire behavior |
| Security | raw promotion, HTMX/URL/CSS/JS context misuse | explicit trust or negative oracle |

## Evidence and release gates

Keep source-host audit, pinned Graal guest execution, backend native
scheduler/channel tests and HTTP wire tests distinct. Pin and record exact
library and compiler commit/tree, runtime build, fixture corpus hash,
run attempt, job-to-step binding, expected outputs and resource limits.
Actions `steps=[]` is runner-admission failure, not a test outcome.
No backend parity, memory-boundedness, transport safety or merge readiness
may be claimed until the relevant tests execute.
