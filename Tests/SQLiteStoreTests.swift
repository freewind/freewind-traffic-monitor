import XCTest
import SQLite3
@testable import TrafficMonitorCore

final class SQLiteStoreTests: XCTestCase {
    private func makeStore() throws -> SQLiteStore {
        try SQLiteStore(path: ":memory:")
    }

    func testRecordAndAggregateByProcess() throws {
        let store = try makeStore()

        try store.record([
            TrafficDelta(timestamp: 100, name: "node", pid: 1, bytesIn: 10, bytesOut: 10),
            TrafficDelta(timestamp: 200, name: "node", pid: 1, bytesIn: 5, bytesOut: 5),
            TrafficDelta(timestamp: 200, name: "curl", pid: 2, bytesIn: 1, bytesOut: 50),
        ])

        let totals = try store.totals(from: 0, to: 1_000)

        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals[0], ProcessTotal(name: "curl", bytesIn: 1, bytesOut: 50))
        XCTAssertEqual(totals[1], ProcessTotal(name: "node", bytesIn: 15, bytesOut: 15))
        XCTAssertEqual(totals[0].total, 51)
    }

    func testRangeIsHalfOpen() throws {
        let store = try makeStore()

        try store.record([
            TrafficDelta(timestamp: 99, name: "before", pid: 1, bytesIn: 10, bytesOut: 0),
            TrafficDelta(timestamp: 100, name: "inside", pid: 2, bytesIn: 20, bytesOut: 0),
            TrafficDelta(timestamp: 199, name: "inside", pid: 2, bytesIn: 30, bytesOut: 0),
            TrafficDelta(timestamp: 200, name: "after", pid: 3, bytesIn: 40, bytesOut: 0),
        ])

        let totals = try store.totals(from: 100, to: 200)

        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0], ProcessTotal(name: "inside", bytesIn: 50, bytesOut: 0))
    }

    func testLargeCountersSurviveRoundTrip() throws {
        let store = try makeStore()
        let big: UInt64 = 9_000_000_000

        try store.record([
            TrafficDelta(timestamp: 1, name: "curl", pid: 1, bytesIn: big, bytesOut: big)
        ])

        let totals = try store.totals(from: 0, to: 10)

        XCTAssertEqual(totals[0].bytesIn, big)
        XCTAssertEqual(totals[0].bytesOut, big)
    }

    func testEmptyRecordWritesNothing() throws {
        let store = try makeStore()

        try store.record([])

        XCTAssertEqual(try store.sampleCount(), 0)
    }

    /// 写入真实文件并重新打开，便于用外部 sqlite3 工具核对落盘结果。
    func testTotalsGroupByDisplayLabel() throws {
        let store = try makeStore()

        try store.record([
            TrafficDelta(timestamp: 1, name: "node", pid: 1, bytesIn: 100, bytesOut: 0, label: "node · a.js"),
            TrafficDelta(timestamp: 1, name: "node", pid: 2, bytesIn: 300, bytesOut: 0, label: "node · b.js"),
        ])

        let totals = try store.totals(from: 0, to: 10)

        XCTAssertEqual(totals.map(\.name), ["node · b.js", "node · a.js"])
        XCTAssertEqual(totals[0].bytesIn, 300)
    }

    func testStoresCommandAndParent() throws {
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

        let totals = try store.totals(from: 0, to: 10)

        XCTAssertEqual(totals[0].parent, "zed")
        XCTAssertEqual(totals[0].command, "node /x/tsserver.js")
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

        let totals = try store.totals(from: 0, to: 200)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].name, "node")
        XCTAssertEqual(totals[0].bytesIn, 1_000)
        XCTAssertEqual(totals[0].bytesOut, 2_000)
    }

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
        let totals = try reopened.totals(from: 0, to: 2_000)
        XCTAssertEqual(totals[0].name, "verge-mihomo")
        XCTAssertEqual(totals[1].name, "curl")
    }

    func testDefaultPathIsStable() throws {        let first = try SQLiteStore.defaultPath()
        let second = try SQLiteStore.defaultPath()

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasSuffix("freewind-traffic-monitor/traffic.sqlite3"))
    }
}
