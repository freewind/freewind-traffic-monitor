import Foundation

/// 进程的静态信息：命令行、父进程等。
public struct ProcessDetails: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let command: String
    public let parentName: String

    public init(pid: Int32, parentPID: Int32, command: String, parentName: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
        self.parentName = parentName
    }
}

/// 读取本机进程的命令行信息。
///
/// nettop 只给进程名（大量 node 进程都叫 `node`），要区分具体是哪个脚本，
/// 需要补一份 `ps -axo pid,ppid,command` 的信息，按 pid 与 nettop 快照合并。
/// 进程退出后 ps 就查不到，因此必须在采样当时保存。
public enum ProcessInspector {
    public static let arguments = ["-axo", "pid,ppid,command"]

    public static func snapshot() throws -> [Int32: ProcessDetails] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        try process.run()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NettopCollector.NettopError.nonZeroExit(status: process.terminationStatus)
        }

        return parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ output: String) -> [Int32: ProcessDetails] {
        var commands: [Int32: String] = [:]
        var parents: [Int32: Int32] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let record = parseLine(String(line)) else {
                continue
            }
            commands[record.pid] = record.command
            parents[record.pid] = record.parentPID
        }

        var result: [Int32: ProcessDetails] = [:]
        for (pid, command) in commands {
            let parentPID = parents[pid] ?? 0
            let parentName = commands[parentPID].map(ProcessIdentity.name(from:)) ?? ""
            result[pid] = ProcessDetails(
                pid: pid,
                parentPID: parentPID,
                command: command,
                parentName: parentName
            )
        }

        return result
    }

    /// 解析一行 `ps -axo pid,ppid,command` 输出：前两列是数字，其余整段是命令行。
    static func parseLine(_ line: String) -> (pid: Int32, parentPID: Int32, command: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }

        var rest = Substring(trimmed)
        var numbers: [Int32] = []

        while numbers.count < 2 {
            guard let spaceIndex = rest.firstIndex(of: " ") else {
                return nil
            }
            guard let value = Int32(rest[rest.startIndex..<spaceIndex]) else {
                return nil
            }
            numbers.append(value)
            rest = rest[rest.index(after: spaceIndex)...]
            rest = Substring(rest.drop(while: { $0 == " " }))
        }

        let command = rest.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else {
            return nil
        }

        return (numbers[0], numbers[1], command)
    }
}
