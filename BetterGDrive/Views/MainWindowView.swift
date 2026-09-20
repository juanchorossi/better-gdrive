import SwiftUI

// MARK: - Navigation

enum AppSection: String, CaseIterable, Identifiable {
    case status, activity, settings

    var id: String { rawValue }
    var label: String {
        switch self {
        case .status:   return L.Tabs.status
        case .activity: return L.Tabs.activity
        case .settings: return L.Tabs.settings
        }
    }
    var icon: String {
        switch self {
        case .status:   return "cloud"
        case .activity: return "arrow.triangle.2.circlepath"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Main window

struct MainWindowView: View {
    @EnvironmentObject var store: StatusStore
    @State private var section: AppSection = .status

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { s in
                Label(s.label, systemImage: s.icon).tag(s)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                switch section {
                case .status:   MainStatusView(section: $section)
                case .activity: MainActivityView()
                case .settings: MainSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(L.General.appName)
        .frame(minWidth: 720, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { store.refresh() } label: {
                    Label(L.General.refresh, systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    store.isAnySyncRunning ? store.stopAll() : store.runAll()
                } label: {
                    Label(
                        store.isAnySyncRunning ? "Stop" : L.General.runAll,
                        systemImage: store.isAnySyncRunning ? "pause.circle" : "play.circle"
                    )
                }
            }
        }
    }
}

// MARK: - Status section

struct MainStatusView: View {
    @EnvironmentObject var store: StatusStore
    @Binding var section: AppSection

    var body: some View {
        VStack(spacing: 0) {
            if store.jobs.isEmpty {
                emptyState
            } else {
                statusBanner
                Divider()
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(store.jobs) { job in
                            MainJobRow(job: job)
                            Divider().padding(.leading, 64)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("No folders synced yet")
                    .font(.title3.bold())
                Text("Add a folder to start syncing with Google Drive.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Go to Settings") { section = .settings }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var statusBanner: some View {
        HStack(spacing: 12) {
            Group {
                if store.isAnySyncRunning {
                    SyncIconView(color: bannerColor, font: .system(size: 22), isActive: true)
                } else {
                    Image(systemName: bannerIcon).font(.system(size: 22)).foregroundStyle(bannerColor)
                }
            }
            .frame(width: 32, height: 32)
            .background(bannerColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(bannerTitle)
                    .font(.headline)
                Text(bannerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let rate = store.currentThrottleRate {
                    Label("Throttled · \(rate)", systemImage: "gauge.low")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.03))
    }

    private var bannerIcon: String {
        if store.jobs.contains(where: { $0.isRunning })             { return "arrow.triangle.2.circlepath" }
        if store.jobs.contains(where: { $0.status == .tokenError }) { return "exclamationmark.shield.fill" }
        if store.jobs.contains(where: { $0.status == .error })      { return "exclamationmark.triangle.fill" }
        if store.jobs.contains(where: { $0.status == .paused })     { return "pause.circle.fill" }
        return "checkmark.icloud.fill"
    }
    private var bannerColor: Color {
        if store.jobs.contains(where: { $0.isRunning })             { return .blue }
        if store.jobs.contains(where: { $0.status == .tokenError }) { return .red }
        if store.jobs.contains(where: { $0.status == .error })      { return .orange }
        if store.jobs.contains(where: { $0.status == .paused })     { return .blue }
        return .green
    }
    private var bannerTitle: String {
        if store.jobs.contains(where: { $0.isRunning })             { return L.Status.syncing }
        if store.jobs.contains(where: { $0.status == .tokenError }) { return L.Status.tokenExpired }
        if store.jobs.contains(where: { $0.status == .error })      { return L.Status.syncError }
        if store.jobs.contains(where: { $0.status == .paused })     { return "Paused" }
        return L.Status.upToDate
    }
    private var bannerSubtitle: String {
        if store.jobs.contains(where: { $0.isRunning })             { return L.Status.syncingDetail }
        if store.jobs.contains(where: { $0.status == .tokenError }) { return "Token expired — reconnect in Settings" }
        if let errJob = store.jobs.first(where: { $0.status == .error }) {
            return errJob.errorMessage ?? L.Status.errorDetail
        }
        if store.jobs.contains(where: { $0.status == .paused })     { return "Tap play to resume syncing" }
        let oldest = store.jobs.compactMap(\.lastSync).min()
        return oldest.map { d in
            let s = -d.timeIntervalSinceNow
            if s < 60    { return "Just synced" }
            if s < 3600  { return "Last sync \(Int(s/60))m ago" }
            if s < 86400 { return "Last sync \(Int(s/3600))h ago" }
            return "Last sync \(Int(s/86400))d ago"
        } ?? L.Status.noHistory
    }
}

struct MainJobRow: View {
    let job: SyncJob
    @EnvironmentObject var store: StatusStore
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                statusIcon
                    .frame(width: 32, height: 32)
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name).fontWeight(.medium)
                    subtitleText
                }

                Spacer()

                if job.isRunning {
                    // Percentage — hidden during finishing (progress=nil then)
                    if let pct = job.progress {
                        Text("\(Int(pct * 100))%")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.blue)
                    }
                    Button { store.pause(job) } label: {
                        Image(systemName: "pause.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if job.status == .paused {
                    // Always-visible blue play button for paused jobs
                    Button { store.run(job) } label: {
                        Image(systemName: "play.circle")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Play button — only on hover for idle rows
                    Button { store.run(job) } label: {
                        Image(systemName: "play.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(hovered ? 1 : 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, job.isRunning ? 6 : 10)

            if job.isRunning {
                progressSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
        .background(hovered ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var subtitleText: some View {
        if job.status == .paused {
            Text("Paused")
                .font(.caption).foregroundStyle(.blue)
        } else if job.isRunning {
            if job.isFinishing {
                let parts = (["Finishing…"] + [job.filesInfo].compactMap { $0 })
                Text(parts.joined(separator: "  ·  "))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else {
                let parts = [job.speed, job.filesInfo, job.eta.map { "ETA \($0)" }].compactMap { $0 }
                if parts.isEmpty, let started = job.syncStarted {
                    let s = -started.timeIntervalSinceNow
                    let elapsed = s < 60 ? "\(Int(s))s" : "\(Int(s / 60))m"
                    Text("Syncing… \(elapsed)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text(parts.isEmpty ? L.Status.syncing : parts.joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } else if job.status == .tokenError {
            Text("Token expired — reconnect in Settings")
                .font(.caption).foregroundStyle(.red)
        } else if job.status == .error {
            Text(job.errorMessage ?? "Sync failed")
                .font(.caption).foregroundStyle(.orange)
                .lineLimit(1).truncationMode(.tail)
        } else if job.status == .unknown {
            if let display = job.lastSyncDisplay {
                Text(display).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Never synced").font(.caption).foregroundStyle(.tertiary)
            }
        } else if let display = job.lastSyncDisplay {
            Text(display)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if job.isFinishing {
                ProgressView().progressViewStyle(.linear).tint(.blue).padding(.leading, 44)
            } else if let p = job.progress {
                ProgressView(value: p).tint(.blue).padding(.leading, 44)
            }
            if let file = job.currentFile {
                Text(file)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.leading, 44)
            }
            if let x = job.transferred {
                Text(x)
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, 44)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if job.isRunning {
            SyncIconView(font: .callout, isActive: job.isRunning)
        } else if job.status == .unknown {
            Image(systemName: "icloud").foregroundStyle(.tertiary).font(.callout)
        } else {
            Image(systemName: job.status.sfSymbol).foregroundStyle(job.status.color).font(.callout)
        }
    }

    private var iconBackground: Color {
        if job.isRunning { return Color.blue.opacity(0.12) }
        if job.status == .unknown { return Color.primary.opacity(0.05) }
        return job.status.color.opacity(0.12)
    }
}

// MARK: - Activity section

struct MainActivityView: View {
    @EnvironmentObject var store: StatusStore
    @State private var jobFilter: String = L.Activity.all
    @State private var search = ""

    private var jobOptions: [String] {
        [L.Activity.all] + store.jobDefinitions.map(\.name)
    }

    private var filtered: [ActivityItem] {
        store.activity.filter { item in
            (jobFilter == L.Activity.all || item.jobName == jobFilter) &&
            (search.isEmpty || item.fileName.localizedCaseInsensitiveContains(search) ||
             item.filePath.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters toolbar
            HStack {
                Picker("Folder", selection: $jobFilter) {
                    ForEach(jobOptions, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L.Activity.search, text: $search)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Column headers — fixed placeholder matches ActivityTableRow icon frame(width:20) + spacing 10
            HStack(spacing: 10) {
                Rectangle().fill(.clear).frame(width: 20, height: 1)
                Text(L.Activity.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Folder")
                    .frame(width: 80, alignment: .leading)
                Text(L.Activity.status)
                    .frame(width: 90, alignment: .leading)
                Text(L.Activity.time)
                    .frame(width: 120, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                    Text(L.Activity.noRecent)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { item in
                            ActivityTableRow(item: item)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }
}

struct ActivityTableRow: View {
    let item: ActivityItem
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.fileIcon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(item.fileName)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.jobName)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 80, alignment: .leading)

            HStack(spacing: 3) {
                Image(systemName: item.operation.icon)
                Text(item.operation.description)
            }
            .font(.caption)
            .foregroundStyle(item.operation.color)
            .frame(width: 90, alignment: .leading)

            Text(item.exactTime)
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(hovered ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

// MARK: - Settings section

struct MainSettingsView: View {
    @EnvironmentObject var store: StatusStore
    @State private var showAddSheet = false
    @State private var jobToDelete: JobDefinition?
    @State private var reconnectPhase: ReconnectPhase = .idle
    private enum ReconnectPhase { case idle, opening, browserOpen, error }
    @State private var lastConnectedAt: Date? = UserDefaults.standard.object(forKey: "lastGoogleConnectedAt") as? Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                foldersSection
                tokenSection
                bandwidthSection
                launchAtLoginSection
            }
            .padding(24)
        }
        .sheet(isPresented: $showAddSheet) {
            AddJobSheet { newJob in
                store.configStore.addJob(newJob)
                store.runDefinition(newJob)
            }
        }
        .task {
            if store.googleAccount != nil, lastConnectedAt == nil {
                let date = rcloneConfModificationDate()
                if let date {
                    UserDefaults.standard.set(date, forKey: "lastGoogleConnectedAt")
                    lastConnectedAt = date
                }
            }
        }
        .confirmationDialog(
            "Remove \"\(jobToDelete?.name ?? "")\"?",
            isPresented: Binding(get: { jobToDelete != nil }, set: { if !$0 { jobToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove folder", role: .destructive) {
                if let def = jobToDelete {
                    store.configStore.removeJob(id: def.id)
                }
                jobToDelete = nil
            }
            Button("Cancel", role: .cancel) { jobToDelete = nil }
        } message: {
            Text("The folder will stop syncing. Your files on Google Drive won't be deleted.")
        }
    }

    // MARK: Folders

    private var foldersSection: some View {
        settingsSection(L.Settings.syncedFolders) {
            VStack(spacing: 0) {
                ForEach(store.jobDefinitions) { def in
                    JobDefinitionRow(def: def, job: store.jobs.first { $0.id == def.id }) {
                        jobToDelete = def
                    }
                    Divider().padding(.leading, 52)
                }

                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .frame(width: 36)
                        Text(L.Settings.addFolder)
                        Spacer()
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    // MARK: Token

    private var tokenSection: some View {
        settingsSection(L.Settings.googleAccount) {
            HStack(spacing: 12) {
                avatarView
                if store.isLoadingAccount {
                    ProgressView().scaleEffect(0.7)
                    Spacer()
                } else if let account = store.googleAccount {
                    connectedInfo(account)
                    Spacer()
                    Button { doReconnect() } label: { reconnectLabel }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(reconnectPhase == .error ? .red : .secondary)
                        .disabled(reconnectPhase == .opening || reconnectPhase == .browserOpen)
                } else {
                    disconnectedInfo
                    Spacer()
                    Button { doReconnect() } label: { reconnectLabel }
                        .buttonStyle(.bordered)
                        .disabled(reconnectPhase == .opening || reconnectPhase == .browserOpen)
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        Group {
            if let url = store.googleAccount?.pictureURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 32)).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    @ViewBuilder
    private func connectedInfo(_ account: GoogleUserInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
                Text(account.name).fontWeight(.medium)
            }
            Text(account.email).font(.caption).foregroundStyle(.secondary)
            if let d = lastConnectedAt {
                Text("Connected \(d.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var disconnectedInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Google Drive").fontWeight(.medium)
            Text("Token expired or not connected")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var reconnectLabel: some View {
        switch reconnectPhase {
        case .idle:
            Text(store.googleAccount != nil ? "Reconnect" : L.Settings.reconnectToken)
        case .opening:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Opening…") }
        case .browserOpen:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Waiting for browser…") }
        case .error:
            Text("Failed — try again")
        }
    }

    private func doReconnect() {
        guard reconnectPhase == .idle || reconnectPhase == .error else { return }
        reconnectPhase = .opening
        Task {
            do {
                try await RcloneRC.reconnectGDrive()
                await MainActor.run { reconnectPhase = .browserOpen }
                await RcloneRC.waitForReconnectComplete()
                if let info = await RcloneRC.fetchGoogleUserInfoFromConfigFile() {
                    let now = Date()
                    UserDefaults.standard.set(now, forKey: "lastGoogleConnectedAt")
                    await MainActor.run {
                        store.googleAccount = info
                        lastConnectedAt = now
                        reconnectPhase = .idle
                    }
                } else {
                    await MainActor.run { reconnectPhase = .idle }
                }
                RcloneRC.stopDaemon()
                await RcloneRC.ensureDaemon()
                // Reset token-error jobs and re-sync them now that we have a fresh token
                await MainActor.run { store.resetTokenErrorJobs() }
            } catch {
                await MainActor.run { reconnectPhase = .error }
            }
        }
    }

    // MARK: Bandwidth

    private var bandwidthSection: some View {
        settingsSection(L.Settings.bandwidth) {
            BandwidthEditor(configStore: store.configStore)
        }
    }

    // MARK: Launch at Login

    private var launchAtLoginSection: some View {
        settingsSection("General") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "power")
                        .font(.title2).foregroundStyle(.secondary)
                    Text("Launch at Login")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.launchAtLoginEnabled },
                        set: { store.launchAtLoginEnabled = $0 }
                    ))
                    .labelsHidden()
                }
                .padding(14)
                Divider().padding(.leading, 52)
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-sync")
                        Text("Also sync on a schedule, not just when files change.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { store.configStore.config.syncIntervalMinutes },
                        set: { store.configStore.config.syncIntervalMinutes = $0; store.configStore.save() }
                    )) {
                        Text("Off").tag(0)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                        Text("8 hours").tag(480)
                        Text("24 hours").tag(1440)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 110)
                }
                .padding(14)
            }
        }
    }

    // MARK: Helper

    private func settingsSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.bottom, 24)
    }

    private func rcloneConfModificationDate() -> Date? {
        let url: URL
        if let env = ProcessInfo.processInfo.environment["RCLONE_CONFIG"] {
            url = URL(fileURLWithPath: env)
        } else {
            url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/rclone/rclone.conf")
        }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

// MARK: - Job definition row

struct JobDefinitionRow: View {
    let def: JobDefinition
    let job: SyncJob?
    var onDelete: () -> Void = {}
    @EnvironmentObject var store: StatusStore
    @State private var hovered = false
    @State private var showEditSheet = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .font(.title3)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(def.name).fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(def.localDisplayPath)
                        .font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(def.driveDisplayPath)
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if !def.excludePatterns.isEmpty {
                        Text("\(def.excludePatterns.count) exclusion\(def.excludePatterns.count == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if let job, job.status != .unknown, let display = job.lastSyncDisplay {
                        if !def.excludePatterns.isEmpty {
                            Text("·").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text("Synced \(display)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    if let j = job, j.isRunning {
                        store.pause(j)
                    } else {
                        store.runDefinition(def)
                    }
                } label: {
                    Image(systemName: job?.isRunning == true ? "pause.fill" : "play.fill")
                        .font(.callout)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(job?.isRunning == true ? "Pause" : "Sync now")

                Button { showEditSheet = true } label: {
                    Image(systemName: "gearshape")
                        .font(.callout)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Edit settings")

                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                }
                .buttonStyle(.plain).foregroundStyle(.red.opacity(0.8))
                .help("Remove folder")
            }
            .opacity(hovered ? 1 : 0)
        }
        .padding(14)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .sheet(isPresented: $showEditSheet) {
            EditJobSheet(def: def) { updated in
                store.configStore.updateJob(updated)
            }
        }
    }
}

// MARK: - Edit job sheet

struct EditJobSheet: View {
    let def: JobDefinition
    let onSave: (JobDefinition) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var copyMode: Bool
    @State private var excludePatterns: [String]
    @State private var customPattern = ""

    init(def: JobDefinition, onSave: @escaping (JobDefinition) -> Void) {
        self.def = def
        self.onSave = onSave
        _copyMode = State(initialValue: def.copyMode)
        _excludePatterns = State(initialValue: def.excludePatterns.isEmpty
            ? ExcludePreset.allCases.map(\.rawValue)
            : def.excludePatterns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name).font(.title2.bold())
                    Text("\(def.localDisplayPath) → \(def.driveDisplayPath)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary).font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SyncTypePicker(copyMode: $copyMode)

                    // Exclude patterns
                    VStack(alignment: .leading, spacing: 8) {
                        let allPresets = ExcludePreset.allCases.map(\.rawValue)
                        let allOn = allPresets.allSatisfy { excludePatterns.contains($0) }
                        HStack {
                            Text("Exclude from sync").font(.subheadline.bold())
                            Spacer()
                            HStack(spacing: 6) {
                                Text(allOn ? "Deselect all" : "Select all").font(.caption)
                                Toggle("", isOn: Binding(
                                    get: { allOn },
                                    set: { on in
                                        if on { for p in allPresets where !excludePatterns.contains(p) { excludePatterns.append(p) } }
                                        else  { excludePatterns.removeAll { allPresets.contains($0) } }
                                    }
                                )).labelsHidden().toggleStyle(.checkbox)
                            }
                            .padding(.trailing, 12)
                        }
                        let custom = excludePatterns.filter { p in !ExcludePreset.allCases.map(\.rawValue).contains(p) }
                        VStack(spacing: 0) {
                            ForEach(ExcludePreset.allCases) { preset in
                                let isOn = excludePatterns.contains(preset.rawValue)
                                HStack(spacing: 10) {
                                    Image(systemName: preset.icon)
                                        .foregroundStyle(.secondary).frame(width: 20)
                                    Text(preset.label)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { isOn },
                                        set: { on in
                                            if on { excludePatterns.append(preset.rawValue) }
                                            else  { excludePatterns.removeAll { $0 == preset.rawValue } }
                                        }
                                    )).labelsHidden()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                Divider().padding(.leading, 42)
                            }
                            ForEach(custom, id: \.self) { p in
                                HStack(spacing: 10) {
                                    Image(systemName: "line.3.horizontal.decrease")
                                        .foregroundStyle(.secondary).frame(width: 20)
                                    Text(p).font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Button { excludePatterns.removeAll { $0 == p } } label: {
                                        Image(systemName: "trash")
                                            .font(.callout)
                                            .foregroundStyle(.red.opacity(0.7))
                                    }.buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                Divider().padding(.leading, 42)
                            }
                        }
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        HStack {
                            TextField("Custom pattern, e.g. *.log", text: $customPattern)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                let p = customPattern.trimmingCharacters(in: .whitespaces)
                                if !p.isEmpty && !excludePatterns.contains(p) {
                                    excludePatterns.append(p)
                                }
                                customPattern = ""
                            }
                            .disabled(customPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") {
                    var updated = def
                    updated.copyMode = copyMode
                    updated.excludePatterns = excludePatterns
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(20)
        }
        .frame(width: 480, height: 560)
    }
}

// MARK: - Add job sheet

struct AddJobSheet: View {
    let onAdd: (JobDefinition) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var localPath = ""
    @State private var driveDest = ""
    @State private var copyMode = false
    @State private var showingPicker = false
    @State private var excludePatterns: [String] = ExcludePreset.allCases.map(\.rawValue)
    @State private var customPattern = ""
    @FocusState private var driveFieldFocused: Bool

    var canSave: Bool { !localPath.isEmpty && !driveDest.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(L.Settings.addFolderTitle)
                    .font(.title2.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary).font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Local folder picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.Settings.localFolder).font(.subheadline.bold())
                        Button { showingPicker = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: localPath.isEmpty ? "folder.badge.plus" : "folder.fill")
                                    .font(.title2)
                                    .foregroundStyle(localPath.isEmpty ? Color.secondary : Color.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    if localPath.isEmpty {
                                        Text("Choose a folder…").foregroundStyle(.secondary)
                                    } else {
                                        Text(URL(fileURLWithPath: localPath).lastPathComponent).fontWeight(.medium)
                                        Text(localPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                Spacer()
                                if !localPath.isEmpty {
                                    Text("Change").font(.caption).foregroundStyle(.blue)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Google Drive destination
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.Settings.driveDestination).font(.subheadline.bold())
                        HStack(spacing: 0) {
                            Text("gdrive:")
                                .foregroundStyle(.secondary).font(.callout.monospaced())
                                .padding(.leading, 10).padding(.trailing, 4)
                            TextField(L.Settings.drivePlaceholder, text: $driveDest)
                                .focused($driveFieldFocused).padding(.trailing, 10)
                        }
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                    }

                    SyncTypePicker(copyMode: $copyMode)

                    // Exclude patterns
                    VStack(alignment: .leading, spacing: 8) {
                        let allPresets = ExcludePreset.allCases.map(\.rawValue)
                        let allOn = allPresets.allSatisfy { excludePatterns.contains($0) }
                        HStack {
                            Text("Exclude from sync").font(.subheadline.bold())
                            Spacer()
                            HStack(spacing: 6) {
                                Text(allOn ? "Deselect all" : "Select all").font(.caption)
                                Toggle("", isOn: Binding(
                                    get: { allOn },
                                    set: { on in
                                        if on { for p in allPresets where !excludePatterns.contains(p) { excludePatterns.append(p) } }
                                        else  { excludePatterns.removeAll { allPresets.contains($0) } }
                                    }
                                )).labelsHidden().toggleStyle(.checkbox)
                            }
                            .padding(.trailing, 12)
                        }
                        let custom2 = excludePatterns.filter { p in !ExcludePreset.allCases.map(\.rawValue).contains(p) }
                        VStack(spacing: 0) {
                            ForEach(ExcludePreset.allCases) { preset in
                                let isOn = excludePatterns.contains(preset.rawValue)
                                HStack(spacing: 10) {
                                    Image(systemName: preset.icon).foregroundStyle(.secondary).frame(width: 20)
                                    Text(preset.label)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { isOn },
                                        set: { on in
                                            if on { excludePatterns.append(preset.rawValue) }
                                            else  { excludePatterns.removeAll { $0 == preset.rawValue } }
                                        }
                                    )).labelsHidden()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                Divider().padding(.leading, 42)
                            }
                            ForEach(custom2, id: \.self) { p in
                                HStack(spacing: 10) {
                                    Image(systemName: "line.3.horizontal.decrease")
                                        .foregroundStyle(.secondary).frame(width: 20)
                                    Text(p).font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Button { excludePatterns.removeAll { $0 == p } } label: {
                                        Image(systemName: "trash")
                                            .font(.callout)
                                            .foregroundStyle(.red.opacity(0.7))
                                    }.buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                Divider().padding(.leading, 42)
                            }
                        }
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        HStack {
                            TextField("Custom pattern, e.g. *.log", text: $customPattern)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                let p = customPattern.trimmingCharacters(in: .whitespaces)
                                if !p.isEmpty && !excludePatterns.contains(p) { excludePatterns.append(p) }
                                customPattern = ""
                            }
                            .disabled(customPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button(L.General.cancel) { dismiss() }.keyboardShortcut(.escape)
                Button(L.General.add) {
                    let folderName = name.isEmpty ? URL(fileURLWithPath: localPath).lastPathComponent : name
                    let id = folderName.lowercased()
                        .replacingOccurrences(of: " ", with: "-")
                        .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                    let job = JobDefinition(
                        id: id.isEmpty ? UUID().uuidString : id,
                        name: folderName,
                        localPath: localPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                        drivePath: "gdrive:\(driveDest)",
                        transfers: 4, copyMode: copyMode,
                        excludePatterns: excludePatterns
                    )
                    onAdd(job)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return)
            }
            .padding(20)
        }
        .frame(width: 480, height: 620)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                localPath = url.path
                if driveDest.isEmpty { driveDest = url.lastPathComponent }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    driveFieldFocused = true
                }
            }
        }
    }
}

// MARK: - Bandwidth Editor

struct BandwidthEditor: View {
    @ObservedObject var configStore: ConfigStore

    @State private var useSchedule = true
    @State private var dayTime    = "09:00"
    @State private var dayLimit   = "5"
    @State private var nightTime  = "23:00"
    @State private var nightLimit = ""
    @State private var flatLimit  = ""
    @State private var saved      = false

    var body: some View {
        VStack(spacing: 0) {
            // Toggle row — left-aligned like the data rows
            HStack(spacing: 10) {
                Image(systemName: "clock").foregroundStyle(.secondary).frame(width: 20)
                Text(L.Settings.throttleSchedule).fontWeight(.medium)
                Spacer()
                Toggle("", isOn: $useSchedule).labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if useSchedule {
                Divider().padding(.leading, 14)
                scheduleRow(icon: "sun.max",  label: "Daytime from",  time: $dayTime,   limit: $dayLimit)
                Divider().padding(.leading, 14)
                scheduleRow(icon: "moon",     label: "Nighttime from", time: $nightTime, limit: $nightLimit)
            } else {
                Divider().padding(.leading, 14)
                HStack(spacing: 10) {
                    Image(systemName: "speedometer").foregroundStyle(.secondary).frame(width: 20)
                    Text("Max speed").foregroundStyle(.secondary)
                    Spacer()
                    limitField($flatLimit)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            Divider().padding(.leading, 14)
            HStack {
                Spacer()
                if saved {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                        .transition(.opacity)
                }
                Button("Apply") { apply() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear { parse(configStore.config.bwlimit) }
    }

    private func scheduleRow(icon: String, label: String, time: Binding<String>, limit: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            Text(label).foregroundStyle(.secondary).frame(width: 115, alignment: .leading)
            TextField("HH:MM", text: time)
                .frame(width: 62)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onChange(of: time.wrappedValue) { val in
                    var digits = val.filter(\.isNumber)
                    if digits.count > 4 { digits = String(digits.prefix(4)) }
                    var result = ""
                    for (i, c) in digits.enumerated() {
                        if i == 2 { result += ":" }
                        result.append(c)
                    }
                    if result != val { time.wrappedValue = result }
                }
            Text("→").foregroundStyle(.tertiary)
            limitField(limit)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func limitField(_ binding: Binding<String>) -> some View {
        HStack(spacing: 6) {
            TextField(L.Settings.noLimit, text: binding)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .onChange(of: binding.wrappedValue) { val in
                    // Allow digits and a single decimal point
                    let allowed = val.filter { $0.isNumber || $0 == "." }
                    let parts = allowed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
                    let cleaned: String
                    if parts.count == 2 {
                        cleaned = "\(parts[0]).\(String(parts[1]).prefix(1))"
                    } else {
                        cleaned = allowed
                    }
                    if cleaned != val { binding.wrappedValue = String(cleaned.prefix(6)) }
                }
            if !binding.wrappedValue.isEmpty {
                Text("MB/s").foregroundStyle(.secondary).font(.callout)
            }
        }
    }

    private func apply() {
        let schedule: String
        if useSchedule {
            let dayVal   = dayLimit.isEmpty   ? "off" : "\(dayLimit)M"
            let nightVal = nightLimit.isEmpty ? "off" : "\(nightLimit)M"
            schedule = "\(dayTime),\(dayVal) \(nightTime),\(nightVal)"
        } else {
            schedule = flatLimit.isEmpty ? "off" : "\(flatLimit)M"
        }
        configStore.config.bwlimit = schedule
        configStore.save()
        Task {
            await RcloneRC.setBwlimit(schedule)
            await MainActor.run {
                saved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
            }
        }
    }

    private func parse(_ raw: String) {
        // Format: "09:00,512k 23:00,off" or "512k" or "off"
        let parts = raw.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            useSchedule = true
            let p0 = parts[0].split(separator: ",")
            let p1 = parts[1].split(separator: ",")
            dayTime    = p0.count > 0 ? String(p0[0]) : "09:00"
            dayLimit   = p0.count > 1 ? parseLimit(String(p0[1])) : "512"
            nightTime  = p1.count > 0 ? String(p1[0]) : "23:00"
            nightLimit = p1.count > 1 ? parseLimit(String(p1[1])) : ""
        } else {
            useSchedule = false
            flatLimit = parseLimit(raw)
        }
    }

    private func parseLimit(_ s: String) -> String {
        if s == "off" || s == "0" || s.isEmpty { return "" }
        // KB values (legacy "512k"): convert to accurate MB decimal
        if s.lowercased().hasSuffix("k"), let kb = Double(s.dropLast()) {
            let mb = kb / 1024
            return mb.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(mb))
                : String(format: "%.1f", mb)
        }
        return s.replacingOccurrences(of: "M", with: "")
                .replacingOccurrences(of: "m", with: "")
    }
}

// MARK: - Sync type picker

struct SyncTypePicker: View {
    @Binding var copyMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync type").font(.subheadline.bold())
            VStack(spacing: 0) {
                option(
                    selected: !copyMode,
                    icon: "arrow.triangle.2.circlepath",
                    title: "Sync",
                    description: "Drive mirrors your local folder. Files you delete locally are also deleted from Drive."
                ) { copyMode = false }
                Divider().padding(.leading, 44)
                option(
                    selected: copyMode,
                    icon: "doc.on.doc",
                    title: "Copy — keep all Drive files",
                    description: "Files are only added to Drive, never deleted. Files you remove locally stay in Drive."
                ) { copyMode = true }
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func option(selected: Bool, icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? .blue : .secondary)
                    .font(.title3)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(selected ? .medium : .regular)
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

