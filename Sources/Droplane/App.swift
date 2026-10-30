import SwiftUI
import TransferCore

@main
struct DroplaneApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Droplane", id: "browser") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 420)
        }
        .defaultSize(width: 1000, height: 620)
        .commands { BrowserCommands(model: model) }

        Window("Transfers", id: "transfers") {
            TransfersView().environment(model)
        }
        .defaultSize(width: 520, height: 320)
    }
}

struct BrowserCommands: Commands {
    @FocusedValue(\.browser) private var browser
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Folder") { browser?.newFolderPrompt = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(browser?.isPhone != true)
        }
        CommandGroup(after: .toolbar) {
            Button(model.showHidden ? "Hide Hidden Files" : "Show Hidden Files") { model.showHidden.toggle() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button("Refresh") { browser?.reload(model) }
                .keyboardShortcut("r")
        }
        CommandMenu("Go") {
            Button("Back") { browser?.goBack(model) }
                .keyboardShortcut("[")
                .disabled(browser?.canGoBack != true)
            Button("Forward") { browser?.goForward(model) }
                .keyboardShortcut("]")
                .disabled(browser?.canGoForward != true)
            Button("Enclosing Folder") { browser?.goUp(model) }
                .keyboardShortcut(.upArrow)
            Divider()
            ForEach(MacPlaces.all) { place in
                Button(place.name) { browser?.go(.mac(place.url), model) }
            }
        }
    }
}
