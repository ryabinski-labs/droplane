import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TransferCore

extension NSPasteboard.PasteboardType {
    static let droplanePhone = NSPasteboard.PasteboardType("com.ryabinskilabs.droplane.phone-item")
}

extension UTType {
    static let droplanePhone = UTType(exportedAs: "com.ryabinskilabs.droplane.phone-item", conformingTo: .data)
}

/// A file promise Finder can resolve, which also carries the phone object for drops inside Droplane.
final class PhonePromise: NSFilePromiseProvider {
    var ref: PhoneRef?

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.droplanePhone]
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .droplanePhone ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .droplanePhone { return ref.flatMap { try? JSONEncoder().encode($0) } }
        return super.pasteboardPropertyList(forType: type)
    }
}

private final class ActionItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

final class BrowserOutlineView: NSOutlineView {
    weak var coordinator: FileOutline.Coordinator?

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch (event.keyCode, cmd) {
        case (51, true), (117, _): coordinator?.deleteSelection() // ⌘⌫, forward delete
        case (36, false), (76, false): coordinator?.renameSelection() // Return renames, as in Finder
        case (125, true): coordinator?.openSelection() // ⌘↓
        default: super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) { coordinator?.copy(coordinator?.browser?.selection ?? []) }
    @objc func paste(_ sender: Any?) { coordinator?.receive(.general, into: nil) }
}

/// Finder-style list view: an NSOutlineView with disclosure triangles, sortable columns, and drag and drop.
struct FileOutline: NSViewRepresentable {
    let browser: BrowserState
    let model: AppModel
    let version: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let ov = BrowserOutlineView()
        ov.coordinator = c
        c.outline = ov
        for (id, title, width) in [("name", "Name", 225.0), ("modified", "Date Modified", 135.0), ("size", "Size", 72.0),
                                   ("kind", "Kind", 84.0), ("copied", "Copied", 44.0), ("orientation", "Orientation", 100.0)] {
            let col = NSTableColumn(identifier: .init(id))
            col.title = title
            col.width = width
            col.minWidth = id == "copied" ? 48 : 60
            // Orientation values arrive progressively, so sorting them would
            // reorder the list under the pointer; that column has no sort descriptor.
            if id != "orientation" {
                col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: id != "modified" && id != "copied")
            }
            if id == "size" { col.headerCell.alignment = .right }
            if id == "copied" { col.headerToolTip = "Files copied to your Mac in this session" }
            if id == "orientation" { col.headerToolTip = "Read from the phone's thumbnail; values appear as they load" }
            ov.addTableColumn(col)
        }
        ov.outlineTableColumn = ov.tableColumns[0]
        ov.headerView = NSTableHeaderView()
        ov.style = .inset
        ov.usesAlternatingRowBackgroundColors = true
        ov.allowsMultipleSelection = true
        ov.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        ov.autoresizesOutlineColumn = false
        ov.dataSource = c
        ov.delegate = c
        ov.target = c
        ov.doubleAction = #selector(Coordinator.doubleClicked(_:))
        ov.registerForDraggedTypes([.fileURL, .droplanePhone])
        ov.setDraggingSourceOperationMask(.copy, forLocal: true)
        ov.setDraggingSourceOperationMask(.copy, forLocal: false)
        ov.draggingDestinationFeedbackStyle = .regular
        let menu = NSMenu()
        menu.delegate = c
        ov.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = ov
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.browser = browser
        c.model = model
        browser.onCopiedMarksChanged = { [weak c] in c?.reloadCopiedColumn() }
        browser.onOrientationCellChanged = { [weak c] node in c?.reloadOrientationCell(node) }
        if let ov = scroll.documentView as? NSOutlineView {
            for id in ["copied", "orientation"] {
                ov.tableColumn(withIdentifier: .init(id))?.isHidden = !browser.isPhone
            }
        }
        if c.version != version {
            c.version = version
            c.setRoots(browser.nodes)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSFilePromiseProviderDelegate {
        weak var outline: NSOutlineView?
        var browser: BrowserState?
        var model: AppModel?
        var version = -1
        private var roots: [Node] = []
        private var sort = NSSortDescriptor(key: "name", ascending: true)
        private let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            f.doesRelativeDateFormatting = true
            return f
        }()

        func setRoots(_ nodes: [Node]) {
            roots = sorted(nodes)
            outline?.reloadData()
        }

        private func sorted(_ nodes: [Node]) -> [Node] {
            let key = sort.key ?? "name", ascending = sort.ascending
            func cmp<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult { a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame }
            return nodes.sorted { a, b in
                if a.isFolder != b.isFolder { return a.isFolder } // folders on top
                let r: ComparisonResult
                switch key {
                case "modified": r = cmp(a.modified ?? .distantPast, b.modified ?? .distantPast)
                case "size": r = cmp(a.size, b.size)
                case "kind": r = a.kind.localizedStandardCompare(b.kind)
                case "copied":
                    let ac = copied(a), bc = copied(b)
                    r = ac == bc ? .orderedSame : (ac ? .orderedDescending : .orderedAscending)
                default: r = a.name.localizedStandardCompare(b.name)
                }
                if r == .orderedSame { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        }

        private func copied(_ node: Node) -> Bool {
            guard let entry = node.phoneRef?.entry else { return false }
            return model?.isCopied(entry) ?? false
        }

        private func resort(_ nodes: [Node]) -> [Node] {
            for n in nodes { n.children = n.children.map(resort) }
            return sorted(nodes)
        }

        // MARK: Data source

        func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? Node else { return roots.count }
            return node.children?.count ?? 0
        }

        func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? Node else { return roots[index] }
            return node.children![index]
        }

        func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Node)?.isFolder ?? false }

        func outlineViewItemWillExpand(_ n: Notification) {
            guard let node = n.userInfo?["NSObject"] as? Node, node.children == nil, !node.isLoading, let browser, let model else { return }
            node.isLoading = true
            Task {
                let kids = await browser.loadChildren(of: node, model)
                node.children = sorted(kids)
                node.isLoading = false
                outline?.reloadItem(node, reloadChildren: true)
                outline?.expandItem(node)
            }
        }

        func outlineView(_ ov: NSOutlineView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
            guard let first = ov.sortDescriptors.first else { return }
            sort = first
            roots = resort(roots)
            ov.reloadData()
        }

        // MARK: Cells

        func outlineView(_ ov: NSOutlineView, viewFor col: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node, let col else { return nil }
            let cell = (ov.makeView(withIdentifier: col.identifier, owner: nil) as? NSTableCellView) ?? makeCell(col.identifier)
            cell.toolTip = nil
            cell.setAccessibilityLabel(nil)
            switch col.identifier.rawValue {
            case "name":
                cell.textField?.stringValue = node.name
                cell.imageView?.image = node.icon
            case "modified":
                cell.textField?.stringValue = node.modified.map(dateFormatter.string(from:)) ?? "--"
            case "size":
                cell.textField?.stringValue = node.isFolder ? "--" : ByteCountFormatter.string(fromByteCount: Int64(node.size), countStyle: .file)
            case "copied":
                let isCopied = copied(node)
                cell.imageView?.image = isCopied
                    ? NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")
                    : nil
                cell.imageView?.contentTintColor = .systemGreen
            case "orientation":
                guard node.isVideo || node.isPhoto else {
                    cell.textField?.stringValue = "—"
                    cell.textField?.textColor = .tertiaryLabelColor
                    cell.imageView?.image = nil
                    return cell
                }
                if let dimensions = node.dimensions {
                    cell.textField?.stringValue = dimensions.orientation.label
                    cell.textField?.textColor = .labelColor
                    cell.imageView?.image = NSImage(systemSymbolName: dimensions.orientation.symbolName,
                                                    accessibilityDescription: nil)
                    cell.imageView?.contentTintColor = .secondaryLabelColor
                    cell.toolTip = "\(dimensions.width) by \(dimensions.height)"
                    cell.setAccessibilityLabel("\(dimensions.orientation.label), \(dimensions.width) by \(dimensions.height)")
                } else {
                    cell.textField?.stringValue = "—"
                    cell.textField?.textColor = .tertiaryLabelColor
                    cell.imageView?.image = nil
                    if let browser, let model { browser.requestOrientation(for: node, model: model) }
                    let failed = browser?.orientationFailed(for: node) == true
                    cell.toolTip = failed ? "Orientation not available from this phone" : "Checking orientation…"
                    cell.setAccessibilityLabel(failed ? "Orientation not available from this phone" : "Checking orientation")
                }
            default:
                cell.textField?.stringValue = node.kind
            }
            return cell
        }

        private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id
            if id.rawValue == "copied" {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                image.imageScaling = .scaleProportionallyDown
                cell.addSubview(image)
                cell.imageView = image
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 14),
                    image.heightAnchor.constraint(equalToConstant: 14),
                ])
                return cell
            }
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = id.rawValue == "name" ? .byTruncatingMiddle : .byTruncatingTail
            cell.addSubview(text)
            cell.textField = text
            if id.rawValue == "name" || id.rawValue == "orientation" {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                image.imageScaling = .scaleProportionallyDown
                cell.addSubview(image)
                cell.imageView = image
                let width: CGFloat = id.rawValue == "name" ? 16 : 14
                let gap: CGFloat = id.rawValue == "name" ? 6 : 4
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: width),
                    image.heightAnchor.constraint(equalToConstant: width),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: gap),
                ])
            } else {
                text.textColor = .secondaryLabelColor
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
                if id.rawValue == "size" { text.alignment = .right }
            }
            NSLayoutConstraint.activate([
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        /// Redraws the Copied column after a download finishes, without re-listing the folder.
        func reloadCopiedColumn() {
            guard let outline, let col = outline.tableColumns.firstIndex(where: { $0.identifier.rawValue == "copied" }) else { return }
            if sort.key == "copied" {
                roots = resort(roots)
                outline.reloadData()
                return
            }
            let visible = outline.rows(in: outline.visibleRect)
            guard visible.length > 0 else { return }
            let rows = IndexSet(integersIn: visible.location..<(visible.location + visible.length))
            outline.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: col))
        }

        func reloadOrientationCell(_ node: Node) {
            guard let outline, let col = outline.tableColumns.firstIndex(where: { $0.identifier.rawValue == "orientation" }) else { return }
            let row = outline.row(forItem: node)
            guard row >= 0 else { return }
            outline.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: col))
        }

        func outlineViewSelectionDidChange(_ n: Notification) {
            guard let ov = outline else { return }
            browser?.selection = ov.selectedRowIndexes.compactMap { ov.item(atRow: $0) as? Node }
        }

        @objc func doubleClicked(_ sender: NSOutlineView) {
            guard sender.clickedRow >= 0, let node = sender.item(atRow: sender.clickedRow) as? Node, let browser, let model else { return }
            browser.open(node, model)
        }

        // MARK: Keyboard actions

        func deleteSelection() {
            let refs = browser?.selection.compactMap(\.phoneRef) ?? []
            if !refs.isEmpty { browser?.pendingDelete = refs }
        }

        func renameSelection() {
            guard let sel = browser?.selection, sel.count == 1, sel[0].phoneRef != nil else { return }
            browser?.renaming = sel[0]
        }

        func openSelection() {
            guard let browser, let model, let first = browser.selection.first else { return }
            browser.open(first, model)
        }

        // MARK: Drag out (phone files become file promises Finder can resolve)

        func outlineView(_ ov: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = item as? Node else { return nil }
            switch node.ref {
            case .mac(let url): return url as NSURL
            case .phone(let ref):
                let type = node.isFolder ? UTType.folder : UTType(filenameExtension: (node.name as NSString).pathExtension) ?? .data
                let promise = PhonePromise(fileType: type.identifier, delegate: self)
                promise.ref = ref
                return promise
            }
        }

        nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            NameSanitizer.forMac((provider as? PhonePromise)?.ref?.entry.name ?? "Untitled")
        }

        nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
            guard let ref = (provider as? PhonePromise)?.ref else { return completionHandler(CocoaError(.fileNoSuchFile)) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let model = self.model else { return completionHandler(DeviceError.disconnected) }
                    model.enqueueDownloads([ref], into: url.deletingLastPathComponent(), completion: completionHandler)
                }
            }
        }

        // MARK: Drop in

        /// Dropping on a folder row targets that folder; anywhere else targets the open folder.
        private func folderTarget(_ item: Any?, _ index: Int) -> Node? {
            guard let node = item as? Node, node.isFolder, index == NSOutlineViewDropOnItemIndex else { return nil }
            return node
        }

        func outlineView(_ ov: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            let target = folderTarget(item, index)
            if target == nil { ov.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex) }
            return accepts(info.draggingPasteboard, into: target) ? .copy : []
        }

        func outlineView(_ ov: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            receive(info.draggingPasteboard, into: folderTarget(item, index))
        }

        private func phoneDestination(_ target: Node?) -> (storage: UInt32, folder: UInt32, name: String)? {
            if let t = target { return t.phoneRef.map { ($0.storage, $0.entry.id, $0.entry.name) } }
            return browser?.currentPhoneFolder
        }

        private func macDestination(_ target: Node?) -> URL? {
            if let t = target { return t.macURL }
            return browser?.currentMacURL
        }

        private func fileURLs(_ pb: NSPasteboard) -> [URL] {
            guard pb.types?.contains(.droplanePhone) != true else { return [] } // phone-to-phone moves aren't supported
            return pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        }

        private func phoneRefs(_ pb: NSPasteboard) -> [PhoneRef] {
            (pb.pasteboardItems ?? []).compactMap { $0.data(forType: .droplanePhone) }.compactMap { try? JSONDecoder().decode(PhoneRef.self, from: $0) }
        }

        private func accepts(_ pb: NSPasteboard, into target: Node?) -> Bool {
            if phoneDestination(target) != nil { return pb.types?.contains(.droplanePhone) != true && pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) }
            if macDestination(target) != nil { return pb.types?.contains(.droplanePhone) == true }
            return false
        }

        @discardableResult
        func receive(_ pb: NSPasteboard, into target: Node?) -> Bool {
            guard let model else { return false }
            if let dest = phoneDestination(target) {
                let urls = fileURLs(pb)
                guard !urls.isEmpty else { return false }
                model.enqueueUploads(urls, storage: dest.storage, folder: dest.folder, folderName: dest.name)
                return true
            }
            if let dir = macDestination(target) {
                let refs = phoneRefs(pb)
                guard !refs.isEmpty else { return false }
                model.enqueueDownloads(refs, into: dir)
                return true
            }
            return false
        }

        func copy(_ nodes: [Node]) {
            guard !nodes.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(nodes.map { node -> NSPasteboardWriting in
                switch node.ref {
                case .mac(let url): return url as NSURL
                case .phone(let ref):
                    let item = NSPasteboardItem()
                    item.setData((try? JSONEncoder().encode(ref)) ?? Data(), forType: .droplanePhone)
                    return item
                }
            })
        }

        // MARK: Context menu

        private func clickedNodes() -> [Node] {
            guard let ov = outline, ov.clickedRow >= 0 else { return [] }
            if ov.selectedRowIndexes.contains(ov.clickedRow) { return browser?.selection ?? [] }
            return (ov.item(atRow: ov.clickedRow) as? Node).map { [$0] } ?? []
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let browser, let model, browser.location != nil else { return }
            let nodes = clickedNodes()
            if nodes.count == 1 { menu.addItem(ActionItem("Open") { browser.open(nodes[0], model) }) }
            let refs = nodes.compactMap(\.phoneRef)
            if !refs.isEmpty {
                menu.addItem(ActionItem("Copy to Downloads") { model.enqueueDownloads(refs, into: MacPlaces.downloads) })
                menu.addItem(ActionItem("Copy to…") { self.chooseFolder(for: refs) })
                menu.addItem(.separator())
                if refs.count == 1 { menu.addItem(ActionItem("Rename…") { browser.renaming = nodes[0] }) }
                menu.addItem(ActionItem("Delete…") { browser.pendingDelete = refs })
            }
            let urls = nodes.compactMap(\.macURL)
            if !urls.isEmpty { menu.addItem(ActionItem("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }) }
            if !nodes.isEmpty {
                menu.addItem(.separator())
                menu.addItem(ActionItem("Copy") { self.copy(nodes) })
            }
            if browser.isPhone {
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                menu.addItem(ActionItem("New Folder") { browser.newFolderPrompt = true })
            }
        }

        private func chooseFolder(for refs: [PhoneRef]) {
            guard let window = outline?.window else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Copy Here"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                MainActor.assumeIsolated { self.model?.enqueueDownloads(refs, into: url) }
            }
        }
    }
}
