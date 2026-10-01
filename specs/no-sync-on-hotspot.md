# Spec: No sync on Personal Hotspot

## Problem
When the Mac connects to an iPhone Personal Hotspot, automatic sync wastes mobile data — the user wants sync to pause automatically on metered connections.

## Behavior

### Golden path
1. User enables "Pause on Personal Hotspot" in Settings → General.
2. Mac connects to the iPhone hotspot (WiFi, USB, or Bluetooth tethering).
3. Auto-sync timer and FSEvents-triggered syncs are silently skipped.
4. The status banner shows "Paused · Hotspot detected" instead of the normal status.
5. The menu bar icon switches to the pause symbol.
6. User can still press play on any job or hit "Sync All" to force a manual sync — the preference only suppresses *automatic* triggers.
7. Mac switches back to a regular network → sync resumes automatically on the next auto-sync tick or file change event.

### Edge cases
- If a sync is already running when the hotspot is detected, it is not stopped mid-flight. The preference only gates new syncs from starting.
- Preference defaults to **on** — new installs and upgrades (which lack the key in config.json) get hotspot protection automatically.
- "Expensive" network detection uses `NWPath.isExpensive` (covers WiFi hotspot, USB tethering, and Bluetooth PAN — all surfaces Apple marks as expensive on macOS 10.15+).

## Interface

### Data model
- `SyncConfig` gains `skipOnHotspot: Bool` (default `true`, backward-compatible decode — new users and upgrades default to on).

### StatusStore
- New `@Published var isOnExpensiveNetwork: Bool` — driven by a persistent `NWPathMonitor`.
- `triggerAutoSyncIfDue()` and `firePendingSync()` check `skipOnHotspot && isOnExpensiveNetwork` and return early if true.
- `headerTitle` / `headerColor` / `menuBarIcon` reflect the hotspot-paused state.

### UI
- Settings → General: new toggle row "Pause on Personal Hotspot" with a caption "Skips automatic sync when connected to iPhone hotspot or USB tethering."
- Status banner: when hotspot-paused, shows `"Paused · Hotspot"` subtitle and blue pause icon (same visual as manual pause, different subtitle).
- Menu bar icon: `"pause.circle"` when hotspot-paused and not otherwise running/erroring.

## Out of scope
- Stopping a sync that is already in progress.
- Per-job granularity (it's a global setting).
- Distinguishing USB tethering from WiFi hotspot (both are "expensive" and both waste data).
- Any UI hint on the individual job rows (only the banner and menu bar change).

## Open questions
- None — `NWPath.isExpensive` covers all hotspot surfaces on macOS 10.15+ without requiring CoreWLAN or SSID parsing.
