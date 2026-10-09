import XCTest
@testable import TrafficMonitorCore

final class NettopCollectorTests: XCTestCase {
    /// 与真实 `nettop -l 1 -P -x -J bytes_in,bytes_out -n` 输出一致，含表头行。
    private let sample = """
                                                                                                          bytes_in       bytes_out
        launchd.1                                                                                                0               0
        mDNSResponder.225                                                                                509312016        46412633
        Paseo Helper.98773                                                                                 3602184          256291
        FreewindSendPas.504                                                                                    123             273
        """

    func testParseSkipsHeaderAndParsesAllRows() {
        let result = NettopCollector.parse(sample)

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(
            result[0],
            ProcessTraffic(name: "launchd", pid: 1, bytesIn: 0, bytesOut: 0)
        )
    }

    func testParseKeepsSpacesInProcessName() {
        let result = NettopCollector.parse(sample)
        let helper = result.first { $0.pid == 98773 }

        XCTAssertEqual(helper?.name, "Paseo Helper")
        XCTAssertEqual(helper?.bytesIn, 3_602_184)
        XCTAssertEqual(helper?.bytesOut, 256_291)
    }

    func testParseTruncatedProcessName() {
        let result = NettopCollector.parse(sample)
        let truncated = result.first { $0.pid == 504 }

        XCTAssertEqual(truncated?.name, "FreewindSendPas")
    }

    func testParseRejectsMalformedLines() {
        XCTAssertNil(NettopCollector.parseLine(""))
        XCTAssertNil(NettopCollector.parseLine("bytes_in bytes_out"))
        XCTAssertNil(NettopCollector.parseLine("node.481 notanumber 100"))
        XCTAssertNil(NettopCollector.parseLine("nodotseparator 100 200"))
        XCTAssertNil(NettopCollector.parseLine("node.notapid 100 200"))
    }

    func testParseHandlesUnitSuffixes() {
        XCTAssertEqual(NettopCollector.parseBytes("1234"), 1_234)
        XCTAssertEqual(NettopCollector.parseBytes("1.5K"), 1_500)
        XCTAssertEqual(NettopCollector.parseBytes("2M"), 2_000_000)
        XCTAssertNil(NettopCollector.parseBytes("abc"))
    }

    func testRealSnapshotReturnsProcesses() throws {
        let result = try NettopCollector.snapshot()

        XCTAssertGreaterThanOrEqual(result.count, 10, "真实 nettop 输出应至少包含 10 个进程")
        XCTAssertTrue(result.contains { $0.name == "mDNSResponder" || $0.pid == 225 })
        XCTAssertTrue(result.allSatisfy { $0.pid > 0 && !$0.name.isEmpty })
    }
}
