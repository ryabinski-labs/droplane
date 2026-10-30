import AppKit
import SwiftUI
import TransferCore
import MTPBridge

/// A phone object plus the storage it lives on; also the payload of in-app drags.
struct PhoneRef: Codable, Hashable {
    let storage: UInt32
    let entry: DeviceEntry
}

final class CancelFlag: @unchecked Sendable { var cancelled = false }

/// Throttles progress updates to the main thread.
private final class Ticker: @unchecked Sendable {
    private var last = Date.distantPast
    func due() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.1 else { return false }
        last = now
        return true
    }
}

struct TransferItem: Identifiable {
    enum State: Equatable { case queued, running, done, failed(String), skipped, cancelled }
    enum Job {
        case download(PhoneRef, into: URL)
        case upload(URL, storage: UInt32, folder: UInt32, folderName: String)
    }
    let id = UUID()
    let batch: UUID
    let job: Job
    let name: String
    let destination: String
    let isFolder: Bool
    var total: UInt64
    var done: UInt64 = 0
    var state: State = .queued
    let flag = CancelFlag()

    var isFinished: Bool { state != .queued && state != .running }
    var toPhone: Bool { if case .upload = job { return true }; return false }

    func retried() -> TransferItem {
        TransferItem(batch: batch, job: job, name: name, destination: destination, isFolder: isFolder, total: total)
    }
}

struct PendingConflict: Identifiable {
    let id = UUID()
    let name: String
    let isFolder: Bool
    let toPhone: Bool
    let more: Bool
}

/// A well-known phone folder shown in the sidebar, e.g. DCIM/Camera.
struct PhonePlace: Identifiable {
    let name: String
    let symbol: String
    let location: Location
    var id: Location { location }
}

func message(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }

@Observable @MainActor
final class AppModel {
    private(set) var device: MTPDevice?
    private(set) var storages: [StorageInfo] = []
    private(set) var phonePlaces: [PhonePlace] = []
    /// Set after Eject; the phone stays disconnected until unplugged or reconnected.
    private(set) var ejectedName: String?
    /// Bumped whenever the phone or its storage list changes, so windows can re-target.
    private(set) var deviceGeneration = 0
    var hint: String?
    var showHidden = false
    var transfers: [TransferItem] = []
    var conflict: PendingConflict?
    var error: String?
    /// Bumped when a batch finishes so open folders re-list.
    private(set) var refreshToken = 0
    private(set) var transferWindowRequest = 0

    @ObservationIgnored private var watching = false
    @ObservationIgnored private var queueRunning = false
    @ObservationIgnored private var applyAll: ConflictChoice?
    @ObservationIgnored private var conflictWaiter: CheckedContinuation<(ConflictChoice, Bool), Never>?
    @ObservationIgnored private var batchWaiters: [UUID: (Error?) -> Void] = [:]
    @ObservationIgnored private var phoneNames: [String: [String: DeviceEntry]] = [:]

    var activeCount: Int { transfers.filter { !$0.isFinished }.count }

    /// Overall progress of the batches still running, for the toolbar ring.
    var activeProgress: Double {
        let batches = Set(transfers.filter { !$0.isFinished }.map(\.batch))
        let items = transfers.filter { batches.contains($0.batch) && !$0.isFolder }
        let total = items.reduce(UInt64(0)) { $0 + $1.total }
        return total == 0 ? 0 : Double(items.reduce(UInt64(0)) { $0 + $1.done }) / Double(total)
    }

    /// The phone's own name when it has one storage, otherwise the storage name.
    func rootName(_ storage: UInt32) -> String {
        if storages.count == 1, let d = device { return d.displayName }
        return storages.first { $0.id == storage }?.name ?? "Phone"
    }

    // MARK: Device

    /// Polls the USB bus: opens a phone when one appears, drops it when it goes away (A-004).
    func startWatching() {
        guard !watching else { return }
        watching = true
        Task { [weak self] in
            while let self {
                await self.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func poll() async {
        if ejectedName != nil {
            // Stay disconnected until the cable is pulled, like ejecting a disk.
            if await Task.detached(operation: { MTPProbe.rawDeviceCount() }).value == 0 { ejectedName = nil }
            return
        }
        if let real = device as? LibMTPDevice {
            let count = await Task.detached { MTPProbe.rawDeviceCount() }.value
            guard device === real else { return }
            if count == 0 { lostDevice() } else if storages.isEmpty { await loadStorages() }
            return
        }
        if device != nil { return }
        let result: Result<LibMTPDevice?, Error> = await Task.detached { Result { try MTPProbe.openFirst() } }.value
        switch result {
        case .success(let d?): await attach(d)
        case .success(nil): hint = nil
        case .failure(let e): hint = message(e)
        }
    }

    private func attach(_ d: MTPDevice) async {
        device = d
        storages = []
        hint = nil
        deviceGeneration += 1
        await loadStorages()
    }

    private func loadStorages() async {
        guard let d = device else { return }
        let r = await Task.detached { Result { try d.storages() } }.value
        guard device === d else { return }
        switch r {
        case .success(let s):
            let changed = s.map(\.id) != storages.map(\.id)
            storages = s
            hint = nil
            if changed {
                await loadPlaces()
                deviceGeneration += 1
            }
        case .failure(let e):
            hint = message(e)
            if !storages.isEmpty { storages = []; phonePlaces = []; deviceGeneration += 1 }
        }
    }

    /// Finds the folders people actually look for, so they don't have to know Android's layout.
    private func loadPlaces() async {
        guard let s = storages.first, case .success(let root) = await listPhone(storage: s.id, folder: 0) else { phonePlaces = []; return }
        func folder(_ name: String, in list: [DeviceEntry]) -> DeviceEntry? {
            list.first { $0.isFolder && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        func crumb(_ e: DeviceEntry) -> Crumb { Crumb(id: e.id, name: e.name) }
        var places: [PhonePlace] = []
        if let dcim = folder("DCIM", in: root) {
            if case .success(let kids) = await listPhone(storage: s.id, folder: dcim.id), let cam = folder("Camera", in: kids) {
                places.append(PhonePlace(name: "Camera", symbol: "camera", location: .phone(storage: s.id, path: [crumb(dcim), crumb(cam)])))
            } else {
                places.append(PhonePlace(name: "DCIM", symbol: "camera", location: .phone(storage: s.id, path: [crumb(dcim)])))
            }
        }
        for (name, label, symbol) in [("Download", "Downloads", "arrow.down.circle"), ("Pictures", "Pictures", "photo"),
                                      ("Movies", "Movies", "film"), ("Documents", "Documents", "doc")] {
            if let f = folder(name, in: root) { places.append(PhonePlace(name: label, symbol: symbol, location: .phone(storage: s.id, path: [crumb(f)]))) }
        }
        phonePlaces = places
    }

    func refreshStorages() { Task { await loadStorages() } }
    func connectDemo() { Task { await attach(DemoDevice()) } }
    func reconnect() { ejectedName = nil }

    func eject() {
        cancelAll()
        if !(device is DemoDevice) { ejectedName = device?.displayName }
        device = nil
        storages = []
        phonePlaces = []
        hint = nil
        deviceGeneration += 1
    }

    private func lostDevice() {
        let hadWork = activeCount > 0
        for i in transfers.indices where !transfers[i].isFinished {
            transfers[i].flag.cancelled = true
            transfers[i].state = .failed(DeviceError.disconnected.errorDescription!)
        }
        device = nil
        storages = []
        phonePlaces = []
        deviceGeneration += 1
        if hadWork { error = DeviceError.disconnected.errorDescription }
        settleBatches()
    }

    func listPhone(storage: UInt32, folder: UInt32) async -> Result<[DeviceEntry], Error> {
        guard let d = device else { return .failure(DeviceError.disconnected) }
        return await Task.detached { Result { try d.list(storage: storage, folder: folder) } }.value
    }

    func report(_ e: Error) { error = message(e) }

    // MARK: Phone file operations

    private func onPhone<T: Sendable>(_ op: @escaping @Sendable (MTPDevice) throws -> T) async throws -> T {
        guard let d = device else { throw DeviceError.disconnected }
        return try await Task.detached { try op(d) }.value
    }

    func deletePhone(_ refs: [PhoneRef]) {
        Task {
            for r in refs {
                do { try await onPhone { try $0.delete(r.entry) } } catch { report(error); break }
            }
            phoneNames = [:]
            refreshToken += 1
        }
    }

    func renamePhone(_ ref: PhoneRef, to name: String) {
        let clean = NameSanitizer.forPhone(name)
        Task {
            do { try await onPhone { try $0.rename(ref.entry, to: clean) } } catch { report(error) }
            refreshToken += 1
        }
    }

    func newPhoneFolder(storage: UInt32, parent: UInt32, name: String) {
        let clean = NameSanitizer.forPhone(name)
        Task {
            do { _ = try await onPhone { try $0.makeFolder(storage: storage, parent: parent, name: clean) } } catch { report(error) }
            refreshToken += 1
        }
    }

    /// Double-click on a phone file: copy it to a temporary folder and open it.
    func open(_ ref: PhoneRef) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Droplane/\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        enqueueDownloads([ref], into: dir) { err in
            if err == nil { NSWorkspace.shared.open(dir.appendingPathComponent(NameSanitizer.forMac(ref.entry.name))) }
        }
    }

    // MARK: Transfer queue (serial, A-006)

    func enqueueDownloads(_ refs: [PhoneRef], into dir: URL, completion: ((Error?) -> Void)? = nil) {
        guard !refs.isEmpty else { completion?(nil); return }
        let batch = UUID()
        if let completion { batchWaiters[batch] = completion }
        let dest = FileManager.default.displayName(atPath: dir.path)
        transfers += refs.map {
            TransferItem(batch: batch, job: .download($0, into: dir), name: $0.entry.name, destination: dest, isFolder: $0.entry.isFolder, total: $0.entry.size)
        }
        startQueue()
    }

    func enqueueUploads(_ urls: [URL], storage: UInt32, folder: UInt32, folderName: String) {
        guard !urls.isEmpty else { return }
        let batch = UUID()
        transfers += urls.map { uploadItem($0, batch: batch, storage: storage, folder: folder, folderName: folderName) }
        startQueue()
    }

    private func uploadItem(_ u: URL, batch: UUID, storage: UInt32, folder: UInt32, folderName: String) -> TransferItem {
        let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        return TransferItem(batch: batch, job: .upload(u, storage: storage, folder: folder, folderName: folderName),
                            name: u.lastPathComponent, destination: folderName, isFolder: v?.isDirectory ?? false, total: UInt64(v?.fileSize ?? 0))
    }

    /// Progress shows in the toolbar ring and the Dock badge; the Transfers window
    /// only comes forward when a decision is needed, so it never steals focus from Finder.
    private func startQueue() {
        guard !queueRunning else { return }
        queueRunning = true
        Task {
            while let next = transfers.first(where: { $0.state == .queued }) { await run(next) }
            queueRunning = false
            applyAll = nil
            phoneNames = [:]
            refreshToken += 1
            await loadStorages() // free space changed
        }
    }

    private func run(_ item: TransferItem) async {
        setState(item.id, .running)
        guard let d = device else { return finish(item.id, .failed(DeviceError.disconnected.errorDescription!)) }
        switch item.job {
        case .download(let ref, let dir): await download(item, ref, into: dir, d)
        case .upload(let url, let storage, let folder, _): await upload(item, url, storage: storage, folder: folder, d)
        }
    }

    private func download(_ item: TransferItem, _ ref: PhoneRef, into dir: URL, _ d: MTPDevice) async {
        let fm = FileManager.default
        let clean = NameSanitizer.forMac(ref.entry.name)
        var target = dir.appendingPathComponent(clean)
        var merge = false
        if fm.fileExists(atPath: target.path) {
            switch await ask(clean, isFolder: ref.entry.isFolder, toPhone: false) {
            case .skip: return finish(item.id, .skipped)
            case .keepBoth:
                target = dir.appendingPathComponent(ConflictResolver.keepBothName(clean, taken: Set((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])))
            case .replace:
                if ref.entry.isFolder { merge = true }
                else {
                    // Replaced Mac files go to the Trash rather than being deleted.
                    do { try fm.trashItem(at: target, resultingItemURL: nil) } catch { return finish(item.id, .failed(message(error))) }
                }
            }
        }
        if ref.entry.isFolder {
            do {
                if !merge { try fm.createDirectory(at: target, withIntermediateDirectories: false) }
                let kids = try await Task.detached { try d.list(storage: ref.storage, folder: ref.entry.id) }.value
                let folderName = target.lastPathComponent
                addChildren(of: item, kids.map {
                    TransferItem(batch: item.batch, job: .download(PhoneRef(storage: ref.storage, entry: $0), into: target),
                                 name: $0.name, destination: folderName, isFolder: $0.isFolder, total: $0.size)
                })
                finish(item.id, .done)
            } catch { finish(item.id, .failed(message(error))) }
            return
        }
        if let free = (try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,
           UInt64(max(free, 0)) < ref.entry.size {
            return finish(item.id, .failed(DeviceError.noSpaceOnMac(needed: ref.entry.size, available: UInt64(max(free, 0))).errorDescription!))
        }
        // A hidden partial file, renamed on success, so a cancel never leaves a half-copied file under the real name.
        let part = dir.appendingPathComponent(".\(target.lastPathComponent).droplane-part")
        let flag = item.flag, report = progressReporter(item.id), finalURL = target
        let failure: Error? = await Task.detached {
            do {
                try d.download(ref.entry, to: part) { n in report(n); return !flag.cancelled }
                try FileManager.default.moveItem(at: part, to: finalURL)
                try? FileManager.default.setAttributes([.modificationDate: ref.entry.modified], ofItemAtPath: finalURL.path)
                return nil
            } catch {
                try? FileManager.default.removeItem(at: part)
                return error
            }
        }.value
        finish(item.id, outcome(failure))
    }

    private func upload(_ item: TransferItem, _ url: URL, storage: UInt32, folder: UInt32, _ d: MTPDevice) async {
        let key = "\(storage)/\(folder)"
        let names: [String: DeviceEntry]
        do { names = try await phoneNamesIn(storage: storage, folder: folder, d) } catch { return finish(item.id, .failed(message(error))) }
        var name = NameSanitizer.forPhone(url.lastPathComponent)
        var mergeInto: UInt32?
        if let existing = names[name] {
            switch await ask(name, isFolder: item.isFolder, toPhone: true) {
            case .skip: return finish(item.id, .skipped)
            case .keepBoth: name = ConflictResolver.keepBothName(name, taken: Set(names.keys))
            case .replace:
                if item.isFolder && existing.isFolder { mergeInto = existing.id }
                else {
                    do { try await Task.detached { try d.delete(existing) }.value } catch { return finish(item.id, .failed(message(error))) }
                    phoneNames[key]?[name] = nil
                }
            }
        }
        if item.isFolder {
            do {
                var folderID = mergeInto ?? 0
                if mergeInto == nil {
                    let n = name
                    folderID = try await Task.detached { try d.makeFolder(storage: storage, parent: folder, name: n) }.value
                    phoneNames[key]?[name] = DeviceEntry(id: folderID, name: name, isFolder: true, size: 0, modified: Date())
                }
                let kids = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])) ?? []
                let id = folderID, folderName = name
                addChildren(of: item, kids.filter { $0.lastPathComponent != ".DS_Store" }
                    .map { uploadItem($0, batch: item.batch, storage: storage, folder: id, folderName: folderName) })
                finish(item.id, .done)
            } catch { finish(item.id, .failed(message(error))) }
            return
        }
        if let free = storages.first(where: { $0.id == storage })?.free, free < item.total {
            return finish(item.id, .failed(DeviceError.noSpaceOnPhone.errorDescription!))
        }
        let flag = item.flag, report = progressReporter(item.id), n = name
        let result: Result<UInt32, Error> = await Task.detached {
            Result { try d.upload(from: url, storage: storage, folder: folder, name: n) { done in report(done); return !flag.cancelled } }
        }.value
        switch result {
        case .success(let newID):
            phoneNames[key]?[name] = DeviceEntry(id: newID, name: name, isFolder: false, size: item.total, modified: Date())
            finish(item.id, .done)
        case .failure(let e): finish(item.id, outcome(e))
        }
    }

    private func outcome(_ failure: Error?) -> TransferItem.State {
        guard let failure else { return .done }
        return (failure as? DeviceError) == .cancelled ? .cancelled : .failed(message(failure))
    }

    private func phoneNamesIn(storage: UInt32, folder: UInt32, _ d: MTPDevice) async throws -> [String: DeviceEntry] {
        let key = "\(storage)/\(folder)"
        if let cached = phoneNames[key] { return cached }
        let list = try await Task.detached { try d.list(storage: storage, folder: folder) }.value
        let map = Dictionary(list.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        phoneNames[key] = map
        return map
    }

    private func progressReporter(_ id: UUID) -> @Sendable (UInt64) -> Void {
        let ticker = Ticker()
        return { [weak self] n in
            guard ticker.due() else { return }
            Task { @MainActor in
                if let i = self?.transfers.firstIndex(where: { $0.id == id }) { self?.transfers[i].done = n }
            }
        }
    }

    private func addChildren(of parent: TransferItem, _ items: [TransferItem]) {
        guard let i = transfers.firstIndex(where: { $0.id == parent.id }) else { return }
        transfers.insert(contentsOf: items, at: i + 1)
    }

    private func setState(_ id: UUID, _ state: TransferItem.State) {
        if let i = transfers.firstIndex(where: { $0.id == id }), transfers[i].state == .queued { transfers[i].state = state }
    }

    private func finish(_ id: UUID, _ state: TransferItem.State) {
        if let i = transfers.firstIndex(where: { $0.id == id }), transfers[i].state == .running {
            transfers[i].state = state
            if state == .done { transfers[i].done = transfers[i].total }
            if case .failed = state { transferWindowRequest += 1 } // show Retry
        }
        settleBatches()
    }

    /// Calls the completion of every batch (e.g. a Finder drop) that has nothing left to do.
    private func settleBatches() {
        for (batch, waiter) in batchWaiters where !transfers.contains(where: { $0.batch == batch && !$0.isFinished }) {
            batchWaiters[batch] = nil
            let states = transfers.filter { $0.batch == batch }.map(\.state)
            if let failure = states.lazy.compactMap({ if case .failed(let m) = $0 { m } else { nil } }).first {
                waiter(DeviceError.other(failure))
            } else if states.contains(.cancelled) {
                waiter(CocoaError(.userCancelled))
            } else {
                waiter(nil)
            }
        }
    }

    func cancel(_ id: UUID) {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[i].flag.cancelled = true
        if transfers[i].state == .queued { transfers[i].state = .cancelled; settleBatches() }
    }

    func cancelAll() { for t in transfers where !t.isFinished { cancel(t.id) } }

    /// No automatic retry (A-010); the user presses Retry.
    func retry(_ id: UUID) {
        guard let i = transfers.firstIndex(where: { $0.id == id }), case .failed = transfers[i].state else { return }
        transfers[i] = transfers[i].retried()
        startQueue()
    }

    func clearFinished() { transfers.removeAll { $0.isFinished } }

    // MARK: Conflicts (DL-006)

    private func ask(_ name: String, isFolder: Bool, toPhone: Bool) async -> ConflictChoice {
        if let a = applyAll { return a }
        transferWindowRequest += 1
        conflict = PendingConflict(name: name, isFolder: isFolder, toPhone: toPhone, more: transfers.contains { $0.state == .queued })
        let (choice, all) = await withCheckedContinuation { conflictWaiter = $0 }
        if all { applyAll = choice }
        return choice
    }

    func resolveConflict(_ c: ConflictChoice, applyToAll: Bool) {
        conflict = nil
        conflictWaiter?.resume(returning: (c, applyToAll))
        conflictWaiter = nil
    }
}
