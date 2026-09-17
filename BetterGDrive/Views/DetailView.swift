import SwiftUI

struct DetailView: View {
    @EnvironmentObject var store: StatusStore

    var job: SyncJob? { store.jobs.first { $0.id == store.selectedJobId } }
    var items: [ActivityItem] { store.selectedJobId.map { store.parseJobActivity($0) } ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            if let job {
                header(job)
                Divider()
                if job.isRunning { progressSection(job) }
            }
            fileList
        }
        .frame(width: 480, height: 420)
        .background(.windowBackground)
    }

    // MARK: - Header

    private func header(_ job: SyncJob) -> some View {
        HStack(spacing: 10) {
            Image(systemName: job.isRunning ? "arrow.triangle.2.circlepath" : job.status.sfSymbol)
                .foregroundStyle(job.isRunning ? .blue : job.status.color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.name).font(.title3.bold())
                Text(job.isRunning ? L.Status.syncing : (job.relativeTime.map { "Last sync \($0) ago" } ?? L.Status.noHistory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Progress

    private func progressSection(_ job: SyncJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = job.progress {
                ProgressView(value: p)
                    .tint(.blue)
            }
            HStack {
                if let speed = job.speed {
                    Label(speed, systemImage: "arrow.up")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let xfer = job.transferred {
                    Text(xfer).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let eta = job.eta {
                    Text("· ETA \(eta)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let file = job.currentFile {
                Text("↳ \(file)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - File list

    private var fileList: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                    Text(L.Activity.noFiles)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Column headers
                    HStack {
                        Text(L.Activity.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(L.Activity.status)
                            .frame(width: 90, alignment: .trailing)
                        Text(L.Activity.time)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                fileRow(item)
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    private func fileRow(_ item: ActivityItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.fileIcon)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(item.fileName)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                Image(systemName: item.operation.icon)
                Text(item.operation.description)
            }
            .font(.caption)
            .foregroundStyle(item.operation.color)
            .frame(width: 90, alignment: .trailing)

            Text(item.relativeTime)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
