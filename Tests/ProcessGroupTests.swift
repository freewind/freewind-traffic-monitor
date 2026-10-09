import XCTest
@testable import TrafficMonitorCore

final class ProcessGroupTests: XCTestCase {
    private func breakdown(
        _ label: String,
        parent: String = "",
        command: String = "",
        bytesIn: UInt64 = 0,
        bytesOut: UInt64 = 0
    ) -> ProcessBreakdown {
        ProcessBreakdown(label: label, parent: parent, command: command, bytesIn: bytesIn, bytesOut: bytesOut)
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
