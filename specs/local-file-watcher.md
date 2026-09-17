# Spec: Local File Watcher

## Problem

When the user adds, modifies, or deletes files in a synced local folder, the app doesn't detect it. A sync only happens when the auto-sync timer fires (or the user triggers it manually), so new local files can sit unsynced for hours.

## Behavior

### Golden path

1. User drops new files into a watched local folder.
2. The app detects the change within ~1 second via FSEvents.
3. The app waits 15 seconds without further changes (debounce) to let batch operations (Finder copy, unzip, git checkout) settle.
4. During the debounce window the job row subtitle shows "Changes detected…".
5. After debounce, if the job is not already running and not paused, the app starts a sync for that job automatically.
6. The sync runs and completes normally.

### Edge cases

- **Batch operations**: Multiple files dropped at once — debounce timer resets on each new event, so sync fires once after everything settles.
- **Sync already running**: Change detected while the job is already syncing → debounce timer starts, but sync is not re-triggered until the current run finishes. After finish, if the debounce fired during the run, the next sync starts immediately.
- **Job paused**: Change detected while paused → debounce fires, but sync is not started. Pending-change state is cleared; when the user resumes, sync starts normally.
- **App launch**: On launch, a sync is triggered for overdue jobs as before (existing behavior, unchanged). File watcher then takes over for incremental changes.
- **Folder deleted**: If the local path no longer exists, the watcher is stopped silently and no sync is attempted.

## Interface

### New type: `LocalFileWatcher`

```swift
final class LocalFileWatcher {
    init(paths: [String], onChange: @escaping () -> Void)
    func start()
    func stop()
}
```

Wraps `FSEventStream` with `kFSEventStreamCreateFlagFileEvents`. Calls `onChange` on any event, coalesced to at most once per second before the debounce layer handles the rest.

### Changes to `StatusStore`

- `private var fileWatchers: [String: LocalFileWatcher]` — one per job id.
- `private var pendingWatcherSync: [String: DispatchWorkItem]` — one debounce item per job id.
- `private var pendingSyncAfterRun: Set<String>` — job ids that need a sync once their current run finishes.
- `startWatchers()` — called after daemon ready; creates a watcher for each job definition.
- `stopWatchers()` — called on job removal or app quit.
- When config changes (job added/removed), watchers are reconciled.

### New `SyncJob` field

```swift
var hasLocalChanges: Bool = false  // true during debounce window
```

Drives the subtitle "Changes detected…" in `JobRow`.

### `MenuBarView` / `JobRow`

Add one new branch in `rowSubtitle` (before the `lastSyncDisplay` branch):

```swift
} else if job.hasLocalChanges {
    Text("Changes detected…")
        .font(.caption2).foregroundStyle(.secondary)
```

## Out of scope

- Watching GDrive (remote) for changes made by other devices.
- Syncing only the changed files (rclone always does a full scan; this is unchanged).
- Configurable debounce duration — 15 seconds is fixed for now.
- Watcher events for jobs in `.error` or `.tokenError` state triggering a sync (they still require manual intervention).

## Open questions

1. **Debounce duration**: 15 seconds feels right for large Finder copies, but could be too slow for small single-file saves. Should it be 5s? Adjustable per job?
2. **"Changes detected" badge on menu bar icon?**: Should the menu bar icon change (e.g., a dot or different symbol) while any job is in the debounce window?
3. **Error state**: If a job is in `.error`, should detected local changes show as "Changes detected…" (implying a sync will eventually happen) or should they be silently queued?
