import Foundation

/// 展开后的明细行：某个进程名下的具体脚本与启动者。
public struct ProcessBreakdown: Equatable, Sendable, Identifiable {
    /// 显示标识，如 `node · tsserver.js`。
    public let label: String
    /// 启动者（父进程名），如 `zed`。
    public let parent: String
    /// 完整命令行。
    public let command: String
    /// 该明细对应的进程 id（可能同时有多个实例）。
    public let pids: [Int32]
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(
        label: String,
        parent: String,
        command: String,
        pids: [Int32] = [],
        bytesIn: UInt64,
        bytesOut: UInt64
    ) {
        self.label = label
        self.parent = parent
        self.command = command
        self.pids = pids
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    public var id: String {
        "\(label)\u{1}\(parent)\u{1}\(command)"
    }

    public var total: UInt64 {
        bytesIn &+ bytesOut
    }

    /// 展开时只显示脚本部分，进程名由父行承担。
    /// `node · tsserver.js` → `tsserver.js`；无法细分时回退为原标识。
    public var scriptName: String {
        let parts = label.components(separatedBy: " · ")
        guard parts.count > 1 else {
            return label
        }
        return parts.dropFirst().joined(separator: " · ")
    }

    public var pidText: String {
        pids.map(String.init).joined(separator: ", ")
    }

    /// 只要有一个实例还在运行，就算运行中。
    public func isRunning(activePIDs: Set<Int32>) -> Bool {
        pids.contains { activePIDs.contains($0) }
    }

    public func statusText(activePIDs: Set<Int32>) -> String {
        guard !pids.isEmpty else {
            return "已退出"
        }
        return isRunning(activePIDs: activePIDs) ? "运行中" : "已退出"
    }
}

/// 折叠状态下一行：按进程名聚合，展开后显示其下的细分项。
public struct ProcessGroup: Equatable, Sendable, Identifiable {
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let children: [ProcessBreakdown]

    public init(name: String, bytesIn: UInt64, bytesOut: UInt64, children: [ProcessBreakdown]) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.children = children
    }

    /// 由明细汇总出总量，避免调用方重复计算。
    public init(name: String, children: [ProcessBreakdown]) {
        self.init(
            name: name,
            bytesIn: children.reduce(0) { $0 &+ $1.bytesIn },
            bytesOut: children.reduce(0) { $0 &+ $1.bytesOut },
            children: children
        )
    }

    public var id: String { name }

    public var total: UInt64 {
        bytesIn &+ bytesOut
    }

    /// 只有一个子项且没有细分出脚本时，展开没有意义。
    public var isExpandable: Bool {
        guard children.count > 0 else {
            return false
        }
        if children.count > 1 {
            return true
        }
        return children[0].label != name
    }

    /// 折叠行显示的命令：取流量最大的那条明细。
    public var summaryCommand: String {
        children.max { $0.total < $1.total }?.command ?? ""
    }

    public var allPIDs: [Int32] {
        children.flatMap(\.pids)
    }

    public var pidSummaryText: String {
        let count = allPIDs.count
        return count == 0 ? "—" : "\(count) 个"
    }

    public func runningBreakdownCount(activePIDs: Set<Int32>) -> Int {
        children.filter { $0.isRunning(activePIDs: activePIDs) }.count
    }

    public func statusText(activePIDs: Set<Int32>) -> String {
        let running = runningBreakdownCount(activePIDs: activePIDs)
        return running == 0 ? "已退出" : "运行中 \(running)"
    }
}

public extension ProcessGroup {
    static var defaultSortOrder: [KeyPathComparator<ProcessGroup>] {
        [KeyPathComparator(\.total, order: .reverse)]
    }

    static var sortableComparators: [KeyPathComparator<ProcessGroup>] {
        [
            KeyPathComparator(\.name),
            KeyPathComparator(\.bytesIn, order: .reverse),
            KeyPathComparator(\.bytesOut, order: .reverse),
            KeyPathComparator(\.total, order: .reverse),
        ]
    }
}

/// 生成可复制的纯文本行，供界面右键菜单与快捷键使用。
public enum ProcessRowFormatter {
    public static let header = "进程\t启动者\tPID\t状态\t上传\t下载\t总计\t命令"

    public static func text(
        for group: ProcessGroup,
        activePIDs: Set<Int32> = [],
        indent: String = ""
    ) -> String {
        line(
            indent: indent,
            name: group.name,
            parent: "",
            pid: group.pidSummaryText,
            status: group.statusText(activePIDs: activePIDs),
            bytesIn: group.bytesIn,
            bytesOut: group.bytesOut,
            total: group.total,
            command: group.summaryCommand
        )
    }

    public static func text(
        for breakdown: ProcessBreakdown,
        activePIDs: Set<Int32> = [],
        indent: String = "  "
    ) -> String {
        line(
            indent: indent,
            name: breakdown.scriptName,
            parent: breakdown.parent,
            pid: breakdown.pidText,
            status: breakdown.statusText(activePIDs: activePIDs),
            bytesIn: breakdown.bytesIn,
            bytesOut: breakdown.bytesOut,
            total: breakdown.total,
            command: breakdown.command
        )
    }

    /// 组行加其全部明细，用于「复制全部」。
    public static func text(
        for groups: [ProcessGroup],
        expandedNames: Set<String> = [],
        activePIDs: Set<Int32> = []
    ) -> String {
        var lines: [String] = []
        for group in groups {
            lines.append(text(for: group, activePIDs: activePIDs))
            if expandedNames.contains(group.name) {
                lines.append(contentsOf: group.children.map { text(for: $0, activePIDs: activePIDs) })
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func line(
        indent: String,
        name: String,
        parent: String,
        pid: String,
        status: String,
        bytesIn: UInt64,
        bytesOut: UInt64,
        total: UInt64,
        command: String
    ) -> String {
        [
            indent + name,
            parent,
            pid,
            status,
            ByteFormat.size(bytesIn),
            ByteFormat.size(bytesOut),
            ByteFormat.size(total),
            command,
        ].joined(separator: "\t")
    }
}
