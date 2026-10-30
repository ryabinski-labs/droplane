import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TransferCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var browser = BrowserState()
    @State private var renameText = ""
    @State private var newFolderName = ""
    @AppStorage("copyDestination") private var copyDestination = MacPlaces.downloads.path

    var body: some View {
        @Bindable var b = browser
        NavigationSplitView {
            Sidebar(browser: browser)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if browser.location != nil {
                    FileOutline(browser: browser, model: model, version: browser.version)
                        .overlay { if browser.isLoading && browser.nodes.isEmpty { ProgressView().controlSize(.small) } }
                    Divider()
                    PathBar(browser: browser)
                } else if model.device != nil {
                    LockedView()
                } else {
                    EmptyDeviceView()
                }
            }
        }
        .navigationTitle(browser.title(model))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button { browser.goBack(model) } label: { Label("Back", systemImage: "chevron.left") }
                        .disabled(!browser.canGoBack)
                    Button { browser.goForward(model) } label: { Label("Forward", systemImage: "chevron.right") }
                        .disabled(!browser.canGoForward)
                }
                .controlGroupStyle(.navigation)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if browser.isPhone {
                    copyButton
                    Button { browser.newFolderPrompt = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                        .help("New folder on the phone")
                    Button { browser.pendingDelete = browser.selection.compactMap(\.phoneRef) } label: { Label("Delete", systemImage: "trash") }
                        .disabled(browser.selection.isEmpty)
                        .help("Delete from the phone")
                }
                Button { openWindow(id: "transfers") } label: {
                    if model.activeCount > 0 {
                        Label { Text("Transfers") } icon: { ProgressView(value: model.activeProgress).progressViewStyle(.circular).controlSize(.small) }
                    } else {
                        Label("Transfers", systemImage: "arrow.up.arrow.down.circle")
                    }
                }
                .help(model.activeCount > 0 ? "Copying \(model.activeCount) \(model.activeCount == 1 ? "item" : "items")" : "Show transfers")
            }
        }
        .focusedSceneValue(\.browser, browser)
        .task { model.startWatching(); browser.deviceChanged(model) }
        .onChange(of: model.deviceGeneration) { browser.deviceChanged(model) }
        .onChange(of: model.refreshToken) { browser.reload(model) }
        .onChange(of: model.showHidden) { browser.reload(model) }
        .onChange(of: model.transferWindowRequest) { openWindow(id: "transfers") }
        .onChange(of: model.activeCount) { _, n in NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil }
        .onChange(of: browser.renaming) { renameText = browser.renaming?.name ?? "" }
        .alert("Rename", isPresented: Binding(get: { browser.renaming != nil }, set: { if !$0 { browser.renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let ref = browser.renaming?.phoneRef, !renameText.isEmpty, renameText != ref.entry.name { model.renamePhone(ref, to: renameText) }
                browser.renaming = nil
            }
            Button("Cancel", role: .cancel) { browser.renaming = nil }
        }
        .alert("New Folder", isPresented: $b.newFolderPrompt) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                if let f = browser.currentPhoneFolder, !newFolderName.isEmpty { model.newPhoneFolder(storage: f.storage, parent: f.folder, name: newFolderName) }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { !browser.pendingDelete.isEmpty }, set: { if !$0 { browser.pendingDelete = [] } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deletePhone(browser.pendingDelete); browser.pendingDelete = [] }
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    /// The main job, always visible: copy the selected phone items to a Mac folder.
    private var copyButton: some View {
        let refs = browser.selection.compactMap(\.phoneRef)
        let saved = URL(fileURLWithPath: copyDestination)
        let destination = FileManager.default.fileExists(atPath: saved.path) ? saved : MacPlaces.downloads
        let name = FileManager.default.displayName(atPath: destination.path)
        return Menu {
            ForEach(MacPlaces.all) { place in
                Button(place.name) { copy(refs, to: place.url) }
            }
            Divider()
            Button("Other Folder…") { chooseFolder(for: refs) }
        } label: {
            Label("Copy to \(name)", systemImage: "square.and.arrow.down")
        } primaryAction: {
            copy(refs, to: destination)
        }
        .labelStyle(.titleAndIcon)
        .disabled(refs.isEmpty)
        .help(refs.isEmpty ? "Select files on the phone to copy them to your Mac" : "Copy the selected items to \(name)")
    }

    private func copy(_ refs: [PhoneRef], to url: URL) {
        copyDestination = url.path
        model.enqueueDownloads(refs, into: url)
    }

    private func chooseFolder(for refs: [PhoneRef]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Copy Here"
        if panel.runModal() == .OK, let url = panel.url { copy(refs, to: url) }
    }

    private var deleteTitle: String {
        let n = browser.pendingDelete.count
        return "Delete \(n) \(n == 1 ? "item" : "items") from your phone? This cannot be undone"
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    let browser: BrowserState

    var body: some View {
        List(selection: Binding(get: { browser.sidebarSelection(model) }, set: { if let l = $0 { browser.go(l, model) } })) {
            Section {
                if model.device == nil {
                    Label(model.ejectedName.map { "\($0) disconnected" } ?? "No phone connected", systemImage: "iphone.slash")
                        .foregroundStyle(.secondary)
                } else if model.storages.isEmpty {
                    Label("Locked", systemImage: "lock").foregroundStyle(.secondary)
                }
                ForEach(model.storages) { s in
                    Label(s.name, systemImage: s.name.localizedCaseInsensitiveContains("sd") ? "sdcard" : "internaldrive")
                        .tag(Location.phone(storage: s.id, path: []))
                        .onDrop(of: [.fileURL], isTargeted: nil) { upload($0, storage: s.id, folder: 0, name: s.name) }
                }
                ForEach(model.phonePlaces) { place in
                    Label(place.name, systemImage: place.symbol)
                        .tag(place.location)
                        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                            guard case .phone(let s, let path) = place.location, let folder = path.last else { return false }
                            return upload(providers, storage: s, folder: folder.id, name: folder.name)
                        }
                }
            } header: {
                HStack {
                    Text(model.device?.displayName ?? "Phone")
                    Spacer()
                    if model.device != nil {
                        Button { model.eject() } label: {
                            Image(systemName: "eject")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                            .help("Disconnect the phone")
                            .accessibilityLabel("Disconnect \(model.device?.displayName ?? "phone")")
                    }
                }
            }
            Section("Mac") {
                ForEach(MacPlaces.all) { place in
                    Label(place.name, systemImage: place.symbol)
                        .tag(Location.mac(place.url))
                        .onDrop(of: [.droplanePhone], isTargeted: nil) { providers in
                            Task {
                                var refs: [PhoneRef] = []
                                for p in providers { if let r = await p.phoneRef() { refs.append(r) } }
                                model.enqueueDownloads(refs, into: place.url)
                            }
                            return true
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func upload(_ providers: [NSItemProvider], storage: UInt32, folder: UInt32, name: String) -> Bool {
        Task {
            var urls: [URL] = []
            for p in providers { if let u = await p.fileURL() { urls.append(u) } }
            model.enqueueUploads(urls, storage: storage, folder: folder, folderName: name)
        }
        return true
    }
}

extension NSItemProvider {
    func fileURL() async -> URL? {
        await withCheckedContinuation { c in _ = loadObject(ofClass: URL.self) { url, _ in c.resume(returning: url) } }
    }
    func phoneRef() async -> PhoneRef? {
        await withCheckedContinuation { c in
            loadDataRepresentation(forTypeIdentifier: UTType.droplanePhone.identifier) { data, _ in
                c.resume(returning: data.flatMap { try? JSONDecoder().decode(PhoneRef.self, from: $0) })
            }
        }
    }
}

/// Finder's path bar and status bar in one strip.
struct PathBar: View {
    @Environment(AppModel.self) private var model
    let browser: BrowserState

    var body: some View {
        HStack(spacing: 4) {
            let items = browser.pathItems(model)
            ForEach(items.indices, id: \.self) { i in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary) }
                Button { browser.go(items[i].location, model) } label: {
                    Label(items[i].name, systemImage: items[i].symbol).lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)
            Text(browser.statusText(model)).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

struct EmptyDeviceView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let name = model.ejectedName {
            ContentUnavailableView {
                Label("\(name) is disconnected", systemImage: "eject.circle")
            } description: {
                Text("You can unplug the cable now.")
            } actions: {
                Button("Connect Again") { model.reconnect() }
            }
        } else {
            ContentUnavailableView {
                Label("Connect your Android phone", systemImage: "cable.connector")
            } description: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Plug the phone into this Mac with a USB cable.")
                    Text("2. Unlock the phone.")
                    Text("3. Tap the USB notification and choose **File transfer**.")
                    Text("On Pixel phones it's called File transfer / Android Auto.")
                        .font(.callout).foregroundStyle(.tertiary)
                    if let hint = model.hint {
                        Label(hint, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(.top, 6)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 420)
            } actions: {
                VStack(spacing: 8) {
                    Text("Droplane opens your phone as soon as it's ready.").font(.callout).foregroundStyle(.secondary)
                    Button("Try the Demo Phone") { model.connectDemo() }
                }
            }
        }
    }
}

struct LockedView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ContentUnavailableView {
            Label(model.device?.displayName ?? "Phone", systemImage: "lock.iphone")
        } description: {
            Text(model.hint ?? DeviceError.locked.errorDescription!)
        } actions: {
            Button("Refresh") { model.refreshStorages() }
        }
    }
}
