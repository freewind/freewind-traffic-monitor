import Darwin
import Foundation

/// 结束本机进程。
///
/// 只能结束当前用户有权限的进程；系统进程或他人进程会因权限不足而失败，
/// 这里把失败原因如实返回，由界面提示。
public enum ProcessKiller {
    public struct Outcome: Equatable, Sendable {
        public let pid: Int32
        public let succeeded: Bool
        public let message: String

        public init(pid: Int32, succeeded: Bool, message: String) {
            self.pid = pid
            self.succeeded = succeeded
            self.message = message
        }
    }

    /// 这些 pid 不允许结束：0/1 是内核与 launchd，负数无意义。
    static func isProtected(_ pid: Int32) -> Bool {
        pid <= 1 || pid == Int32(ProcessInfo.processInfo.processIdentifier)
    }

    /// 默认发送 SIGTERM，`force` 为真时发送 SIGKILL。
    public static func terminate(pid: Int32, force: Bool = false) -> Outcome {
        guard !isProtected(pid) else {
            return Outcome(pid: pid, succeeded: false, message: "该进程受保护，不能结束")
        }

        let signalNumber = force ? SIGKILL : SIGTERM
        guard kill(pid, signalNumber) == 0 else {
            let reason = String(cString: strerror(errno))
            return Outcome(pid: pid, succeeded: false, message: reason)
        }

        return Outcome(pid: pid, succeeded: true, message: "已发送结束信号")
    }

    public static func terminate(pids: [Int32], force: Bool = false) -> [Outcome] {
        pids.map { terminate(pid: $0, force: force) }
    }

    /// 汇总多条结果，全部成功时返回 nil，否则返回可直接展示的错误说明。
    public static func errorMessage(from outcomes: [Outcome]) -> String? {
        let failures = outcomes.filter { !$0.succeeded }
        guard !failures.isEmpty else {
            return nil
        }
        let details = failures.map { "PID \($0.pid): \($0.message)" }.joined(separator: "；")
        return "结束进程失败 —— \(details)"
    }
}
