# Sync Delete Confirmation

## Problem
Jobs in sync mode (not copy mode) can delete files on the destination without warning. A misconfigured job can cause permanent data loss before the user has a chance to react.

## Behavior

### Golden path — files would be deleted
1. User triggers a sync-mode upload job manually (play button in popover or main window).
2. App runs a rclone dry-run to discover which files would be deleted.
3. If 1 or more files would be deleted, a native confirmation sheet appears:
   - Title: "X files will be deleted from [destination]"
   - Body: scrollable list of filenames
   - Buttons: **Delete and Sync** (destructive) · **Switch to Copy** · **Cancel**
4. **Delete and Sync** → sync runs normally, files get deleted.
5. **Switch to Copy** → job is updated to copy mode, sync runs without deleting anything.
6. **Cancel** → nothing happens.

### Golden path — no deletions
Dry-run finds zero deletions → sync starts immediately, no dialog shown.

### Scheduled / automatic runs
No confirmation shown. These run unattended.

### Dry-run failure
If the dry-run fails for any reason, skip the confirmation and proceed with the normal sync. Don't block the user.

### Download jobs
Always use copy mode (enforced in code). No dry-run, no confirmation.

## Interface

### `RcloneRC`
```swift
static func dryRunDeletions(job: JobDefinition) async -> [String]
// Returns relative paths of files that would be deleted.
// Returns [] on any error (fail open).
// Runs sync/sync with DryRun:true, polls until complete, parses log for "Would delete" lines.
```

### `StatusStore`
```swift
struct PendingDeletion: Identifiable {
    let id = UUID()
    let job: SyncJob
    let filesToDelete: [String]
}
@Published var pendingDeletion: PendingDeletion? = nil

func run(_ job: SyncJob)              // checks for deletions first if sync-mode upload
func confirmDeleteAndSync(_ job: SyncJob)   // skips dry-run, runs sync directly
func switchToCopyAndSync(_ job: SyncJob)    // updates job to copyMode=true, then runs
```

### UI
- `.sheet(item: $store.pendingDeletion)` on both `MenuBarView` and `MainWindowView`.
- Sheet shows a `List` with the filenames, capped height with scroll.

## Out of scope
- Letting the user choose individual files to preserve
- Confirmation for scheduled/automatic runs
- Undo after sync runs

## Open questions
- None — ready to implement.
