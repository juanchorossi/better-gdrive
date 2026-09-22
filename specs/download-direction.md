# Spec: Download Direction (Drive → Local)

## Problem

Users who keep files in Google Drive cannot pull them to their local machine with BetterGDrive — every job today is hardcoded to upload (local → Drive).

## Behavior

### Golden path

1. User opens the "Add Job" sheet.
2. A direction picker is shown at the top: **Upload** (↑ Local → Drive) or **Download** (↓ Drive → Local). Default: Upload (preserves current behavior).
3. User selects **Download**, picks a GDrive path (source) and a local folder (destination), names the job, and saves.
4. The job appears in the sidebar with a **↓** badge next to its name, so it is instantly distinguishable from upload jobs.
5. When the sync runs (manually, on a schedule, or auto-triggered), rclone copies files from Drive to the local folder.
6. The activity feed shows the operation as **"downloaded"** instead of "uploaded".

### Edge cases

- **Existing jobs**: All jobs with no `direction` field default to `.upload` on decode. Config is backward-compatible, no migration needed.
- **Download + sync mode (destructive)**: If the user picks "Sync" (not "Copy") for a download job, rclone will delete local files that aren't in Drive. The UI must show a visible warning in the job form when direction is Download and copy mode is off. The warning: *"Sync will delete local files not found in Drive."*
- **File watcher disabled for download jobs**: The `LocalFileWatcher` is only relevant for upload jobs. Download jobs do not watch the local folder for changes — Drive is the source and it is not observable via FSEvents.
- **Activity op**: A file moved from Drive to local is recorded as `.downloaded`. The existing `.uploaded` and `.updated` ops continue to map to upload jobs only. Rclone's `transferred` list does not distinguish "new file" from "updated file" for downloads, so all download transfers are recorded as `.downloaded`.
- **GitPullFirst**: Meaningless for download jobs. The field is ignored when direction is `.download`.
- **Exclude patterns / filter file**: These still apply — the user may want to download only a subset of Drive files.
- **Rename or re-edit a job**: Changing direction on an existing job is allowed. No data migration is needed since direction only affects the rclone invocation.
- **Manual sync trigger**: Same behavior as upload jobs — the "Sync now" button kicks off the job immediately regardless of direction.

## Interface

### New type: `SyncDirection`

```swift
enum SyncDirection: String, Codable {
    case upload   // local → Drive (default, current behavior)
    case download // Drive → local
}
```

### Changes to `JobDefinition`

Add one field:

```swift
var direction: SyncDirection   // default .upload
```

Backward-compatible decode: `(try? c.decode(SyncDirection.self, forKey: .direction)) ?? .upload`.

`gitPullFirst` is ignored by `startSync` when `direction == .download`.

### Changes to `RcloneRC.startSync`

When `job.direction == .download`, swap source and destination:

```swift
let src = direction == .upload
    ? job.localPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
    : job.drivePath
let dst = direction == .upload
    ? job.drivePath
    : job.localPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
// body["srcFs"] = src, body["dstFs"] = dst
```

### Changes to `ActivityOp`

Add one case:

```swift
case downloaded
```

With:
- `description`: `"downloaded"`
- `icon`: `"arrow.down.circle"`
- `color`: `.purple`

### Changes to `StatusStore`

In `handleTransferred`, when the active job has `direction == .download`, record `.downloaded` for all transferred files.
`LocalFileWatcher` creation is skipped for jobs where `direction == .download`.

### UI changes

**Job creation form (`MainWindowView` or wherever the Add Job sheet lives)**:
- Add a `Picker` or `SegmentedControl` at the top for direction (Upload / Download).
- Inline warning text below the copy/sync toggle when `direction == .download && !copyMode`.

**Job row / sidebar**:
- Show a direction badge: `↑` for upload, `↓` for download, placed after the job name or as a subtitle prefix.
- No other row changes.

**Detail view header**:
- No changes needed — it already shows the job name and status.

## Out of scope

- Watching Google Drive for remote changes (webhooks / Drive push notifications).
- Bidirectional sync (two-way merge).
- Conflict resolution.
- Per-file download decisions (cherry-pick individual files from Drive).
- Changing `localPath` label to "Destination folder" in the form (pure cosmetic, can follow in a polish pass).

## Open questions

1. **Sync mode for downloads**: Should download jobs be forced to `copyMode = true` to prevent accidental local deletions, or is the warning sufficient? Forcing copy mode removes a legitimate "mirror" use case; the warning keeps it opt-in.
2. **Speed indicator in DetailView**: The progress panel shows `Label(speed, systemImage: "arrow.up")`. Should it switch to `"arrow.down"` for download jobs?
3. **Menu bar icon during download sync**: Currently the icon implies upload. Worth a follow-up to make it direction-neutral or direction-aware.
