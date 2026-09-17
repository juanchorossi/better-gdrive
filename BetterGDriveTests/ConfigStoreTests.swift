import XCTest
@testable import Better_GDrive

final class ConfigStoreTests: XCTestCase {

    // Back up and restore the real config file around every test.
    private var originalConfigData: Data?

    override func setUp() {
        super.setUp()
        originalConfigData = try? Data(contentsOf: ConfigStore.configURL)
        // Seed a clean empty config so each test is independent.
        let empty = SyncConfig(bwlimit: "off", jobs: [])
        if let data = try? JSONEncoder().encode(empty) {
            try? data.write(to: ConfigStore.configURL)
        }
    }

    override func tearDown() {
        if let data = originalConfigData {
            try? data.write(to: ConfigStore.configURL)
        } else {
            try? FileManager.default.removeItem(at: ConfigStore.configURL)
        }
        super.tearDown()
    }

    // MARK: - addJob

    func testAddJobAppendsToConfig() {
        let store = ConfigStore()
        XCTAssertTrue(store.config.jobs.isEmpty)

        store.addJob(makeJob(id: "j1"))

        XCTAssertEqual(store.config.jobs.count, 1)
        XCTAssertEqual(store.config.jobs[0].id, "j1")
    }

    func testAddMultipleJobsPreservesOrder() {
        let store = ConfigStore()
        store.addJob(makeJob(id: "a"))
        store.addJob(makeJob(id: "b"))
        store.addJob(makeJob(id: "c"))

        XCTAssertEqual(store.config.jobs.map(\.id), ["a", "b", "c"])
    }

    func testAddJobPersistsToDisk() {
        let store = ConfigStore()
        store.addJob(makeJob(id: "persisted"))

        let reloaded = ConfigStore()
        XCTAssertTrue(reloaded.config.jobs.contains { $0.id == "persisted" })
    }

    // MARK: - removeJob

    func testRemoveJobDeletesFromConfig() {
        let store = ConfigStore()
        store.addJob(makeJob(id: "to-remove"))
        store.addJob(makeJob(id: "keep"))

        store.removeJob(id: "to-remove")

        XCTAssertFalse(store.config.jobs.contains { $0.id == "to-remove" })
        XCTAssertTrue(store.config.jobs.contains { $0.id == "keep" })
    }

    func testRemoveNonExistentJobIsNoop() {
        let store = ConfigStore()
        store.addJob(makeJob(id: "real"))
        let before = store.config.jobs.count

        store.removeJob(id: "ghost")

        XCTAssertEqual(store.config.jobs.count, before)
    }

    func testRemoveJobPersistsToDisk() {
        let store = ConfigStore()
        store.addJob(makeJob(id: "gone"))
        store.removeJob(id: "gone")

        let reloaded = ConfigStore()
        XCTAssertFalse(reloaded.config.jobs.contains { $0.id == "gone" })
    }

    // MARK: - updateJob

    func testUpdateJobChangesName() {
        let store = ConfigStore()
        store.addJob(makeJob(id: "u1", name: "Original"))

        var updated = makeJob(id: "u1", name: "Updated")
        store.updateJob(updated)

        XCTAssertEqual(store.config.jobs.first { $0.id == "u1" }?.name, "Updated")
    }

    func testUpdateJobChangesLocalPath() {
        let store = ConfigStore()
        store.addJob(makeJob(id: "u2", localPath: "~/Old"))

        store.updateJob(makeJob(id: "u2", localPath: "~/New"))

        XCTAssertEqual(store.config.jobs.first { $0.id == "u2" }?.localPath, "~/New")
    }

    func testUpdateNonExistentJobIsNoop() {
        let store = ConfigStore()
        let before = store.config.jobs.count

        store.updateJob(makeJob(id: "nobody"))

        XCTAssertEqual(store.config.jobs.count, before)
    }

    func testUpdateJobPersistsToDisk() {
        let store = ConfigStore()
        store.addJob(makeJob(id: "p1", name: "Before"))
        store.updateJob(makeJob(id: "p1", name: "After"))

        let reloaded = ConfigStore()
        XCTAssertEqual(reloaded.config.jobs.first { $0.id == "p1" }?.name, "After")
    }

    // MARK: - Default config

    func testDefaultConfigWhenFileIsMissing() {
        try? FileManager.default.removeItem(at: ConfigStore.configURL)
        let store = ConfigStore()
        XCTAssertTrue(store.config.jobs.isEmpty)
        XCTAssertFalse(store.config.bwlimit.isEmpty)
    }

    // MARK: - Helper

    private func makeJob(
        id: String = "test",
        name: String = "Test",
        localPath: String = "~/Documents",
        drivePath: String = "gdrive:Docs"
    ) -> JobDefinition {
        JobDefinition(id: id, name: name, localPath: localPath,
                      drivePath: drivePath, transfers: 4, copyMode: false)
    }
}
