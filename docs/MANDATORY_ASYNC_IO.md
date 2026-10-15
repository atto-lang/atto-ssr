# Mandatory nonblocking guest I/O

The compiler launcher always asserts `--core-io=native-async-only`, independently
of guest arguments and capability grants. This asserts the mandatory compiler
invariant; it is not a package option. A user-supplied downgrade or duplicate
policy fails. An older compiler without this invariant must fail closed; the
launcher must never retry without the assertion or select a blocking backend.
Existing exact-source pin and clean-checkout checks remain enforced.

Legacy synchronous I/O in this package is not automatically migrated by changing
the launcher. Unsupported fs/HTTP/network/stdio source rejects until a genuine
native asynchronous implementation is available. In particular neither a
`_async` suffix nor a worker wrapper makes an old implementation compliant.
Host launcher tests establish forwarding/admission only, not guest-library or
native asynchronous I/O implementation. Full guest suites need migration and
independent execution evidence before release. Source pins are preserved rather
than silently advancing a package to an unqualified compiler snapshot.
