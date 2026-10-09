import Foundation

/// 一段时间内某个进程新增的流量。
public struct TrafficDelta: Equatable, Sendable {
    public let timestamp: Int64
    public let name: String
    public let pid: Int32
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(timestamp: Int64, name: String, pid: Int32, bytesIn: UInt64, bytesOut: UInt64) {
        self.timestamp = timestamp
        self.name = name
        self.pid = pid
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// 某进程在某区间内的流量合计。
public struct ProcessTotal: Equatable, Sendable, Identifiable {
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    /// 区间内的结果按进程名分组，因此进程名可作唯一标识。
    public var id: String { name }

    public init(name: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    public var total: UInt64 {
        bytesIn &+ bytesOut
    }
}

public extension ProcessTotal {
    /// 排行默认排序：总流量从大到小，最快看到流量大户。
    static var defaultSortOrder: [KeyPathComparator<ProcessTotal>] {
        [KeyPathComparator(\.total, order: .reverse)]
    }

    /// 供界面切换排序使用的字段集合。
    static var sortableComparators: [KeyPathComparator<ProcessTotal>] {
        [
            KeyPathComparator(\.name),
            KeyPathComparator(\.bytesIn, order: .reverse),
            KeyPathComparator(\.bytesOut, order: .reverse),
            KeyPathComparator(\.total, order: .reverse),
        ]
    }
}

/// 把 nettop 的累计值换算成「本轮新增」。
///
/// nettop 给出的是进程自启动以来的累计字节，因此需要保存上一轮快照做差值：
/// - 首次出现的进程：累计值即本轮新增
/// - 正常增长：本轮新增 = 本轮累计 − 上轮累计
/// - 数值回退（同 pid 被新进程复用）：视为重新开始，本轮累计即新增
public final class TrafficAggregator {
    private struct Key: Hashable {
        let name: String
        let pid: Int32
    }

    private var lastValues: [Key: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

    public init() {}

    public func ingest(_ snapshot: [ProcessTraffic], at timestamp: Int64) -> [TrafficDelta] {
        var deltas: [TrafficDelta] = []
        var currentValues: [Key: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

        for item in snapshot {
            let key = Key(name: item.name, pid: item.pid)
            let previous = lastValues[key]

            let deltaIn = Self.delta(current: item.bytesIn, previous: previous?.bytesIn)
            let deltaOut = Self.delta(current: item.bytesOut, previous: previous?.bytesOut)

            currentValues[key] = (item.bytesIn, item.bytesOut)

            guard deltaIn > 0 || deltaOut > 0 else {
                continue
            }

            deltas.append(
                TrafficDelta(
                    timestamp: timestamp,
                    name: item.name,
                    pid: item.pid,
                    bytesIn: deltaIn,
                    bytesOut: deltaOut
                )
            )
        }

        lastValues = currentValues
        return deltas
    }

    static func delta(current: UInt64, previous: UInt64?) -> UInt64 {
        guard let previous else {
            return current
        }
        return current >= previous ? current - previous : current
    }
}
