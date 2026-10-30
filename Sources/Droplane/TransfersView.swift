import SwiftUI
import UniformTypeIdentifiers
import TransferCore

struct TransfersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var m = model
        VStack(spacing: 0) {
            if model.transfers.isEmpty {
                ContentUnavailableView("No Transfers", systemImage: "arrow.up.arrow.down.circle",
                                       description: Text("Drag files between your phone and Finder to copy them."))
            } else {
                List(model.transfers) { TransferRow(item: $0) }
            }
            Divider()
            HStack {
                Text(summary).foregroundStyle(.secondary)
                Spacer()
                Button("Clear Finished") { model.clearFinished() }.disabled(!model.transfers.contains { $0.isFinished })
                Button("Stop All") { model.cancelAll() }.disabled(model.activeCount == 0)
            }
            .padding(10)
        }
        .frame(minWidth: 460, minHeight: 220)
        .sheet(item: $m.conflict) { ConflictSheet(conflict: $0) }
    }

    private var summary: String {
        let active = model.activeCount
        if active == 0 { return model.transfers.isEmpty ? "" : "All transfers finished" }
        return active == 1 ? "Copying 1 item" : "Copying \(active) items"
    }
}

struct TransferRow: View {
    @Environment(AppModel.self) private var model
    let item: TransferItem

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(for: item.isFolder ? .folder : UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("“\(item.name)” to \(item.toPhone ? "phone folder " : "")“\(item.destination)”")
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
            }
            Spacer(minLength: 8)
            switch item.state {
            case .queued, .running:
                Button { model.cancel(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Stop")
                    .accessibilityLabel("Stop copying \(item.name)")
            case .failed:
                Button("Retry") { model.retry(item.id) }
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var detail: some View {
        switch item.state {
        case .queued:
            Text("Waiting…").font(.caption).foregroundStyle(.secondary)
        case .running where item.isFolder:
            ProgressView().progressViewStyle(.linear)
        case .running:
            ProgressView(value: Double(item.done), total: Double(max(item.total, 1)))
            Text("\(bytes(item.done)) of \(bytes(item.total))").font(.caption).foregroundStyle(.secondary)
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .skipped:
            Text("Skipped").font(.caption).foregroundStyle(.secondary)
        case .cancelled:
            Text("Stopped").font(.caption).foregroundStyle(.secondary)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    private func bytes(_ n: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }
}

struct ConflictSheet: View {
    @Environment(AppModel.self) private var model
    let conflict: PendingConflict
    @State private var applyAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 6) {
                    Text("An item named “\(conflict.name)” already exists in this location.").font(.headline)
                    Text(explanation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if conflict.more { Toggle("Apply to All", isOn: $applyAll) }
                }
            }
            HStack {
                Button("Skip") { model.resolveConflict(.skip, applyToAll: applyAll) }
                Spacer()
                Button(conflict.isFolder ? "Merge" : "Replace") { model.resolveConflict(.replace, applyToAll: applyAll) }
                Button("Keep Both") { model.resolveConflict(.keepBoth, applyToAll: applyAll) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled()
    }

    private var explanation: String {
        if conflict.isFolder { return "Merge adds the copied items to the existing folder. Nothing in it is deleted." }
        return conflict.toPhone ? "Replace permanently deletes the file on the phone." : "Replace moves the existing file to the Trash."
    }
}
