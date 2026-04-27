import Foundation

enum LocalLogActivityState: Equatable {
    case waiting
    case working
    case idle
}

struct LocalLogSnapshot: Equatable {
    var state: LocalLogActivityState
    var lastObservedAt: Date
    var summary: String?
}

actor LocalLogMonitor {
    private static let tailByteCount = 24_000
    private static let recentWindow: TimeInterval = 35
    private static let staleWindow: TimeInterval = 120

    private struct LogSource {
        let directory: String
        let filePrefix: String?
    }

    private let sources: [AIPlatform: [LogSource]]

    init() {
        self.sources = [
            .claude: [LogSource(directory: "~/Library/Logs/Claude", filePrefix: nil)]
        ]
    }

    func captureSnapshots(now: Date = Date()) async -> [AIPlatform: LocalLogSnapshot] {
        let sources = self.sources
        return await Task.detached(priority: .utility) {
            var snapshots: [AIPlatform: LocalLogSnapshot] = [:]
            for (platform, platformSources) in sources {
                guard let snapshot = Self.captureSnapshot(
                    for: platform,
                    from: platformSources,
                    now: now
                ) else {
                    continue
                }
                snapshots[platform] = snapshot
            }
            return snapshots
        }.value
    }

    private static func captureSnapshot(
        for platform: AIPlatform,
        from sources: [LogSource],
        now: Date
    ) -> LocalLogSnapshot? {
        let candidates = collectLogCandidates(from: sources)
        guard let newest = candidates.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            return nil
        }

        guard let rawText = readTail(from: newest.url, byteCount: Self.tailByteCount) else {
            return nil
        }

        let lower = rawText.lowercased()
        let recentTail = recentLogSegment(from: lower, lineLimit: 80)
        let age = now.timeIntervalSince(newest.modifiedAt)
        let requestMatched = containsAny(in: recentTail, patterns: requestPatterns)
        let workMatched = containsAny(in: recentTail, patterns: workPatterns)

        let state: LocalLogActivityState
        if age > Self.staleWindow {
            state = .idle
        } else if workMatched && age <= Self.recentWindow {
            state = .working
        } else if requestMatched && age <= Self.recentWindow {
            state = .waiting
        } else {
            state = .idle
        }

        return LocalLogSnapshot(
            state: state,
            lastObservedAt: newest.modifiedAt,
            summary: summaryText(for: platform, state: state)
        )
    }

    private static func collectLogCandidates(
        from sources: [LogSource]
    ) -> [(url: URL, modifiedAt: Date)] {
        let fileManager = FileManager.default
        var candidates: [(url: URL, modifiedAt: Date)] = []

        for source in sources {
            let expanded = NSString(string: source.directory).expandingTildeInPath
            let directoryURL = URL(fileURLWithPath: expanded, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "log" else {
                    continue
                }

                if let filePrefix = source.filePrefix,
                   !fileURL.lastPathComponent.lowercased().hasPrefix(filePrefix.lowercased()) {
                    continue
                }

                guard
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                    values.isRegularFile == true,
                    let modifiedAt = values.contentModificationDate
                else {
                    continue
                }

                candidates.append((url: fileURL, modifiedAt: modifiedAt))
            }
        }

        return candidates
    }

    private static func readTail(from url: URL, byteCount: Int) -> String? {
        let fileManager = FileManager.default
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSizeNumber = attributes[.size] as? NSNumber
        else {
            return nil
        }

        let fileSize = fileSizeNumber.uint64Value
        let startOffset = fileSize > UInt64(byteCount) ? fileSize - UInt64(byteCount) : 0

        do {
            try handle.seek(toOffset: startOffset)
            let data = try handle.readToEnd() ?? Data()
            return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }

    private static func containsAny(in text: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            text.contains(pattern)
        }
    }

    private static func recentLogSegment(from text: String, lineLimit: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else {
            return text
        }
        return lines.suffix(max(lineLimit, 1)).joined(separator: "\n")
    }

    private static func summaryText(for platform: AIPlatform, state: LocalLogActivityState) -> String {
        switch (platform, state) {
        case (.claude, .working):
            return "Claude 로컬 로그에서 작업 이벤트가 감지되었습니다."
        case (.claude, .waiting):
            return "Claude 로컬 로그에서 요청 수신 신호가 감지되었습니다."
        case (.claude, .idle):
            return "Claude 로컬 로그에서 최근 작업 신호가 없습니다."
        case (_, .working):
            return "로컬 로그에서 작업 이벤트가 감지되었습니다."
        case (_, .waiting):
            return "로컬 로그에서 요청 수신 신호가 감지되었습니다."
        case (_, .idle):
            return "로컬 로그에서 최근 작업 신호가 없습니다."
        }
    }

    private static let requestPatterns: [String] = [
        "user prompt",
        "incoming request",
        "request received",
        "enqueue prompt",
        "queued prompt",
        "message received from user"
    ]

    private static let workPatterns: [String] = [
        "streaming response",
        "assistant response",
        "tool_call",
        "executing tool",
        "completion finished",
        "model output chunk",
        "responding to user"
    ]
}
