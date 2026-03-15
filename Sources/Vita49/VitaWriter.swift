import Foundation

public struct VitaWriter: Sendable {
    public init() {}

    public func encode(_ packet: VitaPacket) -> Data {
        var data = Data()
        write(UInt16(packet.payload.count + 16), into: &data)
        write(packet.sequence, into: &data)
        write(packet.streamIdentifier, into: &data)
        write(packet.timestamp, into: &data)
        data.append(packet.payload)
        return data
    }

    private func write<T: FixedWidthInteger>(_ value: T, into data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer in
            data.append(contentsOf: buffer)
        }
    }
}
