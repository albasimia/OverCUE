import XCTest
import OverCUECore

final class UnifiedShortcutLearnTests: XCTestCase {
    func testGenericBackendRemainsAvailableWhenACK05Fails() {
        var session = UnifiedShortcutLearnSession()
        session.begin(editorPresetID: "preset-b", target: .action(.playPause))
        session.backendStarted(.genericHID)
        session.backendFailed(.ack05)

        XCTAssertTrue(session.hasAvailableBackend)
        XCTAssertEqual(session.claim(by: .genericHID)?.editorPresetID, "preset-b")
    }

    func testACK05BackendRemainsAvailableWhenGenericHIDFails() {
        var session = UnifiedShortcutLearnSession()
        session.begin(editorPresetID: "preset-a", target: .action(.cue))
        session.backendFailed(.genericHID)
        session.backendStarted(.ack05)

        XCTAssertTrue(session.hasAvailableBackend)
        XCTAssertEqual(session.claim(by: .ack05)?.editorPresetID, "preset-a")
    }

    func testFirstBackendIsTheOnlyWinner() {
        var session = UnifiedShortcutLearnSession()
        session.begin(editorPresetID: "preset-a", target: .action(.cue))
        session.backendStarted(.genericHID)
        session.backendStarted(.ack05)

        XCTAssertNotNil(session.claim(by: .genericHID))
        XCTAssertNil(session.claim(by: .ack05))
        session.complete(by: .genericHID)
        guard case let .completed(context, winner) = session.phase else {
            return XCTFail("Expected completed capture")
        }
        XCTAssertEqual(context.editorPresetID, "preset-a")
        XCTAssertEqual(winner, .genericHID)
    }

    func testEditorPresetIsPinnedAtSessionStart() {
        var session = UnifiedShortcutLearnSession()
        session.begin(editorPresetID: "preset-at-start", target: .action(.jumpForward))
        session.backendStarted(.genericHID)

        XCTAssertEqual(
            session.claim(by: .genericHID)?.editorPresetID,
            "preset-at-start"
        )
    }

    func testActiveSessionCannotBeReplacedByAnotherLearnRequest() {
        var session = UnifiedShortcutLearnSession()
        let first = session.begin(
            editorPresetID: "preset-at-start",
            target: .action(.jumpForward)
        )
        session.backendStarted(.genericHID)

        let replacement = session.begin(
            editorPresetID: "preset-later",
            target: .action(.cue)
        )

        XCTAssertNotNil(first)
        XCTAssertNil(replacement)
        XCTAssertEqual(
            session.claim(by: .genericHID)?.editorPresetID,
            "preset-at-start"
        )
    }
}
