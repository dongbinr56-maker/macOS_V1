import Foundation

struct QuotaHistoryPoint: Codable, Equatable, Identifiable {
    let timestamp: Date
    let progress: Double

    var id: Date { timestamp }
}

final class QuotaHistoryStore {
    private struct EntryKey: Hashable, Codable {
        let accountID: UUID
        let quotaLabel: String
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let maxSamplesPerEntry: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "quotaHistory.v1",
        maxSamplesPerEntry: Int = 48
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maxSamplesPerEntry = max(8, maxSamplesPerEntry)
    }

    func history(for accountID: UUID, quotaLabel: String) -> [QuotaHistoryPoint] {
        let key = EntryKey(accountID: accountID, quotaLabel: normalizedLabel(quotaLabel))
        return load()[key] ?? []
    }

    func record(entries: [UsageQuotaEntry], for accountID: UUID, at timestamp: Date = Date()) {
        guard !entries.isEmpty else {
            return
        }

        var storage = load()
        for entry in entries {
            guard let progress = entry.progress ?? extractQuotaPercent(from: entry.valueText) else {
                continue
            }

            let key = EntryKey(accountID: accountID, quotaLabel: normalizedLabel(entry.label))
            var history = storage[key] ?? []

            if let last = history.last,
               abs(last.progress - progress) < 0.0001,
               timestamp.timeIntervalSince(last.timestamp) < 60 {
                continue
            }

            history.append(
                QuotaHistoryPoint(
                    timestamp: timestamp,
                    progress: min(max(progress, 0), 1)
                )
            )

            if history.count > maxSamplesPerEntry {
                history.removeFirst(history.count - maxSamplesPerEntry)
            }

            storage[key] = history
        }

        persist(storage)
    }

    func removeHistory(for accountID: UUID) {
        var storage = load()
        storage.keys
            .filter { $0.accountID == accountID }
            .forEach { storage.removeValue(forKey: $0) }
        persist(storage)
    }

    private func normalizedLabel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func load() -> [EntryKey: [QuotaHistoryPoint]] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? decoder.decode([EntryKey: [QuotaHistoryPoint]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist(_ storage: [EntryKey: [QuotaHistoryPoint]]) {
        guard let encoded = try? encoder.encode(storage) else {
            return
        }
        defaults.set(encoded, forKey: storageKey)
    }
}
