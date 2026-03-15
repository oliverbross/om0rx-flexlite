import Diagnostics
import Foundation
import Transport

public enum ConnectorError: LocalizedError {
    case smartLinkNotImplemented

    public var errorDescription: String? {
        switch self {
        case .smartLinkNotImplemented:
            return "SmartLinkConnector is scaffolded only. Validate auth and traversal against captures before enabling it."
        }
    }
}

public protocol RadioConnector: Sendable {
    var mode: ConnectionMode { get }
    func connect(
        profile: ConnectionProfile,
        diagnostics: DiagnosticsCenter?,
        onLineReceived: (@Sendable (String) async -> Void)?,
        onEvent: (@Sendable (TransportEvent) async -> Void)?
    ) async throws -> any CommandTransport
}

public struct LanConnector: RadioConnector {
    public let mode: ConnectionMode = .lan

    public init() {}

    public func connect(
        profile: ConnectionProfile,
        diagnostics: DiagnosticsCenter?,
        onLineReceived: (@Sendable (String) async -> Void)?,
        onEvent: (@Sendable (TransportEvent) async -> Void)?
    ) async throws -> any CommandTransport {
        let transport = TCPCommandClient(diagnostics: diagnostics, onLineReceived: onLineReceived, onEvent: onEvent)
        try await transport.connect(host: profile.host, port: profile.tcpPort)
        return transport
    }
}

public struct ManualHostConnector: RadioConnector {
    public let mode: ConnectionMode = .manualHost

    public init() {}

    public func connect(
        profile: ConnectionProfile,
        diagnostics: DiagnosticsCenter?,
        onLineReceived: (@Sendable (String) async -> Void)?,
        onEvent: (@Sendable (TransportEvent) async -> Void)?
    ) async throws -> any CommandTransport {
        let transport = TCPCommandClient(diagnostics: diagnostics, onLineReceived: onLineReceived, onEvent: onEvent)
        try await transport.connect(host: profile.host, port: profile.tcpPort)
        return transport
    }
}

public struct VpnConnector: RadioConnector {
    public let mode: ConnectionMode = .vpn

    public init() {}

    public func connect(
        profile: ConnectionProfile,
        diagnostics: DiagnosticsCenter?,
        onLineReceived: (@Sendable (String) async -> Void)?,
        onEvent: (@Sendable (TransportEvent) async -> Void)?
    ) async throws -> any CommandTransport {
        let transport = TCPCommandClient(diagnostics: diagnostics, onLineReceived: onLineReceived, onEvent: onEvent)
        try await transport.connect(host: profile.host, port: profile.tcpPort)
        return transport
    }
}

public struct SmartLinkConnector: RadioConnector {
    public let mode: ConnectionMode = .smartLink

    public init() {}

    public func connect(
        profile: ConnectionProfile,
        diagnostics: DiagnosticsCenter?,
        onLineReceived: (@Sendable (String) async -> Void)?,
        onEvent: (@Sendable (TransportEvent) async -> Void)?
    ) async throws -> any CommandTransport {
        if let diagnostics {
            await diagnostics.log(.notice, "SmartLink connector requested before implementation", metadata: ["profile": profile.name])
        }
        throw ConnectorError.smartLinkNotImplemented
    }
}
