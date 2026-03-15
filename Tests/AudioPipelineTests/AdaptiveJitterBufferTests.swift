import Audio
import Foundation
import Testing
import Vita49

@Test
func jitterBufferCapsDepth() async {
    let buffer = AdaptiveJitterBuffer<VitaPacket>(capacity: 2)
    await buffer.push(VitaPacket(streamIdentifier: 1, sequence: 1, timestamp: 1, payload: Data([1])))
    await buffer.push(VitaPacket(streamIdentifier: 1, sequence: 2, timestamp: 2, payload: Data([2])))
    await buffer.push(VitaPacket(streamIdentifier: 1, sequence: 3, timestamp: 3, payload: Data([3])))

    #expect(await buffer.depth() == 2)
}
