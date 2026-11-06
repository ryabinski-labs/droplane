import Foundation
import UniformTypeIdentifiers

/// What a phone file looks like to the media filter, judged by its extension.
public enum MediaKind: Sendable {
    case video
    case photo
    case other
}

public enum MediaClassifier {
    /// macOS already knows which extensions are movies and images, so use its
    /// type database instead of a hand-written list that ages badly.
    public static func kind(of name: String) -> MediaKind {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .image) { return .photo }
        return .other
    }

    public static func isVideo(_ name: String) -> Bool { kind(of: name) == .video }
    public static func isPhoto(_ name: String) -> Bool { kind(of: name) == .photo }
}

/// The five things the phone list can show.
public enum MediaFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case videos
    case photos
    case horizontalVideos
    case verticalVideos

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .videos: return "Videos"
        case .photos: return "Photos"
        case .horizontalVideos: return "Horizontal videos"
        case .verticalVideos: return "Vertical videos"
        }
    }

    /// Compact title for the toolbar pop-up.
    public var shortTitle: String {
        switch self {
        case .all: return "All"
        case .videos: return "Videos"
        case .photos: return "Photos"
        case .horizontalVideos: return "Horizontal"
        case .verticalVideos: return "Vertical"
        }
    }

    public var emptyTitle: String {
        switch self {
        case .all: return "No items in this folder"
        case .videos: return "No videos in this folder"
        case .photos: return "No photos in this folder"
        case .horizontalVideos: return "No horizontal videos in this folder"
        case .verticalVideos: return "No vertical videos in this folder"
        }
    }

    /// Only these two modes need every video's dimensions before the list is
    /// complete, because a file cannot be shown until it is known to match.
    public var requiresOrientationCheck: Bool {
        self == .horizontalVideos || self == .verticalVideos
    }

    /// Whether a file belongs in the current mode. Folders are kept by the
    /// browser for navigation, so the caller only asks about files.
    public func matches(name: String, orientation: MediaOrientation?) -> Bool {
        switch self {
        case .all:
            return true
        case .videos:
            return MediaClassifier.isVideo(name)
        case .photos:
            return MediaClassifier.isPhoto(name)
        case .horizontalVideos:
            return MediaClassifier.isVideo(name) && orientation == .horizontal
        case .verticalVideos:
            return MediaClassifier.isVideo(name) && orientation == .vertical
        }
    }

    /// Folders stay visible in every mode so the user can keep navigating.
    public func includes(isFolder: Bool, name: String, orientation: MediaOrientation?) -> Bool {
        isFolder || matches(name: name, orientation: orientation)
    }
}

public enum MediaOrientation: String, Sendable, Equatable {
    case vertical
    case horizontal
    case square

    public var label: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        case .square: return "Square"
        }
    }

    public var symbolName: String {
        switch self {
        case .vertical: return "rectangle.portrait"
        case .horizontal: return "rectangle.landscape"
        case .square: return "square"
        }
    }
}

/// Pixel size read from the phone's representative sample or thumbnail.
public struct MediaDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var orientation: MediaOrientation {
        if width == height { return .square }
        return width > height ? .horizontal : .vertical
    }
}

/// Reads pixel dimensions from a JPEG header without decoding the image.
public enum JPEGDimensions {
    public static func size(in data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var i = 2
        while i + 3 < bytes.count {
            guard bytes[i] == 0xFF else {
                i += 1
                continue
            }
            var marker = bytes[i + 1]
            while marker == 0xFF, i + 3 < bytes.count {
                i += 1
                marker = bytes[i + 1]
            }
            i += 2
            // Standalone markers carry no length field.
            if marker == 0xD8 || marker == 0xD9 || (0xD0...0xD7).contains(marker) || marker == 0x01 { continue }
            // Start of scan: the frame header, if any, came before this point.
            if marker == 0xDA { return nil }
            guard i + 1 < bytes.count else { return nil }
            let length = Int(bytes[i]) << 8 | Int(bytes[i + 1])
            guard length >= 2 else { return nil }
            // SOF0 through SOF15, excluding the non-frame markers DHT, DAC, and JPG.
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                guard i + 6 < bytes.count else { return nil }
                let height = Int(bytes[i + 3]) << 8 | Int(bytes[i + 4])
                let width = Int(bytes[i + 5]) << 8 | Int(bytes[i + 6])
                guard width > 0, height > 0 else { return nil }
                return (width, height)
            }
            i += length
        }
        return nil
    }
}
