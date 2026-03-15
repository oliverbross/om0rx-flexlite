import CoreMIDI
import Diagnostics
import Foundation

public struct MidiSourceDescriptor: Identifiable, Hashable, Sendable {
    public let id: MIDIUniqueID
    public let name: String

    public init(id: MIDIUniqueID, name: String) {
        self.id = id
        self.name = name
    }
}

public actor MidiManager {
    private let diagnostics: DiagnosticsCenter?

    public init(diagnostics: DiagnosticsCenter? = nil) {
        self.diagnostics = diagnostics
    }

    public func availableSources() -> [MidiSourceDescriptor] {
        (0..<MIDIGetNumberOfSources()).compactMap { index in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { return nil }
            return MidiSourceDescriptor(id: uniqueIdentifier(for: endpoint), name: name(for: endpoint))
        }
    }

    public func logDiagnosticProbe() async {
        let sources = availableSources()
        if let diagnostics {
            await diagnostics.log(.info, "Scanned MIDI sources", metadata: ["count": "\(sources.count)"])
        }
    }

    private func uniqueIdentifier(for endpoint: MIDIEndpointRef) -> MIDIUniqueID {
        var identifier: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &identifier)
        return identifier
    }

    private func name(for endpoint: MIDIEndpointRef) -> String {
        var nameRef: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &nameRef)
        return nameRef?.takeRetainedValue() as String? ?? "Unknown MIDI Source"
    }
}
