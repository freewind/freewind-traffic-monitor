import XCTest
@testable import TrafficMonitorCore

final class ProcessRowFormatterTests: XCTestCase {
    private let group = ProcessGroup(name: "node", children: [
        ProcessBreakdown(
            label: "node · vite.js",
            parent: "npm",
            command: "node /x/vite.js --port 3000",
            bytesIn: 2_000,
            bytesOut: 3_000
        )
    ])

    func testHeaderListsAllColumns() {
        XCTAssertEqual(ProcessRowFormatter.header, "进程\t启动者\t上传\t下载\t总计\t命令")
    }

    func testGroupLineContainsValuesAndCommand() {
        let line = ProcessRowFormatter.text(for: group)

        XCTAssertEqual(line, "node\t\t2.00 KB\t3.00 KB\t5.00 KB\tnode /x/vite.js --port 3000")
    }

    func testBreakdownLineIsIndentedAndShowsParent() {
        let line = ProcessRowFormatter.text(for: group.children[0])

        XCTAssertEqual(line, "  vite.js\tnpm\t2.00 KB\t3.00 KB\t5.00 KB\tnode /x/vite.js --port 3000")
    }

    func testFullTextIncludesChildrenOnlyWhenExpanded() {
        let collapsed = ProcessRowFormatter.text(for: [group])
        let expanded = ProcessRowFormatter.text(for: [group], expandedNames: ["node"])

        XCTAssertEqual(collapsed.split(separator: "\n").count, 1)
        XCTAssertEqual(expanded.split(separator: "\n").count, 2)
    }
}
