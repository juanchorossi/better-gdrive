import SwiftUI

/// Sync arrow icon that spins when active.
/// Uses .rotate (macOS 15+) or .pulse (macOS 14) depending on availability.
struct SyncIconView: View {
    var color: Color = .blue
    var font: Font = .body
    var isActive: Bool

    var body: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(color).font(font)
                .symbolEffect(.rotate, isActive: isActive)
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(color).font(font)
                .symbolEffect(.pulse, options: .repeating, isActive: isActive)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var store: StatusStore
    @State private var tab: Tab = .status
    @Environment(\.openWindow) private var openWindow

    enum Tab { case status, activity }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.jobs.isEmpty {
                emptyContent
            } else {
                HStack(spacing: 0) {
                    tabButton(L.Tabs.status, tab: .status)
                    tabButton(L.Tabs.activity, tab: .activity)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 0)

                Divider()

                if tab == .status {
                    statusContent
                } else {
                    activityContent
                }
            }

            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var emptyContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No folders configured")
                .fontWeight(.medium)
            Button("Open Settings") { openMainWindow() }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if store.isAnySyncRunning {
                SyncIconView(color: store.headerColor, isActive: true)
            } else {
                Image(systemName: store.menuBarIcon).foregroundStyle(store.headerColor)
            }
            Text(store.headerTitle)
                .font(.headline)
            Spacer()
            if !store.jobs.isEmpty {
                Button {
                    store.isAnySyncRunning ? store.stopAll() : store.runAll()
                } label: {
                    Image(systemName: store.isAnySyncRunning ? "pause.circle" : "play.circle")
                }
                .buttonStyle(.plain)
                .help(store.isAnySyncRunning ? "Stop" : L.General.runAll)

                Button { openMainWindow() } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help(L.General.openWindow)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func tabButton(_ title: String, tab t: Tab) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                    .padding(.vertical, 4)
                Rectangle()
                    .fill(tab == t ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openMainWindow() {
        // Close the menu bar popover (it's hosted in an NSPanel)
        NSApp.windows.filter { $0 is NSPanel }.forEach { $0.close() }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.windows
                .filter { !($0 is NSPanel) && $0.canBecomeMain }
                .forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(L.General.appName)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Status tab

    private var statusContent: some View {
        VStack(spacing: 0) {
            ForEach(store.jobs) { job in
                JobRow(job: job, store: store)
                if job.id != store.jobs.last?.id {
                    Divider().padding(.leading, 36)
                }
            }
        }
    }

    // MARK: - Activity tab

    private var activityContent: some View {
        Group {
            if store.activity.isEmpty {
                Text(L.Activity.noRecent)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.activity) { item in
                            ActivityRow(item: item)
                            if item.id != store.activity.last?.id {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
    }

}

// MARK: - Job Row

struct JobRow: View {
    let job: SyncJob
    let store: StatusStore
    @State private var hovered = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                statusIcon

                VStack(alignment: .leading, spacing: 1) {
                    Text(job.name).fontWeight(.medium)
                    rowSubtitle
                }

                Spacer()

                if job.isRunning {
                    if let pct = job.progress {
                        Text("\(Int(pct * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.blue)
                    }
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.secondary)
                        .onTapGesture { store.pause(job) }
                } else if job.status == .paused {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.blue)
                        .onTapGesture { store.run(job) }
                } else {
                    // Play on hover only
                    Image(systemName: "play.circle")
                        .foregroundStyle(.secondary)
                        .opacity(hovered ? 1 : 0)
                }
            }
            if job.isRunning { progressSection }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(hovered ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            if job.isRunning {
                store.selectedJobId = job.id
                openWindow(id: "detail")
            } else {
                store.run(job)
            }
        }
    }

    @ViewBuilder
    private var rowSubtitle: some View {
        if job.isRunning {
            if job.isFinishing {
                Text("Finishing…")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                let parts = [job.speed, job.filesInfo, job.eta.map { "ETA \($0)" }].compactMap { $0 }
                if parts.isEmpty, let started = job.syncStarted {
                    let s = -started.timeIntervalSinceNow
                    let elapsed = s < 60 ? "\(Int(s))s" : "\(Int(s / 60))m"
                    Text("Syncing… \(elapsed)")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text(parts.isEmpty ? "Syncing…" : parts.joined(separator: "  ·  "))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } else if job.status == .tokenError {
            Text("Token expired — reconnect in Settings")
                .font(.caption2).foregroundStyle(.red)
        } else if job.status == .error {
            Text(job.errorMessage ?? "Sync failed")
                .font(.caption2).foregroundStyle(.orange)
                .lineLimit(1).truncationMode(.tail)
        } else if job.status == .paused {
            Text("Paused")
                .font(.caption2).foregroundStyle(.blue)
        } else if job.status == .unknown {
            if let display = job.lastSyncDisplay {
                Text(display).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Never synced").font(.caption2).foregroundStyle(.tertiary)
            }
        } else if job.hasLocalChanges {
            Text("Changes detected…")
                .font(.caption2).foregroundStyle(.secondary)
        } else if let display = job.lastSyncDisplay {
            Text(display)
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if job.isRunning {
            SyncIconView(isActive: true)
                .frame(width: 16)
        } else if job.status != .unknown {
            Image(systemName: job.status.sfSymbol)
                .foregroundStyle(job.status.color)
                .frame(width: 16)
        } else {
            Color.clear.frame(width: 16)
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if job.isFinishing {
            ProgressView().progressViewStyle(.linear).tint(.blue).padding(.leading, 24)
        } else if let p = job.progress {
            ProgressView(value: p).tint(.blue).padding(.leading, 24)
        }
        if let file = job.currentFile {
            Text(file)
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
                .padding(.leading, 24)
        }
        if let x = job.transferred {
            Text(x)
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.fileIcon)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(item.jobName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let folder = item.parentFolder {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(folder)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(item.relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Text(item.operation.description)
                    .font(.caption)
                    .foregroundStyle(item.operation.color)
                Image(systemName: item.operation.icon)
                    .font(.caption)
                    .foregroundStyle(item.operation.color)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}
