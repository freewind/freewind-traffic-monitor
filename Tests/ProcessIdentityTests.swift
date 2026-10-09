import XCTest
@testable import TrafficMonitorCore

final class ProcessIdentityTests: XCTestCase {
    func testNameIsExecutableBaseName() {
        XCTAssertEqual(
            ProcessIdentity.name(from: "/usr/local/opt/node/bin/node /a/b/index.js"),
            "node"
        )
        XCTAssertEqual(
            ProcessIdentity.name(from: "/Applications/Zed.app/Contents/MacOS/zed --flag"),
            "zed"
        )
    }

    func testNodeLabelUsesScriptName() {
        let label = ProcessIdentity.label(
            name: "node",
            command: "/usr/local/Cellar/node/26.4.0/bin/node --max-old-space-size=8092 /x/typescript/lib/tsserver.js --serverMode partialSemantic"
        )

        XCTAssertEqual(label, "node · tsserver.js")
    }

    func testNodeLabelSkipsOptionArguments() {
        let label = ProcessIdentity.label(
            name: "node",
            command: "/usr/local/bin/node /usr/local/bin/vtsls /usr/local/bin/vtsls --stdio"
        )

        XCTAssertEqual(label, "node · vtsls")
    }

    func testGenericIndexFileFallsBackToPackageDirectory() {
        let label = ProcessIdentity.label(
            name: "node",
            command: "/usr/local/opt/node/bin/node /usr/local/lib/node_modules/openclaw/dist/index.js gateway --port 18789"
        )

        XCTAssertEqual(label, "node · openclaw")
    }

    func testNodeWithoutScriptArgumentKeepsPlainName() {
        let label = ProcessIdentity.label(name: "node", command: "node -e \"console.log(1)\"")

        XCTAssertEqual(label, "node")
    }

    func testNonInterpreterKeepsPlainName() {
        let label = ProcessIdentity.label(
            name: "Google Chrome Helper",
            command: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper --type=renderer /tmp/x.js"
        )

        XCTAssertEqual(label, "Google Chrome Helper")
    }

    func testRewrittenArgv0WinsOverScriptArgument() {
        let label = ProcessIdentity.label(name: "node", command: "next-server (v16.3.8)")

        XCTAssertEqual(label, "node · next-server")
    }

    func testLongScriptNameIsTruncated() {
        let longName = String(repeating: "a", count: 60) + ".js"
        let label = ProcessIdentity.label(name: "node", command: "node /x/chunks/\(longName) 53834")

        XCTAssertEqual(label.count, "node · ".count + ProcessIdentity.maxDetailLength)
        XCTAssertTrue(label.hasSuffix("…"))
    }

    func testPlainNodePathScriptIsIdentified() {
        let label = ProcessIdentity.label(name: "node", command: "node /tmp/dl.js --count 3")

        XCTAssertEqual(label, "node · dl.js")
    }
}
