import Foundation

public struct ResponseParser: Sendable {
    public init() {}

    public func parse(line: String) -> RadioMessage {
        guard let prefix = line.first else {
            return .unknown(line)
        }

        let payload = String(line.dropFirst())

        switch prefix {
        case "V":
            return .version(payload)
        case "H":
            return .handle(payload)
        case "R":
            return .response(parseResponse(payload))
        case "S":
            return .status(StatusParser().parse(payload: payload))
        case "M":
            return .notice(parseNotice(payload))
        default:
            return .unknown(line)
        }
    }

    private func parseResponse(_ payload: String) -> CommandResponse {
        let components = payload.split(separator: "|", omittingEmptySubsequences: false)
        let sequence = components.indices.contains(0) ? Int(components[0]) ?? 0 : 0
        let codeHex = components.indices.contains(1) ? String(components[1]) : "FFFFFFFF"
        let code = UInt32(codeHex, radix: 16) ?? UInt32(codeHex) ?? 0xFFFFFFFF
        let payload = components.indices.contains(2) ? String(components[2]) : ""
        let debugOutput = components.count > 3 ? components[3...].joined(separator: "|") : nil
        return CommandResponse(sequence: sequence, codeHex: codeHex, code: code, payload: payload, debugOutput: debugOutput)
    }

    private func parseNotice(_ payload: String) -> RadioNotice {
        let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let codeHex = parts.isEmpty ? "00000000" : String(parts[0])
        let value = UInt32(codeHex, radix: 16) ?? 0
        let severityRaw = Int((value >> 24) & 0x03)
        let severity = MessageSeverity(rawValue: severityRaw) ?? .informational
        let text = parts.count > 1 ? String(parts[1]) : ""
        return RadioNotice(codeHex: codeHex, severity: severity, text: text)
    }
}

public struct StatusParser: Sendable {
    public init() {}

    public func parse(payload: String) -> StatusMessage {
        let statusParts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let handle = statusParts.isEmpty ? "0" : String(statusParts[0])
        let messageBody = statusParts.count > 1 ? String(statusParts[1]) : ""
        let parts = messageBody.split(separator: " ")
        guard let object = parts.first else {
            return StatusMessage(handle: handle, object: "unknown", identifier: nil, properties: [:])
        }

        var index = 1
        var identifier: String?

        if parts.indices.contains(1), !parts[1].contains("=") {
            identifier = String(parts[1])
            index = 2
        }

        var properties: [String: String] = [:]
        for token in parts.dropFirst(index) {
            let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 {
                properties[pair[0]] = pair[1]
            }
        }

        return StatusMessage(handle: handle, object: String(object), identifier: identifier, properties: properties)
    }
}
