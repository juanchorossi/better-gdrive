import XCTest
@testable import Better_GDrive

// All StatusStore state lives on MainActor.
@MainActor
final class StatusStoreTests: XCTestCase {

    // MARK: - headerTitle

    func testHeaderTitleWhenNoJobs() {
        let store = StatusStore()
        store.jobs = []
        XCTAssertEqual(store.headerTitle, L.General.appName)
    }

    func testHeaderTitleWhenSyncing() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .running, isRunning: true)]
        XCTAssertEqual(store.headerTitle, L.Status.syncing)
    }

    func testHeaderTitleWhenTokenError() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .tokenError)]
        XCTAssertEqual(store.headerTitle, L.Status.tokenExpired)
    }

    func testHeaderTitleWhenSyncError() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .error)]
        XCTAssertEqual(store.headerTitle, L.Status.syncError)
    }

    func testHeaderTitleWhenAllOk() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .ok), makeJob(id: "2", status: .ok)]
        XCTAssertEqual(store.headerTitle, L.Status.upToDate)
    }

    // Syncing takes priority over errors.
    func testHeaderTitleSyncingTakesPriorityOverError() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .error), makeJob(id: "2", status: .running, isRunning: true)]
        XCTAssertEqual(store.headerTitle, L.Status.syncing)
    }

    // Token error takes priority over generic error.
    func testHeaderTitleTokenErrorTakesPriorityOverSyncError() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .error), makeJob(id: "2", status: .tokenError)]
        XCTAssertEqual(store.headerTitle, L.Status.tokenExpired)
    }

    // MARK: - menuBarIcon

    func testMenuBarIconWhenDaemonNotReady() {
        let store = StatusStore()
        store.daemonReady = false
        store.jobs = []
        XCTAssertEqual(store.menuBarIcon, "exclamationmark.circle")
    }

    func testMenuBarIconWhenSyncing() {
        let store = StatusStore()
        store.daemonReady = true
        store.jobs = [makeJob(status: .running, isRunning: true)]
        XCTAssertEqual(store.menuBarIcon, "arrow.triangle.2.circlepath")
    }

    func testMenuBarIconWhenTokenError() {
        let store = StatusStore()
        store.daemonReady = true
        store.jobs = [makeJob(status: .tokenError)]
        XCTAssertEqual(store.menuBarIcon, "exclamationmark.triangle.fill")
    }

    func testMenuBarIconWhenSyncError() {
        let store = StatusStore()
        store.daemonReady = true
        store.jobs = [makeJob(status: .error)]
        XCTAssertEqual(store.menuBarIcon, "exclamationmark.triangle")
    }

    func testMenuBarIconCloudWhenIdle() {
        let store = StatusStore()
        store.daemonReady = true
        store.jobs = [makeJob(status: .ok)]
        XCTAssertEqual(store.menuBarIcon, "cloud")
    }

    // MARK: - menuBarSuffix

    func testMenuBarSuffixEmptyWhenNoJobs() {
        let store = StatusStore()
        store.jobs = []
        XCTAssertEqual(store.menuBarSuffix, "")
    }

    // menuBarSuffix is empty when idle (time info lives in headerTitle, not the icon suffix)
    func testMenuBarSuffixEmptyWhenIdleRecentSync() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -30))]
        XCTAssertEqual(store.menuBarSuffix, "")
    }

    func testMenuBarSuffixEmptyWhenIdleMinutesAgo() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -300))]
        XCTAssertEqual(store.menuBarSuffix, "")
    }

    func testMenuBarSuffixEmptyWhenIdleHoursAgo() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -7200))]
        XCTAssertEqual(store.menuBarSuffix, "")
    }

    func testMenuBarSuffixEmptyWhenIdleDaysAgo() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -172_800))]
        XCTAssertEqual(store.menuBarSuffix, "")
    }

    func testMenuBarSuffixEmptyWhileRunningNoProgress() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .running, isRunning: true, lastSync: Date())]
        XCTAssertEqual(store.menuBarSuffix, "")
    }

    func testMenuBarSuffixShowsPercentageWhenRunningWithProgress() {
        let store = StatusStore()
        var job = makeJob(status: .running, isRunning: true)
        job.progress = 0.75
        store.jobs = [job]
        XCTAssertEqual(store.menuBarSuffix, "75%")
    }

    func testMenuBarSuffixZeroProgressIsEmpty() {
        let store = StatusStore()
        var job = makeJob(status: .running, isRunning: true)
        job.progress = 0.0
        store.jobs = [job]
        XCTAssertEqual(store.menuBarSuffix, "")
    }

    func testMenuBarSuffixShowsBangOnError() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .error)]
        XCTAssertEqual(store.menuBarSuffix, "!")
    }

    func testMenuBarSuffixShowsBangOnTokenError() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .tokenError)]
        XCTAssertEqual(store.menuBarSuffix, "!")
    }

    // Multiple idle jobs — suffix is always empty (no time info in the icon)
    func testMenuBarSuffixEmptyWithMultipleIdleJobs() {
        let store = StatusStore()
        store.jobs = [
            makeJob(id: "a", lastSync: Date(timeIntervalSinceNow: -600)),
            makeJob(id: "b", lastSync: Date(timeIntervalSinceNow: -7200)),
        ]
        XCTAssertEqual(store.menuBarSuffix, "")
    }

    // MARK: - headerTitle time formats

    func testHeaderTitleShowsJustNowForVeryRecentSync() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -30))]
        XCTAssertEqual(store.headerTitle, "Synced just now")
    }

    func testHeaderTitleShowsMinutesAgoFormat() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -300))]
        XCTAssertEqual(store.headerTitle, "Synced 5m ago")
    }

    func testHeaderTitleShowsHoursAgoFormat() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -7200))]
        XCTAssertEqual(store.headerTitle, "Synced 2h ago")
    }

    // Syncs older than 24h must use calendar date format, not "Xd ago"
    func testHeaderTitleShowsCalendarDateForOldSync() {
        let store = StatusStore()
        let twoDaysAgo = Date(timeIntervalSinceNow: -172_800)
        store.jobs = [makeJob(lastSync: twoDaysAgo)]
        // Must NOT contain "d ago" (the old broken format)
        XCTAssertFalse(store.headerTitle.contains("d ago"), "headerTitle should not use 'Xd ago' format")
        XCTAssertTrue(store.headerTitle.hasPrefix("Synced "), "headerTitle should start with 'Synced '")
    }

    // Oldest lastSync drives the title when multiple jobs exist
    func testHeaderTitleUsesOldestSyncAcrossJobs() {
        let store = StatusStore()
        store.jobs = [
            makeJob(id: "a", lastSync: Date(timeIntervalSinceNow: -300)),   // 5 min
            makeJob(id: "b", lastSync: Date(timeIntervalSinceNow: -7200)),  // 2 h (oldest)
        ]
        XCTAssertEqual(store.headerTitle, "Synced 2h ago")
    }

    // MARK: - Aggregate predicates

    func testAllOkWhenNoJobs() {
        let store = StatusStore()
        store.jobs = []
        XCTAssertTrue(store.allOk) // vacuously true
    }

    func testAllOkFalseWhenRunning() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .ok), makeJob(id: "2", status: .running, isRunning: true)]
        XCTAssertFalse(store.allOk)
    }

    func testAllOkTrueWhenAllOk() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .ok), makeJob(id: "2", status: .ok)]
        XCTAssertTrue(store.allOk)
    }

    func testHasError() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .ok), makeJob(id: "2", status: .error)]
        XCTAssertTrue(store.hasError)
        XCTAssertFalse(store.hasTokenError)
    }

    func testHasTokenError() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .tokenError)]
        XCTAssertTrue(store.hasTokenError)
    }

    // MARK: - Error classification

    func testInvalidGrantIsTokenError() {
        XCTAssertTrue(StatusStore.isTokenError("oauth2: \"invalid_grant\" \"Token has been expired or revoked.\""))
        XCTAssertTrue(StatusStore.isTokenError("token expired and there's no refresh token"))
    }

    // A mid-sync Google 401 is a hiccup, not an expired sign-in (the token stays valid).
    func testGoogle401IsHiccupNotTokenError() {
        let raw = "couldn't list directory: googleapi: Error 401: Request had invalid authentication credentials., authError"
        XCTAssertFalse(StatusStore.isTokenError(raw))
        XCTAssertTrue(StatusStore.isGoogleAuthHiccup(raw))
    }

    func testIOErrorMessageIncludesCount() {
        let store = StatusStore()
        let raw = "not deleting files as there were IO errors"
        XCTAssertEqual(store.friendlyError(raw), "Some files failed — nothing deleted")
        XCTAssertEqual(store.friendlyError(raw, errorCount: 1), "1 file failed — nothing deleted")
        XCTAssertEqual(store.friendlyError(raw, errorCount: 7), "7 files failed — nothing deleted")
    }

    func testPermissionDeniedNamesTheFolder() {
        let store = StatusStore()
        let raw = "not deleting files as there were IO errors"
        let detail = "failed to get info about directory entry \"/Users/me/Documents/Ualá/Netskope Bkp/EPDLP/logs/epdlp.err.log\": lstat /Users/me/Documents/Ualá/Netskope Bkp/EPDLP/logs/epdlp.err.log: permission denied"
        XCTAssertEqual(store.friendlyError(raw, errorCount: 2, lastDetail: detail, localPath: "/Users/me/Documents/Ualá"),
                       "Can't read \"Netskope Bkp/EPDLP/logs\" — no permission")
        // Unrelated detail keeps the count message
        XCTAssertEqual(store.friendlyError(raw, errorCount: 2, lastDetail: "googleapi: Error 500", localPath: "/Users/me/Documents/Ualá"),
                       "2 files failed — nothing deleted")
    }

    func testUnreadableFolderIsRelativeToJobRoot() {
        XCTAssertEqual(StatusStore.unreadableFolder(in: "x \"/a/b/c/d.txt\": permission denied", localPath: "/a/b"), "c")
        XCTAssertEqual(StatusStore.unreadableFolder(in: "x \"/a/b/c/d.txt\": permission denied", localPath: nil), "/a/b/c")
        XCTAssertNil(StatusStore.unreadableFolder(in: "x \"/a/b/c\": no such file", localPath: "/a/b"))
        XCTAssertNil(StatusStore.unreadableFolder(in: nil, localPath: "/a/b"))
    }

    // MARK: - Retry backoff

    func testRetryDelayDoublesAndCaps() {
        XCTAssertEqual(StatusStore.retryDelay(afterFailures: 1), 60)
        XCTAssertEqual(StatusStore.retryDelay(afterFailures: 2), 120)
        XCTAssertEqual(StatusStore.retryDelay(afterFailures: 5), 960)
        XCTAssertEqual(StatusStore.retryDelay(afterFailures: 6), 1800)
        XCTAssertEqual(StatusStore.retryDelay(afterFailures: 50), 1800)
    }

    // MARK: - Error subtitle

    func testErrorSubtitleAppendsStreakAfterAnHour() {
        var job = makeJob(status: .error)
        job.errorMessage = "Some files failed — nothing deleted"
        XCTAssertEqual(job.errorSubtitle, "Some files failed — nothing deleted")
        job.failingSince = Date().addingTimeInterval(-30 * 60)
        XCTAssertEqual(job.errorSubtitle, "Some files failed — nothing deleted")
        job.failingSince = Date().addingTimeInterval(-5 * 3600)
        XCTAssertEqual(job.errorSubtitle, "Some files failed — nothing deleted · failing for 5h")
        job.failingSince = Date().addingTimeInterval(-12 * 86400)
        XCTAssertEqual(job.errorSubtitle, "Some files failed — nothing deleted · failing for 12 days")
    }

    func testErrorTooltipCombinesCountAndDetail() {
        var job = makeJob(status: .error)
        XCTAssertNil(job.errorTooltip)
        job.errors = 3
        job.lastErrorDetail = "lstat x: permission denied"
        XCTAssertEqual(job.errorTooltip, "3 files failed\nlstat x: permission denied")
    }

    // MARK: - Helper

    private func makeJob(
        id: String = "1",
        status: JobStatus = .ok,
        isRunning: Bool = false,
        lastSync: Date? = nil,
        direction: SyncDirection = .upload
    ) -> SyncJob {
        var job = SyncJob(id: id, name: "Test", status: status,
                          lastSync: lastSync, errors: 0, isRunning: isRunning)
        job.direction = direction
        return job
    }
}
