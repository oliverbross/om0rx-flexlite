import Foundation

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
}

public struct LogEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let metadata: [String: String]

    public init(id: UUID = UUID(), timestamp: Date = .now, level: LogLevel, message: String, metadata: [String: String] = [:]) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.metadata = metadata
    }
}

public actor DiagnosticsCenter {
    private var events: [LogEvent] = []
    private let maxEvents = 400
    private let sensitiveNeedles = ["token", "secret", "password", "auth", "guid", "uuid"]

    public init() {}

    public func log(_ level: LogLevel, _ message: String, metadata: [String: String] = [:]) {
        events.append(LogEvent(level: level, message: message, metadata: metadata))
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    public func recentEvents(limit: Int = 200) -> [LogEvent] {
        Array(events.suffix(limit))
    }

    public func clear() {
        events.removeAll(keepingCapacity: true)
    }

    public func exportRedactedLog() -> String {
        let formatter = ISO8601DateFormatter()
        return events.map { event in
            let renderedMetadata = redact(event.metadata)
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: " ")
            if renderedMetadata.isEmpty {
                return "\(formatter.string(from: event.timestamp)) [\(event.level.rawValue.uppercased())] \(event.message)"
            }
            return "\(formatter.string(from: event.timestamp)) [\(event.level.rawValue.uppercased())] \(event.message) \(renderedMetadata)"
        }.joined(separator: "\n")
    }

    private func redact(_ metadata: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: metadata.map { key, value in
            let shouldRedact = sensitiveNeedles.contains { key.localizedCaseInsensitiveContains($0) }
            return (key, shouldRedact ? "<redacted>" : value)
        })
    }
}
