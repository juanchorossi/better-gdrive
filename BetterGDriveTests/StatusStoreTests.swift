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

    func testMenuBarSuffixNowForRecentSync() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -30))]
        XCTAssertEqual(store.menuBarSuffix, L.General.now)
    }

    func testMenuBarSuffixMinutes() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -300))]
        XCTAssertEqual(store.menuBarSuffix, "5m")
    }

    func testMenuBarSuffixHours() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -7200))]
        XCTAssertEqual(store.menuBarSuffix, "2h")
    }

    func testMenuBarSuffixDays() {
        let store = StatusStore()
        store.jobs = [makeJob(lastSync: Date(timeIntervalSinceNow: -172_800))]
        XCTAssertEqual(store.menuBarSuffix, "2d")
    }

    func testMenuBarSuffixEmptyWhileRunning() {
        let store = StatusStore()
        store.jobs = [makeJob(status: .running, isRunning: true, lastSync: Date())]
        // Running job with no progress — suffix should be empty string
        XCTAssertEqual(store.menuBarSuffix, "")
    }

    func testMenuBarSuffixShowsOldestSync() {
        let store = StatusStore()
        store.jobs = [
            makeJob(id: "a", lastSync: Date(timeIntervalSinceNow: -600)),   // 10 min
            makeJob(id: "b", lastSync: Date(timeIntervalSinceNow: -7200)),  // 2 h (oldest)
        ]
        // menuBarSuffix uses the oldest lastSync
        XCTAssertEqual(store.menuBarSuffix, "2h")
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

    // MARK: - Helper

    private func makeJob(
        id: String = "1",
        status: JobStatus = .ok,
        isRunning: Bool = false,
        lastSync: Date? = nil
    ) -> SyncJob {
        SyncJob(id: id, name: "Test", status: status,
                lastSync: lastSync, errors: 0, isRunning: isRunning)
    }
}
