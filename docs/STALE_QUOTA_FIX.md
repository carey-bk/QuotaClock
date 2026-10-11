# Stale quota after manual refresh (1.1.1)

On 2026-10-09 the shared snapshot retained Codex values last fetched around
2026-10-08 16:23 (Asia/Shanghai), with `stale`, `usingLastKnownGood=true`, and
`Request timed out` / `Provider unavailable`. DeepSeek continued refreshing.

Two application bugs concealed recovery failure:

1. `SnapshotController.refreshAll(manual:)` discarded its argument and always
   passed `false`. The manual button therefore respected automatic retry backoff.
2. The menu footer used snapshot publication time, so another provider's success
   made stale Codex quota appear recently updated. Metric-bearing cards omitted
   their failure/stale state.

The manual flag now reaches the coordinator. Card freshness uses last successful
quota retrieval, with the same 15-minute freshness threshold as the coordinator.
The menu footer uses the oldest successful retrieval among displayed cards and
labels stale data. Cards keep their original geometry with no added stale row. Stale full cards
omit quota advice; the bottom menu status bar carries freshness and elapsed time.
Account-specific error details remain in AI Services settings.

An isolated live read of the current account succeeded without changing active
credentials or writing Keychain data. The installed 1.1.0 account-specific Refresh
also recovered Hanz: weekly 58%, 5h reset October 9 16:14, week reset October 14
11:29, matching Codex's current reset boundaries. Percentages are time-sensitive.
The original network failure's exact cause cannot be established from the retained
sanitized errors; no proxy or credential settings were changed.

Validation: 170 Core tests passed, including stale/fresh timestamp regression and
existing independent backoff/manual-recovery tests. Current-account live RPC passed.

Installed verification: 1.1.1 (82), notarization Accepted
`13afc0e5-7f5c-4fa3-ba88-3c11bf67421f`, stapled and Gatekeeper accepted.
Manual Refresh All in the installed General page completed with all three Codex
accounts and DeepSeek healthy; fresh attempt/success timestamps were confirmed
in the canonical snapshot and account rows no longer showed stale status.
English/Chinese large and medium card renders verified the layout. Build 83
removes the card stale row after real-world overflow feedback; stale rendering
now retains the original progress-bar margins.
This build includes the previously requested notification wording. No GitHub
release or commit was made as part of this diagnosis.
