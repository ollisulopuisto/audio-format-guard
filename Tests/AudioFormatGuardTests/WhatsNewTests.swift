import XCTest
@testable import AudioFormatGuard

final class WhatsNewTests: XCTestCase {

    private static let fixture = """
    # Changelog

    ## [Unreleased]

    ### Added
    - Unreleased work in progress.

    ## [v26.09.28.6] - 2026-09-28

    ### Added
    - Native macOS application icon.
    - Added scripts/generate-icon.sh.

    ### Changed
    - Bumped app bundle versioning to 26.09.28.6.

    ## [v26.09.28.5] - 2026-09-28

    ### Added
    - Integrated unquarantine.command script.

    ## [v26.09.20] - 2026-09-20

    - Older single-section release.
    """

    func testParsesReleasedSectionsNewestFirstSkippingUnreleased() {
        let sections = ChangelogNotes.parse(Self.fixture)
        XCTAssertEqual(sections.map(\.version), ["v26.09.28.6", "v26.09.28.5", "v26.09.20"])
        XCTAssertEqual(sections[0].items, [
            "Native macOS application icon.",
            "Added scripts/generate-icon.sh.",
            "Bumped app bundle versioning to 26.09.28.6.",
        ])
        XCTAssertFalse(sections.contains { $0.version == "Unreleased" })
    }

    func testCompareVersionsIsNumericPerSegmentAndIgnoresVPrefix() {
        XCTAssertEqual(ChangelogNotes.compareVersions("v26.09.28.5", "v26.09.28.6"), -1)
        XCTAssertEqual(ChangelogNotes.compareVersions("26.09.28.6", "v26.09.28.6"), 0)
        XCTAssertEqual(ChangelogNotes.compareVersions("v26.09.20", "v26.09.28.5"), -1)
        XCTAssertEqual(ChangelogNotes.compareVersions("v26.09.28.6", "v26.09.28.6"), 0)
    }

    func testSectionsSinceShowsOnlyTheUpgradeWindow() {
        let sections = ChangelogNotes.parse(Self.fixture)
        let pending = ChangelogNotes.sectionsSince(
            sections, current: "v26.09.28.6", lastSeen: "v26.09.20")
        XCTAssertEqual(pending.map(\.version), ["v26.09.28.6", "v26.09.28.5"])
        // A downgrade shows nothing.
        XCTAssertTrue(ChangelogNotes.sectionsSince(
            sections, current: "v26.09.20", lastSeen: "v26.09.28.6").isEmpty)
        // Empty lastSeen means full history.
        XCTAssertEqual(ChangelogNotes.sectionsSince(
            sections, current: "v26.09.28.6", lastSeen: "").count, 3)
    }

    func testRealRepositoryChangelogParses() {
        // <repo>/Tests/AudioFormatGuardTests/WhatsNewTests.swift -> repo root
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(
            contentsOf: repoRoot.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        else {
            XCTFail("repository CHANGELOG.md unreadable")
            return
        }
        let sections = ChangelogNotes.parse(text)
        XCTAssertTrue(sections.count >= 5, "expected the real release history, got \(sections.count)")
        XCTAssertTrue(sections.allSatisfy { !$0.items.isEmpty })
        XCTAssertFalse(sections.contains { $0.version == "Unreleased" })
        XCTAssertEqual(sections.first?.version, "v26.09.28.6")
    }

    func testMarkerOnlyMovesForward() {
        let suite = UserDefaults(suiteName: "WhatsNewTests.\(UUID().uuidString)")!
        WhatsNewState.recordSeen("v26.09.28.6", defaults: suite)
        XCTAssertEqual(suite.string(forKey: "whatsNewSeenVersion"), "v26.09.28.6")
        // An older acknowledgement (downgrade/reinstall) never moves it back.
        WhatsNewState.recordSeen("v26.09.20", defaults: suite)
        XCTAssertEqual(suite.string(forKey: "whatsNewSeenVersion"), "v26.09.28.6")
        // Empty versions are never recorded.
        WhatsNewState.recordSeen("", defaults: UserDefaults(suiteName: "WhatsNewTests.\(UUID().uuidString)")!)
    }
}
