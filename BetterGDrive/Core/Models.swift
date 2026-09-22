import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SyncDirection: String, Codable {
    case upload   // local → Drive (default)
    case download // Drive → local
}

struct SyncJob: Identifiable {
    let id: String
    let name: String
    var status: JobStatus
    var lastSync: Date?
    var errors: Int
    var isRunning: Bool
    var progress: Double?   // 0.0–1.0, nil when indeterminate
    var currentFile: String?
    var speed: String?
    var eta: String?
    var transferred: String?
    var filesInfo: String?  // e.g. "3 / 10 files"
    var isFinishing: Bool = false  // bytes done but rclone still verifying
    var syncStarted: Date?  // set when isRunning becomes true
    var errorMessage: String?  // last rclone error, shown in subtitle
    var hasLocalChanges: Bool = false  // true during FSEvents debounce window
    var direction: SyncDirection = .upload

    // Returns a display string that already includes the right suffix.
    var lastSyncDisplay: String? {
        guard let date = lastSync else { return nil }
        let diff = -date.timeIntervalSinceNow
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // Legacy: used by menuBarSuffix (short form without "ago")
    var relativeTime: String? {
        guard let date = lastSync else { return nil }
        let diff = -date.timeIntervalSinceNow
        if diff < 60    { return "now" }
        if diff < 3600  { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        return "\(Int(diff / 86400))d"
    }
}

struct ActivityItem: Identifiable, Codable {
    let id: UUID
    var timestamp: Date
    var jobName: String
    var filePath: String
    var operation: ActivityOp

    var drivePath: String?

    init(timestamp: Date, jobName: String, filePath: String, operation: ActivityOp, drivePath: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.jobName = jobName
        self.filePath = filePath
        self.operation = operation
        self.drivePath = drivePath
    }

    var fileName: String { URL(fileURLWithPath: filePath).lastPathComponent }

    var parentFolder: String? {
        let url = URL(fileURLWithPath: filePath)
        let parent = url.deletingLastPathComponent().path
        guard parent != ".", parent != "/" , !parent.isEmpty else { return nil }
        return parent
    }

    var fileIcon: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":                          return "doc.richtext"
        case "png","jpg","jpeg","heic","gif": return "photo"
        case "mp3","m4a","flac","wav","aiff": return "music.note"
        case "mp4","mov","avi","mkv":        return "film"
        case "zip","tar","gz","rar":         return "archivebox"
        case "swift","py","js","ts","sh","rb","go","rs": return "chevron.left.forwardslash.chevron.right"
        default:                             return "doc"
        }
    }

    var relativeTime: String {
        let diff = -timestamp.timeIntervalSinceNow
        if diff < 60    { return L.General.now }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }

    var exactTime: String { Self.timestampFormatter.string(from: timestamp) }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()
}

enum ActivityOp: String, Codable, CustomStringConvertible {
    case uploaded, updated, deleted, moved, downloaded

    var description: String {
        switch self {
        case .uploaded:   return L.Ops.uploaded
        case .updated:    return L.Ops.updated
        case .deleted:    return L.Ops.deleted
        case .moved:      return L.Ops.moved
        case .downloaded: return L.Ops.downloaded
        }
    }

    var icon: String {
        switch self {
        case .uploaded:   return "arrow.up.circle"
        case .updated:    return "arrow.triangle.2.circlepath"
        case .deleted:    return "trash"
        case .moved:      return "arrow.right.circle"
        case .downloaded: return "arrow.down.circle"
        }
    }

    var color: Color {
        switch self {
        case .uploaded:   return .blue
        case .updated:    return .green
        case .deleted:    return .red
        case .moved:      return .orange
        case .downloaded: return .purple
        }
    }
}

enum JobStatus {
    case ok, error, tokenError, running, paused, unknown

    var sfSymbol: String {
        switch self {
        case .ok:         return "checkmark.icloud"
        case .error:      return "exclamationmark.triangle"
        case .tokenError: return "exclamationmark.shield"
        case .running:    return "arrow.triangle.2.circlepath"
        case .paused:     return "pause.circle"
        case .unknown:    return "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .ok:         return .green
        case .error:      return .orange
        case .tokenError: return .red
        case .running:    return .blue
        case .paused:     return .blue
        case .unknown:    return .secondary
        }
    }
}
