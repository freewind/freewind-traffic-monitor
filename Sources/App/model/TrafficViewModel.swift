import Foundation
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

    @Published private(set) var rows: [ProcessTotal] = []
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?

    private let store: SQLiteStore?
    private var lastSampleTimestamp: Int64?

    init(store: SQLiteStore?) {
        self.store = store
    }

    var visibleRows: [ProcessTotal] {
        ProxyProcessFilter.visible(rows, enabled: ignoreProxyProcesses)
    }

    var hiddenProcessCount: Int {
        rows.count - visibleRows.count
    }

    var totalBytesIn: UInt64 {
        visibleRows.reduce(0) { $0 &+ $1.bytesIn }
    }

    var totalBytesOut: UInt64 {
        visibleRows.reduce(0) { $0 &+ $1.bytesOut }
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

        do {
            let (from, to) = timeBounds()
            rows = try store.totals(from: from, to: to)
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
