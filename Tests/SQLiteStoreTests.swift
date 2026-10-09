import XCTest
import SQLite3
@testable import TrafficMonitorCore

final class SQLiteStoreTests: XCTestCase {
    private func makeStore() throws -> SQLiteStore {
        try SQLiteStore(path: ":memory:")
    }

    private func breakdown(
        _ label: String,
        parent: String = "",
        command: String = "",
        bytesIn: UInt64 = 0,
        bytesOut: UInt64 = 0
    ) -> ProcessBreakdown {
        ProcessBreakdown(label: label, parent: parent, command: command, bytesIn: bytesIn, bytesOut: bytesOut)
    }

    func testGroupedTotalsAggregateByProcessName() throws {
        let store = try makeStore()

        try store.record([
            TrafficDelta(timestamp: 100, name: "node", pid: 1, bytesIn: 10, bytesOut: 10, label: "node · a.js"),
            TrafficDelta(timestamp: 200, name: "node", pid: 2, bytesIn: 5, bytesOut: 5, label: "node · b.js"),
            TrafficDelta(timestamp: 200, name: "curl", pid: 3, bytesIn: 1, bytesOut: 50, label: "curl"),
        ])

        let groups = try store.groupedTotals(from: 0, to: 1_000)

        XCTAssertEqual(groups.map(\.name), ["curl", "node"])
        XCTAssertEqual(groups[1].bytesIn, 15)
        XCTAssertEqual(groups[1].bytesOut, 15)
        XCTAssertEqual(groups[1].children.map(\.label).sorted(), ["node · a.js", "node · b.js"])
    }

    func testGroupedTotalsRangeIsHalfOpen() throws {
        let store = try makeStore()

        try store.record([
            TrafficDelta(timestamp: 99, name: "before", pid: 1, bytesIn: 10, bytesOut: 0),
            TrafficDelta(timestamp: 100, name: "inside", pid: 2, bytesIn: 20, bytesOut: 0),
            TrafficDelta(timestamp: 199, name: "inside", pid: 2, bytesIn: 30, bytesOut: 0),
            TrafficDelta(timestamp: 200, name: "after", pid: 3, bytesIn: 40, bytesOut: 0),
        ])

        let groups = try store.groupedTotals(from: 100, to: 200)

        XCTAssertEqual(groups.map(\.name), ["inside"])
        XCTAssertEqual(groups[0].bytesIn, 50)
    }

    func testChildrenCarryCommandAndParent() throws {
        let store = try makeStore()

        try store.record([
            TrafficDelta(
                timestamp: 1,
                name: "node",
                pid: 1,
                bytesIn: 10,
                bytesOut: 0,
                label: "node · tsserver.js",
                command: "node /x/tsserver.js",
                parent: "zed"
            )
        ])

        let children = try store.groupedTotals(from: 0, to: 10)[0].children

        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].parent, "zed")
        XCTAssertEqual(children[0].command, "node /x/tsserver.js")
        XCTAssertEqual(children[0].scriptName, "tsserver.js")
    }

    func testLegacyRowsWithoutLabelFallBackToName() throws {
        let store = try makeStore()

        try store.record([
            TrafficDelta(timestamp: 1, name: "node", pid: 1, bytesIn: 7, bytesOut: 0, label: "")
        ])

        let group = try store.groupedTotals(from: 0, to: 10)[0]

        XCTAssertEqual(group.name, "node")
        XCTAssertEqual(group.children.map(\.label), ["node"])
        XCTAssertFalse(group.isExpandable)
    }

    func testLargeCountersSurviveRoundTrip() throws {
        let store = try makeStore()
        let big: UInt64 = 9_000_000_000

        try store.record([
            TrafficDelta(timestamp: 1, name: "curl", pid: 1, bytesIn: big, bytesOut: big)
        ])

        let group = try store.groupedTotals(from: 0, to: 10)[0]

        XCTAssertEqual(group.bytesIn, big)
        XCTAssertEqual(group.bytesOut, big)
    }

    func testEmptyRecordWritesNothing() throws {
        let store = try makeStore()

        try store.record([])

        XCTAssertEqual(try store.sampleCount(), 0)
    }

    /// 老版本数据库没有 label/command/parent 列，升级后应自动补列并把 label 回填为进程名。
    func testMigratesLegacyDatabase() throws {
        let path = NSTemporaryDirectory() + "fw-legacy-\(UUID().uuidString).sqlite3"
        try? FileManager.default.removeItem(atPath: path)
        defer { try? FileManager.default.removeItem(atPath: path) }

        var legacyDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &legacyDB), SQLITE_OK)
        let legacySQL = """
        CREATE TABLE traffic (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            name TEXT NOT NULL,
            pid INTEGER NOT NULL,
            bytes_in INTEGER NOT NULL,
            bytes_out INTEGER NOT NULL
        );
        INSERT INTO traffic (ts, name, pid, bytes_in, bytes_out) VALUES (100, 'node', 42, 1000, 2000);
        """
        XCTAssertEqual(sqlite3_exec(legacyDB, legacySQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(legacyDB)

        let store = try SQLiteStore(path: path)
        let columns = try store.columnNames()
        XCTAssertTrue(columns.isSuperset(of: ["label", "command", "parent"]))

        let groups = try store.groupedTotals(from: 0, to: 200)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].name, "node")
        XCTAssertEqual(groups[0].bytesIn, 1_000)
        XCTAssertEqual(groups[0].bytesOut, 2_000)
    }

    /// 写入真实文件并重新打开，便于用外部 sqlite3 工具核对落盘结果。
    func testWritesRealFileAndPersists() throws {
        let path = "/tmp/freewind-traffic-monitor-test.sqlite3"
        try? FileManager.default.removeItem(atPath: path)

        do {
            let store = try SQLiteStore(path: path)
            try store.record([
                TrafficDelta(timestamp: 1_000, name: "curl", pid: 42, bytesIn: 10_000_000, bytesOut: 1_024),
                TrafficDelta(timestamp: 1_000, name: "verge-mihomo", pid: 43, bytesIn: 500, bytesOut: 20_000_000),
            ])
            XCTAssertEqual(try store.sampleCount(), 2)
        }

        let reopened = try SQLiteStore(path: path)
        XCTAssertEqual(try reopened.sampleCount(), 2)
        let groups = try reopened.groupedTotals(from: 0, to: 2_000)
        XCTAssertEqual(groups.map(\.name), ["verge-mihomo", "curl"])
    }

    func testDefaultPathIsStable() throws {
        let first = try SQLiteStore.defaultPath()
        let second = try SQLiteStore.defaultPath()

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasSuffix("freewind-traffic-monitor/traffic.sqlite3"))
    }

    func testUnusedBreakdownHelperMatchesInitializer() {
        XCTAssertEqual(breakdown("x").label, "x")
    }
}
