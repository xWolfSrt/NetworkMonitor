# Interface languages

Confirmed implementation, 2026-10-27:
- The app defaults to Simplified Chinese independently of macOS language. General offers 简体中文 and English; `interfaceLanguage` is the only new preference.
- Language changes update SwiftUI views, the settings toolbar/window and AppKit menus in place. The selected pane, filters, counters and running speed-test state retain their identity.
- `L10n.text` separates interpolation values from keys; `L10n.translate` is reserved for known built-in display metadata. Never translate arbitrary App names, SSIDs, custom network labels, parser input, IDs, storage keys or CSV headers.
- Core resources have English and Simplified Chinese catalogs. SwiftPM lowercases the `zh-hans.lproj` output; the app packager copies its resource bundle into Contents/Resources. Installed builds resolve that bundle before the SwiftPM development fallback.
- Dates and durations follow the selected interface locale, while calendar accounting boundaries and export machine formats retain their existing behavior.

Verification: default/persistence/fallback, interpolation safety, catalog parity, live toolbar updates and isolated native UI renders, followed by `make test` and `make app`. Never enable Hotspot or run a real speed test for localization checks.

Before replacement, back up the installed app, stopped history and preferences. Verify existing history bytes and unrelated preferences after launch.

## Unicode sampling regression found during verification

Real nettop output contained process names truncated inside a UTF-8 scalar. The previous per-read strict String initializer discarded the whole read, including unrelated valid traffic rows. A deterministic shell fixture reproduced missing counters before the fix.

`NettopTextDecoder` now buffers complete CSV lines, repairs invalid name bytes and preserves valid Chinese/emoji split across PTY reads. Quiet publication waits for any partial byte line, and restarting clears decoder state. Accounting formulas, proxy roles, IDs and stored data are unchanged. The fixed invalid-name subprocess regression and real one-hop/two-hop proxy fixtures passed. The earlier exploratory change from fixed fixture delays to semaphore readiness was withdrawn because empty loopback frames do not deliver samples.
