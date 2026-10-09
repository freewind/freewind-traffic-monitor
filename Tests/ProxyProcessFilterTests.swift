import XCTest
@testable import TrafficMonitorCore

final class ProxyProcessFilterTests: XCTestCase {
    private func group(_ name: String) -> ProcessGroup {
        ProcessGroup(
            name: name,
            children: [ProcessBreakdown(label: name, parent: "", command: name, bytesIn: 1, bytesOut: 1)]
        )
    }

    private var groups: [ProcessGroup] { [group("verge-mihomo"), group("curl"), group("clash")] }

    func testFiltersProxyProcessesByDefault() {
        XCTAssertEqual(ProxyProcessFilter.visible(groups).map(\.name), ["curl"])
    }

    func testDisabledFilterKeepsEverything() {
        XCTAssertEqual(ProxyProcessFilter.visible(groups, enabled: false).count, 3)
    }

    func testCustomIgnoreList() {
        XCTAssertEqual(ProxyProcessFilter.visible(groups, ignoring: ["curl"]).map(\.name), ["verge-mihomo", "clash"])
    }
}
