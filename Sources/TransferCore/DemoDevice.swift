import Foundation

/// In-memory fake phone so the app can be shown without hardware (A-005).
public final class DemoDevice: MTPDevice, @unchecked Sendable {
    public let displayName = "Demo Phone"
    private let lock = NSLock()
    private var nodes: [UInt32: (entry: DeviceEntry, parent: UInt32, storage: UInt32, data: Data?)] = [:]
    private var nextID: UInt32 = 100
    public var delayPerChunk: TimeInterval = 0.02

    public init() {
        let now = Date()
        func add(_ name: String, folder: Bool, parent: UInt32, size: Int = 0) -> UInt32 {
            let id = nextID; nextID += 1
            nodes[id] = (DeviceEntry(id: id, name: name, isFolder: folder, size: UInt64(size), modified: now.addingTimeInterval(-Double(id) * 3600)), parent, 1, folder ? nil : Data(count: size))
            return id
        }
        let dcim = add("DCIM", folder: true, parent: 0)
        let cam = add("Camera", folder: true, parent: dcim)
        for i in 1...12 { _ = add("IMG_20261030_\(String(format: "%04d", i)).jpg", folder: false, parent: cam, size: 2_400_000 + i * 90_000) }
        _ = add("VID_20261029_1802.mp4", folder: false, parent: cam, size: 48_000_000)
        let dl = add("Download", folder: true, parent: 0)
        _ = add("boarding-pass.pdf", folder: false, parent: dl, size: 310_000)
        _ = add("notes: draft.txt", folder: false, parent: dl, size: 1_200)
        _ = add("Pictures", folder: true, parent: 0)
        _ = add(".thumbnails", folder: true, parent: 0)
        let movies = add("Movies", folder: true, parent: 0)
        let prime = add("PrimeCam", folder: true, parent: movies)
        _ = add("PrimeCam_20261030_1421.mp4", folder: false, parent: prime, size: 220_000_000)
    }

    public func storages() throws -> [StorageInfo] {
        [StorageInfo(id: 1, name: "Internal storage", capacity: 128_000_000_000, free: 61_000_000_000)]
    }
    public func list(storage: UInt32, folder: UInt32) throws -> [DeviceEntry] {
        lock.lock(); defer { lock.unlock() }
        return nodes.values.filter { $0.parent == folder && $0.storage == storage }.map(\.entry)
            .sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
    }
    public func download(_ entry: DeviceEntry, to url: URL, progress: @Sendable (UInt64) -> Bool) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url); defer { try? h.close() }
        let chunk = 1_000_000; var done: UInt64 = 0
        while done < entry.size {
            let n = min(UInt64(chunk), entry.size - done)
            try h.write(contentsOf: Data(count: Int(n))); done += n
            Thread.sleep(forTimeInterval: delayPerChunk)
            if !progress(done) { try? FileManager.default.removeItem(at: url); throw DeviceError.cancelled }
        }
    }
    public func upload(from url: URL, storage: UInt32, folder: UInt32, name: String, progress: @Sendable (UInt64) -> Bool) throws -> UInt32 {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        var done: UInt64 = 0
        while done < size {
            done = min(size, done + 1_000_000)
            Thread.sleep(forTimeInterval: delayPerChunk)
            if !progress(done) { throw DeviceError.cancelled }
        }
        lock.lock(); defer { lock.unlock() }
        let id = nextID; nextID += 1
        nodes[id] = (DeviceEntry(id: id, name: name, isFolder: false, size: size, modified: Date()), folder, storage, nil)
        return id
    }
    public func rename(_ entry: DeviceEntry, to name: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard var n = nodes[entry.id] else { throw DeviceError.other("Not found") }
        n.entry = DeviceEntry(id: entry.id, name: name, isFolder: entry.isFolder, size: entry.size, modified: entry.modified)
        nodes[entry.id] = n
    }
    public func delete(_ entry: DeviceEntry) throws {
        lock.lock(); defer { lock.unlock() }
        nodes[entry.id] = nil
        for (k, v) in nodes where v.parent == entry.id { nodes[k] = nil }
    }
    public func makeFolder(storage: UInt32, parent: UInt32, name: String) throws -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        let id = nextID; nextID += 1
        nodes[id] = (DeviceEntry(id: id, name: name, isFolder: true, size: 0, modified: Date()), parent, storage, nil)
        return id
    }
}
