import Foundation

public struct DeviceEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UInt32
    public let name: String
    public let isFolder: Bool
    public let size: UInt64
    public let modified: Date
    public init(id: UInt32, name: String, isFolder: Bool, size: UInt64, modified: Date) {
        self.id = id; self.name = name; self.isFolder = isFolder; self.size = size; self.modified = modified
    }
}

public struct StorageInfo: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let name: String
    public let capacity: UInt64
    public let free: UInt64
    public init(id: UInt32, name: String, capacity: UInt64, free: UInt64) {
        self.id = id; self.name = name; self.capacity = capacity; self.free = free
    }
}

public enum DeviceError: Error, Equatable, LocalizedError, Sendable {
    case locked
    case busy
    case disconnected
    case noSpaceOnPhone
    case noSpaceOnMac(needed: UInt64, available: UInt64)
    case cancelled
    case other(String)

    public var errorDescription: String? {
        switch self {
        case .locked: return "Unlock your phone and choose File transfer (MTP) in the USB notification"
        case .busy: return "Another app is using your phone. Quit Android File Transfer, Samsung Smart Switch, or any other phone manager, then press Refresh"
        case .disconnected: return "Phone disconnected"
        case .noSpaceOnPhone: return "Not enough space on the phone"
        case .noSpaceOnMac(let n, let a):
            let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useGB]
            return "Not enough space on the Mac: needs \(f.string(fromByteCount: Int64(n))), has \(f.string(fromByteCount: Int64(a)))"
        case .cancelled: return "Cancelled"
        case .other(let m): return m
        }
    }
}

/// Abstraction over libmtp. Folder id 0 is a storage root.
public protocol MTPDevice: AnyObject, Sendable {
    var displayName: String { get }
    func storages() throws -> [StorageInfo]
    func list(storage: UInt32, folder: UInt32) throws -> [DeviceEntry]
    func download(_ entry: DeviceEntry, to url: URL, progress: @Sendable (UInt64) -> Bool) throws
    /// Returns the new object's id.
    func upload(from url: URL, storage: UInt32, folder: UInt32, name: String, progress: @Sendable (UInt64) -> Bool) throws -> UInt32
    func rename(_ entry: DeviceEntry, to name: String) throws
    func delete(_ entry: DeviceEntry) throws
    /// Returns the new folder's id.
    func makeFolder(storage: UInt32, parent: UInt32, name: String) throws -> UInt32
}
