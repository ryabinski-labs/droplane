import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TransferCore

struct Crumb: Hashable {
    let id: UInt32
    let name: String
}

enum Location: Hashable {
    case phone(storage: UInt32, path: [Crumb])
    case mac(URL)
    var isPhone: Bool { if case .phone = self { return true }; return false }
}

struct MacPlace: Identifiable {
    let name: String
    let symbol: String
    let url: URL
    var id: URL { url }
}

enum MacPlaces {
    private static func dir(_ d: FileManager.SearchPathDirectory) -> URL { FileManager.default.urls(for: d, in: .userDomainMask)[0] }
    static let downloads = dir(.downloadsDirectory)
    static let all: [MacPlace] = [
        MacPlace(name: "Desktop", symbol: "menubar.dock.rectangle", url: dir(.desktopDirectory)),
        MacPlace(name: "Documents", symbol: "doc", url: dir(.documentDirectory)),
        MacPlace(name: "Downloads", symbol: "arrow.down.circle", url: downloads),
        MacPlace(name: "Pictures", symbol: "photo", url: dir(.picturesDirectory)),
        MacPlace(name: "Movies", symbol: "film", url: dir(.moviesDirectory)),
        MacPlace(name: "Music", symbol: "music.note", url: dir(.musicDirectory)),
        MacPlace(name: NSUserName(), symbol: "house", url: FileManager.default.homeDirectoryForCurrentUser),
    ]
}

/// One row in the file list. A class because NSOutlineView tracks items by identity.
final class Node: NSObject {
    enum Ref {
        case phone(PhoneRef)
        case mac(URL)
    }
    let ref: Ref
    let name: String
    let isFolder: Bool
    let size: UInt64
    let modified: Date?
    let kind: String
    /// Phone folders from the storage root down to and including this node.
    let crumbs: [Crumb]
    var children: [Node]?
    var isLoading = false

    init(phone entry: DeviceEntry, storage: UInt32, parent: [Crumb]) {
        ref = .phone(PhoneRef(storage: storage, entry: entry))
        name = entry.name
        isFolder = entry.isFolder
        size = entry.size
        modified = entry.modified
        kind = entry.isFolder ? "Folder" : UTType(filenameExtension: (entry.name as NSString).pathExtension)?.localizedDescription ?? "Document"
        crumbs = parent + [Crumb(id: entry.id, name: entry.name)]
    }

    init(mac url: URL) {
        let v = try? url.resourceValues(forKeys: Node.macKeys)
        ref = .mac(url)
        name = v?.localizedName ?? url.lastPathComponent
        isFolder = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
        size = UInt64(v?.fileSize ?? 0)
        modified = v?.contentModificationDate
        kind = v?.localizedTypeDescription ?? (isFolder ? "Folder" : "Document")
        crumbs = []
    }

    static let macKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey, .localizedNameKey]

    var phoneRef: PhoneRef? { if case .phone(let r) = ref { return r }; return nil }
    var macURL: URL? { if case .mac(let u) = ref { return u }; return nil }

    lazy var icon: NSImage = Icons.icon(for: self)

    static func phoneNodes(_ entries: [DeviceEntry], storage: UInt32, parent: [Crumb], hidden: Bool) -> [Node] {
        entries.filter { hidden || !$0.name.hasPrefix(".") }.map { Node(phone: $0, storage: storage, parent: parent) }
    }

    static func macNodes(in url: URL, hidden: Bool) -> [Node] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(macKeys),
                                                                  options: hidden ? [] : [.skipsHiddenFiles])) ?? []
        return urls.map(Node.init(mac:))
    }
}

enum Icons {
    private static var cache: [String: NSImage] = [:]
    static func icon(for node: Node) -> NSImage {
        if let url = node.macURL { return NSWorkspace.shared.icon(forFile: url.path) }
        let ext = (node.name as NSString).pathExtension.lowercased()
        let key = node.isFolder ? "/folder" : ext
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(for: node.isFolder ? .folder : UTType(filenameExtension: ext) ?? .data)
        cache[key] = image
        return image
    }
}

/// Per-window navigation state: where the window is, its history, and what it lists.
@Observable @MainActor
final class BrowserState {
    private(set) var location: Location?
    private var back: [Location] = []
    private var forward: [Location] = []
    private(set) var nodes: [Node] = []
    private(set) var version = 0
    private(set) var isLoading = false
    var selection: [Node] = []
    var renaming: Node?
    var pendingDelete: [PhoneRef] = []
    var newFolderPrompt = false
    @ObservationIgnored private var loadToken = UUID()
    @ObservationIgnored private var deviceID: ObjectIdentifier?
    @ObservationIgnored private var loadedLocation: Location?

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var isPhone: Bool { location?.isPhone ?? false }

    func go(_ l: Location, _ model: AppModel) {
        guard l != location else { return }
        if let current = location { back.append(current) }
        forward = []
        location = l
        reload(model)
    }

    func goBack(_ model: AppModel) {
        guard let l = back.popLast() else { return }
        if let current = location { forward.append(current) }
        location = l
        reload(model)
    }

    func goForward(_ model: AppModel) {
        guard let l = forward.popLast() else { return }
        if let current = location { back.append(current) }
        location = l
        reload(model)
    }

    func goUp(_ model: AppModel) {
        switch location {
        case .phone(let s, let path)? where !path.isEmpty: go(.phone(storage: s, path: Array(path.dropLast())), model)
        case .mac(let url)? where url.path != "/": go(.mac(url.deletingLastPathComponent()), model)
        default: break
        }
    }

    func open(_ node: Node, _ model: AppModel) {
        switch node.ref {
        case .phone(let r):
            if node.isFolder { go(.phone(storage: r.storage, path: node.crumbs), model) } else { model.open(r) }
        case .mac(let url):
            if node.isFolder { go(.mac(url), model) } else { NSWorkspace.shared.open(url) }
        }
    }

    /// The sidebar row matching the open folder, if any, as Finder highlights it.
    func sidebarSelection(_ model: AppModel) -> Location? {
        switch location {
        case .phone(_, let path)? where path.isEmpty: return location
        case .phone?: return model.phonePlaces.contains { $0.location == location } ? location : nil
        case .mac(let u)?: return MacPlaces.all.first { $0.url.standardizedFileURL == u.standardizedFileURL }.map { .mac($0.url) }
        case nil: return nil
        }
    }

    /// The phone folder new items land in when nothing more specific is targeted.
    var currentPhoneFolder: (storage: UInt32, folder: UInt32, name: String)? {
        guard case .phone(let s, let path)? = location else { return nil }
        return (s, path.last?.id ?? 0, path.last?.name ?? "Internal storage")
    }

    var currentMacURL: URL? { if case .mac(let u)? = location { return u }; return nil }

    func title(_ model: AppModel) -> String {
        switch location {
        case .phone(let s, let path)?: return path.last?.name ?? model.rootName(s)
        case .mac(let u)?: return FileManager.default.displayName(atPath: u.path)
        case nil: return model.device?.displayName ?? "Droplane"
        }
    }

    /// Re-targets the window when a phone appears, unlocks, or goes away.
    func deviceChanged(_ model: AppModel) {
        let newID = model.device.map { ObjectIdentifier($0) }
        let sameDevice = newID == deviceID
        deviceID = newID
        if !sameDevice { back.removeAll { $0.isPhone }; forward.removeAll { $0.isPhone } }
        guard let first = model.storages.first else {
            if isPhone || location == nil { location = nil; nodes = []; version += 1 }
            return
        }
        var stillValid = false
        if case .phone(let s, _)? = location { stillValid = sameDevice && model.storages.contains { $0.id == s } }
        if location == nil || (isPhone && !stillValid) {
            location = .phone(storage: first.id, path: [])
            reload(model)
        }
    }

    func reload(_ model: AppModel) {
        let token = UUID()
        loadToken = token
        selection = []
        switch location {
        case nil:
            nodes = []
            version += 1
        case .mac(let url)?:
            nodes = Node.macNodes(in: url, hidden: model.showHidden)
            loadedLocation = location
            version += 1
        case .phone(let s, let path)?:
            isLoading = true
            // Never show the previous folder's contents under the new folder's title.
            if loadedLocation != location {
                nodes = []
                version += 1
            }
            let target = location
            Task {
                let result = await model.listPhone(storage: s, folder: path.last?.id ?? 0)
                guard loadToken == token else { return }
                isLoading = false
                switch result {
                case .success(let entries):
                    nodes = Node.phoneNodes(entries, storage: s, parent: path, hidden: model.showHidden)
                    loadedLocation = target
                case .failure(let e): nodes = []; model.report(e)
                }
                version += 1
            }
        }
    }

    func loadChildren(of node: Node, _ model: AppModel) async -> [Node] {
        switch node.ref {
        case .mac(let url): return Node.macNodes(in: url, hidden: model.showHidden)
        case .phone(let r):
            guard case .success(let entries) = await model.listPhone(storage: r.storage, folder: r.entry.id) else { return [] }
            return Node.phoneNodes(entries, storage: r.storage, parent: node.crumbs, hidden: model.showHidden)
        }
    }

    struct PathItem {
        let name: String
        let symbol: String
        let location: Location
    }

    /// Finder-style path bar entries for the current folder.
    func pathItems(_ model: AppModel) -> [PathItem] {
        switch location {
        case .phone(let s, let path)?:
            let root = PathItem(name: model.rootName(s), symbol: "iphone", location: .phone(storage: s, path: []))
            return [root] + path.indices.map { PathItem(name: path[$0].name, symbol: "folder", location: .phone(storage: s, path: Array(path[...$0]))) }
        case .mac(let url)?:
            var items: [PathItem] = []
            var u = url.standardizedFileURL
            while items.count < 6 {
                items.insert(PathItem(name: FileManager.default.displayName(atPath: u.path), symbol: u.path == "/" ? "internaldrive" : "folder", location: .mac(u)), at: 0)
                if u.path == "/" { break }
                u = u.deletingLastPathComponent()
            }
            return items
        case nil:
            return []
        }
    }

    func statusText(_ model: AppModel) -> String {
        let count = nodes.count == 1 ? "1 item" : "\(nodes.count) items"
        var free: Int64?
        switch location {
        case .phone(let s, _)?: free = model.storages.first { $0.id == s }.map { Int64($0.free) }
        case .mac(let u)?: free = (try? u.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        case nil: break
        }
        guard let free else { return count }
        return "\(count), \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) available"
    }
}

struct BrowserKey: FocusedValueKey { typealias Value = BrowserState }
extension FocusedValues {
    var browser: BrowserState? {
        get { self[BrowserKey.self] }
        set { self[BrowserKey.self] = newValue }
    }
}
