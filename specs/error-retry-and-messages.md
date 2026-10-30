# Spec: Error retry backoff and honest error messages

## Problem
A folder that fails permanently is retried every 60 seconds forever, and a transient Google 401 is reported as "Sign-in expired" even though the token is valid — so the UI lies and the daemon burns CPU, Drive quota and disk (551 MB log, ~1,000 full-tree runs/day).

## Behavior

### Golden path
1. A sync ends in error. The job row shows a short message with a count when rclone gives one:
   `3 files failed — nothing deleted`. Hovering the row shows the last failed path and rclone's reason.
2. The job is retried automatically with exponential backoff: 1m, 2m, 4m, 8m, 16m, then every 30m. Pressing ▶ retries immediately and resets the backoff.
3. If the job keeps failing, the row appends how long it has been failing: `… · failing for 12 days`. This survives app restarts.
4. The first successful sync clears the message, the backoff and the "failing for" counter.

### Sign-in expired
5. A job is marked **Sign-in expired** only when rclone reports `invalid_grant` or an expired token, or when a Google `authError` is confirmed by a live check (`operations/about` on the remote fails with an auth error).
6. A Google `authError` that is *not* confirmed is a normal transient error (`Google auth hiccup — retrying`) and follows the backoff rule.
7. Sign-in expired jobs are never auto-retried. On app launch, if the live check passes, they are cleared and synced.
8. The banner, header and rows all use the same wording: "Sign-in expired". No "Sign-in required".

### Edge cases
- Backoff counter lives in memory; a restart resets it to the first step (1m). "Failing since" is persisted.
- Manual ▶ on a backed-off job starts it immediately.
- The rclone log is rotated to `.old` when it exceeds 50 MB at daemon start (one generation kept).

## Interface

### StatusStore / SyncJob
- `SyncJob` gains `failingSince: Date?`, `lastErrorDetail: String?`.
- `UserDefaults` gains `failingSince.<jobId>` (Date). `status.<jobId>` now also stores `"tokenError"` and is loaded back as `.tokenError`.
- `triggerAutoSyncIfDue()` consults a per-job `nextRetryAt` computed from consecutive failures.
- `RCStats` gains `lastError`.

### RcloneRC
- `verifyGoogleAuth(remote:) async -> Bool?` — `true` valid, `false` auth rejected, `nil` undetermined (network).
- `_filter` uses `ExcludeRule` (bug fix: `Exclude` was silently ignored).

### UI
- Menu + main window rows: error subtitle `"<message> · failing for <duration>"` when failing > 1h; `.help()` tooltip with `lastErrorDetail`.
- Token error rows say "Sign-in expired".

## Out of scope
- Cleaning up `node_modules` already uploaded to Drive by the ignored excludes.
- Deduplicating duplicate Drive objects.
- Per-job configurable retry policy.

## Open questions
- None.
