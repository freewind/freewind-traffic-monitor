import XCTest
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
