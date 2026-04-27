import XCTest
@testable import AIWebUsageMonitor

final class QuotaHistoryStoreTests: XCTestCase {
    func testRecordAndLoadHistory() {
        let suiteName = "QuotaHistoryStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = QuotaHistoryStore(defaults: defaults, storageKey: "quota-history-test")
        let accountID = UUID()
        let now = Date()

        store.record(
            entries: [UsageQuotaEntry(label: "주간 사용 한도", valueText: "45% 남음", progress: 0.45)],
            for: accountID,
            at: now
        )

        let history = store.history(for: accountID, quotaLabel: "주간 사용 한도")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.progress ?? -1, 0.45, accuracy: 0.0001)
    }

    func testHistoryIsCappedByMaxSamples() {
        let suiteName = "QuotaHistoryStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = QuotaHistoryStore(defaults: defaults, storageKey: "quota-history-test", maxSamplesPerEntry: 8)
        let accountID = UUID()
        let base = Date()

        for index in 0..<20 {
            store.record(
                entries: [UsageQuotaEntry(label: "5시간 사용 한도", valueText: "\(index)%", progress: Double(index) / 100)],
                for: accountID,
                at: base.addingTimeInterval(Double(index) * 61)
            )
        }

        let history = store.history(for: accountID, quotaLabel: "5시간 사용 한도")
        XCTAssertEqual(history.count, 8)
        XCTAssertEqual(history.first?.progress ?? -1, 0.12, accuracy: 0.0001)
        XCTAssertEqual(history.last?.progress ?? -1, 0.19, accuracy: 0.0001)
    }

    func testHistoryPrunesOldSamplesByRetentionWindow() {
        let suiteName = "QuotaHistoryStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("테스트 UserDefaults를 생성하지 못했습니다.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = QuotaHistoryStore(
            defaults: defaults,
            storageKey: "quota-history-test",
            maxSamplesPerEntry: 48,
            retentionWindow: 2 * 24 * 60 * 60
        )
        let accountID = UUID()
        let now = Date()

        store.record(
            entries: [UsageQuotaEntry(label: "주간 사용 한도", valueText: "70% 남음", progress: 0.7)],
            for: accountID,
            at: now.addingTimeInterval(-3 * 24 * 60 * 60)
        )
        store.record(
            entries: [UsageQuotaEntry(label: "주간 사용 한도", valueText: "66% 남음", progress: 0.66)],
            for: accountID,
            at: now
        )

        let history = store.history(for: accountID, quotaLabel: "주간 사용 한도")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.progress ?? -1, 0.66, accuracy: 0.0001)
    }
}
