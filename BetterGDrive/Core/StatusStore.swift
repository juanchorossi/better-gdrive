import Foundation
import Combine
import ServiceManagement
import SwiftUI

struct GoogleUserInfo {
    let name: String
    let email: String
    let pictureURL: URL?
}

final class StatusStore: ObservableObject {
    @Published var jobs: [SyncJob] = []
    @Published var activity: [ActivityItem] = []
    @Published var selectedJobId: String?
    @Published var daemonReady = false
    @Published var googleAccount: GoogleUserInfo?
    @Published var isLoadingAccount = true
    @Published var needsSetup: Bool

    let configStore = ConfigStore()
    var jobDefinitions: [JobDefinition] { configStore.config.jobs }

    private static let activityURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/rclone-sync")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("activity.json")
    }()

    // configJobId → rclone RC jobId
    private var runningJobs: [String: Int] = [:]
    private var isPolling = false
    private var timerCancellable: AnyCancellable?
    private var autoSyncCancellable: AnyCancellable?
    private var configCancellable: AnyCancellable?
    private var cachedLaunchAtLogin: Bool?
    // Tracks "configId:filePath" to avoid duplicate activity entries during live polling
    private var seenTransferKeys: Set<String> = []

    // File watchers: one per job, started after daemon is ready
    private var fileWatchers: [String: LocalFileWatcher] = [:]
    // Debounce tasks: cancelled and recreated on each FSEvent
    private var debounceTask: [String: Task<Void, Never>] = [:]
    // Jobs that need a sync triggered once their current run finishes
    private var pendingSyncAfterRun: Set<String> = []

    private static let watcherDebounceNs: UInt64 = 15_000_000_000  // 15 seconds

    // MARK: - Computed

    var allOk: Bool            { jobs.allSatisfy { $0.status == .ok && !$0.isRunning } }
    var isAnySyncRunning: Bool { jobs.contains(where: { $0.isRunning }) }
    var hasError: Bool         { jobs.contains(where: { $0.status == .error }) }
    var hasTokenError: Bool    { jobs.contains(where: { $0.status == .tokenError }) }
    var hasAnyPaused: Bool     { jobs.contains(where: { $0.status == .paused }) }

    var headerTitle: String {
        if jobs.isEmpty      { return L.General.appName }
        if isAnySyncRunning  { return L.Status.syncing }
        if hasTokenError     { return L.Status.tokenExpired }
        if hasError          { return L.Status.syncError }
        if hasAnyPaused      { return "Paused" }
        if let oldest = jobs.compactMap(\.lastSync).min() {
            let diff = -oldest.timeIntervalSinceNow
            if diff < 60    { return "Synced just now" }
            if diff < 3600  { return "Synced \(Int(diff/60))m ago" }
            if diff < 86400 { return "Synced \(Int(diff/3600))h ago" }
            return "Synced \(Int(diff/86400))d ago"
        }
        return L.Status.upToDate
    }

    var headerColor: Color {
        if jobs.isEmpty      { return .secondary }
        if isAnySyncRunning  { return .blue }
        if hasTokenError     { return .red }
        if hasError          { return .orange }
        if hasAnyPaused      { return .blue }
        return .green
    }

    var menuBarIcon: String {
        if !daemonReady                                              { return "exclamationmark.circle" }
        if jobs.contains(where: { $0.isRunning })                   { return "arrow.triangle.2.circlepath" }
        if jobs.contains(where: { $0.status == .tokenError })       { return "exclamationmark.triangle.fill" }
        if jobs.contains(where: { $0.status == .error })            { return "exclamationmark.triangle" }
        if jobs.contains(where: { $0.status == .paused })           { return "pause.circle" }
        return "cloud"
    }

    var currentThrottleRate: String? {
        let raw = configStore.config.bwlimit.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        let parts = raw.split(separator: " ").map(String.init)

        if parts.count == 1 {
            return parseBwRate(parts[0])
        }

        // Schedule format: "HH:MM,rate HH:MM,rate ..."
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        var periods: [(minutes: Int, rate: String?)] = []
        for part in parts {
            let comps = part.split(separator: ",")
            guard comps.count == 2 else { continue }
            let timeParts = comps[0].split(separator: ":")
            guard timeParts.count == 2,
                  let h = Int(timeParts[0]), let m = Int(timeParts[1]) else { continue }
            periods.append((h * 60 + m, parseBwRate(String(comps[1]))))
        }
        periods.sort { $0.minutes < $1.minutes }

        // Find the last period whose start time <= now; wrap around midnight to last period
        var active = periods.last
        for p in periods.reversed() {
            if p.minutes <= nowMinutes { active = p; break }
        }
        return active?.rate
    }

    private func parseBwRate(_ s: String) -> String? {
        let lower = s.lowercased()
        if lower == "off" || lower == "0" || lower.isEmpty { return nil }
        if lower.hasSuffix("m"), let mb = Double(s.dropLast()), mb > 0 {
            return mb.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(mb)) MB/s" : "\(mb) MB/s"
        }
        // KB values: display as MB rounded to nearest integer (same as BandwidthEditor UI)
        if lower.hasSuffix("k"), let kb = Double(s.dropLast()), kb > 0 {
            let mb = kb / 1024
            return mb.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(mb)) MB/s" : String(format: "%.1f MB/s", mb)
        }
        return nil
    }

    var menuBarSuffix: String {
        if let running = jobs.first(where: { $0.isRunning }) {
            if let p = running.progress, p > 0 { return "\(Int(p * 100))%" }
            return ""
        }
        guard let oldest = jobs.compactMap(\.lastSync).min() else { return "" }
        let diff = -oldest.timeIntervalSinceNow
        if diff < 60    { return L.General.now }
        if diff < 3600  { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        return "\(Int(diff / 86400))d"
    }

    // MARK: - Init

    private func loadActivity() -> [ActivityItem] {
        guard let data = try? Data(contentsOf: Self.activityURL),
              let items = try? JSONDecoder().decode([ActivityItem].self, from: data) else { return [] }
        return items
    }

    private func saveActivity() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Array(activity.prefix(500))) {
            try? data.write(to: Self.activityURL)
        }
    }

    static func isGDriveConfigured() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/rclone/rclone.conf")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        var inGDrive = false
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "[gdrive]"          { inGDrive = true;  continue }
            if t.hasPrefix("[")         { inGDrive = false; continue }
            if inGDrive && t.hasPrefix("token") { return true }
        }
        return false
    }

    @MainActor
    func refreshAfterSetup() async {
        needsSetup = false
        await RcloneRC.ensureDaemon()
        await MainActor.run { daemonReady = true }
        let info = try? await RcloneRC.fetchGoogleUserInfo()
        await MainActor.run { googleAccount = info; isLoadingAccount = false }
    }

    init() {
        needsSetup = !StatusStore.isGDriveConfigured()
        activity = []
        jobs = buildJobs()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.activityURL),
           let items = try? decoder.decode([ActivityItem].self, from: data) {
            activity = items
        }

        Task {
            await RcloneRC.ensureDaemon()
            let savedBwlimit = configStore.config.bwlimit
            await RcloneRC.setBwlimit(savedBwlimit)
            await MainActor.run { daemonReady = true; self.startWatchers() }
            let info = try? await RcloneRC.fetchGoogleUserInfo()
            await MainActor.run { googleAccount = info; isLoadingAccount = false }
        }

        timerCancellable = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isPolling else { return }
                Task { await self.poll() }
            }

        // Auto-sync: check every 60s whether any job is overdue.
        autoSyncCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.triggerAutoSyncIfDue() } }

        // objectWillChange fires BEFORE the new value is set, so defer one cycle
        configCancellable = configStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.syncJobsFromConfig() } }

        // Trigger auto-sync check on launch (after daemon is ready)
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                self.triggerAutoSyncIfDue()
                self.retryErrorJobs()
            }
        }
    }

    // MARK: - Public actions

    func refresh() { Task { await poll() } }

    @MainActor
    private func retryErrorJobs() {
        guard !needsSetup else { return }
        for def in jobDefinitions {
            guard let job = jobs.first(where: { $0.id == def.id }),
                  job.status == .error, !job.isRunning else { continue }
            Task { await startJob(def) }
        }
    }

    @MainActor
    private func triggerAutoSyncIfDue() {
        guard !needsSetup else { return }
        let interval = configStore.config.syncIntervalMinutes
        let threshold = interval > 0 ? TimeInterval(interval * 60) : nil
        let defs = jobDefinitions
        for def in defs {
            guard !jobs.contains(where: { $0.id == def.id && $0.isRunning }),
                  !jobs.contains(where: { $0.id == def.id && $0.status == .paused }) else { continue }
            let lastSync = UserDefaults.standard.object(forKey: "lastSync.\(def.id)") as? Date
            // Always start a job that has never synced; otherwise only if interval is set and overdue
            let overdue: Bool
            if let lastSync, let threshold {
                overdue = -lastSync.timeIntervalSinceNow > threshold
            } else {
                overdue = lastSync == nil  // never synced → always start
            }
            if overdue { Task { await startJob(def) } }
        }
    }

    @MainActor
    func resetTokenErrorJobs() {
        for i in jobs.indices where jobs[i].status == .tokenError || jobs[i].status == .error {
            jobs[i].status       = .unknown
            jobs[i].errorMessage = nil
            UserDefaults.standard.removeObject(forKey: "status.\(jobs[i].id)")
            UserDefaults.standard.removeObject(forKey: "errorMessage.\(jobs[i].id)")
        }
        // Kick off jobs that were blocked by the token error
        let defs = jobDefinitions.filter { def in
            jobs.contains(where: { $0.id == def.id && !$0.isRunning })
        }
        for def in defs { Task { await startJob(def) } }
    }

    func run(_ job: SyncJob) {
        guard let def = jobDefinitions.first(where: { $0.id == job.id }) else { return }
        Task { await startJob(def) }
    }

    func runDefinition(_ def: JobDefinition) {
        // Ensure the job exists in jobs[] — config may not have propagated yet
        if !jobs.contains(where: { $0.id == def.id }) {
            let lastSync = UserDefaults.standard.object(forKey: "lastSync.\(def.id)") as? Date
            let ok = UserDefaults.standard.string(forKey: "status.\(def.id)") == "ok"
            jobs.append(SyncJob(id: def.id, name: def.name,
                                status: lastSync != nil ? (ok ? .ok : .error) : .unknown,
                                lastSync: lastSync, errors: 0, isRunning: false))
        }
        Task { await startJob(def) }
    }

    func runAll() {
        for def in jobDefinitions { Task { await startJob(def) } }
    }

    func pause(_ job: SyncJob) {
        guard let rcId = runningJobs[job.id] else { return }
        let configId = job.id
        Task {
            await RcloneRC.stopJob(rcId)
            await MainActor.run {
                self.runningJobs.removeValue(forKey: configId)
                if let i = self.jobs.firstIndex(where: { $0.id == configId }) {
                    self.jobs[i].isRunning = false
                    self.jobs[i].status    = .paused
                    self.jobs[i].progress  = nil
                    self.jobs[i].speed     = nil
                    self.jobs[i].eta       = nil
                    self.jobs[i].filesInfo = nil
                }
                UserDefaults.standard.set("paused", forKey: "status.\(configId)")
            }
        }
    }

    func stop(_ job: SyncJob) {
        guard let rcId = runningJobs[job.id] else { return }
        let configId = job.id
        Task {
            await RcloneRC.stopJob(rcId)
            await MainActor.run {
                self.runningJobs.removeValue(forKey: configId)
                if let i = self.jobs.firstIndex(where: { $0.id == configId }) {
                    self.jobs[i].isRunning = false
                    self.jobs[i].status    = .ok
                }
                UserDefaults.standard.set("ok", forKey: "status.\(configId)")
            }
        }
    }

    func stopAll() {
        for job in jobs where job.isRunning { stop(job) }
    }

    func parseJobActivity(_ jobId: String) -> [ActivityItem] {
        let name = jobDefinitions.first(where: { $0.id == jobId })?.name ?? jobId
        return activity.filter { $0.jobName == name }
    }

    // MARK: - Launch at Login

    var launchAtLoginEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else        { try SMAppService.mainApp.unregister() }
            } catch {
                print("LaunchAtLogin error: \(error)")
            }
        }
    }

    // MARK: - Private

    private func buildJobs() -> [SyncJob] {
        jobDefinitions.map { def in
            let lastSync   = UserDefaults.standard.object(forKey: "lastSync.\(def.id)") as? Date
            let savedState = UserDefaults.standard.string(forKey: "status.\(def.id)")
            let status: JobStatus
            if savedState == "paused"      { status = .paused }
            else if lastSync == nil        { status = .unknown }
            else if savedState == "ok"     { status = .ok }
            else                           { status = .error }
            var job = SyncJob(id: def.id, name: def.name, status: status,
                              lastSync: lastSync, errors: 0, isRunning: false)
            if status == .error {
                job.errorMessage = UserDefaults.standard.string(forKey: "errorMessage.\(def.id)")
            }
            return job
        }
    }

    private func syncJobsFromConfig() {
        let defs = jobDefinitions
        // Add new jobs, remove deleted ones, preserve running state
        jobs = defs.map { def in
            if let existing = jobs.first(where: { $0.id == def.id }) {
                return existing
            }
            let lastSync = UserDefaults.standard.object(forKey: "lastSync.\(def.id)") as? Date
            let ok       = UserDefaults.standard.string(forKey: "status.\(def.id)") == "ok"
            let status: JobStatus = lastSync != nil ? (ok ? .ok : .error) : .unknown
            var job = SyncJob(id: def.id, name: def.name,
                              status: status, lastSync: lastSync, errors: 0, isRunning: false)
            if status == .error {
                job.errorMessage = UserDefaults.standard.string(forKey: "errorMessage.\(def.id)")
            }
            return job
        }
        Task { @MainActor [weak self] in self?.startWatchers() }
    }

    // MARK: - File watchers

    @MainActor
    private func startWatchers() {
        let currentIds = Set(jobDefinitions.map(\.id))
        // Stop watchers for removed jobs
        for id in fileWatchers.keys where !currentIds.contains(id) {
            fileWatchers[id]?.stop()
            fileWatchers.removeValue(forKey: id)
            debounceTask[id]?.cancel()
            debounceTask.removeValue(forKey: id)
            pendingSyncAfterRun.remove(id)
        }
        // Start watchers for new jobs
        for def in jobDefinitions where fileWatchers[def.id] == nil {
            let path = (def.localPath as NSString).expandingTildeInPath
            let jobId = def.id
            let watcher = LocalFileWatcher(path: path) { [weak self] in
                Task { @MainActor [weak self] in self?.handleLocalChange(jobId: jobId) }
            }
            watcher.start()
            fileWatchers[def.id] = watcher
        }
    }

    @MainActor
    private func handleLocalChange(jobId: String) {
        debounceTask[jobId]?.cancel()
        if let i = jobs.firstIndex(where: { $0.id == jobId }) {
            jobs[i].hasLocalChanges = true
        }
        debounceTask[jobId] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.watcherDebounceNs)
            guard !Task.isCancelled else { return }
            self?.firePendingSync(jobId: jobId)
        }
    }

    @MainActor
    private func firePendingSync(jobId: String) {
        debounceTask.removeValue(forKey: jobId)
        guard let i = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[i].hasLocalChanges = false
        let job = jobs[i]
        // Don't auto-sync if paused or blocked on an auth/sync error
        guard job.status != .paused, job.status != .tokenError, job.status != .error else { return }
        if job.isRunning {
            pendingSyncAfterRun.insert(jobId)
        } else {
            guard let def = jobDefinitions.first(where: { $0.id == jobId }) else { return }
            Task { await startJob(def) }
        }
    }

    private func startJob(_ def: JobDefinition) async {
        await MainActor.run {
            if let i = jobs.firstIndex(where: { $0.id == def.id }) {
                jobs[i].isRunning = true
                jobs[i].status = .running
                jobs[i].syncStarted = Date()
            }
        }

        do {
            let rcId = try await RcloneRC.startSync(job: def)
            await MainActor.run { runningJobs[def.id] = rcId }
        } catch {
            let msg = friendlyError(error.localizedDescription)
            await MainActor.run {
                if let i = jobs.firstIndex(where: { $0.id == def.id }) {
                    jobs[i].isRunning = false
                    jobs[i].status = .error
                    jobs[i].errorMessage = msg
                }
                UserDefaults.standard.set("error", forKey: "status.\(def.id)")
                UserDefaults.standard.set(msg, forKey: "errorMessage.\(def.id)")
            }
        }
    }

    private func poll() async {
        await MainActor.run { isPolling = true }
        defer { Task { @MainActor in self.isPolling = false } }

        // Always verify daemon is alive; restart if it crashed
        if !(await RcloneRC.ping()) {
            await RcloneRC.ensureDaemon()
            let alive = await RcloneRC.ping()
            await MainActor.run {
                self.daemonReady = alive
                // New daemon has no knowledge of prior job IDs — clear them
                // so jobs don't stay stuck in isRunning=true indefinitely.
                self.abandonRunningJobs()
            }
            return
        }

        let snapshot = await MainActor.run { runningJobs }
        guard !snapshot.isEmpty else { return }

        let defs = await MainActor.run { jobDefinitions }

        for (configId, rcId) in snapshot {
            let group = "job/\(rcId)"
            let jobName = defs.first(where: { $0.id == configId })?.name ?? configId

            if let stats = try? await RcloneRC.stats(group: group) {
                await MainActor.run { self.applyStats(stats, configId: configId) }
            }

            // Live activity: add newly transferred files without waiting for job to finish
            let xfers = (try? await RcloneRC.transferred(group: group)) ?? []
            if !xfers.isEmpty {
                await MainActor.run { self.addLiveActivity(xfers, configId: configId, jobName: jobName) }
            }

            do {
                let status = try await RcloneRC.jobStatus(rcId)
                if status.finished {
                    await MainActor.run { self.finishJob(configId: configId, rcId: rcId, status: status, transferred: xfers, jobName: jobName) }
                }
            } catch {
                // Job not found on daemon — daemon likely restarted; abandon the job.
                await MainActor.run { self.abandonRunningJobs() }
                break
            }
        }
    }

    @MainActor
    private func applyStats(_ stats: RCStats, configId: String) {
        guard let i = jobs.firstIndex(where: { $0.id == configId }) else { return }
        let total = stats.totalBytes ?? 0
        let done  = stats.bytes ?? 0
        let rawPct = total > 0 ? Double(done) / Double(total) : nil
        let finishing = total > 0 && done >= total
        jobs[i].isFinishing  = finishing
        jobs[i].progress     = finishing ? nil : rawPct
        jobs[i].currentFile  = finishing ? nil : stats.transferring?.first?.name.map { URL(fileURLWithPath: $0).lastPathComponent }
        if let spd = stats.speed, spd > 0, spd <= Double(Int64.max) { jobs[i].speed = formatBytes(Int64(spd)) + "/s" }
        if !finishing, let eta = stats.transferring?.first?.eta { jobs[i].eta = formatETA(eta) } else { jobs[i].eta = nil }
        if total > 0 { jobs[i].transferred = "\(formatBytes(done)) / \(formatBytes(total))" }
        if let t = stats.transfers, let tt = stats.totalTransfers, tt > 0 {
            jobs[i].filesInfo = "\(t) / \(tt) files"
        } else if let t = stats.transfers, t > 0 {
            jobs[i].filesInfo = "\(t) files"
        } else if let c = stats.checks, c > 0 {
            // No transfers yet — rclone is scanning which files need to sync
            let fmt = { (n: Int) in Self.countFormatter.string(from: NSNumber(value: n)) ?? "\(n)" }
            if let tc = stats.totalChecks, tc > c {
                jobs[i].filesInfo = "Scanning \(fmt(c)) / \(fmt(tc))"
            } else {
                jobs[i].filesInfo = "Scanning \(fmt(c)) files"
            }
        }
    }

    @MainActor
    private func abandonRunningJobs() {
        for configId in runningJobs.keys {
            guard let i = jobs.firstIndex(where: { $0.id == configId }) else { continue }
            jobs[i].isRunning   = false
            jobs[i].progress    = nil
            jobs[i].currentFile = nil
            jobs[i].speed       = nil
            jobs[i].eta         = nil
            jobs[i].filesInfo   = nil
            jobs[i].isFinishing   = false
            jobs[i].syncStarted   = nil
            jobs[i].errorMessage  = nil
            // Revert to last persisted status so the icon doesn't stay blue-running.
            let saved = UserDefaults.standard.string(forKey: "status.\(configId)")
            jobs[i].status = saved == "ok" ? .ok : saved == "paused" ? .paused : .unknown
            pendingSyncAfterRun.remove(configId)
        }
        runningJobs.removeAll()
    }

    @MainActor
    private func finishJob(configId: String, rcId: Int, status: RCJobStatus, transferred: [RCTransferred], jobName: String) {
        runningJobs.removeValue(forKey: configId)

        guard let i = jobs.firstIndex(where: { $0.id == configId }) else { return }
        jobs[i].isRunning    = false
        jobs[i].progress     = nil
        jobs[i].currentFile  = nil
        jobs[i].speed        = nil
        jobs[i].eta          = nil
        jobs[i].filesInfo    = nil
        jobs[i].isFinishing  = false
        jobs[i].syncStarted  = nil

        let isToken = status.error?.lowercased().contains("oauth") == true ||
                      status.error?.lowercased().contains("token") == true ||
                      status.error?.lowercased().contains("invalid_grant") == true
        // Treat nil success as failure — rclone omits the field on some network errors.
        let hasErr  = !(status.success == true)
        jobs[i].status       = isToken ? .tokenError : hasErr ? .error : .ok
        let errorMsg = hasErr ? friendlyError(status.error) : nil
        jobs[i].errorMessage = errorMsg

        // Only record a successful sync time — a failed attempt must not overwrite
        // the last-known-good timestamp or the UI will show "just now" after an error.
        if !hasErr {
            jobs[i].lastSync = Date()
            UserDefaults.standard.set(Date(), forKey: "lastSync.\(configId)")
        }
        UserDefaults.standard.set(hasErr ? "error" : "ok", forKey: "status.\(configId)")
        if let msg = errorMsg {
            UserDefaults.standard.set(msg, forKey: "errorMessage.\(configId)")
        } else {
            UserDefaults.standard.removeObject(forKey: "errorMessage.\(configId)")
        }

        // If a file-watcher change arrived while this job was running, sync again now
        if pendingSyncAfterRun.remove(configId) != nil,
           jobs[i].status == .ok,
           let def = jobDefinitions.first(where: { $0.id == configId }) {
            Task { await startJob(def) }
        }

        // Clear seen keys for this job; add any remaining transfers not yet shown
        let pendingItems = transferred
            .filter { $0.checked != true && ($0.error == nil || $0.error!.isEmpty) }
            .compactMap { item -> ActivityItem? in
                let key = "\(configId):\(item.name)"
                guard !seenTransferKeys.contains(key) else { return nil }
                return ActivityItem(timestamp: Date(), jobName: jobName, filePath: item.name, operation: .uploaded)
            }
        seenTransferKeys = seenTransferKeys.filter { !$0.hasPrefix("\(configId):") }
        if !pendingItems.isEmpty {
            activity = Array((pendingItems + activity).prefix(500))
            saveActivity()
        }
    }

    @MainActor
    private func addLiveActivity(_ transferred: [RCTransferred], configId: String, jobName: String) {
        let newItems = transferred
            .filter { $0.checked != true && ($0.error == nil || $0.error!.isEmpty) }
            .compactMap { item -> ActivityItem? in
                let key = "\(configId):\(item.name)"
                guard !seenTransferKeys.contains(key) else { return nil }
                seenTransferKeys.insert(key)
                return ActivityItem(timestamp: Date(), jobName: jobName, filePath: item.name, operation: .uploaded)
            }
        if !newItems.isEmpty {
            activity = Array((newItems + activity).prefix(500))
            saveActivity()
        }
    }

    // MARK: - Formatting

    private func friendlyError(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Unknown error" }
        if raw.contains("invalid_grant") || raw.contains("token") || raw.contains("oauth") {
            return "Token expired — reconnect in Settings"
        }
        if raw.contains("no space left") || raw.contains("quota") {
            return "Drive storage full"
        }
        if raw.contains("permission") || raw.contains("forbidden") {
            return "Permission denied"
        }
        if raw.contains("no such host") || raw.contains("network is unreachable") ||
           raw.contains("connection refused") {
            return "No internet connection"
        }
        if raw.contains("i/o timeout") || raw.contains("deadline exceeded") {
            return "Network timeout"
        }
        if raw.contains("connection reset") || raw.contains("broken pipe") {
            return "Connection interrupted"
        }
        // Strip rclone path prefixes and return the last meaningful segment
        let clean = raw.components(separatedBy: ": ").last ?? raw
        let trimmed = clean.trimmingCharacters(in: .whitespaces)
        return String((trimmed.isEmpty ? raw : trimmed).prefix(80))
    }

    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    private func formatBytes(_ bytes: Int64) -> String {
        let units: [(Double, String)] = [(1_073_741_824, "GiB"), (1_048_576, "MiB"), (1_024, "KiB")]
        for (div, label) in units {
            if Double(bytes) >= div { return String(format: "%.2f \(label)", Double(bytes) / div) }
        }
        return "\(bytes) B"
    }

    private func formatETA(_ secs: Int) -> String {
        if secs < 60   { return "\(secs)s" }
        if secs < 3600 { return "\(secs/60)m\(secs%60)s" }
        return "\(secs/3600)h\((secs%3600)/60)m"
    }
}
