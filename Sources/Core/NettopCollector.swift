import Foundation

/// 单个进程的一次流量快照（累计值，自该进程启动起算）。
public struct ProcessTraffic: Equatable, Sendable {
    public let name: String
    public let pid: Int32
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    /// 显示标识：普通进程等于 name，解释器进程会带上脚本名（如 `node · tsserver.js`）。
    public let label: String
    public let command: String
    public let parent: String

    public init(
        name: String,
        pid: Int32,
        bytesIn: UInt64,
        bytesOut: UInt64,
        label: String? = nil,
        command: String = "",
        parent: String = ""
    ) {
        self.name = name
        self.pid = pid
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.label = label ?? name
        self.command = command
        self.parent = parent
    }
}

/// 按进程读取本机流量快照。
///
/// 数据来源是系统自带的 `nettop`：它以 Apple 私有 entitlement
/// `com.apple.private.network.statistics` 读取内核的网络统计。
/// 本工具不申请任何 entitlement，只把 nettop 当作子进程调用并解析其输出，
/// 因此无需开发者签名、无需系统扩展、无需 root。
public enum NettopCollector {
    /// nettop 参数：
    /// - `-l 1` 只采样一次
    /// - `-P` 按进程聚合
    /// - `-x` 关闭交互式界面，输出纯文本
    /// - `-J bytes_in,bytes_out` 只输出上下行累计字节
    /// - `-n` 不做域名反解，避免额外 DNS 开销
    public static let arguments = ["-l", "1", "-P", "-x", "-J", "bytes_in,bytes_out", "-n"]

    public static func snapshot() throws -> [ProcessTraffic] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        try process.run()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NettopError.nonZeroExit(status: process.terminationStatus)
        }

        return parse(String(decoding: data, as: UTF8.self))
    }

    public enum NettopError: Error {
        case nonZeroExit(status: Int32)
    }

    public static func parse(_ output: String) -> [ProcessTraffic] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseLine(String($0)) }
    }

    /// 解析一行输出。数据行形如：
    ///
    ///     Paseo Helper.98773                 3602184           256291
    ///     mDNSResponder.225              509312016         46412633
    ///
    /// 进程名可能含空格，因此从行尾取两个数值，其余部分视为 `名称.pid`。
    public static func parseLine(_ line: String) -> ProcessTraffic? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 3 else {
            return nil
        }

        let outToken = tokens[tokens.count - 1]
        let inToken = tokens[tokens.count - 2]
        guard let bytesOut = parseBytes(outToken), let bytesIn = parseBytes(inToken) else {
            return nil
        }

        let identifier = tokens[0..<(tokens.count - 2)].joined(separator: " ")
        guard let separatorIndex = identifier.lastIndex(of: ".") else {
            return nil
        }

        let name = String(identifier[identifier.startIndex..<separatorIndex])
        let pidText = String(identifier[identifier.index(after: separatorIndex)...])
        guard !name.isEmpty, let pid = Int32(pidText) else {
            return nil
        }

        return ProcessTraffic(name: name, pid: pid, bytesIn: bytesIn, bytesOut: bytesOut)
    }

    static func parseBytes(_ token: String) -> UInt64? {
        if let value = UInt64(token) {
            return value
        }

        let suffixes: [Character: UInt64] = ["K": 1_000, "M": 1_000_000, "G": 1_000_000_000]
        guard let last = token.last, let multiplier = suffixes[last] else {
            return nil
        }

        let numberPart = String(token.dropLast())
        guard let value = Double(numberPart) else {
            return nil
        }

        return UInt64(value * Double(multiplier))
    }
}
