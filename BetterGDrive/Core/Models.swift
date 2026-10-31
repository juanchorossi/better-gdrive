import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension Bundle {
    /// Marketing version from Info.plist (e.g. "1.2.4").
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

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
    var failingSince: Date?        // first failure of the current error streak (persisted)
    var lastErrorDetail: String?   // rclone's last per-file error, shown as tooltip

    // "12 days" / "3h" — nil while the streak is shorter than an hour.
    var failingForDisplay: String? {
        guard let since = failingSince else { return nil }
        let diff = -since.timeIntervalSinceNow
        if diff < 3600  { return nil }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        let days = Int(diff / 86400)
        return days == 1 ? "1 day" : "\(days) days"
    }

    // Subtitle for a job in .error: message plus streak length when it's been a while.
    var errorSubtitle: String {
        let msg = errorMessage ?? "Sync failed"
        guard let dur = failingForDisplay else { return msg }
        return "\(msg) · failing for \(dur)"
    }

    // Tooltip text for an error row: last failed path + reason, if rclone gave one.
    var errorTooltip: String? {
        guard status == .error else { return nil }
        var parts: [String] = []
        if errors > 0 { parts.append(errors == 1 ? "1 file failed" : "\(errors) files failed") }
        if let d = lastErrorDetail, !d.isEmpty { parts.append(d) }
        guard !parts.isEmpty else { return nil }
        parts.append("Details in Activity")
        return parts.joined(separator: "\n")
    }

    var lastSyncDisplay: String? {
        guard let date = lastSync else { return nil }
        let diff = -date.timeIntervalSinceNow
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        let days = Int(diff / 86400)
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    var relativeTime: String? {
        guard let date = lastSync else { return nil }
        let diff = -date.timeIntervalSinceNow
        if diff < 60    { return L.General.now }
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
    var detail: String?      // short reason for .failed items
    var resolvedAt: Date?    // set when a later clean run of the job reconciled this failure

    init(timestamp: Date, jobName: String, filePath: String, operation: ActivityOp,
         drivePath: String? = nil, detail: String? = nil, resolvedAt: Date? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.jobName = jobName
        self.filePath = filePath
        self.operation = operation
        self.drivePath = drivePath
        self.detail = detail
        self.resolvedAt = resolvedAt
    }

    var isResolved: Bool { operation == .failed && resolvedAt != nil }

    /// Status column text: the operation, or "Failed · resolved" once a later run fixed it.
    var statusLabel: String {
        isResolved ? "\(L.Ops.failed) · \(L.Ops.resolved)" : operation.description
    }

    /// Status column color: resolved failures are dimmed so live ones stand out.
    var statusColor: Color { isResolved ? operation.color.opacity(0.45) : operation.color }

    var fileName: String { URL(fileURLWithPath: filePath).lastPathComponent }

    /// Row title: failures show the full path (the folder is the point), others the file name.
    var displayName: String { operation == .failed ? filePath : fileName }

    /// Tooltip for failed rows: path, reason, and when a later run synced it OK.
    var failureTooltip: String? {
        guard operation == .failed else { return nil }
        let resolved = resolvedAt.map { "\(L.Ops.syncedOKAt) \(Self.timestampFormatter.string(from: $0))" }
        return [filePath, detail, resolved].compactMap { $0 }.joined(separator: "\n")
    }

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
    case uploaded, updated, deleted, moved, downloaded, failed

    var description: String {
        switch self {
        case .uploaded:   return L.Ops.uploaded
        case .updated:    return L.Ops.updated
        case .deleted:    return L.Ops.deleted
        case .moved:      return L.Ops.moved
        case .downloaded: return L.Ops.downloaded
        case .failed:     return L.Ops.failed
        }
    }

    var icon: String {
        switch self {
        case .uploaded:   return "arrow.up.circle"
        case .updated:    return "arrow.triangle.2.circlepath"
        case .deleted:    return "trash"
        case .moved:      return "arrow.right.circle"
        case .downloaded: return "arrow.down.circle"
        case .failed:     return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .uploaded:   return .blue
        case .updated:    return .green
        case .deleted:    return .red
        case .moved:      return .orange
        case .downloaded: return .purple
        case .failed:     return .red
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
