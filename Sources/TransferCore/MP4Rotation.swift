import Foundation

/// Reads the display rotation from an MP4 `moov` box.
///
/// Android phones often store a portrait clip as a landscape frame plus a
/// rotation matrix in `tkhd`; width and height alone therefore say
/// "horizontal" for a vertical video. The matrix is the authoritative signal.
public enum MP4Rotation {
    public struct Result: Equatable, Sendable {
        /// Display width after applying the matrix.
        public let width: Int
        /// Display height after applying the matrix.
        public let height: Int
        /// Clockwise display rotation in degrees, normalized to 0, 90, 180, or 270.
        public let rotationDegrees: Int

        public init(width: Int, height: Int, rotationDegrees: Int) {
            self.width = width
            self.height = height
            self.rotationDegrees = rotationDegrees
        }
    }

    /// Returns the display size and rotation of the video track in an MP4
    /// fragment. `data` may be the head or tail of the file; the parser looks
    /// for a complete `moov` box inside it.
    public static func videoTrack(in data: Data) -> Result? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { return nil }

        var search = 4
        while search + 4 <= bytes.count {
            guard bytes[search] == 0x6D, bytes[search + 1] == 0x6F,
                  bytes[search + 2] == 0x6F, bytes[search + 3] == 0x76 else {
                search += 1
                continue
            }
            let moovStart = search - 4
            guard let moovSize = boxSize(bytes, at: moovStart), moovSize >= 8 else {
                search += 4
                continue
            }
            let moovEnd = min(moovStart + moovSize, bytes.count)
            if let result = parseMoov(bytes, start: moovStart + 8, end: moovEnd) {
                return result
            }
            search += 4
        }
        return nil
    }

    private static func parseMoov(_ bytes: [UInt8], start: Int, end: Int) -> Result? {
        for box in boxes(bytes, start: start, end: end) where box.type == "trak" {
            for child in boxes(bytes, start: box.body, end: box.end) where child.type == "tkhd" {
                if let result = parseTkhd(bytes, box: child) { return result }
            }
        }
        return nil
    }

    private static func parseTkhd(_ bytes: [UInt8], box: Box) -> Result? {
        guard box.body < box.end else { return nil }
        let version = bytes[box.body]
        let matrixOffset = box.body + (version == 1 ? 52 : 40)
        guard matrixOffset + 44 <= box.end else { return nil }

        let a = readInt32(bytes, at: matrixOffset)
        let b = readInt32(bytes, at: matrixOffset + 4)
        let widthFixed = readUInt32(bytes, at: matrixOffset + 36)
        let heightFixed = readUInt32(bytes, at: matrixOffset + 40)
        guard widthFixed > 0, heightFixed > 0 else { return nil } // audio or metadata track

        let encodedWidth = Int(widthFixed >> 16)
        let encodedHeight = Int(heightFixed >> 16)
        guard encodedWidth > 0, encodedHeight > 0 else { return nil }

        let angle = atan2(Double(b), Double(a)) * 180 / .pi
        let snapped = (Int((angle / 90).rounded()) * 90 % 360 + 360) % 360
        let portrait = snapped == 90 || snapped == 270
        return Result(
            width: portrait ? encodedHeight : encodedWidth,
            height: portrait ? encodedWidth : encodedHeight,
            rotationDegrees: snapped
        )
    }

    private struct Box {
        let type: String
        let start: Int
        let body: Int
        let end: Int
    }

    private static func boxes(_ bytes: [UInt8], start: Int, end: Int) -> [Box] {
        var result: [Box] = []
        var i = start
        while i + 8 <= end {
            guard let size = boxSize(bytes, at: i), size >= 8 else { break }
            let type = String(bytes: bytes[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
            let header = boxHeaderSize(bytes, at: i)
            let boxEnd = min(i + size, end)
            if boxEnd > i { result.append(Box(type: type, start: i, body: i + header, end: boxEnd)) }
            if size == 0 { break }
            i += size
        }
        return result
    }

    private static func boxHeaderSize(_ bytes: [UInt8], at index: Int) -> Int {
        guard index + 8 <= bytes.count else { return 8 }
        return readUInt32(bytes, at: index) == 1 ? 16 : 8
    }

    private static func boxSize(_ bytes: [UInt8], at index: Int) -> Int? {
        guard index + 8 <= bytes.count else { return nil }
        let size = readUInt32(bytes, at: index)
        if size == 0 { return bytes.count - index }
        if size == 1 {
            guard index + 16 <= bytes.count else { return nil }
            let large = readUInt64(bytes, at: index + 8)
            guard large <= UInt64(Int.max) else { return nil }
            return Int(large)
        }
        return Int(size)
    }

    private static func readUInt32(_ bytes: [UInt8], at index: Int) -> Int {
        guard index + 4 <= bytes.count else { return 0 }
        return Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
    }

    private static func readInt32(_ bytes: [UInt8], at index: Int) -> Int32 {
        Int32(bitPattern: UInt32(readUInt32(bytes, at: index)))
    }

    private static func readUInt64(_ bytes: [UInt8], at index: Int) -> UInt64 {
        guard index + 8 <= bytes.count else { return 0 }
        return UInt64(bytes[index]) << 56 | UInt64(bytes[index + 1]) << 48 | UInt64(bytes[index + 2]) << 40
            | UInt64(bytes[index + 3]) << 32 | UInt64(bytes[index + 4]) << 24 | UInt64(bytes[index + 5]) << 16
            | UInt64(bytes[index + 6]) << 8 | UInt64(bytes[index + 7])
    }
}
