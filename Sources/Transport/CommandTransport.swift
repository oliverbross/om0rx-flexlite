import Foundation

public protocol CommandTransport: Sendable {
    func connect(host: String, port: UInt16) async throws
    func disconnect() async
    func send(command: String) async throws
}

public enum TransportEvent: Sendable, Equatable {
    case ready
    case disconnected
    case failed(String)
}

public struct DiscoveredRadio: Identifiable, Hashable, Sendable {
    public let id: String
    public var nickname: String
    public var model: String
    public var host: String
    public var serial: String?

    public init(id: String, nickname: String, model: String, host: String, serial: String? = nil) {
        self.id = id
        self.nickname = nickname
        self.model = model
        self.host = host
        self.serial = serial
    }
}
