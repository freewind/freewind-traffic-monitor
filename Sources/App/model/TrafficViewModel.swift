import Foundation
import AppKit
import TrafficMonitorCore

@MainActor
final class TrafficViewModel: ObservableObject {
    enum RangeKind: String, CaseIterable, Identifiable {
        case today
        case last7Days
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "今天"
            case .last7Days: return "近 7 天"
            case .custom: return "自定义"
            }
        }
    }

    @Published var rangeKind: RangeKind = .today
    @Published var customStart = Calendar.current.startOfDay(for: Date().addingTimeInterval(-6 * 86_400))
    @Published var customEnd = Date()
    @Published var ignoreProxyProcesses = true
    @Published var expandedNames: Set<String> = []
    @Published var selectedRowID: String?

    @Published private(set) var groups: [ProcessGroup] = []
    /// 本次刷新时刻仍在运行的 pid，用于区分运行中与已退出。
    @Published private(set) var activePIDs: Set<Int32> = []
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?
    /// 最近一次操作（如结束进程）的结果提示。
    @Published var actionMessage: String?

    private let store: SQLiteStore?
    private var lastSampleTimestamp: Int64?
    private var selectedRowText = ""

    init(store: SQLiteStore?) {
        self.store = store
    }

    var visibleGroups: [ProcessGroup] {
        ProxyProcessFilter.visible(groups, enabled: ignoreProxyProcesses)
    }

    var hiddenProcessCount: Int {
        groups.count - visibleGroups.count
    }

    var totalBytesIn: UInt64 {
        visibleGroups.reduce(0) { $0 &+ $1.bytesIn }
    }

    var totalBytesOut: UInt64 {
        visibleGroups.reduce(0) { $0 &+ $1.bytesOut }
    }

    var totalBytes: UInt64 {
        totalBytesIn &+ totalBytesOut
    }

    var rangeText: String {
        let (from, to) = timeBounds()
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        let start = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(from)))
        let end = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(to)))
        return "\(start) ~ \(end)"
    }

    /// 收到一次采样：换算实时速率并刷新区间排行。
    func apply(_ sample: SamplingScheduler.Sample, interval: TimeInterval) {
        let bytesIn = sample.deltas.reduce(UInt64(0)) { $0 &+ $1.bytesIn }
        let bytesOut = sample.deltas.reduce(UInt64(0)) { $0 &+ $1.bytesOut }

        let elapsed: Double
        if let last = lastSampleTimestamp, sample.timestamp > last {
            elapsed = Double(sample.timestamp - last)
        } else {
            elapsed = interval
        }
        lastSampleTimestamp = sample.timestamp

        downloadRate = Double(bytesIn) / elapsed
        uploadRate = Double(bytesOut) / elapsed

        refresh()
    }

    func refresh() {
        guard let store else {
            lastError = "数据库不可用"
            return
        }

        activePIDs = (try? ProcessInspector.snapshot()).map { Set($0.keys) } ?? []

        do {
            let (from, to) = timeBounds()
            groups = try store.groupedTotals(from: from, to: to)
            lastError = nil
            lastRefresh = Date()
        } catch {
            lastError = "查询失败：\(error)"
        }
    }

    func resetRates() {
        downloadRate = 0
        uploadRate = 0
        lastSampleTimestamp = nil
    }

    func isExpanded(_ group: ProcessGroup) -> Bool {
        expandedNames.contains(group.name)
    }

    func toggleExpansion(_ group: ProcessGroup) {
        if expandedNames.contains(group.name) {
            expandedNames.remove(group.name)
        } else {
            expandedNames.insert(group.name)
        }
    }

    func select(id: String, text: String) {
        selectedRowID = id
        selectedRowText = text
    }

    func copy(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func copyCommand(of group: ProcessGroup) {
        copy(group.children.map(\.command).filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    func copyRow(_ text: String) {
        copy(text)
    }

    func copyAll() {
        var text = ProcessRowFormatter.header + "\n"
        text += ProcessRowFormatter.text(
            for: visibleGroups,
            expandedNames: expandedNames,
            activePIDs: activePIDs
        )
        copy(text)
    }

    /// 结束进程；全部成功返回 nil，否则返回可直接展示的错误说明。
    @discardableResult
    func terminate(pids: [Int32]) -> String? {
        let outcomes = ProcessKiller.terminate(pids: pids)
        refresh()

        let error = ProcessKiller.errorMessage(from: outcomes)
        actionMessage = error ?? "已结束 \(pids.count) 个进程"
        return error
    }

    func copySelection() {
        copy(selectedRowText)
    }

    /// 左闭右开区间 [from, to)。
    func timeBounds(now: Date = Date()) -> (Int64, Int64) {
        RangeCalculator.bounds(for: currentRange, now: now)
    }

    var currentRange: TrafficRange {
        switch rangeKind {
        case .today:
            return .today
        case .last7Days:
            return .lastDays(7)
        case .custom:
            return .custom(from: customStart, to: customEnd)
        }
    }
}
