import Foundation
import Combine

struct JobDefinition: Codable, Identifiable {
    var id: String
    var name: String
    var localPath: String    // puede tener ~
    var drivePath: String    // ej: gdrive:Projects
    var transfers: Int
    var copyMode: Bool
    var filterFile: String?
    var gitPullFirst: Bool?
    var excludePatterns: [String]

    init(id: String, name: String, localPath: String, drivePath: String,
         transfers: Int, copyMode: Bool, filterFile: String? = nil,
         gitPullFirst: Bool? = nil, excludePatterns: [String] = []) {
        self.id = id; self.name = name; self.localPath = localPath
        self.drivePath = drivePath; self.transfers = transfers
        self.copyMode = copyMode; self.filterFile = filterFile
        self.gitPullFirst = gitPullFirst; self.excludePatterns = excludePatterns
    }

    // Backward-compatible decoding: existing configs without excludePatterns default to []
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        localPath       = try c.decode(String.self, forKey: .localPath)
        drivePath       = try c.decode(String.self, forKey: .drivePath)
        transfers       = try c.decode(Int.self,    forKey: .transfers)
        copyMode        = try c.decode(Bool.self,   forKey: .copyMode)
        filterFile      = try c.decodeIfPresent(String.self, forKey: .filterFile)
        gitPullFirst    = try c.decodeIfPresent(Bool.self,   forKey: .gitPullFirst)
        excludePatterns = (try? c.decode([String].self, forKey: .excludePatterns)) ?? []
    }

    var localURL: URL {
        URL(fileURLWithPath: (localPath as NSString).expandingTildeInPath)
    }
    var localDisplayPath: String {
        localPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
    var driveDisplayPath: String {
        drivePath.replacingOccurrences(of: "gdrive:", with: "")
    }
}

// Common patterns users typically want to exclude from cloud sync
enum ExcludePreset: String, CaseIterable, Identifiable {
    case nodeModules   = "node_modules/"
    case git           = ".git/"
    case dsStore       = ".DS_Store"
    case pythonCache   = "__pycache__/"
    case dotEnv        = ".env*"
    case buildDist     = "{build,dist,out}/"
    case nextJs        = ".next/"
    case rustTarget    = "target/"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nodeModules:  return "node_modules"
        case .git:          return ".git"
        case .dsStore:      return ".DS_Store"
        case .pythonCache:  return "Python cache (__pycache__)"
        case .dotEnv:       return ".env files"
        case .buildDist:    return "Build output (build / dist)"
        case .nextJs:       return ".next (Next.js)"
        case .rustTarget:   return "Rust target/"
        }
    }

    var icon: String {
        switch self {
        case .nodeModules:  return "shippingbox"
        case .git:          return "chevron.left.forwardslash.chevron.right"
        case .dsStore:      return "desktopcomputer"
        case .pythonCache:  return "terminal"
        case .dotEnv:       return "lock"
        case .buildDist:    return "hammer"
        case .nextJs:       return "triangle"
        case .rustTarget:   return "gearshape"
        }
    }
}

struct SyncConfig: Codable {
    var bwlimit: String
    var jobs: [JobDefinition]
    var syncIntervalMinutes: Int  // 0 = manual only

    init(bwlimit: String, jobs: [JobDefinition], syncIntervalMinutes: Int = 0) {
        self.bwlimit = bwlimit
        self.jobs = jobs
        self.syncIntervalMinutes = syncIntervalMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bwlimit             = try c.decode(String.self, forKey: .bwlimit)
        jobs                = try c.decode([JobDefinition].self, forKey: .jobs)
        syncIntervalMinutes = (try? c.decode(Int.self, forKey: .syncIntervalMinutes)) ?? 0
    }
}

final class ConfigStore: ObservableObject {
    @Published var config: SyncConfig

    static let configURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/rclone-sync")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.configURL),
           let parsed = try? JSONDecoder().decode(SyncConfig.self, from: data) {
            config = parsed
        } else {
            config = SyncConfig(bwlimit: "09:00,1M 23:00,off", jobs: [])
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: Self.configURL)
        }
    }

    func addJob(_ job: JobDefinition) {
        config.jobs.append(job)
        save()
    }

    func removeJob(id: String) {
        config.jobs.removeAll { $0.id == id }
        save()
    }

    func updateJob(_ job: JobDefinition) {
        if let idx = config.jobs.firstIndex(where: { $0.id == job.id }) {
            config.jobs[idx] = job
            save()
        }
    }
}
