# Local work rules

- Reproduce behavioral defects safely before fixing them. Test the real export boundary and process ownership decisions; do not signal unrelated processes.
- Validate process identity using PID, kernel start time, UID and executable path. Parent PID alone or a command-line substring is insufficient.
- Treat Wi-Fi labels and app display names as untrusted spreadsheet text when exporting.
- Use `make test`, not `swift test`; record any skipped live checks separately.
- Use `make app` for the native architecture. Verify bundle/signatures and compare the installed copy after replacement.
- Development builds share settings/history with the installed copy. Stop it before replacement or copying its database, and retain a rollback app plus data snapshot.
- No real network speed tests, privileged helper installation, security-update changes or unrequested publication.

- Default fork development uses local `develop` tracking `origin/develop`. Base any necessary isolated feature branch on `develop`; retain `main` for the separately authorised upstream/release workflow.
