# Headroom identity and forwarding accounting

Authorized 2026-10-27 (Asia/Shanghai): fix duplicated forwarding attribution, show Headroom separately from Python, rebuild and install locally. Preserve existing data, settings, security hardening and rollback sets.

## Confirmed defects and regression evidence

- The previous path-first resolver collapsed Homebrew's bundled Python runtime into Python.app, including Headroom. A real Python `-m headroom.cli` regression returned Python instead of Headroom.
- Only explicit system proxy endpoints were recognised. A client → Headroom → Nano fixture credited the Headroom hop (610 bytes) as ordinary Python, missed the original client's 550 bytes and produced no separate Headroom transport row.
- Additional failing fixtures covered late endpoint discovery within one CSV frame, a vanished proxy's port reused by another local service, and a direct Headroom upstream delta with no current loopback frame.

## Implementation contract

- `RuntimeTool` recognises an exact Headroom module or console-script entry point, rather than searching arbitrary command arguments. Ordinary Python, `-c` strings, similarly named modules and unrelated scripts remain distinct.
- `RuntimeToolLookup` uses current-user kernel process metadata and bounded `KERN_PROCARGS2` reads. Only argc arguments are decoded, never the following environment. Arguments are not cached, logged or stored; the bounded cache holds only classification, endpoint and PID/UID/path/kernel-start identity.
- Headroom uses stable key `runtime:headroom`, its own name and a native icon. Child tools can be adopted by Headroom instead of the interpreter bundle.
- Headroom proxy instances with explicit loopback `--host` and `--port` add their listener to the existing loopback sampler. MCP `serve --proxy-url` does not define a listener. No process scan, new service, administrator access, request interception or proxy setting change is added.
- A forwarding process stays in transport accounting for both direct upstream traffic and downstream-proxy traffic. The original client is ordinary app usage; Headroom and Nano are separate informational transport hops. Their bytes are never added to ordinary app totals or the physical headline again.
- Endpoint changes are resolved across a complete frame, so clients appearing before their proxy are handled. Departed endpoints, PID/name changes and sampler restarts do not leave a local service falsely classified as an internet proxy.
- This is socket-level attribution: proxy protocol/control bytes may be included. PAC, TUN-only paths, unknown listener defaults, non-loopback Headroom listeners, negotiated UDP relays and sockets too short for nettop remain outside the guaranteed contract. No claim of exact payload-to-wire equality is made.

## Preserving earlier mixed records

- Earlier generic Python.app entries, including adopted child rows, cannot be reliably split after the fact. Do not rename all those bytes to Headroom.
- On the first runtime-classification upgrade, JSON moves those exact entries to `legacyApps` and records `runtimeAttributionStartedAt`. They are shown as “Earlier mixed usage”, outside the ordinary ranking and app lower bound. New ordinary Python remains separate from this archive.
- SQLite version 3 adds `legacy_app_traffic`. In one transaction, matching pre-upgrade rows move there without changing their byte values, their contribution is removed from `traffic.app_in/app_out`, and the version advances. Physical interface counters and sessions remain intact. Reopening does not repeat the migration.
- History displays the archive separately. Retention, clear and app-metadata cleanup include it. Normal CSV omits transport and legacy informational rows to avoid a duplicate sum; original records remain available in local history and the rollback snapshot.

## Verification

- Original implementation failed the identity and chained-proxy regressions. Dynamic-order, retired-port and direct-upstream regressions were also observed failing before their fixes.
- Final `make test`: all 487 tests / 1573 assertions passed, with live checks enabled. The real-nettop two-hop fixture sent a bounded 1 MiB response entirely on loopback; the source was attributed once, the Headroom hop was separate, and the downstream server side was not billed again.
- Native build, stopped-data backup and installed-byte preservation are recorded in `current-project-state.md` after replacement. No real speed test or remote publication is part of this task.
