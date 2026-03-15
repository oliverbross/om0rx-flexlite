import Foundation

public struct VitaPacket: Sendable, Equatable {
    public var streamIdentifier: UInt32
    public var sequence: UInt16
    public var timestamp: UInt64
    public var payload: Data

    public init(streamIdentifier: UInt32, sequence: UInt16, timestamp: UInt64, payload: Data) {
        self.streamIdentifier = streamIdentifier
        self.sequence = sequence
        self.timestamp = timestamp
        self.payload = payload
    }
}

public enum VitaError: Error {
    case packetTooShort
    case invalidLength
}

public struct VitaParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> VitaPacket {
        guard data.count >= 8 else {
            throw VitaError.packetTooShort
        }

        if let legacyPacket = try parseLegacyPacket(data) {
            return legacyPacket
        }

        let header = readUInt32(data, at: 0)
        let packetLength = Int(header & 0xFFFF) * 4
        guard packetLength == data.count, data.count >= 8 else {
            throw VitaError.invalidLength
        }

        let sequence = UInt16((header >> 16) & 0x0F)
        let streamIdentifier = readUInt32(data, at: 4)
        let classIDPresent = ((header >> 27) & 0x01) == 1
        let trailerPresent = ((header >> 26) & 0x01) == 1
        let tsi = Int((header >> 22) & 0x03)
        let tsf = Int((header >> 20) & 0x03)

        var offset = 8
        if classIDPresent {
            offset += 8
        }

        if tsi != 0 {
            offset += 4
        }

        let timestamp: UInt64
        if tsf != 0 {
            guard offset + 8 <= data.count else {
                throw VitaError.invalidLength
            }
            timestamp = readUInt64(data, at: offset)
            offset += 8
        } else {
            timestamp = 0
        }

        let payloadEnd = data.count - (trailerPresent ? 4 : 0)
        guard offset <= payloadEnd else {
            throw VitaError.invalidLength
        }

        let payload = data.subdata(in: offset..<payloadEnd)
        return VitaPacket(streamIdentifier: streamIdentifier, sequence: sequence, timestamp: timestamp, payload: payload)
    }

    private func parseLegacyPacket(_ data: Data) throws -> VitaPacket? {
        guard data.count >= 16 else {
            return nil
        }

        let declaredLength = Int(readUInt16(data, at: 0))
        guard declaredLength == data.count else {
            return nil
        }

        let sequence = readUInt16(data, at: 2)
        let streamIdentifier = readUInt32(data, at: 4)
        let timestamp = readUInt64(data, at: 8)
        let payload = data.subdata(in: 16..<data.count)
        return VitaPacket(streamIdentifier: streamIdentifier, sequence: sequence, timestamp: timestamp, payload: payload)
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        data[offset..<offset + 2].reduce(into: UInt16.zero) { partial, byte in
            partial = (partial << 8) | UInt16(byte)
        }
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<offset + 4].reduce(into: UInt32.zero) { partial, byte in
            partial = (partial << 8) | UInt32(byte)
        }
    }

    private func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        data[offset..<offset + 8].reduce(into: UInt64.zero) { partial, byte in
            partial = (partial << 8) | UInt64(byte)
        }
    }
}
