import Foundation
import CLibMTP
import TransferCore

/// libmtp is not thread-safe, so every call goes through one lock.
private let mtpLock = NSRecursiveLock()
private let initOnce: Void = { LIBMTP_Init() }()

private final class ProgressBox {
    let report: (UInt64) -> Bool
    var stopped = false
    init(_ r: @escaping (UInt64) -> Bool) { report = r }
}

private let progressCallback: LIBMTP_progressfunc_t = { sent, _, data in
    guard let data else { return 0 }
    let box = Unmanaged<ProgressBox>.fromOpaque(data).takeUnretainedValue()
    if box.report(sent) { return 0 }
    box.stopped = true
    return 1
}

public enum MTPProbe {
    /// Number of MTP devices on the bus, without opening them.
    public static func rawDeviceCount() -> Int {
        _ = initOnce
        mtpLock.lock(); defer { mtpLock.unlock() }
        var raw: UnsafeMutablePointer<LIBMTP_raw_device_t>?
        var n: Int32 = 0
        let err = LIBMTP_Detect_Raw_Devices(&raw, &n)
        defer { free(raw) }
        return err == LIBMTP_ERROR_NONE ? Int(n) : 0
    }

    /// Opens the first MTP device. Throws `.busy` if another app holds it.
    public static func openFirst() throws -> LibMTPDevice? {
        _ = initOnce
        mtpLock.lock(); defer { mtpLock.unlock() }
        var raw: UnsafeMutablePointer<LIBMTP_raw_device_t>?
        var n: Int32 = 0
        let err = LIBMTP_Detect_Raw_Devices(&raw, &n)
        defer { free(raw) }
        guard err == LIBMTP_ERROR_NONE, n > 0, let raw else { return nil }
        guard let dev = LIBMTP_Open_Raw_Device_Uncached(raw) else { throw DeviceError.busy }
        return LibMTPDevice(dev)
    }
}

public final class LibMTPDevice: MTPDevice, @unchecked Sendable {
    private let dev: UnsafeMutablePointer<LIBMTP_mtpdevice_t>
    public let displayName: String

    init(_ dev: UnsafeMutablePointer<LIBMTP_mtpdevice_t>) {
        self.dev = dev
        func take(_ p: UnsafeMutablePointer<CChar>?) -> String? {
            guard let p else { return nil }; defer { free(p) }; return String(cString: p)
        }
        let maker = take(LIBMTP_Get_Manufacturername(dev)) ?? ""
        let model = take(LIBMTP_Get_Modelname(dev)) ?? "Android phone"
        displayName = maker.isEmpty || model.hasPrefix(maker) ? model : "\(maker) \(model)"
    }

    deinit {
        mtpLock.lock(); LIBMTP_Release_Device(dev); mtpLock.unlock()
    }

    private func lastError(_ fallback: String) -> DeviceError {
        var msg = fallback
        if let stack = LIBMTP_Get_Errorstack(dev), let text = stack.pointee.error_text { msg = String(cString: text) }
        LIBMTP_Clear_Errorstack(dev)
        if MTPProbe.rawDeviceCount() == 0 { return .disconnected }
        return .other(msg)
    }

    public func storages() throws -> [StorageInfo] {
        mtpLock.lock(); defer { mtpLock.unlock() }
        guard LIBMTP_Get_Storage(dev, Int32(LIBMTP_STORAGE_SORTBY_NOTSORTED)) == 0 else { throw DeviceError.locked }
        var out: [StorageInfo] = []
        var s = dev.pointee.storage
        while let st = s {
            let name = st.pointee.StorageDescription.map { String(cString: $0) } ?? "Storage"
            out.append(StorageInfo(id: st.pointee.id, name: name, capacity: st.pointee.MaxCapacity, free: st.pointee.FreeSpaceInBytes))
            s = st.pointee.next
        }
        // A locked Android phone exposes no storage.
        if out.isEmpty { throw DeviceError.locked }
        return out
    }

    public func list(storage: UInt32, folder: UInt32) throws -> [DeviceEntry] {
        mtpLock.lock(); defer { mtpLock.unlock() }
        let parent = folder == 0 ? LIBMTP_FILES_AND_FOLDERS_ROOT : folder
        var out: [DeviceEntry] = []
        var f = LIBMTP_Get_Files_And_Folders(dev, storage, parent)
        // NULL is also what an empty folder returns, so only the error stack tells a failure apart.
        if f == nil, LIBMTP_Get_Errorstack(dev) != nil { throw lastError("Couldn't open this folder") }
        while let file = f {
            let name = file.pointee.filename.map { String(cString: $0) } ?? "?"
            out.append(DeviceEntry(id: file.pointee.item_id, name: name,
                                   isFolder: file.pointee.filetype == LIBMTP_FILETYPE_FOLDER,
                                   size: file.pointee.filesize,
                                   modified: Date(timeIntervalSince1970: TimeInterval(file.pointee.modificationdate))))
            f = file.pointee.next
            LIBMTP_destroy_file_t(file)
        }
        return out.sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
    }

    public func download(_ entry: DeviceEntry, to url: URL, progress: @Sendable (UInt64) -> Bool) throws {
        try withoutActuallyEscaping(progress) { p in
            let box = Unmanaged.passRetained(ProgressBox(p)); defer { box.release() }
            mtpLock.lock(); defer { mtpLock.unlock() }
            if LIBMTP_Get_File_To_File(dev, entry.id, url.path, progressCallback, box.toOpaque()) != 0 {
                try? FileManager.default.removeItem(at: url)
                throw box.takeUnretainedValue().stopped ? DeviceError.cancelled : lastError("Couldn't copy \(entry.name)")
            }
        }
    }

    public func upload(from url: URL, storage: UInt32, folder: UInt32, name: String, progress: @Sendable (UInt64) -> Bool) throws -> UInt32 {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        return try withoutActuallyEscaping(progress) { p in
            let box = Unmanaged.passRetained(ProgressBox(p)); defer { box.release() }
            mtpLock.lock(); defer { mtpLock.unlock() }
            guard let meta = LIBMTP_new_file_t() else { throw DeviceError.other("Out of memory") }
            defer { LIBMTP_destroy_file_t(meta) }
            meta.pointee.filename = strdup(name)
            meta.pointee.filesize = size
            meta.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
            meta.pointee.parent_id = folder
            meta.pointee.storage_id = storage
            if LIBMTP_Send_File_From_File(dev, url.path, meta, progressCallback, box.toOpaque()) != 0 {
                if box.takeUnretainedValue().stopped { throw DeviceError.cancelled }
                let e = lastError("Couldn't copy \(name)")
                if case .other(let m) = e, m.localizedCaseInsensitiveContains("space") || m.localizedCaseInsensitiveContains("full") { throw DeviceError.noSpaceOnPhone }
                throw e
            }
            return meta.pointee.item_id
        }
    }

    public func rename(_ entry: DeviceEntry, to name: String) throws {
        mtpLock.lock(); defer { mtpLock.unlock() }
        if LIBMTP_Set_Object_String(dev, entry.id, LIBMTP_PROPERTY_ObjectFileName, name) != 0 { throw lastError("Couldn't rename \(entry.name)") }
    }

    public func delete(_ entry: DeviceEntry) throws {
        mtpLock.lock(); defer { mtpLock.unlock() }
        if LIBMTP_Delete_Object(dev, entry.id) != 0 { throw lastError("Couldn't delete \(entry.name)") }
    }

    public func makeFolder(storage: UInt32, parent: UInt32, name: String) throws -> UInt32 {
        mtpLock.lock(); defer { mtpLock.unlock() }
        let cname = strdup(name); defer { free(cname) }
        let id = LIBMTP_Create_Folder(dev, cname, parent, storage)
        if id == 0 { throw lastError("Couldn't create \(name)") }
        return id
    }
}
