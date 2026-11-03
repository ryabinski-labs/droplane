import Foundation

/// The aggregate numbers shown by the bottom copy bar and the toolbar ring.
///
/// `items` must be limited to the current queue cycle by the caller. The cycle
/// starts when the queue starts and ends when the queue is empty, so files that
/// have already finished stay in the total until the whole queue is done.
struct TransferProgress {
    struct Item {
        let name: String
        let total: UInt64
        let done: UInt64
        let state: TransferItem.State
        let isFolder: Bool

        var isFinished: Bool { state != .queued && state != .running }

        /// A file that will move bytes this cycle. Failed, skipped, and cancelled
        /// files are left out so the remaining work can still reach 100%.
        var countsTowardTotal: Bool {
            switch state {
            case .queued, .running, .done: return true
            case .failed, .skipped, .cancelled: return false
            }
        }

        var effectiveDone: UInt64 {
            min(state == .done ? total : done, total)
        }
    }

    let currentName: String?
    let currentIsFile: Bool
    let currentDone: UInt64
    let currentTotal: UInt64
    let overallDone: UInt64
    let overallTotal: UInt64
    let itemCount: Int
    let finishedCount: Int

    init(items: [Item]) {
        let files = items.filter { !$0.isFolder }
        itemCount = files.count
        finishedCount = files.filter(\.isFinished).count

        let counted = files.filter(\.countsTowardTotal)
        overallTotal = counted.reduce(0) { $0 + $1.total }
        overallDone = counted.reduce(0) { $0 + $1.effectiveDone }

        let current = items.first { $0.state == .running } ?? items.first { !$0.isFinished }
        currentName = current?.name
        currentIsFile = current.map { !$0.isFolder } ?? false
        currentTotal = currentIsFile ? current?.total ?? 0 : 0
        currentDone = currentIsFile ? current?.effectiveDone ?? 0 : 0
    }

    var fraction: Double {
        overallTotal == 0 ? 0 : Double(overallDone) / Double(overallTotal)
    }

    var percent: Int { Int((fraction * 100).rounded()) }

    /// 1-based position of the current item among the files in the cycle.
    var position: Int {
        itemCount == 0 ? 0 : min(finishedCount + 1, itemCount)
    }

    var showsPosition: Bool { itemCount > 1 }
    var showsPerFileLine: Bool { itemCount > 1 && currentIsFile }
    var isPreparing: Bool { overallTotal == 0 }
}
