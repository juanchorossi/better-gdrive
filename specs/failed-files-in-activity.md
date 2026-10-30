# Spec: Failed files in Activity

## Problem
When a sync fails, the job row shows only the last error. If several files or folders failed there is no place in the app to see which ones; the only record is the rclone log.

## Behavior

### Golden path
1. A sync runs and some files fail (transfer errors or unreadable local folders).
2. Each failure appears in the **Activity** tab as a red **Failed** row: file or folder name, job, a short reason (`No permission`, `Google auth hiccup`, `File vanished`, or rclone's last error segment), and time.
3. Failed rows live alongside Uploaded/Downloaded rows, newest first, in the same 500-item list, and persist in `activity.json` like the rest.
4. The error row's tooltip ends with `Details in Activity`.

### Edge cases
- Transfer failures come from rclone's `core/transferred` (items with a non-empty `error`), live during the run and at the end.
- Listing failures (e.g. `lstat … permission denied` on a folder) never reach `core/transferred`. They are read from the rclone log lines written during the job (`ERROR : <path>: <reason>`), attributed to the job only if `<localPath>/<path>` exists on disk. Root-level summary lines (`Google drive root …: not deleting …`, `Attempt N/3 failed`) are skipped.
- At most 50 failed rows are added per run so a broken folder tree cannot flush the whole list.
- A file that fails and then succeeds on rclone's retry shows both rows: the failure and the upload. rclone reports one `core/transferred` entry per attempt.
- The same path failing again with the same reason does **not** add a new row while the newest row for that path is already that failure. A later success resets this, so the next failure shows again.
- Failed rows show the full relative path as title (the folder is the point), with path and reason in the tooltip.
- Failed rows have no "Open in Google Drive" link.
- Old `activity.json` entries without the new field decode unchanged.

## Interface

### Models
- `ActivityOp` gains `.failed` ("Failed", `xmark.circle`, red).
- `ActivityItem` gains `detail: String?` (short reason).

### RcloneRC
- `logOffset()` returns the current size of the rclone log.
- `failedListings(since:)` / pure `parseFailedListings(_:)` turn log text into `(path, reason)` pairs.

### StatusStore
- Records the log offset when a job starts.
- `addLiveActivity` / `finishJob` no longer drop transfers with `error`; they become `.failed` items.
- On a failed finish, parses the log slice for listing errors and adds them.
- `shortReason(_:)` maps raw rclone reasons to the short labels above.

### UI
- Menu popover Activity row: second line shows `job · reason · time` for failed items.
- Main window Activity table and job detail list: failed rows use the plain red label, tooltip with the full reason.

## Out of scope
- A counter or link from the job row to a filtered Activity view.
- Filtering Activity by type.
- Retrying a single failed file.

## Open questions
- None.
