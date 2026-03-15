import Foundation

public enum ReplayEvent: Sendable {
    case control(ControlLogEntry)
    case udp(UDPLogEntry, Data)
}

public struct CaptureReplayer {
    private let loader = CaptureBundleLoader()

    public init() {}

    public func replay(
        bundleAt url: URL,
        speed: ReplaySpeed,
        onEvent: @escaping @Sendable (ReplayEvent) async -> Void
    ) async throws {
        let bundle = try loader.loadBundle(at: url)
        var events: [(date: Date, event: ReplayEvent)] = bundle.controlEntries.map { ($0.timestamp, .control($0)) }
        events += bundle.udpEntries.map { ($0.timestamp, .udp($0, loader.frameData(for: $0, in: bundle))) }
        events.sort { $0.date < $1.date }

        var lastDate: Date?
        for entry in events {
            if let lastDate, speed != .burst {
                let delta = entry.date.timeIntervalSince(lastDate)
                if speed == .realtime {
                    try? await Task.sleep(for: .seconds(max(delta, 0)))
                } else if speed == .half {
                    try? await Task.sleep(for: .seconds(max(delta / 2, 0)))
                } else if speed == .step {
                    _ = readLine()
                }
            }

            await onEvent(entry.event)
            lastDate = entry.date
        }
    }
}
