import Diagnostics
import Foundation
import Network

public actor TCPCommandClient: CommandTransport {
    private let diagnostics: DiagnosticsCenter?
    private let queue = DispatchQueue(label: "FlexLite.TCPCommandClient")
    private let onLineReceived: (@Sendable (String) async -> Void)?
    private let onEvent: (@Sendable (TransportEvent) async -> Void)?

    private var connection: NWConnection?
    private var inboundBuffer = Data()

    public init(
        diagnostics: DiagnosticsCenter? = nil,
        onLineReceived: (@Sendable (String) async -> Void)? = nil,
        onEvent: (@Sendable (TransportEvent) async -> Void)? = nil
    ) {
        self.diagnostics = diagnostics
        self.onLineReceived = onLineReceived
        self.onEvent = onEvent
    }

    public func connect(host: String, port: UInt16) async throws {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let resumeGate = ResumeGate()
            connection.stateUpdateHandler = { [diagnostics, weak self] state in
                switch state {
                case .ready:
                    resumeGate.resume(continuation)
                    if let onEvent = self?.onEvent {
                        Task { await onEvent(.ready) }
                    }
                case .failed(let error):
                    resumeGate.resume(continuation, throwing: error)
                    if let onEvent = self?.onEvent {
                        Task { await onEvent(.failed(error.localizedDescription)) }
                    }
                case .cancelled:
                    if let onEvent = self?.onEvent {
                        Task { await onEvent(.disconnected) }
                    }
                default:
                    break
                }

                if let diagnostics {
                    Task {
                        await diagnostics.log(.debug, "TCP state changed", metadata: ["state": "\(state)"])
                    }
                }
            }

            connection.start(queue: queue)
        }

        receiveLoop()
    }

    public func disconnect() async {
        connection?.cancel()
        connection = nil
        inboundBuffer.removeAll(keepingCapacity: false)
        if let diagnostics {
            await diagnostics.log(.info, "Disconnected TCP control socket")
        }
        if let onEvent {
            await onEvent(.disconnected)
        }
    }

    public func send(command: String) async throws {
        guard let connection else {
            throw NWError.posix(.ENOTCONN)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: Data((command + "\n").utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        if let diagnostics {
            await diagnostics.log(.debug, "Sent command", metadata: ["command": command])
        }
    }

    private func receiveLoop() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                if let error, let diagnostics = self.diagnostics {
                    await diagnostics.log(.warning, "Receive error", metadata: ["error": error.localizedDescription])
                }

                if let data, !data.isEmpty {
                    await self.consume(data)
                }

                if isComplete {
                    await self.disconnect()
                } else if error == nil {
                    await self.receiveLoop()
                } else if let onEvent {
                    await onEvent(.failed(error?.localizedDescription ?? "Unknown TCP receive error"))
                }
            }
        }
    }

    private func consume(_ data: Data) async {
        inboundBuffer.append(data)

        while let newlineIndex = inboundBuffer.firstIndex(of: 0x0A) {
            let lineData = inboundBuffer.prefix(upTo: newlineIndex)
            inboundBuffer.removeSubrange(...newlineIndex)

            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty
            else {
                continue
            }

            if let onLineReceived {
                await onLineReceived(line)
            }
        }
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resume(_ continuation: CheckedContinuation<Void, any Error>, throwing error: (any Error)? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
