import XCTest
@testable import TrafficMonitorCore

final class ProcessTotalSortingTests: XCTestCase {
    private let rows = [
        ProcessTotal(name: "node", bytesIn: 100, bytesOut: 10),
        ProcessTotal(name: "curl", bytesIn: 5, bytesOut: 5_000),
        ProcessTotal(name: "mDNSResponder", bytesIn: 900, bytesOut: 900),
    ]

    func testDefaultSortIsTotalDescending() {
        let sorted = rows.sorted(using: ProcessTotal.defaultSortOrder)

        XCTAssertEqual(sorted.map(\.name), ["curl", "mDNSResponder", "node"])
    }

    func testSortByBytesInDescending() {
        let comparator = KeyPathComparator(\ProcessTotal.bytesIn, order: .reverse)
        let sorted = rows.sorted(using: [comparator])

        XCTAssertEqual(sorted.map(\.name), ["mDNSResponder", "node", "curl"])
    }

    func testSortByBytesOutDescending() {
        let comparator = KeyPathComparator(\ProcessTotal.bytesOut, order: .reverse)
        let sorted = rows.sorted(using: [comparator])

        XCTAssertEqual(sorted.map(\.name), ["curl", "mDNSResponder", "node"])
    }

    func testSortByNameAscending() {
        let comparator = KeyPathComparator(\ProcessTotal.name)
        let sorted = rows.sorted(using: [comparator])

        XCTAssertEqual(sorted.map(\.name), ["curl", "mDNSResponder", "node"])
    }

    func testSortableComparatorsCoverAllColumns() {
        XCTAssertEqual(ProcessTotal.sortableComparators.count, 5)
    }
}
