import AVFoundation
import CoreAudio
import Foundation

public enum AudioDeviceRole: String, Codable, Sendable {
    case input
    case output
}

public struct AudioDeviceDescriptor: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let role: AudioDeviceRole

    public init(id: String, name: String, role: AudioDeviceRole) {
        self.id = id
        self.name = name
        self.role = role
    }
}

public actor AudioDeviceManager {
    public init() {}

    public func inputDevices() -> [AudioDeviceDescriptor] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices.map {
            AudioDeviceDescriptor(id: $0.uniqueID, name: $0.localizedName, role: .input)
        }
    }

    public func outputDevices() -> [AudioDeviceDescriptor] {
        allOutputAudioDevices().map {
            AudioDeviceDescriptor(id: "\($0.id)", name: $0.name, role: .output)
        }
    }

    public func defaultOutputDeviceID() -> String? {
        var defaultDeviceID = AudioDeviceID.zero
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultDeviceID)
        guard status == noErr else { return nil }
        return "\(defaultDeviceID)"
    }

    private func allOutputAudioDevices() -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID.zero, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else {
            return []
        }

        return devices.compactMap { deviceID in
            guard supportsOutput(deviceID) else { return nil }
            return (deviceID, deviceName(deviceID))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func supportsOutput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        return status == noErr ? ((unmanagedName?.takeRetainedValue() as String?) ?? "Audio Device \(deviceID)") : "Audio Device \(deviceID)"
    }
}
