import XCTest
@testable import TrafficMonitorCore

final class SamplingSchedulerTests: XCTestCase {
    private func makeSnapshot(_ bytes: UInt64) -> [ProcessTraffic] {
        [ProcessTraffic(name: "curl", pid: 42, bytesIn: bytes, bytesOut: 0)]
    }

    func testFlushWritesDeltaToStore() throws {
        let store = try SQLiteStore(path: ":memory:")
        var currentBytes: UInt64 = 1_000
        var timestamp: Int64 = 10

        let scheduler = SamplingScheduler(
            store: store,
            interval: 60,
            collector: { [self] in makeSnapshot(currentBytes) },
            now: { timestamp }
        )

        scheduler.flush()
        XCTAssertEqual(try store.totals(from: 0, to: 1_000).first?.bytesIn, 1_000)

        currentBytes = 4_000
        timestamp = 20
        scheduler.flush()
        XCTAssertEqual(try store.totals(from: 0, to: 1_000).first?.bytesIn, 4_000)

        currentBytes = 4_000
        timestamp = 30
        scheduler.flush()
        XCTAssertEqual(try store.sampleCount(), 2, "无新增时不应写库")
    }

    func testTimerKeepsSampling() throws {
        let store = try SQLiteStore(path: ":memory:")
        let counter = Counter()

        let scheduler = SamplingScheduler(
            store: store,
            interval: 0.1,
            collector: {
                let value = counter.next()
                return [ProcessTraffic(name: "node", pid: 1, bytesIn: value * 1_000, bytesOut: 0)]
            },
            now: { Int64(Date().timeIntervalSince1970) }
        )

        scheduler.start()
        Thread.sleep(forTimeInterval: 0.55)
        scheduler.stop()

        XCTAssertGreaterThanOrEqual(try store.sampleCount(), 3)
    }

    func testCollectorErrorIsReportedAndDoesNotCrash() throws {
        struct Failure: Error {}
        let store = try SQLiteStore(path: ":memory:")
        let expectation = expectation(description: "onError 被调用")

        let scheduler = SamplingScheduler(
            store: store,
            interval: 60,
            collector: { throw Failure() },
            now: { 0 }
        )
        scheduler.onError = { _ in
            expectation.fulfill()
        }

        scheduler.flush()
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(try store.sampleCount(), 0)
    }

    private final class Counter: @unchecked Sendable {
        private var value: UInt64 = 0
        private let lock = NSLock()

        func next() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }
}
