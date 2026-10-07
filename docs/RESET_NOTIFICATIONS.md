# Codex reset notifications (1.1.0)

General and the final onboarding page share an opt-in notification control.
Enabling it requests macOS alert/sound permission. Denied permission links to
System Settings. Existing and fresh installations default to off.

Only successful, fresh Codex observations are compared. A known 5-hour or weekly
window must cross its previous reset time and report a new future reset boundary.
Countdown expiry, stale/error data, account removal, first samples, and duplicate
refreshes do not notify. Delayed server rollover retains the previous baseline.
Detector state is persisted per account/window to prevent repeats across relaunch.
Disabling clears baselines; re-enabling does not generate historical alerts.
The app must be running and successfully refresh to detect a reset. This is local
notification delivery; no remote push server or extra polling is introduced.

Validation: 169 Core tests passed, including reset/deduplication/persistence,
stale data, delayed rollover and account changes. Release build succeeded.
Installed General and onboarding controls were checked through accessibility;
brand wordmarks were visually checked. Actual quota-reset banner delivery is not
yet verified against a live reset.

Release evidence (2026-10-07): application notarization Accepted, submission
`0fa9d98f-880f-4d35-bf17-41ed6fb84e6e`. Application and standalone saver stapled;
installed 1.1.0 (81) passed codesign, stapler validation and Gatekeeper assessment
with `source=Notarized Developer ID`. Original app backed up under
`build.noindex/install-backups/pre-1.1.0/`. Current system notification permission
was denied; the app correctly exposes the System Settings link.

DMG notarization also Accepted: `9c635c4d-21ec-4f45-b783-f224f84332a3`.
Installer: `QuotaClock-1.1.0-81.dmg`. Release assets include the notarized installer, signed Sparkle ZIP, appcast and
SHA-256 checksums.
