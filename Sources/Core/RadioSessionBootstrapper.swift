import Diagnostics
import Foundation
import SmartSDRProtocol

public enum RadioCommandKind: String, Sendable {
    case name
    case clientGUI
    case clientStation
    case startPersistence
    case udpPort
    case ping
    case subscribeRadio
    case subscribeSlice
    case subscribeInterlock
    case subscribeCWX
    case subscribeAudioStream
    case sliceList
    case sliceCreate
    case micInput
    case createRxStream
    case createTxStream
    case remoteAudio
    case audioClientAdd
    case audioClientGain
    case audioClientMute
    case tune
    case filter
    case mode
    case xmit
    case transmitSet
    case cwWPM
    case cwxSend
    case cwxInsert
    case cwxClear
    case cwxErase
    case cwxMacroSave
    case cwxMacroSend
    case cwxQSK
    case custom
}

public struct PlannedRadioCommand: Sendable {
    public var kind: RadioCommandKind
    public var body: String

    public init(kind: RadioCommandKind, body: String) {
        self.kind = kind
        self.body = body
    }
}

public actor RadioSessionBootstrapper {
    private let encoder = CommandEncoder()
    private let diagnostics: DiagnosticsCenter?

    public init(diagnostics: DiagnosticsCenter? = nil) {
        self.diagnostics = diagnostics
    }

    public func bootstrapPlan(profile: ConnectionProfile, wanProfile: WANOperatingProfile) -> [PlannedRadioCommand] {
        [
            PlannedRadioCommand(kind: .name, body: encoder.name("FlexLite")),
            PlannedRadioCommand(kind: .clientGUI, body: encoder.clientGUI(profile.clientID)),
            PlannedRadioCommand(kind: .clientStation, body: encoder.clientStation(profile.stationName)),
            PlannedRadioCommand(kind: .udpPort, body: encoder.clientUDPPort(profile.udpPort)),
            PlannedRadioCommand(kind: .ping, body: encoder.ping()),
            PlannedRadioCommand(kind: .subscribeRadio, body: encoder.subscribe(.radio)),
            PlannedRadioCommand(kind: .subscribeSlice, body: encoder.subscribe(.slice)),
            PlannedRadioCommand(kind: .subscribeCWX, body: encoder.subscribe(.cwx)),
            PlannedRadioCommand(kind: .subscribeAudioStream, body: encoder.subscribe(.audioStream)),
            PlannedRadioCommand(kind: .sliceList, body: encoder.sliceList()),
            PlannedRadioCommand(kind: .micInput, body: encoder.micInput())
        ] + encoder.remoteAudioCommands(profile: wanProfile.remoteAudio).enumerated().map { index, body in
            PlannedRadioCommand(
                kind: index == 0 ? .createRxStream : index == 1 ? .createTxStream : .remoteAudio,
                body: body
            )
        }
    }

    public func logPlan(_ commands: [PlannedRadioCommand]) async {
        guard let diagnostics else { return }
        for command in commands {
            await diagnostics.log(.debug, "Bootstrap planned", metadata: ["kind": command.kind.rawValue, "command": command.body])
        }
    }
}
