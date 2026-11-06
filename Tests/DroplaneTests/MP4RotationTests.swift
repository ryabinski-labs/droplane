import XCTest
@testable import TransferCore

final class MP4RotationTests: XCTestCase {
    func testPortraitClipWithNinetyDegreeMatrix() {
        let data = moov(trak(tkhd(matrix: rotated90, width: 3840, height: 2160)))
        let result = MP4Rotation.videoTrack(in: data)
        XCTAssertEqual(result, MP4Rotation.Result(width: 2160, height: 3840, rotationDegrees: 90))
    }

    func testPortraitClipWithTwoHundredSeventyDegreeMatrix() {
        let data = moov(trak(tkhd(matrix: rotated270, width: 3840, height: 2160)))
        let result = MP4Rotation.videoTrack(in: data)
        XCTAssertEqual(result, MP4Rotation.Result(width: 2160, height: 3840, rotationDegrees: 270))
    }

    func testHorizontalClipWithIdentityMatrix() {
        let data = moov(trak(tkhd(matrix: identity, width: 3840, height: 2160)))
        let result = MP4Rotation.videoTrack(in: data)
        XCTAssertEqual(result, MP4Rotation.Result(width: 3840, height: 2160, rotationDegrees: 0))
    }

    func testUpsideDownClipDoesNotSwapWidthAndHeight() {
        let data = moov(trak(tkhd(matrix: upsideDown, width: 3840, height: 2160)))
        let result = MP4Rotation.videoTrack(in: data)
        XCTAssertEqual(result, MP4Rotation.Result(width: 3840, height: 2160, rotationDegrees: 180))
    }

    func testAudioTrackWithZeroSizeIsSkipped() {
        let audio = trak(tkhd(matrix: rotated90, width: 0, height: 0))
        let video = trak(tkhd(matrix: identity, width: 1920, height: 1080))
        let data = moov(audio + video)
        let result = MP4Rotation.videoTrack(in: data)
        XCTAssertEqual(result, MP4Rotation.Result(width: 1920, height: 1080, rotationDegrees: 0))
    }

    func testTailBufferWithLeadingMediaDataStillFindsMoov() {
        let padding = Data(repeating: 0xAB, count: 4096)
        let data = padding + moov(trak(tkhd(matrix: rotated90, width: 3840, height: 2160)))
        let result = MP4Rotation.videoTrack(in: data)
        XCTAssertEqual(result?.rotationDegrees, 90)
        XCTAssertEqual(result?.width, 2160)
        XCTAssertEqual(result?.height, 3840)
    }

    func testMissingMoovReturnsNil() {
        XCTAssertNil(MP4Rotation.videoTrack(in: Data("not an mp4".utf8)))
        XCTAssertNil(MP4Rotation.videoTrack(in: Data()))
    }

    func testTruncatedTkhdReturnsNil() {
        let full = moov(trak(tkhd(matrix: rotated90, width: 3840, height: 2160)))
        let truncated = full.prefix(full.count / 2)
        XCTAssertNil(MP4Rotation.videoTrack(in: Data(truncated)))
    }

    // MARK: - Fixtures

    private var identity: [Int32] { [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000] }
    private var rotated90: [Int32] { [0, 0x00010000, 0, -0x00010000, 0, 0, 0, 0, 0x40000000] }
    private var rotated270: [Int32] { [0, -0x00010000, 0, 0x00010000, 0, 0, 0, 0, 0x40000000] }
    private var upsideDown: [Int32] { [-0x00010000, 0, 0, 0, -0x00010000, 0, 0, 0, 0x40000000] }

    private func tkhd(matrix: [Int32], width: UInt32, height: UInt32) -> Data {
        var body = Data([0, 0, 0, 7]) // version 0, flags 7
        body.append(Data(count: 8)) // creation and modification times
        body.append(be32(1)) // track id
        body.append(Data(count: 4)) // reserved
        body.append(Data(count: 4)) // duration
        body.append(Data(count: 8)) // reserved
        body.append(Data(count: 2)) // layer
        body.append(Data(count: 2)) // alternate group
        body.append(Data(count: 2)) // volume
        body.append(Data(count: 2)) // reserved
        for value in matrix {
            var bigEndian = value.bigEndian
            withUnsafeBytes(of: &bigEndian) { body.append(contentsOf: $0) }
        }
        body.append(be32(width << 16))
        body.append(be32(height << 16))
        return box("tkhd", body)
    }

    private func trak(_ children: Data) -> Data { box("trak", children) }
    private func moov(_ children: Data) -> Data { box("moov", children) }

    private func box(_ type: String, _ payload: Data) -> Data {
        be32(UInt32(payload.count + 8)) + Data(type.utf8) + payload
    }

    private func be32(_ value: UInt32) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }
}
