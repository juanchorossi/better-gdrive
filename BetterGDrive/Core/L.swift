// All user-visible strings live here.
// To add a new language:
//   1. Create Sources/Resources/<lang>.lproj/Localizable.strings
//   2. Replace each `= "..."` with `= NSLocalizedString("key", comment: "...")`
//   3. Fill in the translations in the .strings file

enum L {
    enum General {
        static let appName    = "Better GDrive"
        static let refresh    = "Refresh"
        static let runAll     = "Run all"
        static let run        = "Run"
        static let cancel     = "Cancel"
        static let openWindow = "Open window"
        static let choose     = "Choose…"
        static let add        = "Add"
        static let now        = "now"
        static let eta        = "ETA"
    }

    enum Tabs {
        static let status   = "Status"
        static let activity = "Activity"
        static let settings = "Settings"
    }

    enum Status {
        static let upToDate       = "Up to date"
        static let syncing        = "Syncing…"
        static let tokenExpired   = "Token expired"
        static let syncError      = "Sync error"
        static let upToDateDetail = "All files are synced with Google Drive"
        static let syncingDetail  = "Syncing files with Google Drive"
        static let tokenDetail    = "Reconnect the token in Settings"
        static let errorDetail    = "Check the job with errors"
        static let lastSync       = "Last sync"
        static let noHistory      = "No history"
    }

    enum Activity {
        static let noRecent = "No recent activity"
        static let name     = "Name"
        static let job      = "Job"
        static let status   = "Status"
        static let time     = "Time"
        static let all      = "All"
        static let search   = "Search"
        static let noFiles  = "No files logged yet"
    }

    enum Ops {
        static let uploaded = "Uploaded"
        static let updated  = "Updated"
        static let deleted  = "Deleted"
        static let moved    = "Moved"
    }

    enum Settings {
        static let syncedFolders    = "Synced folders"
        static let addFolder        = "Add folder"
        static let googleAccount    = "Google Account"
        static let reconnectToken   = "Reconnect token"
        static let tokenDetail      = "If the token expired, reconnect it here"
        static let bandwidth        = "Bandwidth"
        static let throttleSchedule = "Throttle schedule"
        static let noLimit          = "no limit"
        static let localFolder      = "Local folder (source)"
        static let driveDestination = "Google Drive destination"
        static let jobName          = "Job name"
        static let namePlaceholder  = "e.g. Photos, Work, Music…"
        static let drivePlaceholder = "e.g. Photos/2026"
        static let copyMode         = "Copy mode (don't delete from Drive)"
        static let addFolderTitle   = "Add folder"
        static let lastSyncAgo      = "Last sync %@ ago"
    }
}
