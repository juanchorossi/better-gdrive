import Foundation
import AppKit

// MARK: - Response types

struct RCSyncResponse: Decodable { let jobid: Int }
struct RCEmpty: Decodable {}
struct RCErrorResponse: Decodable { let error: String? }

struct RCJobStatus: Decodable {
    let id: Int
    let finished: Bool
    let success: Bool?
    let error: String?
}

struct RCStats: Decodable {
    let speed: Double?
    let bytes: Int64?
    let totalBytes: Int64?
    let errors: Int?
    let transfers: Int?
    let totalTransfers: Int?
    let checks: Int?
    let totalChecks: Int?
    let transferring: [RCTransferring]?

    enum CodingKeys: String, CodingKey {
        case speed, bytes, errors, transfers, checks, transferring
        case totalBytes = "totalBytes"
        case totalTransfers = "totalTransfers"
        case totalChecks = "totalChecks"
    }
}

struct RCTransferring: Decodable {
    let name: String?
    let percentage: Double?
    let speed: Double?
    let eta: Int?
    let bytes: Int64?
    let size: Int64?
}

struct RCTransferred: Decodable {
    let name: String
    let size: Int64?
    let checked: Bool?
    let error: String?
    let jobid: Int?
}

// MARK: - RC Client

enum RcloneRC {
    static let port = 5572
    static var base: URL { URL(string: "http://127.0.0.1:\(port)")! }

    // Per-launch random secret — held in memory only, never written to disk.
    // Rotated on every daemon start so cached values cannot be replayed.
    nonisolated(unsafe) private static var rcSecret: String = UUID().uuidString

    private static var basicAuthHeader: String {
        Data("bettergdrive:\(rcSecret)".utf8).base64EncodedString()
    }

    static var rclonePath: String {
        // 1. Bundled binary (production)
        if let bundled = Bundle.main.path(forResource: "rclone", ofType: nil) {
            return bundled
        }
        // 2. Homebrew fallbacks (development)
        for path in ["/opt/homebrew/bin/rclone", "/usr/local/bin/rclone"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return "rclone"
    }

    private static var daemon: Process?

    // MARK: Daemon lifecycle

    static func ensureDaemon() async {
        guard !(await ping()) else { return }

        // Kill the old daemon (hung or crashed) before starting a fresh one.
        // If we don't, the new process can't bind port 5572 and fails silently.
        if let old = daemon {
            old.terminate()
            // Wait for the process to actually exit so it releases the port.
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .utility).async { old.waitUntilExit(); c.resume() }
            }
            daemon = nil
        }

        // Rotate secret on each new daemon start.
        rcSecret = UUID().uuidString

        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/bettergdrive-rclone.log")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: rclonePath)
        p.arguments = [
            "rcd",
            "--rc-user", "bettergdrive",
            "--rc-pass", rcSecret,
            "--rc-addr", "127.0.0.1:\(port)",
            "--log-file", logURL.path,
            "--log-level", "INFO",
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        daemon = p

        // Wait until ready (max 3s)
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await ping() { return }
        }
    }

    static func stopDaemon() { daemon?.terminate(); daemon = nil }

    static func setBwlimit(_ schedule: String) async {
        _ = try? await post("core/bwlimit", body: ["rate": schedule]) as RCEmpty
    }

    static func fetchGoogleUserInfo() async throws -> GoogleUserInfo? {
        struct RemotesResp: Decodable { let remotes: [String]? }
        struct ConfigResp: Decodable { let token: String? }
        struct TokenJSON: Decodable { let access_token: String }

        let remotes = (try? await post("config/listremotes", body: [:]) as RemotesResp)?.remotes ?? ["gdrive"]
        guard let remoteName = remotes.first else { return nil }

        let config: ConfigResp = try await post("config/get", body: ["name": remoteName])
        guard let tokenJSON = config.token,
              let tokenData = tokenJSON.data(using: .utf8),
              let token = try? JSONDecoder().decode(TokenJSON.self, from: tokenData) else { return nil }

        // rclone requests scope=drive; the /oauth2/v2/userinfo endpoint needs openid/email scope.
        // Use the Drive API's about endpoint instead — it works with the drive scope.
        return await callDriveAbout(accessToken: token.access_token)
    }

    private static func callDriveAbout(accessToken: String) async -> GoogleUserInfo? {
        struct DriveAbout: Decodable {
            struct User: Decodable {
                let displayName: String?
                let emailAddress: String?
                let photoLink: String?
            }
            let user: User?
        }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=user")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let about = try? JSONDecoder().decode(DriveAbout.self, from: data),
              let user = about.user,
              let email = user.emailAddress, !email.isEmpty else { return nil }
        return GoogleUserInfo(name: user.displayName ?? email, email: email,
                              pictureURL: user.photoLink.flatMap(URL.init))
    }

    // Reads the token directly from ~/.config/rclone/rclone.conf after a reconnect,
    // bypassing the RC daemon (which may still have a stale token in memory).
    static func fetchGoogleUserInfoFromConfigFile() async -> GoogleUserInfo? {
        let configURL: URL
        if let env = ProcessInfo.processInfo.environment["RCLONE_CONFIG"] {
            configURL = URL(fileURLWithPath: env)
        } else {
            configURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/rclone/rclone.conf")
        }
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }

        // Parse INI-style file: track sections, find first type=drive section, grab token.
        var inSection = false
        var isGDrive = false
        var tokenJSON: String?

        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") && t.hasSuffix("]") {
                if inSection && isGDrive && tokenJSON != nil { break }
                inSection = true; isGDrive = false; tokenJSON = nil
            } else if inSection {
                if let eq = t.firstIndex(of: "=") {
                    let key = t[..<eq].trimmingCharacters(in: .whitespaces)
                    let val = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    if key == "type"  { isGDrive = (val == "drive") }
                    if key == "token" { tokenJSON = val }
                }
            }
        }

        guard isGDrive, let json = tokenJSON,
              let data = json.data(using: .utf8) else { return nil }

        struct TokenJSON: Decodable { let access_token: String }

        guard let token = try? JSONDecoder().decode(TokenJSON.self, from: data) else { return nil }
        return await callDriveAbout(accessToken: token.access_token)
    }

    static func ping() async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("rc/noop"), timeoutInterval: 1)
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        req.setValue("Basic \(basicAuthHeader)", forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: Sync control

    static func startSync(job: JobDefinition) async throws -> Int {
        if job.direction != .download && job.gitPullFirst == true { await gitPull(path: job.localPath) }

        let localExpanded = job.localPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let src = job.direction == .download ? job.drivePath : localExpanded
        let dst = job.direction == .download ? localExpanded  : job.drivePath

        // Download jobs never delete local files regardless of copyMode setting.
        let endpoint = (job.copyMode || job.direction == .download) ? "sync/copy" : "sync/sync"

        // Reject on-the-fly backend connection strings (start with ":" or contain inline
        // key=value syntax). Only named remotes in the form "remotename:path" are accepted.
        guard !job.drivePath.hasPrefix(":"),
              !job.drivePath.contains(","),
              job.drivePath.contains(":") else {
            throw CocoaError(.fileWriteUnknown)
        }

        var body: [String: Any] = [
            "srcFs": src,
            "dstFs": dst,
            "_async": true,
            "createEmptySrcDirs": true,
            "_config": ["Transfers": job.transfers] as [String: Any]
        ]

        var filterParams: [String: Any] = [:]
        if let ff = job.filterFile {
            let p = ff.replacingOccurrences(of: "~", with: NSHomeDirectory())
            filterParams["FilterFrom"] = [p]
        }
        if !job.excludePatterns.isEmpty {
            filterParams["Exclude"] = job.excludePatterns
        }
        if !filterParams.isEmpty {
            body["_filter"] = filterParams
        }

        let resp: RCSyncResponse = try await post(endpoint, body: body)
        return resp.jobid
    }

    // Dry-runs a sync-mode upload job and returns the paths that would be deleted from Drive.
    // Returns [] on any error so callers can fail open.
    static func dryRunDeletions(job: JobDefinition) async -> [String] {
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/bettergdrive-rclone.log")

        let startOffset: UInt64
        if let fh = try? FileHandle(forReadingFrom: logURL) {
            startOffset = fh.seekToEndOfFile()
            fh.closeFile()
        } else {
            startOffset = 0
        }

        let localExpanded = job.localPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        var body: [String: Any] = [
            "srcFs": localExpanded,
            "dstFs": job.drivePath,
            "_async": true,
            "_config": ["DryRun": true, "Transfers": job.transfers] as [String: Any]
        ]

        var filterParams: [String: Any] = [:]
        if let ff = job.filterFile {
            filterParams["FilterFrom"] = [ff.replacingOccurrences(of: "~", with: NSHomeDirectory())]
        }
        if !job.excludePatterns.isEmpty { filterParams["Exclude"] = job.excludePatterns }
        if !filterParams.isEmpty { body["_filter"] = filterParams }

        guard let resp = try? await post("sync/sync", body: body) as RCSyncResponse else { return [] }

        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let status = try? await jobStatus(resp.jobid) else { break }
            if status.finished { break }
        }
        await stopJob(resp.jobid)

        guard let fh = try? FileHandle(forReadingFrom: logURL) else { return [] }
        fh.seek(toFileOffset: startOffset)
        let data = fh.readDataToEndOfFile()
        fh.closeFile()

        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").compactMap { line -> String? in
            guard line.contains(": Would delete"),
                  let range = line.range(of: "INFO  : ") else { return nil }
            let after = String(line[range.upperBound...])
            guard let end = after.range(of: ": Would delete") else { return nil }
            return String(after[..<end.lowerBound])
        }
    }

    static func stopJob(_ id: Int) async {
        _ = try? await post("job/stop", body: ["jobid": id]) as RCEmpty
    }

    static func jobStatus(_ id: Int) async throws -> RCJobStatus {
        try await post("job/status", body: ["jobid": id])
    }

    static func stats(group: String) async throws -> RCStats {
        try await post("core/stats", body: ["group": group])
    }

    static func transferred(group: String) async throws -> [RCTransferred] {
        struct Resp: Decodable { let transferred: [RCTransferred]? }
        let r: Resp = try await post("core/transferred", body: ["group": group])
        return r.transferred ?? []
    }

    // MARK: - Drive folder browser

    struct DriveItem: Decodable, Identifiable {
        let name: String
        let path: String
        let isDir: Bool

        var id: String { path }

        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case path = "Path"
            case isDir = "IsDir"
        }
    }

    static func listDriveFolders(remote: String) async throws -> [DriveItem] {
        struct Resp: Decodable { let list: [DriveItem] }
        let r: Resp = try await post("operations/list", body: [
            "fs": "gdrive:",
            "remote": remote,
            "opt": ["noModTime": true, "noMimeType": true] as [String: Any]
        ])
        return r.list.filter { $0.isDir }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Private helpers

    @discardableResult
    private static func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Basic \(basicAuthHeader)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode(RCErrorResponse.self, from: data))?.error
                      ?? "RC error \(http.statusCode)"
            throw NSError(domain: "RcloneRC", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // Starts the OAuth reconnect flow. Returns once rclone has printed the auth URL
    // and the browser is open. Call waitForReconnectComplete() to wait for auth to finish.
    static func reconnectGDrive() async throws {
        // Terminate the previous process and WAIT for it to actually release port 53682
        // before starting a new one — otherwise the new process fails to bind that port.
        if let prev = reconnectProcess {
            prev.terminate()
            reconnectInPipe?.fileHandleForWriting.closeFile()
            reconnectPipe?.fileHandleForReading.readabilityHandler = nil  // release GCD source
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .utility).async { prev.waitUntilExit(); c.resume() }
            }
            reconnectProcess = nil
            reconnectPipe    = nil
            reconnectInPipe  = nil
        }
        reconnectProcess = nil
        reconnectPipe    = nil
        reconnectInPipe  = nil

        let p = Process()
        p.executableURL = URL(fileURLWithPath: rclonePath)
        p.arguments = ["config", "reconnect", "gdrive:"]
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
             "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"],
            uniquingKeysWith: { _, new in new }
        )

        let outPipe = Pipe()
        let inPipe  = Pipe()
        p.standardOutput = outPipe
        p.standardError  = outPipe   // merge both so we catch the URL on either
        p.standardInput  = inPipe

        try p.run()
        reconnectProcess = p
        reconnectPipe    = outPipe
        reconnectInPipe  = inPipe

        // Answer both interactive prompts then close stdin (mirrors printf "y\ny\n" | rclone).
        // rclone reads them, starts the OAuth HTTP server on :53682, then exits cleanly once
        // the callback arrives. Closing stdin is required — an open pipe would block rclone
        // after OAuth completes (waiting for input that never arrives).
        try? inPipe.fileHandleForWriting.write(contentsOf: Data("y\ny\n".utf8))
        try? inPipe.fileHandleForWriting.closeFile()

        // Wait until rclone prints the auth URL, then open it in the browser.
        // We open it ourselves (NSWorkspace) rather than relying on rclone's `open`
        // call, which can silently fail when rclone is a child of a GUI process.
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let state = OAuthURLDetector(continuation: c)
            outPipe.fileHandleForReading.readabilityHandler = state.makeHandler()
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                reconnectProcess?.terminate()
                state.fail(CocoaError(.fileReadUnknown))
            }
        }
    }

    nonisolated(unsafe) private static var reconnectProcess: Process?
    nonisolated(unsafe) private static var reconnectPipe: Pipe?
    nonisolated(unsafe) private static var reconnectInPipe: Pipe?

    // Waits until the reconnect rclone process exits (i.e. OAuth completed or timed out).
    // Uses waitUntilExit() on a background thread to avoid the race between
    // setting terminationHandler and rclone exiting before we can set it.
    static func waitForReconnectComplete() async {
        guard let p = reconnectProcess else {
            reconnectProcess = nil; reconnectPipe = nil; reconnectInPipe = nil; return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async { p.waitUntilExit(); c.resume() }
        }
        reconnectPipe?.fileHandleForReading.readabilityHandler = nil
        reconnectProcess = nil
        reconnectPipe    = nil
        reconnectInPipe  = nil
    }


    // Writes a bare [gdrive] section to rclone.conf with the supplied OAuth credentials.
    // Call this before reconnectGDrive() so rclone has a remote to reconnect.
    static func createGDriveConfig(clientId: String, clientSecret: String) throws {
        let configURL: URL
        if let env = ProcessInfo.processInfo.environment["RCLONE_CONFIG"] {
            configURL = URL(fileURLWithPath: env)
        } else {
            configURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/rclone/rclone.conf")
        }

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        var content = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""

        // Remove any existing [gdrive] section.
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var skip = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "[gdrive]" { skip = true; continue }
            if t.hasPrefix("[") && t.hasSuffix("]") { skip = false }
            if !skip { result.append(line) }
        }
        content = result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let section = """


        [gdrive]
        type = drive
        client_id = \(clientId)
        client_secret = \(clientSecret)
        """
        content += section + "\n"
        try content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func gitPull(path: String) async {
        let resolved = path.replacingOccurrences(of: "~", with: NSHomeDirectory())
        // Verify the path stays within the user's home directory before passing it to git.
        let home = NSHomeDirectory()
        guard resolved.hasPrefix(home + "/") || resolved == home else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", resolved, "pull", "--rebase", "--autostash", "--no-verify",
                       "-c", "core.hooksPath=/dev/null"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        await withCheckedContinuation { c in p.terminationHandler = { _ in c.resume() } }
    }
}

private final class OAuthURLDetector: @unchecked Sendable {
    private let continuation: CheckedContinuation<Void, Error>
    private let lock = NSLock()
    private var accumulated = ""
    private var settled = false

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func makeHandler() -> (FileHandle) -> Void {
        { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self.receive(text: text, handle: handle)
        }
    }

    private func receive(text: String, handle: FileHandle) {
        var urlToOpen: URL?
        lock.lock()
        if !settled {
            accumulated += text
            // Look for /auth specifically — rclone also prints the bare host in a
            // "Make sure your Redirect URL is set to http://127.0.0.1:53682/" notice
            // that appears before the real auth link, which would trigger a false match.
            if let range = accumulated.range(of: "http://127.0.0.1:53682/auth") {
                let tail = accumulated[range.lowerBound...]
                let raw = tail.components(separatedBy: .whitespacesAndNewlines).first ?? ""
                let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let url = URL(string: cleaned) {
                    settled = true
                    // Drain properly so rclone is never blocked writing to the pipe
                    handle.readabilityHandler = { h in _ = h.availableData }
                    urlToOpen = url
                }
            }
        }
        lock.unlock()
        if let url = urlToOpen {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            continuation.resume()
        }
    }

    func fail(_ error: Error) {
        lock.lock()
        let shouldFail = !settled
        if shouldFail { settled = true }
        lock.unlock()
        if shouldFail { continuation.resume(throwing: error) }
    }
}
