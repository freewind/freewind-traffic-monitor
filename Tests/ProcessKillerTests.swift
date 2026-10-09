import XCTest
@testable import TrafficMonitorCore

final class ProcessKillerTests: XCTestCase {
    func testProtectedPIDsAreRejected() {
        XCTAssertTrue(ProcessKiller.isProtected(0))
        XCTAssertTrue(ProcessKiller.isProtected(1))
        XCTAssertTrue(ProcessKiller.isProtected(Int32(ProcessInfo.processInfo.processIdentifier)))

        let outcome = ProcessKiller.terminate(pid: 1)
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.message, "该进程受保护，不能结束")
    }

    func testNonExistentProcessFails() {
        let pid: Int32 = 9_999_999
        let outcome = ProcessKiller.terminate(pid: pid)

        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.pid, pid)
        XCTAssertFalse(outcome.message.isEmpty)
    }

    func testErrorMessageIsNilWhenAllSucceed() {
        let outcomes = [ProcessKiller.Outcome(pid: 42, succeeded: true, message: "ok")]

        XCTAssertNil(ProcessKiller.errorMessage(from: outcomes))
    }

    func testErrorMessageAggregatesFailures() {
        let outcomes = [
            ProcessKiller.Outcome(pid: 42, succeeded: true, message: "ok"),
            ProcessKiller.Outcome(pid: 43, succeeded: false, message: "Operation not permitted"),
        ]

        let message = ProcessKiller.errorMessage(from: outcomes)

        XCTAssertEqual(message, "结束进程失败 —— PID 43: Operation not permitted")
    }

    func testTerminateSendsSignalToChildProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()

        let pid = Int32(process.processIdentifier)
        let outcome = ProcessKiller.terminate(pid: pid)

        XCTAssertTrue(outcome.succeeded, "应当能结束自己启动的子进程：\(outcome.message)")
        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
    }
}
