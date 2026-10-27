# Current project state

Verified 2026-10-26 (Asia/Shanghai).

## Confirmed baseline
- Fork: `xWolfSrt/NetworkMonitor`; origin points to that fork.
- Source: `/Users/mac/Developer/NetworkMonitor`; starting commit `1f2f275`.
- SwiftPM project, Swift 5 language mode, Swift 6 toolchain, AppKit/SwiftUI, system SQLite; macOS 13+.
- Installed at `/Applications/NetworkMonitor.app`; local Apple silicon build with ad-hoc signing.
- Baseline `make test`: 447 tests / 1379 assertions passed.
- Normal monitoring uses a `nettop` child. No telemetry upload path was found in the bounded source review; this is not a guarantee about future revisions.
- Hotspot mode is off and its root helper, sudoers rule and LaunchDaemon are not installed.
- History is local plaintext and defaults to indefinite retention.

## Authorized current work
Explicit local system-proxy attribution is implemented as specified in `proxy-attribution.md`: separate external/loopback sampling, original-app client accounting, separate proxy transport totals, additive local history storage and an activation-time note. Preserve all security fixes and existing history; do not enable Hotspot mode or publish remotely. Installation validation is recorded below when complete.

## Risks and next direction
The optional Hotspot feature can pause security updates and leaves update suppression on ordinary exit. Keep it disabled for monitoring-only use. Continue privacy/security review before adding integrations or privileged behavior.

## Security hardening implementation
- Orphan recovery now uses an app-private child record, validated against kernel PID/start time/UID/executable identity and orphan status. Untracked legacy processes are deliberately left alone.
- CSV text receives formula-prefix neutralization before ordinary CSV quoting, including leading whitespace/control-character cases.
- Startup and command-line uninstall share the same recorded-child validation; command-line process scans were removed from those nettop recovery paths.
- Validation: original CSV implementation fails both new export regressions; the hardened core passes all 458 tests / 1421 assertions, including live sampling. Release build and the uninstall recovery hook pass; installed bundle/signatures match the build.
- Local installation: build 76 is running from `/Applications/NetworkMonitor.app`. Historical row counts were preserved (sessions 1, apps 19, traffic 2, app_traffic 32). The recorded child matches the running app/nettop relationship and its recovery file has mode 0600.
- Rollback app, preferences and stopped SQLite data snapshot: `backups/before-security-20261026-171549` (Git-ignored). Hotspot mode remains off and its privileged components remain absent.
- Login-item settings were not modified. Re-reading the system BTM database and reading app UI timed out; next-login behavior has not been re-accepted after this local replacement.

## Proxy attribution installation

- Feature code: local branch `codex/proxy-attribution`, commit `dd3be32`. Native ad-hoc-signed build 77 was installed at `/Applications/NetworkMonitor.app`; all installed bundle files matched the verified build.
- Validation: all 475 tests / 1503 assertions passed, including the real-nettop localhost fixture and existing live sampling/lifecycle/CPU tests. No live checks were skipped and no real speed test ran.
- Runtime: original apps including ChatGPT and Google Chrome accumulated new ordinary-app samples, Nano accumulated only in the separate transport table, and every one of the 54 pre-upgrade per-app history rows retained at least its previous bytes. Existing SQLite app rows were not relabelled or reassigned.
- Both nettop children matched the running app, UID, executable path and kernel start time in separate mode-0600 records. A six-second runtime sample measured about 1.49% of one CPU core across both children; this is a bounded observation, not a battery benchmark.
- Preferences were byte-value equivalent after plist decoding (no changed keys). Hotspot remained off; privileged helper, sudoers entry and LaunchDaemon remained absent. No internet socket was open by the monitoring app in the read-only snapshot.
- Rollback App, stopped local data and preferences: `backups/before-proxy-20261026-182822` (mode 0700, Git-ignored), with `runtime-verification.json`. The earlier security rollback remains intact.
- Proxy configuration and login-item registration were not changed. Menu/history views compile and their runtime data path is verified; visual layout and next-login relaunch were not manually re-accepted during this replacement.
- This is a local installation only. Nothing was pushed, no issue/PR/release was created, and no repository settings were changed.

## Menu bar legibility (2026-10-27)

- User reported unreadable menu-bar rates over a light wallpaper. The previous title used 8.5 pt regular text with fixed pale green/grey colours.
- Live rates now use a macOS template image at the default colour settings, allowing the status button to supply its foreground for appearance, wallpaper and selection. Explicit custom colours remain non-template images. The Settings reset action is labelled “Use Automatic Contrast”; no new preference or preference migration is required.
- The two rows use 10 pt semibold monospaced glyphs drawn on separate CoreText baselines within the existing 22 pt image. Rate formatting and constant-width behaviour remain unchanged; the status item is slightly wider because its text is larger. Speed-test colours remain explicitly selected by the existing test palette.
- `make test`: 477 tests / 1518 assertions passed, including all live checks and new template/custom-colour and 1×/2× unclipped-glyph raster regressions. No real speed test ran. Native ad-hoc-signed build 79 (feature code `a91629b`) was installed and relaunched successfully; installed files matched the verified build.

- Installation validation: both owned nettop kernel identities and mode-0600 records matched the running App. All 936 previous ordinary-app history rows and 29 proxy-transport rows retained at least their previous bytes. Preferences were unchanged, with no custom-colour overrides, so automatic contrast is active. Hotspot remained off and privileged components remained absent.
- Rollback App, stopped data, preferences and `runtime-verification.json`: `backups/before-legibility-20261027-111832` (mode 0700, Git-ignored). Earlier rollback sets remain intact. Local branch: `codex/menu-bar-legibility`; nothing was pushed remotely. Pixel layout was verified in rendered images; a separate manual desktop screenshot acceptance was not performed.

## Headroom accounting (2026-10-27)

- Headroom module/console entry points now have stable identity `runtime:headroom`, independent of Python.app. Its explicit local proxy listener participates in chained attribution; forwarding hops are separate from original-app counters, including direct-upstream and transient-order cases.
- Earlier mixed Python and adopted-child records are preserved as separate informational legacy usage. SQLite version 3 migrates exact old rows transactionally and keeps physical/session counters intact. New ordinary Python, Headroom transport and the earlier archive remain distinct across reopening.
- All 487 tests / 1573 assertions passed, with real-nettop one-hop/two-hop loopback checks, process-lifecycle checks and no real speed test. See `headroom-accounting.md` for measured regressions, scope and privacy boundaries.
- Native build, backup and installed runtime validation are pending below; no remote push or repository setting change is authorised.
