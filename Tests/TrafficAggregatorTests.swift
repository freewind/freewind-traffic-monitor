import XCTest
@testable import TrafficMonitorCore

final class TrafficAggregatorTests: XCTestCase {
    func testFirstSnapshotCountsAsDelta() {
        let aggregator = TrafficAggregator()
        let snapshot = [
            ProcessTraffic(name: "node", pid: 100, bytesIn: 1_000, bytesOut: 200),
            ProcessTraffic(name: "curl", pid: 200, bytesIn: 50, bytesOut: 10),
        ]

        let deltas = aggregator.ingest(snapshot, at: 1_000)

        XCTAssertEqual(deltas.count, 2)
        XCTAssertEqual(deltas[0].bytesIn, 1_000)
        XCTAssertEqual(deltas[0].bytesOut, 200)
        XCTAssertEqual(deltas[0].timestamp, 1_000)
        XCTAssertEqual(deltas[1].name, "curl")
    }

    func testSecondSnapshotOnlyRecordsIncrease() {
        let aggregator = TrafficAggregator()
        _ = aggregator.ingest(
            [ProcessTraffic(name: "node", pid: 100, bytesIn: 1_000, bytesOut: 200)],
            at: 1_000
        )

        let deltas = aggregator.ingest(
            [ProcessTraffic(name: "node", pid: 100, bytesIn: 3_500, bytesOut: 260)],
            at: 1_005
        )

        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas[0].bytesIn, 2_500)
        XCTAssertEqual(deltas[0].bytesOut, 60)
        XCTAssertEqual(deltas[0].timestamp, 1_005)
    }

    func testUnchangedSnapshotProducesNoDelta() {
        let aggregator = TrafficAggregator()
        _ = aggregator.ingest(
            [ProcessTraffic(name: "node", pid: 100, bytesIn: 1_000, bytesOut: 200)],
            at: 1_000
        )

        let deltas = aggregator.ingest(
            [ProcessTraffic(name: "node", pid: 100, bytesIn: 1_000, bytesOut: 200)],
            at: 1_005
        )

        XCTAssertTrue(deltas.isEmpty)
    }

    func testCounterResetIsTreatedAsNewProcess() {
        let aggregator = TrafficAggregator()
        _ = aggregator.ingest(
            [ProcessTraffic(name: "node", pid: 100, bytesIn: 9_000, bytesOut: 200)],
            at: 1_000
        )

        let deltas = aggregator.ingest(
            [ProcessTraffic(name: "node", pid: 100, bytesIn: 400, bytesOut: 0)],
            at: 1_005
        )

        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas[0].bytesIn, 400)
        XCTAssertEqual(deltas[0].bytesOut, 0)
    }

    func testProcessReappearingIsTreatedAsNewProcess() {
        let aggregator = TrafficAggregator()
        _ = aggregator.ingest(
            [ProcessTraffic(name: "curl", pid: 300, bytesIn: 5_000, bytesOut: 0)],
            at: 1_000
        )
        _ = aggregator.ingest([], at: 1_005)

        let deltas = aggregator.ingest(
            [ProcessTraffic(name: "curl", pid: 300, bytesIn: 700, bytesOut: 0)],
            at: 1_010
        )

        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas[0].bytesIn, 700)
    }

    func testDifferentLabelsOfSameNameAreTrackedSeparately() {
        let aggregator = TrafficAggregator()
        _ = aggregator.ingest(
            [
                ProcessTraffic(name: "node", pid: 1, bytesIn: 100, bytesOut: 0, label: "node · a.js"),
                ProcessTraffic(name: "node", pid: 2, bytesIn: 200, bytesOut: 0, label: "node · b.js"),
            ],
            at: 1
        )

        let deltas = aggregator.ingest(
            [
                ProcessTraffic(name: "node", pid: 1, bytesIn: 300, bytesOut: 0, label: "node · a.js"),
                ProcessTraffic(name: "node", pid: 2, bytesIn: 500, bytesOut: 0, label: "node · b.js"),
            ],
            at: 2
        )

        XCTAssertEqual(deltas.count, 2)
        XCTAssertEqual(deltas.first { $0.label == "node · a.js" }?.bytesIn, 200)
        XCTAssertEqual(deltas.first { $0.label == "node · b.js" }?.bytesIn, 300)
    }

    func testDeltaHelperHandlesMissingAndRegressedValues() {
        XCTAssertEqual(TrafficAggregator.delta(current: 500, previous: nil), 500)
        XCTAssertEqual(TrafficAggregator.delta(current: 500, previous: 200), 300)
        XCTAssertEqual(TrafficAggregator.delta(current: 200, previous: 500), 200)
    }
}
