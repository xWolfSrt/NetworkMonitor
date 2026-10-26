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
Fix startup process selection and spreadsheet formula injection in CSV export, add regression coverage, and replace the local installed app after verification. Preserve existing data and settings; do not enable Hotspot mode.

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
