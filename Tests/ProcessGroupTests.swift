import XCTest
@testable import TrafficMonitorCore

final class ProcessGroupTests: XCTestCase {
    private func breakdown(
        _ label: String,
        parent: String = "",
        command: String = "",
        pids: [Int32] = [],
        bytesIn: UInt64 = 0,
        bytesOut: UInt64 = 0
    ) -> ProcessBreakdown {
        ProcessBreakdown(
            label: label,
            parent: parent,
            command: command,
            pids: pids,
            bytesIn: bytesIn,
            bytesOut: bytesOut
        )
    }

    func testGroupSumsChildren() {
        let group = ProcessGroup(name: "node", children: [
            breakdown("node · a.js", bytesIn: 100, bytesOut: 200),
            breakdown("node · b.js", bytesIn: 1_000, bytesOut: 0),
        ])

        XCTAssertEqual(group.bytesIn, 1_100)
        XCTAssertEqual(group.bytesOut, 200)
        XCTAssertEqual(group.total, 1_300)
    }

    func testScriptNameStripsProcessName() {
        XCTAssertEqual(breakdown("node · tsserver.js").scriptName, "tsserver.js")
        XCTAssertEqual(breakdown("Google Chrome Helper").scriptName, "Google Chrome Helper")
    }

    func testNotExpandableWhenSinglePlainChild() {
        let group = ProcessGroup(name: "curl", children: [breakdown("curl")])

        XCTAssertFalse(group.isExpandable)
    }

    func testExpandableWhenScriptDiffers() {
        let group = ProcessGroup(name: "node", children: [breakdown("node · vite.js")])

        XCTAssertTrue(group.isExpandable)
    }

    func testExpandableWhenMultipleChildren() {
        let group = ProcessGroup(name: "node", children: [breakdown("node"), breakdown("node")])

        XCTAssertTrue(group.isExpandable)
    }

    func testSummaryCommandIsLargestChild() {
        let group = ProcessGroup(name: "node", children: [
            breakdown("node · a.js", command: "node /a.js", bytesIn: 10),
            breakdown("node · b.js", command: "node /b.js", bytesIn: 9_000),
        ])

        XCTAssertEqual(group.summaryCommand, "node /b.js")
    }

    func testStatusAndPIDSummaryUseActivePIDs() {
        let group = ProcessGroup(name: "node", children: [
            breakdown("node · a.js", pids: [100]),
            breakdown("node · b.js", pids: [200, 201]),
        ])

        XCTAssertEqual(group.pidSummaryText, "3 个")
        XCTAssertEqual(group.statusText(activePIDs: []), "已退出")
        XCTAssertEqual(group.statusText(activePIDs: [100]), "运行中 1")
        XCTAssertEqual(group.statusText(activePIDs: [100, 201]), "运行中 2")
        XCTAssertEqual(group.runningBreakdownCount(activePIDs: [201]), 1)
    }

    func testEmptyGroupShowsDashForPID() {
        XCTAssertEqual(ProcessGroup(name: "gone", children: []).pidSummaryText, "—")
    }

    func testBreakdownStatusWithoutPIDsIsExited() {
        let item = breakdown("node · a.js")

        XCTAssertEqual(item.statusText(activePIDs: [1, 2]), "已退出")
        XCTAssertFalse(item.isRunning(activePIDs: [1, 2]))
    }

    func testDefaultSortIsTotalDescending() {
        let groups = [
            ProcessGroup(name: "node", children: [breakdown("node", bytesIn: 100, bytesOut: 0)]),
            ProcessGroup(name: "curl", children: [breakdown("curl", bytesIn: 5, bytesOut: 5_000)]),
        ]

        let sorted = groups.sorted(using: ProcessGroup.defaultSortOrder)

        XCTAssertEqual(sorted.map(\.name), ["curl", "node"])
    }

    func testSortableComparatorsCoverAllColumns() {
        XCTAssertEqual(ProcessGroup.sortableComparators.count, 4)
    }
}
