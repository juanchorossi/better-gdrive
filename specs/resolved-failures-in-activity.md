# Spec: Resolved failures in Activity

## Problem
A **Failed** row in Activity looks the same whether the problem is still happening or a later sync already fixed it. Folder listing failures never get a matching "Uploaded" row, so the user cannot tell from the app that the failure was retried and resolved.

## Behavior

### Golden path
1. A sync fails and leaves one or more **Failed** rows for that job (files or folders).
2. A later run of the same job finishes with **zero errors**.
3. Every unresolved **Failed** row of that job is marked resolved at that moment. The row stays in the list, in its original position, but reads `Failed · resolved` in dimmed red instead of full red. Its tooltip gains a line `Synced OK <date time>`.
4. Rows of jobs that keep failing stay full red and unchanged.

### Edge cases
- Only a run that ends with no errors resolves rows. A run that ends in error, in a Google auth hiccup, or in a token error resolves nothing.
- Failures recorded by the same successful run (a file that failed on attempt 1 and succeeded on retry) are resolved too, since the run ended clean.
- A resolved failure does not suppress a new failure of the same path with the same reason: the repeat-dedupe only looks at unresolved rows.
- Old `activity.json` entries without the new field decode unchanged and count as unresolved.
- Resolution is per job, not per path: a clean run means the whole tree is reconciled.

## Interface

### Models
- `ActivityItem` gains `resolvedAt: Date?`, `isResolved`, `statusLabel` (operation name, or `Failed · resolved`), `statusColor` (operation color, dimmed for resolved), and the extra tooltip line.

### StatusStore
- Pure `resolveFailures(for jobName:in:at:)` marks matching rows; `finishJob` applies it after a clean run and saves.
- `isRepeatedFailure` ignores rows that are already resolved.

### UI
- Menu popover, main window table and job detail list render `statusLabel` / `statusColor` instead of the raw operation.

## Out of scope
- Removing or hiding resolved rows.
- Per-path verification against Drive before marking resolved.
- A filter to show only unresolved failures.

## Open questions
- None.
