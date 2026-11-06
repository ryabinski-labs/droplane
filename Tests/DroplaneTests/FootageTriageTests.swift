import XCTest
@testable import Droplane
@testable import TransferCore

final class MediaClassificationTests: XCTestCase {
    func testVideosAndPhotosAreClassifiedByUniformType() {
        XCTAssertEqual(MediaClassifier.kind(of: "PrimeCam_20261030_1421.mov"), .video)
        XCTAssertEqual(MediaClassifier.kind(of: "VID_20261029_1802.MP4"), .video)
        XCTAssertEqual(MediaClassifier.kind(of: "IMG_20261030_0001.jpg"), .photo)
        XCTAssertEqual(MediaClassifier.kind(of: "IMG_20261030_0002.HEIC"), .photo)
        XCTAssertEqual(MediaClassifier.kind(of: "boarding-pass.pdf"), .other)
        XCTAssertEqual(MediaClassifier.kind(of: "notes: draft.txt"), .other)
        XCTAssertEqual(MediaClassifier.kind(of: "no-extension"), .other)
    }

    func testDimensionsMapToOrientation() {
        XCTAssertEqual(MediaDimensions(width: 1080, height: 1920).orientation, .vertical)
        XCTAssertEqual(MediaDimensions(width: 3840, height: 2160).orientation, .horizontal)
        XCTAssertEqual(MediaDimensions(width: 1080, height: 1080).orientation, .square)
    }

    func testOrientationFilterMatchesOnlyVideosInThatDirection() {
        let horizontal = MediaOrientation.horizontal
        let vertical = MediaOrientation.vertical

        XCTAssertTrue(MediaFilter.horizontalVideos.matches(name: "clip.mov", orientation: horizontal))
        XCTAssertFalse(MediaFilter.horizontalVideos.matches(name: "clip.mov", orientation: vertical))
        XCTAssertFalse(MediaFilter.horizontalVideos.matches(name: "photo.jpg", orientation: horizontal))
        XCTAssertFalse(MediaFilter.horizontalVideos.matches(name: "clip.mov", orientation: nil))

        XCTAssertTrue(MediaFilter.verticalVideos.matches(name: "clip.mov", orientation: vertical))
        XCTAssertFalse(MediaFilter.verticalVideos.matches(name: "clip.mov", orientation: horizontal))
        XCTAssertFalse(MediaFilter.verticalVideos.matches(name: "clip.mov", orientation: .square))
    }

    func testFoldersStayVisibleInEveryMode() {
        for filter in MediaFilter.allCases {
            XCTAssertTrue(filter.includes(isFolder: true, name: "Camera", orientation: nil), filter.title)
            XCTAssertTrue(filter.includes(isFolder: true, name: "Camera", orientation: .horizontal), filter.title)
        }
    }

    func testVideosAndPhotosModesKeepTheirOwnMediaOnly() {
        XCTAssertTrue(MediaFilter.videos.matches(name: "clip.mov", orientation: .vertical))
        XCTAssertFalse(MediaFilter.videos.matches(name: "photo.jpg", orientation: .horizontal))
        XCTAssertTrue(MediaFilter.photos.matches(name: "photo.jpg", orientation: .horizontal))
        XCTAssertFalse(MediaFilter.photos.matches(name: "clip.mov", orientation: .horizontal))
        XCTAssertTrue(MediaFilter.all.matches(name: "notes.txt", orientation: nil))
    }
}

final class JPEGDimensionsTests: XCTestCase {
    func testReadsWidthAndHeightFromASOF0Header() {
        let jpeg = Data([
            0xFF, 0xD8,             // start of image
            0xFF, 0xC0,             // SOF0
            0x00, 0x11,             // segment length
            0x08,                   // precision
            0x04, 0x38,             // height 1080
            0x07, 0x80,             // width 1920
            0x03,                   // components
            0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
            0xFF, 0xD9,             // end of image
        ])
        let size = JPEGDimensions.size(in: jpeg)
        XCTAssertEqual(size?.width, 1920)
        XCTAssertEqual(size?.height, 1080)
    }

    func testRejectsNonJPEGData() {
        XCTAssertNil(JPEGDimensions.size(in: Data([0x89, 0x50, 0x4E, 0x47])))
        XCTAssertNil(JPEGDimensions.size(in: Data()))
    }
}

@MainActor
final class FootageTriageModelTests: XCTestCase {
    func testSuccessfulDownloadMarksThePhoneFileCopied() async throws {
        let model = AppModel()
        model.connectDemo()
        try await waitUntil { model.device != nil }

        let file = try await demoFile("notes: draft.txt", inFolder: "Download", model: model)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertFalse(model.isCopied(file))
        model.enqueueDownloads([PhoneRef(storage: 1, entry: file)], into: dir)
        try await waitUntil { model.activeCount == 0 }

        XCTAssertTrue(model.isCopied(file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(NameSanitizer.forMac(file.name)).path))
    }

    func testAFileQueuedWithoutTheMarkFlagDoesNotBecomeCopied() async throws {
        let model = AppModel()
        model.connectDemo()
        try await waitUntil { model.device != nil }

        let file = try await demoFile("notes: draft.txt", inFolder: "Download", model: model)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        model.enqueueDownloads([PhoneRef(storage: 1, entry: file)], into: dir, marksCopied: false)
        try await waitUntil { model.activeCount == 0 }

        XCTAssertFalse(model.isCopied(file))
    }

    func testDemoDeviceReportsAVarietyOfOrientations() throws {
        let device = DemoDevice()
        let root = try device.list(storage: 1, folder: 0)
        let dcim = try XCTUnwrap(root.first { $0.name == "DCIM" })
        let dcimKids = try device.list(storage: 1, folder: dcim.id)
        let camera = try XCTUnwrap(dcimKids.first { $0.name == "Camera" })
        let entries = try device.list(storage: 1, folder: camera.id)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

        XCTAssertEqual(try device.dimensions(of: byName["VID_20261029_1802.mp4"]!)?.orientation, .horizontal)
        XCTAssertEqual(try device.dimensions(of: byName["VID_20261029_1803_vertical.mp4"]!)?.orientation, .vertical)
        XCTAssertEqual(try device.dimensions(of: byName["VID_20261029_1805_square.mp4"]!)?.orientation, .square)
        XCTAssertEqual(try device.dimensions(of: byName["IMG_20261030_0006.jpg"]!)?.orientation, .square)
        XCTAssertNil(try device.dimensions(of: byName["VID_20261030_0900_no-thumbnail.mov"]!))
    }

    /// The full filter pipeline: loading a phone folder, checking every video,
    /// hiding non-matches, and counting the one file the phone cannot describe.
    func testHorizontalAndVerticalFiltersShowOnlyMatchingVideos() async throws {
        let (model, browser) = try await cameraBrowser()

        browser.setFilter(.horizontalVideos, model: model)
        try await waitUntil {
            !browser.isCheckingOrientation && browser.orientationTotal == 4
                && browser.orientationDone == browser.orientationTotal
        }

        XCTAssertEqual(browser.nodes.map(\.name), ["VID_20261029_1802.mp4"])
        XCTAssertEqual(browser.orientationFailed, 1)
        XCTAssertEqual(browser.orientationTotal, 4)
        XCTAssertEqual(browser.statusText(model).hasPrefix("1 of 16 items"), true)
        XCTAssertEqual(browser.nodes.filter { !$0.isFolder }.compactMap(\.phoneRef).count, 1)
        XCTAssertEqual(browser.shownPhoneRefs.map(\.entry.name), ["VID_20261029_1802.mp4"])

        browser.selection = browser.nodes
        browser.setFilter(.verticalVideos, model: model)
        try await waitUntil { !browser.isCheckingOrientation }
        XCTAssertEqual(browser.nodes.map(\.name), ["VID_20261029_1803_vertical.mp4"])
        XCTAssertTrue(browser.selection.isEmpty)

        browser.setFilter(.videos, model: model)
        XCTAssertEqual(browser.nodes.count, 4)
        browser.setFilter(.photos, model: model)
        XCTAssertEqual(browser.nodes.count, 12)
        browser.setFilter(.all, model: model)
        XCTAssertEqual(browser.nodes.count, 16)
    }

    /// A lazy cell request and the filter must share one phone request; otherwise
    /// switching filters mid-load counts the file as a failure.
    func testFilterSwitchDuringALazyOrientationRequestDoesNotCountAFalseFailure() async throws {
        let (model, browser) = try await cameraBrowser()
        let horizontal = try XCTUnwrap(browser.allNodes.first { $0.name == "VID_20261029_1802.mp4" })

        browser.requestOrientation(for: horizontal, model: model)
        try await Task.sleep(for: .milliseconds(30))
        browser.setFilter(.horizontalVideos, model: model)
        try await waitUntil {
            !browser.isCheckingOrientation && browser.orientationDone == browser.orientationTotal
        }

        XCTAssertEqual(browser.orientationFailed, 1)
        XCTAssertEqual(browser.nodes.map(\.name), ["VID_20261029_1802.mp4"])
    }

    private func cameraBrowser() async throws -> (AppModel, BrowserState) {
        let model = AppModel()
        model.connectDemo()
        try await waitUntil { model.device != nil }
        let device = try XCTUnwrap(model.device as? DemoDevice)
        let root = try device.list(storage: 1, folder: 0)
        let dcim = try XCTUnwrap(root.first { $0.name == "DCIM" })
        let dcimKids = try device.list(storage: 1, folder: dcim.id)
        let camera = try XCTUnwrap(dcimKids.first { $0.name == "Camera" })

        let browser = BrowserState()
        browser.go(.phone(storage: 1, path: [
            Crumb(id: dcim.id, name: dcim.name),
            Crumb(id: camera.id, name: camera.name),
        ]), model)
        try await waitUntil { !browser.isLoading && browser.allNodes.count == 16 }
        XCTAssertEqual(browser.nodes.count, 16)
        return (model, browser)
    }

    private func demoFile(_ name: String, inFolder folderName: String, model: AppModel) async throws -> DeviceEntry {
        guard case .success(let root) = await model.listPhone(storage: 1, folder: 0),
              let folder = root.first(where: { $0.name == folderName }) else {
            throw XCTSkip("Demo folder \(folderName) not found")
        }
        guard case .success(let children) = await model.listPhone(storage: 1, folder: folder.id),
              let file = children.first(where: { $0.name == name }) else {
            throw XCTSkip("Demo file \(name) not found")
        }
        return file
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }
}
