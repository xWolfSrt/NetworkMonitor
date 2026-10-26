# Local system-proxy attribution

Approved 2026-10-26 (Asia/Shanghai). Scope: improve the existing local Fork and update the installed app after validation. Keep security fixes, data, settings and rollback material.

## Confirmed starting point
- macOS system HTTP/HTTPS/SOCKS proxy is local port 65532, served by Nano 1.0.10.
- A read-only nettop loopback snapshot exposes original client processes and both halves of their local proxy connections.
- Current sampling excludes loopback. The parser also groups local connections with LAN traffic.

## Accounting contract
- Discover enabled, explicit loopback HTTP/HTTPS/SOCKS endpoints with SystemConfiguration; read no proxy credentials and change no system settings.
- Keep the existing persistent `nettop -t external` stream for direct traffic. Add a separate `nettop -t loopback` stream; only confirmed client-side TCP socket bytes to a configured proxy endpoint count toward the originating app. Never infer internet usage from raw loopback process totals when closed socket details are unavailable.
- Discover forwarding processes during the discarded priming sample so their first external delta can be classified. Keep separate validated child records for the two owned subprocesses, and stop/recover both through the existing kernel-identity checks.
- Exclude other loopback services and ordinary LAN traffic. Loopback bytes must never be subtracted from physical interface counters.
- Identify a forwarding process by its server-side connection to an active system-proxy endpoint, not by app name. Show its external traffic separately as Proxy transport, outside the app ranking and per-app lower bound.
- Keep physical interface counters as the headline/rate source. Do not add client and transport figures together. Payload and wire volumes may differ.
- Separate transport samples from ordinary app samples in current buckets and an additive SQLite history table. Keep old history unchanged; do not invent attribution for past Nano traffic. Display when proxy attribution began.
- Keep CSV export for ordinary attributed apps and its existing formula protection; transport totals must not be added again.

## Boundaries
- Explicit local TCP system proxies only. No guaranteed attribution for PAC/WPAD, TUN-only paths, negotiated UDP relays, proxy chains split across unrelated apps, or connections too short for nettop to retain. Such short connections can be undercounted; ordinary localhost root totals stay excluded.
- Proxy transport includes the forwarding app's own external traffic too; nettop cannot reliably distinguish its own update/control requests from forwarded wire bytes. Keep it an aggregate.
- Existing SQLite app history stays unchanged. Current-day bucket entries for a recognized forwarding process move to the separate aggregate, without assigning any earlier bytes to clients. New transport samples use the additive `proxy_transport_traffic` table (`user_version = 2`); client attribution is recorded only from this feature's activation onward.
- No interception/decryption of content, root helper, network extension, external telemetry or real speed test.
- Changing ports or disabling the system proxy must refresh recognition without restarting the app.

## Verification
- Regression fixtures: IPv4/IPv6 endpoints, client/server direction, direct plus proxied traffic, unrelated local services, LAN subtraction, proxy changes and PID/name churn.
- Store/history: deduplication, old JSON/SQLite compatibility, persistence, retention/clear, ordinary CSV totals and formula escaping.
- Full existing tests, native Release build/signature, a bounded local proxy fixture, then backed-up installation and live Nano/process/data checks.

## Verified implementation (2026-10-26)

- `make test`: 475 tests / 1503 assertions passed, with all live checks enabled. The bounded real-nettop fixture transferred 1 MiB each through two localhost services and confirmed original-client attribution, zero server-side billing and zero unrelated-localhost billing.
- Fixtures also cover the view-model two-stream path, priming roles, closed-socket root exclusion, UDP same-port exclusion, SQLite v1 compatibility, reopen/retention/clear and CSV separation.
- Native build, installed data and owned-child checks are recorded in `current-project-state.md` after replacement. No real speed test or proxy-setting change is part of validation.
