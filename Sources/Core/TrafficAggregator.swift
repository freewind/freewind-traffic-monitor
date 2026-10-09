import Foundation

/// 一段时间内某个进程（按显示标识细分）新增的流量。
public struct TrafficDelta: Equatable, Sendable {
    public let timestamp: Int64
    /// 显示标识，如 `node · tsserver.js`；普通进程等于进程名。
    public let label: String
    /// 原始进程名，如 `node`。
    public let name: String
    public let pid: Int32
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let command: String
    public let parent: String

    public init(
        timestamp: Int64,
        name: String,
        pid: Int32,
        bytesIn: UInt64,
        bytesOut: UInt64,
        label: String? = nil,
        command: String = "",
        parent: String = ""
    ) {
        self.timestamp = timestamp
        self.label = label ?? name
        self.name = name
        self.pid = pid
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.command = command
        self.parent = parent
    }
}

/// 某进程（显示标识）在某区间内的流量合计。
public struct ProcessTotal: Equatable, Sendable, Identifiable {
    public let name: String
    public let parent: String
    public let command: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(name: String, bytesIn: UInt64, bytesOut: UInt64, parent: String = "", command: String = "") {
        self.name = name
        self.parent = parent
        self.command = command
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    /// 区间内的结果按显示标识分组，因此标识可作唯一键。
    public var id: String { name }

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
            KeyPathComparator(\.parent),
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
///
/// 差值按「标识 + pid」追踪：同一个 `node` 可能同时有多个进程在跑，
/// 但它们的标识不同（脚本不同），因此可以分别统计。
public final class TrafficAggregator {
    private struct Key: Hashable {
        let label: String
        let pid: Int32
    }

    private var lastValues: [Key: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

    public init() {}

    public func ingest(_ snapshot: [ProcessTraffic], at timestamp: Int64) -> [TrafficDelta] {
        var deltas: [TrafficDelta] = []
        var currentValues: [Key: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

        for item in snapshot {
            let key = Key(label: item.label, pid: item.pid)
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
                    bytesOut: deltaOut,
                    label: item.label,
                    command: item.command,
                    parent: item.parent
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
