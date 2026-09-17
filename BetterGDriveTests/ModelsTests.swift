import XCTest
@testable import Better_GDrive

// MARK: - JobDefinition

final class JobDefinitionTests: XCTestCase {

    func testLocalDisplayPathStripsHome() {
        let job = makeJob(localPath: NSHomeDirectory() + "/Documents/Photos")
        XCTAssertEqual(job.localDisplayPath, "~/Documents/Photos")
    }

    func testLocalDisplayPathNoHomePrefix() {
        let job = makeJob(localPath: "/usr/local/bin")
        XCTAssertEqual(job.localDisplayPath, "/usr/local/bin")
    }

    func testDriveDisplayPathStripsPrefix() {
        let job = makeJob(drivePath: "gdrive:Projects/2024")
        XCTAssertEqual(job.driveDisplayPath, "Projects/2024")
    }

    func testDriveDisplayPathRootRemote() {
        let job = makeJob(drivePath: "gdrive:")
        XCTAssertEqual(job.driveDisplayPath, "")
    }

    func testLocalURLExpandsTilde() {
        let job = makeJob(localPath: "~/Documents")
        XCTAssertEqual(job.localURL, URL(fileURLWithPath: NSHomeDirectory() + "/Documents"))
    }

    func testLocalURLAbsolutePath() {
        let job = makeJob(localPath: "/tmp/test")
        XCTAssertEqual(job.localURL, URL(fileURLWithPath: "/tmp/test"))
    }

    // MARK: - JSON round-trip

    func testJSONRoundTripMinimal() throws {
        let job = makeJob()
        let config = SyncConfig(bwlimit: "09:00,5M 23:00,off", jobs: [job])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SyncConfig.self, from: data)
        XCTAssertEqual(decoded.bwlimit, config.bwlimit)
        XCTAssertEqual(decoded.jobs.count, 1)
        let d = decoded.jobs[0]
        XCTAssertEqual(d.id, job.id)
        XCTAssertEqual(d.name, job.name)
        XCTAssertEqual(d.localPath, job.localPath)
        XCTAssertEqual(d.drivePath, job.drivePath)
        XCTAssertEqual(d.transfers, job.transfers)
        XCTAssertFalse(d.copyMode)
        XCTAssertNil(d.filterFile)
        XCTAssertNil(d.gitPullFirst)
    }

    func testJSONRoundTripWithOptionals() throws {
        let job = JobDefinition(
            id: "xyz", name: "Work", localPath: "~/Work",
            drivePath: "gdrive:Work", transfers: 8, copyMode: true,
            filterFile: "~/.gitignore", gitPullFirst: true
        )
        let data = try JSONEncoder().encode(SyncConfig(bwlimit: "off", jobs: [job]))
        let decoded = try JSONDecoder().decode(SyncConfig.self, from: data)
        let d = decoded.jobs[0]
        XCTAssertEqual(d.filterFile, "~/.gitignore")
        XCTAssertEqual(d.gitPullFirst, true)
        XCTAssertTrue(d.copyMode)
    }

    func testJSONRoundTripEmptyJobs() throws {
        let config = SyncConfig(bwlimit: "off", jobs: [])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SyncConfig.self, from: data)
        XCTAssertTrue(decoded.jobs.isEmpty)
    }

    // MARK: - Helper

    private func makeJob(
        id: String = "test-id",
        name: String = "Test",
        localPath: String = "~/Documents",
        drivePath: String = "gdrive:Docs"
    ) -> JobDefinition {
        JobDefinition(id: id, name: name, localPath: localPath,
                      drivePath: drivePath, transfers: 4, copyMode: false)
    }
}

// MARK: - SyncJob

final class SyncJobTests: XCTestCase {

    func testRelativeTimeNilWhenNoLastSync() {
        let job = makeJob(lastSync: nil)
        XCTAssertNil(job.relativeTime)
    }

    func testRelativeTimeNowForRecentSync() {
        let job = makeJob(lastSync: Date(timeIntervalSinceNow: -30))
        XCTAssertEqual(job.relativeTime, L.General.now)
    }

    func testRelativeTimeMinutes() {
        let job = makeJob(lastSync: Date(timeIntervalSinceNow: -300)) // 5 min
        XCTAssertEqual(job.relativeTime, "5m")
    }

    func testRelativeTimeHours() {
        let job = makeJob(lastSync: Date(timeIntervalSinceNow: -7200)) // 2 h
        XCTAssertEqual(job.relativeTime, "2h")
    }

    func testRelativeTimeDays() {
        let job = makeJob(lastSync: Date(timeIntervalSinceNow: -172_800)) // 2 d
        XCTAssertEqual(job.relativeTime, "2d")
    }

    func testRelativeTimeBoundaryMinute() {
        // exactly 60s — first threshold that switches from "now" to minutes
        let job = makeJob(lastSync: Date(timeIntervalSinceNow: -60))
        XCTAssertEqual(job.relativeTime, "1m")
    }

    func testRelativeTimeBoundaryHour() {
        let job = makeJob(lastSync: Date(timeIntervalSinceNow: -3600))
        XCTAssertEqual(job.relativeTime, "1h")
    }

    private func makeJob(lastSync: Date?) -> SyncJob {
        SyncJob(id: "1", name: "Test", status: .ok,
                lastSync: lastSync, errors: 0, isRunning: false)
    }
}

// MARK: - ActivityItem

final class ActivityItemTests: XCTestCase {

    func testFileName() {
        XCTAssertEqual(makeItem("folder/sub/document.pdf").fileName, "document.pdf")
    }

    func testFileNameRootFile() {
        XCTAssertEqual(makeItem("notes.txt").fileName, "notes.txt")
    }

    func testParentFolderWithNestedPath() {
        XCTAssertEqual(makeItem("/work/projects/main.swift").parentFolder, "/work/projects")
    }

    func testParentFolderRootFileIsNil() {
        XCTAssertNil(makeItem("file.txt").parentFolder)
    }

    func testParentFolderSlashRootIsNil() {
        XCTAssertNil(makeItem("/file.txt").parentFolder)
    }

    func testFileIconPDF() {
        XCTAssertEqual(makeItem("doc.pdf").fileIcon, "doc.richtext")
    }

    func testFileIconImages() {
        for ext in ["png", "jpg", "jpeg", "heic", "gif"] {
            XCTAssertEqual(makeItem("img.\(ext)").fileIcon, "photo", "ext: \(ext)")
        }
    }

    func testFileIconAudio() {
        for ext in ["mp3", "m4a", "flac", "wav", "aiff"] {
            XCTAssertEqual(makeItem("audio.\(ext)").fileIcon, "music.note", "ext: \(ext)")
        }
    }

    func testFileIconVideo() {
        for ext in ["mp4", "mov", "avi", "mkv"] {
            XCTAssertEqual(makeItem("video.\(ext)").fileIcon, "film", "ext: \(ext)")
        }
    }

    func testFileIconArchive() {
        for ext in ["zip", "tar", "gz", "rar"] {
            XCTAssertEqual(makeItem("arc.\(ext)").fileIcon, "archivebox", "ext: \(ext)")
        }
    }

    func testFileIconCode() {
        for ext in ["swift", "py", "js", "ts", "sh", "rb", "go", "rs"] {
            XCTAssertEqual(makeItem("code.\(ext)").fileIcon,
                           "chevron.left.forwardslash.chevron.right", "ext: \(ext)")
        }
    }

    func testFileIconUnknownFallsBackToDoc() {
        XCTAssertEqual(makeItem("data.csv").fileIcon, "doc")
        XCTAssertEqual(makeItem("noextension").fileIcon, "doc")
    }

    private func makeItem(_ path: String) -> ActivityItem {
        ActivityItem(timestamp: Date(), jobName: "Test", filePath: path, operation: .uploaded)
    }
}

// MARK: - JobStatus

final class JobStatusTests: XCTestCase {

    func testSfSymbols() {
        XCTAssertEqual(JobStatus.ok.sfSymbol,         "checkmark.icloud")
        XCTAssertEqual(JobStatus.error.sfSymbol,      "exclamationmark.triangle")
        XCTAssertEqual(JobStatus.tokenError.sfSymbol, "exclamationmark.shield")
        XCTAssertEqual(JobStatus.running.sfSymbol,    "arrow.triangle.2.circlepath")
        XCTAssertEqual(JobStatus.unknown.sfSymbol,    "circle.dashed")
    }
}

// MARK: - ActivityOp

final class ActivityOpTests: XCTestCase {

    func testDescriptions() {
        XCTAssertEqual(ActivityOp.uploaded.description, L.Ops.uploaded)
        XCTAssertEqual(ActivityOp.updated.description,  L.Ops.updated)
        XCTAssertEqual(ActivityOp.deleted.description,  L.Ops.deleted)
        XCTAssertEqual(ActivityOp.moved.description,    L.Ops.moved)
    }

    func testIcons() {
        XCTAssertEqual(ActivityOp.uploaded.icon, "arrow.up.circle")
        XCTAssertEqual(ActivityOp.updated.icon,  "arrow.triangle.2.circlepath")
        XCTAssertEqual(ActivityOp.deleted.icon,  "trash")
        XCTAssertEqual(ActivityOp.moved.icon,    "arrow.right.circle")
    }
}
