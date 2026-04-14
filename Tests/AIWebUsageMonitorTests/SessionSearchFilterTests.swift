import XCTest
@testable import AIWebUsageMonitor

final class SessionSearchFilterTests: XCTestCase {
    func testMeaningfulConversationTitleDropsGenericUsageTitles() {
        XCTAssertNil(PlatformTaskSignals(conversationTitle: "설정").meaningfulConversationTitle)
        XCTAssertNil(PlatformTaskSignals(conversationTitle: "Usage").meaningfulConversationTitle)
        XCTAssertEqual(
            PlatformTaskSignals(conversationTitle: "Build pixel office").meaningfulConversationTitle,
            "Build pixel office"
        )
    }

    func testSearchMatchesDisplayNameAndPrompt() {
        let session = makeSession(
            platform: .codex,
            displayName: "Codex Alpha",
            profileName: "dongbin",
            conversationTitle: "Build pixel office",
            prompt: "Analyze quota parser"
        )

        XCTAssertTrue(SessionSearchFilter(query: "alpha").matches(session))
        XCTAssertTrue(SessionSearchFilter(query: "quota parser").matches(session))
        XCTAssertTrue(SessionSearchFilter(query: "pixel office").matches(session))
    }

    func testSearchMatchesProfileAndPlatform() {
        let session = makeSession(
            platform: .claude,
            displayName: "Research Bot",
            profileName: "team-claude",
            conversationTitle: "Weekly review",
            prompt: "Summarize backlog"
        )

        XCTAssertTrue(SessionSearchFilter(query: "team-claude").matches(session))
        XCTAssertTrue(SessionSearchFilter(query: "claude").matches(session))
        XCTAssertFalse(SessionSearchFilter(query: "cursor").matches(session))
    }

    func testSearchIgnoresGenericUsageConversationTitles() {
        let session = makeSession(
            platform: .codex,
            displayName: "Codex Ops",
            profileName: "ops",
            conversationTitle: "Settings",
            prompt: "Analyze quota parser"
        )

        XCTAssertFalse(SessionSearchFilter(query: "settings").matches(session))
        XCTAssertTrue(SessionSearchFilter(query: "quota parser").matches(session))
    }

    func testApplyReturnsAllSessionsWhenQueryIsEmpty() {
        let sessions = [
            makeSession(platform: .codex, displayName: "A", profileName: nil, conversationTitle: nil, prompt: nil),
            makeSession(platform: .claude, displayName: "B", profileName: nil, conversationTitle: nil, prompt: nil)
        ]

        XCTAssertEqual(SessionSearchFilter(query: "").apply(to: sessions).count, 2)
    }

    private func makeSession(
        platform: AIPlatform,
        displayName: String,
        profileName: String?,
        conversationTitle: String?,
        prompt: String?
    ) -> WebAccountSession {
        WebAccountSession(
            platform: platform,
            displayName: displayName,
            profileName: profileName,
            snapshot: UsageSnapshot(
                headline: "Ready",
                sourceURL: platform.dashboardURL,
                debugExcerpt: "debug",
                quota: QuotaSnapshot(
                    entries: [
                        UsageQuotaEntry(
                            label: "5-hour usage limit",
                            valueText: "80%",
                            resetText: "2 hours",
                            progress: 0.8
                        )
                    ]
                ),
                activity: ActivitySnapshot(),
                taskSignals: PlatformTaskSignals(
                    conversationTitle: conversationTitle,
                    latestUserPromptPreview: prompt,
                    latestAssistantPreview: "Thinking"
                ),
                updatedAt: Date()
            )
        )
    }
}
