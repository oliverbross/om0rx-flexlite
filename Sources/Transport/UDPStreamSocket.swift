import Foundation
import Network

public actor UDPStreamSocket {
    private let queue = DispatchQueue(label: "FlexLite.UDPStreamSocket")
    private var listener: NWListener?
    private var outboundConnection: NWConnection?
    private var activeConnection: NWConnection?
    private let onDatagram: (@Sendable (Data) async -> Void)?

    public init(onDatagram: (@Sendable (Data) async -> Void)? = nil) {
        self.onDatagram = onDatagram
    }

    public func bind(localPort: UInt16) throws {
        let listener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: localPort)!)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.queue.async {
                Task { await self.accept(connection: connection) }
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func configure(remoteHost: String, remotePort: UInt16) {
        let connection = NWConnection(host: NWEndpoint.Host(remoteHost), port: NWEndpoint.Port(rawValue: remotePort)!, using: .udp)
        connection.start(queue: queue)
        outboundConnection = connection
    }

    public func send(_ data: Data) async throws {
        guard let outboundConnection else {
            throw NWError.posix(.ENOTCONN)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            outboundConnection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func close() {
        activeConnection?.cancel()
        outboundConnection?.cancel()
        listener?.cancel()
        activeConnection = nil
        outboundConnection = nil
        listener = nil
    }

    private func accept(connection: NWConnection) async {
        activeConnection = connection
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            self.queue.async {
                Task {
                    if let data, !data.isEmpty, let onDatagram = self.onDatagram {
                        await onDatagram(data)
                    }

                    if error == nil {
                        await self.receive(on: connection)
                    }
                }
            }
        }
    }
}
