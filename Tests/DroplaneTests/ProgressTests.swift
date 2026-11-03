import XCTest
@testable import Droplane

/// Regression coverage for the copy bar's total progress. The bar used to drop a
/// whole batch from the denominator as soon as it finished, so copying two files
/// showed 100% for the first one and then reset to 0% for the second.
@MainActor
final class ProgressTests: XCTestCase {
    func testQueueProgressKeepsFinishedFilesUntilTheQueueIsEmpty() throws {
        let (model, dir) = try modelCopyingTwoFiles()
        defer { try? FileManager.default.removeItem(at: dir) }
        let firstTotal = model.transfers[0].total
        let secondTotal = model.transfers[1].total
        let secondDone = secondTotal / 5

        // The first file has finished; the second is halfway through its first chunk.
        model.transfers[0].state = .done
        model.transfers[0].done = firstTotal
        model.transfers[1].state = .running
        model.transfers[1].done = secondDone

        let progress = model.progress
        XCTAssertEqual(progress.overallTotal, firstTotal + secondTotal)
        XCTAssertEqual(progress.overallDone, firstTotal + secondDone)
        XCTAssertEqual(progress.fraction, Double(firstTotal + secondDone) / Double(firstTotal + secondTotal), accuracy: 0.0001)
        XCTAssertEqual(model.activeProgress, progress.fraction, accuracy: 0.0001)
        XCTAssertEqual(progress.currentName, "second.mov")
        XCTAssertEqual(progress.currentTotal, secondTotal)
        XCTAssertEqual(progress.currentDone, secondDone)
        XCTAssertEqual(progress.itemCount, 2)
        XCTAssertEqual(progress.position, 2)
        XCTAssertTrue(progress.showsPosition)
        XCTAssertTrue(progress.showsPerFileLine)
        XCTAssertFalse(progress.isPreparing)
    }

    func testQueueCycleClearsWhenTheQueueIsEmpty() async throws {
        let (model, dir) = try modelCopyingTwoFiles()
        defer { try? FileManager.default.removeItem(at: dir) }
        for _ in 0..<100 where model.activeCount > 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.activeCount, 0)
        XCTAssertTrue(model.progressBatches.isEmpty)
    }

    func testTransferProgressShowsCurrentAndOverallTotals() {
        let progress = TransferProgress(items: [
            .init(name: "first.mov", total: 204_700_000, done: 204_700_000, state: .done, isFolder: false),
            .init(name: "second.mov", total: 112_300_000, done: 20_000_000, state: .running, isFolder: false),
        ])

        XCTAssertEqual(progress.overallTotal, 317_000_000)
        XCTAssertEqual(progress.overallDone, 224_700_000)
        XCTAssertEqual(progress.fraction, 224_700_000.0 / 317_000_000.0, accuracy: 0.0001)
        XCTAssertEqual(progress.percent, 71)
        XCTAssertEqual(progress.currentName, "second.mov")
        XCTAssertEqual(progress.currentDone, 20_000_000)
        XCTAssertEqual(progress.currentTotal, 112_300_000)
        XCTAssertEqual(progress.position, 2)
        XCTAssertTrue(progress.showsPerFileLine)
        XCTAssertFalse(progress.isPreparing)
    }

    func testTransferProgressSkipsDeadBytesButKeepsThePositionCount() {
        let progress = TransferProgress(items: [
            .init(name: "cancelled.mov", total: 100, done: 50, state: .cancelled, isFolder: false),
            .init(name: "running.mov", total: 100, done: 20, state: .running, isFolder: false),
        ])

        XCTAssertEqual(progress.overallTotal, 100)
        XCTAssertEqual(progress.overallDone, 20)
        XCTAssertEqual(progress.fraction, 0.2, accuracy: 0.0001)
        XCTAssertEqual(progress.itemCount, 2)
        XCTAssertEqual(progress.position, 2)
    }

    func testTransferProgressExcludesFoldersFromItemCounts() {
        let progress = TransferProgress(items: [
            .init(name: "Camera", total: 0, done: 0, state: .running, isFolder: true),
            .init(name: "clip.mov", total: 100, done: 0, state: .queued, isFolder: false),
        ])

        XCTAssertEqual(progress.itemCount, 1)
        XCTAssertEqual(progress.overallTotal, 100)
        XCTAssertEqual(progress.currentName, "Camera")
        XCTAssertFalse(progress.currentIsFile)
        XCTAssertFalse(progress.showsPerFileLine)
    }

    func testTransferProgressPreparesWhenSizesAreUnknown() {
        let progress = TransferProgress(items: [
            .init(name: "Camera", total: 0, done: 0, state: .running, isFolder: true),
        ])

        XCTAssertEqual(progress.itemCount, 0)
        XCTAssertEqual(progress.overallTotal, 0)
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(progress.position, 0)
        XCTAssertTrue(progress.isPreparing)
    }

    func testSingleFileDoesNotShowThePerFileLine() {
        let progress = TransferProgress(items: [
            .init(name: "clip.mov", total: 100, done: 25, state: .running, isFolder: false),
        ])

        XCTAssertEqual(progress.overallDone, 25)
        XCTAssertEqual(progress.overallTotal, 100)
        XCTAssertEqual(progress.percent, 25)
        XCTAssertFalse(progress.showsPosition)
        XCTAssertFalse(progress.showsPerFileLine)
    }

    /// Creates a model with one queued batch of two real temporary files, so the
    /// queue-cycle tracking is exercised through the same path the app uses.
    private func modelCopyingTwoFiles() throws -> (AppModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = dir.appendingPathComponent("first.mov")
        let second = dir.appendingPathComponent("second.mov")
        XCTAssertTrue(FileManager.default.createFile(atPath: first.path, contents: Data(count: 2_047)))
        XCTAssertTrue(FileManager.default.createFile(atPath: second.path, contents: Data(count: 1_123)))

        let model = AppModel()
        model.enqueueUploads([first, second], storage: 1, folder: 0, folderName: "Phone")
        XCTAssertEqual(model.transfers.count, 2)
        XCTAssertEqual(model.transfers[0].name, "first.mov")
        XCTAssertEqual(model.transfers[1].name, "second.mov")
        return (model, dir)
    }
}
