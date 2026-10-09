import XCTest
@testable import TrafficMonitorCore

final class ProxyProcessFilterTests: XCTestCase {
    private let rows = [
        ProcessTotal(name: "verge-mihomo", bytesIn: 999, bytesOut: 999),
        ProcessTotal(name: "curl", bytesIn: 10, bytesOut: 1),
        ProcessTotal(name: "clash", bytesIn: 5, bytesOut: 5),
    ]

    func testFiltersProxyProcessesByDefault() {
        let visible = ProxyProcessFilter.visible(rows)

        XCTAssertEqual(visible.map(\.name), ["curl"])
    }

    func testDisabledFilterKeepsEverything() {
        let visible = ProxyProcessFilter.visible(rows, enabled: false)

        XCTAssertEqual(visible.count, 3)
    }

    func testFiltersProxyProcessWithScriptSuffix() {
        let labeled = [
            ProcessTotal(name: "verge-mihomo · index.js", bytesIn: 10, bytesOut: 10),
            ProcessTotal(name: "curl", bytesIn: 1, bytesOut: 1),
        ]

        XCTAssertEqual(ProxyProcessFilter.visible(labeled).map(\.name), ["curl"])
    }

    func testCustomIgnoreList() {
        let visible = ProxyProcessFilter.visible(rows, ignoring: ["curl"])

        XCTAssertEqual(visible.map(\.name), ["verge-mihomo", "clash"])
    }
}
