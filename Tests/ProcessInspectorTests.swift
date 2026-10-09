import XCTest
@testable import TrafficMonitorCore

final class ProcessInspectorTests: XCTestCase {
    private let sample = """
      PID  PPID COMMAND
        1     0 /sbin/launchd
      481     1 /usr/local/opt/node/bin/node /usr/local/lib/node_modules/openclaw/dist/index.js gateway --port 18789
    71082 71000 /Applications/Zed.app/Contents/MacOS/zed
    22130 21996 /Users/me/.workbuddy/binaries/node/versions/22.22.2-6/bin/node /Applications/WorkBuddy.app/Contents/Resources/app.asar.unpacked/main/preload/fork-preload.cjs
    """

    func testParseSkipsHeaderAndReadsAllRows() {
        let result = ProcessInspector.parse(sample)

        XCTAssertEqual(result.count, 4)
        XCTAssertNil(result[0])
        XCTAssertEqual(result[481]?.command.hasPrefix("/usr/local/opt/node/bin/node"), true)
    }

    func testParseResolvesParentName() {
        let result = ProcessInspector.parse(sample)

        XCTAssertEqual(result[481]?.parentPID, 1)
        XCTAssertEqual(result[481]?.parentName, "launchd")
        XCTAssertEqual(result[71082]?.parentPID, 71000)
        XCTAssertEqual(result[71082]?.parentName, "", "父进程不在快照里时应留空")
    }

    func testParseKeepsFullCommandWithSpaces() {
        let result = ProcessInspector.parse(sample)

        XCTAssertEqual(result[22130]?.command.contains("app.asar.unpacked/main/preload/fork-preload.cjs"), true)
    }

    func testParseRejectsMalformedLines() {
        XCTAssertNil(ProcessInspector.parseLine("PID PPID COMMAND"))
        XCTAssertNil(ProcessInspector.parseLine(""))
        XCTAssertNil(ProcessInspector.parseLine("481 1"))
        XCTAssertNil(ProcessInspector.parseLine("481 1   "))
    }

    func testRealSnapshotContainsCurrentProcess() throws {
        let result = try ProcessInspector.snapshot()

        XCTAssertGreaterThan(result.count, 10)
        let current = result[Int32(ProcessInfo.processInfo.processIdentifier)]
        XCTAssertNotNil(current, "当前测试进程应当出现在 ps 快照中")
        XCTAssertTrue(current?.command.contains("xctest") ?? false)
    }
}
