import Audio
import CaptureKit
import CW
import Diagnostics
import Foundation
import MIDI
import SmartSDRProtocol
import Transport
import Vita49

public enum SessionPhase: String, Codable, CaseIterable, Sendable {
    case disconnected
    case connecting
    case bootstrapping
    case ready
    case rxOnly
    case txArming
    case transmitting
    case recovering
    case error
}

public struct CWQueueState: Codable, Equatable, Sendable {
    public var pendingCount: Int
    public var lastBlock: Int?
    public var lastRadioIndex: Int?

    public init(pendingCount: Int = 0, lastBlock: Int? = nil, lastRadioIndex: Int? = nil) {
        self.pendingCount = pendingCount
        self.lastBlock = lastBlock
        self.lastRadioIndex = lastRadioIndex
    }
}

public struct AudioPipelineStageCounters: Codable, Equatable, Sendable {
    public var udpAudioPacketsReceived: Int
    public var vitaAudioPacketsParsed: Int
    public var decoderPayloadsAccepted: Int
    public var decodedPCMFramesProduced: Int
    public var playbackBuffersSubmitted: Int
    public var playbackBuffersRendered: Int
    public var captureFramesWritten: Int

    public init(
        udpAudioPacketsReceived: Int = 0,
        vitaAudioPacketsParsed: Int = 0,
        decoderPayloadsAccepted: Int = 0,
        decodedPCMFramesProduced: Int = 0,
        playbackBuffersSubmitted: Int = 0,
        playbackBuffersRendered: Int = 0,
        captureFramesWritten: Int = 0
    ) {
        self.udpAudioPacketsReceived = udpAudioPacketsReceived
        self.vitaAudioPacketsParsed = vitaAudioPacketsParsed
        self.decoderPayloadsAccepted = decoderPayloadsAccepted
        self.decodedPCMFramesProduced = decodedPCMFramesProduced
        self.playbackBuffersSubmitted = playbackBuffersSubmitted
        self.playbackBuffersRendered = playbackBuffersRendered
        self.captureFramesWritten = captureFramesWritten
    }
}

private enum SessionControllerError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No active command transport is connected."
        }
    }
}

private struct PendingCommandContext: Sendable {
    let kind: RadioCommandKind
    let sentAt: Date
    let body: String
}

@MainActor
public final class RadioSessionController: ObservableObject {
    @Published public var connectionProfile: ConnectionProfile
    @Published public var wanProfile: WANOperatingProfile
    @Published public private(set) var phase: SessionPhase = .disconnected
    @Published public private(set) var activeSlice = Slice()
    @Published public private(set) var txState = TxState()
    @Published public private(set) var audioState = AudioStreamState()
    @Published public private(set) var networkMetrics = NetworkMetrics()
    @Published public private(set) var connectionStatus = "Disconnected"
    @Published public private(set) var diagnosticsText = ""
    @Published public private(set) var availableMacros: [CWMacro]
    @Published public private(set) var cwxQueueState = CWQueueState()
    @Published public private(set) var inputDevices: [AudioDeviceDescriptor] = []
    @Published public private(set) var outputDevices: [AudioDeviceDescriptor] = []
    @Published public private(set) var midiSources: [MidiSourceDescriptor] = []
    @Published public private(set) var selectedInputDeviceID: String?
    @Published public private(set) var selectedOutputDeviceID: String?
    @Published public private(set) var selectedMidiSourceID: Int32?
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var clientID: String?
    @Published public var captureEnabled = false
    @Published public private(set) var activeCapturePath: String?
    @Published public private(set) var udpPacketCount = 0
    @Published public private(set) var sequenceGapCount = 0
    @Published public private(set) var lastDecodeError: String?
    @Published public private(set) var stageCounters = AudioPipelineStageCounters()

    private let diagnostics: DiagnosticsCenter
    private let bootstrapper: RadioSessionBootstrapper
    private let cwEngine: CWEngine
    private let midiManager: MidiManager
    private let audioDeviceManager: AudioDeviceManager
    private let audioPipeline: RemoteAudioPipeline
    private let udpIngress: UDPIngressCoordinator
    private let tuningCoalescer = TuningCoalescer()
    private let parser = ResponseParser()
    private let encoder = CommandEncoder()
    private let sequenceGenerator = CommandSequenceGenerator()
    private let preferencesStore = AppPreferencesStore()

    private var transport: (any CommandTransport)?
    private var udpSocket: UDPStreamSocket?
    private var captureRecorder: CaptureRecorder?
    private var pendingCommands: [Int: PendingCommandContext] = [:]
    private var manualDisconnectRequested = false
    private var reconnectTask: Task<Void, Never>?
    private var diagnosticsRefreshTask: Task<Void, Never>?
    private var rxAudioStreamID: UInt32?
    private var txAudioStreamID: UInt32?
    private var clientHandle: String?
    private var selectedSliceID: Int?
    private var selectedSliceOwnedByClient = false
    private var selectedOwnedSliceIsTransmit = false
    private var didAttemptClientSliceProvision = false
    private var didProcessSliceList = false
    private var sawAnySliceInList = false
    private var audioClientSliceID: Int?
    private var audioClientBindingInFlightSliceID: Int?
    private var captureFramesWritten = 0
    private var tracedProtocolSequences: Set<Int> = []

    public init() {
        let diagnostics = DiagnosticsCenter()
        let audioPipeline = RemoteAudioPipeline(capacity: 64, diagnostics: diagnostics)
        self.diagnostics = diagnostics
        self.bootstrapper = RadioSessionBootstrapper(diagnostics: diagnostics)
        let defaultMacros = Self.defaultMacros
        self.cwEngine = CWEngine(diagnostics: diagnostics, macros: defaultMacros)
        self.availableMacros = defaultMacros
        self.midiManager = MidiManager(diagnostics: diagnostics)
        self.audioDeviceManager = AudioDeviceManager()
        self.audioPipeline = audioPipeline
        self.udpIngress = UDPIngressCoordinator(audioPipeline: audioPipeline)
        self.connectionProfile = ConnectionProfile(name: "Primary Radio", mode: .manualHost, host: "192.168.0.199")
        self.wanProfile = .wanSSB

        Task {
            await restorePreferences()
            await refreshHardwareOptions()
            scheduleDiagnosticsRefresh(immediate: true)
        }
    }

    deinit {
        let recorder = captureRecorder
        Task {
            try? await recorder?.flushManifest()
            try? await recorder?.finish(notes: "app quit")
        }
    }

    public func connect() {
        guard phase == .disconnected || phase == .recovering || phase == .error else { return }
        manualDisconnectRequested = false
        lastErrorMessage = nil
        transition(to: .connecting, status: "Connecting to \(connectionProfile.host)")
        Task {
            if captureEnabled {
                try? await ensureCaptureRecorderInitialized()
                try? await captureRecorder?.flushManifest()
            }
            await startSession()
        }
    }

    public func reconnectNow() {
        Task {
            await transport?.disconnect()
            await MainActor.run {
                self.phase = .recovering
                self.connectionStatus = "Recovering..."
            }
            await startSession()
        }
    }

    public func disconnect() {
        manualDisconnectRequested = true
        reconnectTask?.cancel()
        reconnectTask = nil
        Task {
            await transport?.disconnect()
            await udpSocket?.close()
            await udpIngress.reset()
            if let captureRecorder {
                try? await captureRecorder.flushManifest()
                try? await captureRecorder.finish(notes: manualDisconnectRequested ? "manual disconnect" : "session ended")
            }
            await MainActor.run {
                self.transport = nil
                self.udpSocket = nil
                self.captureRecorder = nil
                self.activeCapturePath = nil
                self.pendingCommands.removeAll()
                self.tracedProtocolSequences.removeAll()
                self.rxAudioStreamID = nil
                self.txAudioStreamID = nil
                self.clientHandle = nil
                self.selectedSliceID = nil
                self.selectedSliceOwnedByClient = false
                self.selectedOwnedSliceIsTransmit = false
                self.didAttemptClientSliceProvision = false
                self.didProcessSliceList = false
                self.sawAnySliceInList = false
                self.audioClientSliceID = nil
                self.audioClientBindingInFlightSliceID = nil
                self.captureFramesWritten = 0
                self.stageCounters = AudioPipelineStageCounters()
                self.transition(to: .disconnected, status: "Disconnected")
            }
        }
    }

    public func setConnectionMode(_ mode: ConnectionMode) {
        connectionProfile.mode = mode
        persistPreferences()
    }

    public func setHost(_ host: String) {
        connectionProfile.host = host
        persistPreferences()
    }

    public func setTCPPort(_ port: UInt16) {
        connectionProfile.tcpPort = port
        persistPreferences()
    }

    public func setUDPPort(_ port: UInt16) {
        connectionProfile.udpPort = port
        persistPreferences()
    }

    public func setProfileName(_ name: String) {
        connectionProfile.name = name
        persistPreferences()
    }

    public func setStationName(_ name: String) {
        connectionProfile.stationName = name
        persistPreferences()
    }

    public func setMode(_ mode: RadioMode) {
        activeSlice.mode = mode
        let filter = recommendedFilter(for: mode)
        activeSlice.filterLowHz = filter.low
        activeSlice.filterHighHz = filter.high
        Task {
            try? await send(body: encoder.sliceSet(id: activeSlice.id, updates: ["mode": mode.rawValue]), kind: .mode)
            try? await send(body: encoder.filter(id: activeSlice.id, lowHz: filter.low, highHz: filter.high), kind: .filter)
            await persistPreferences()
        }
    }

    public func setFrequencyMHz(_ value: Double) {
        activeSlice.frequencyMHz = value
        let sliceID = activeSlice.id
        Task {
            await tuningCoalescer.submit(targetFrequencyMHz: value) { [weak self] frequency in
                guard let self else { return }
                try? await self.send(body: self.encoder.sliceTune(id: sliceID, frequencyMHz: frequency), kind: .tune)
            }
        }
    }

    public func stepFrequency(by deltaMHz: Double) {
        setFrequencyMHz(activeSlice.frequencyMHz + deltaMHz)
    }

    public func setFilter(low: Int, high: Int) {
        activeSlice.filterLowHz = low
        activeSlice.filterHighHz = high
        Task {
            try? await send(body: encoder.filter(id: activeSlice.id, lowHz: low, highHz: high), kind: .filter)
        }
    }

    public func setAFGain(_ gain: Int) {
        activeSlice.afGain = max(0, min(gain, 100))
        Task {
            guard let clientID else { return }
            let value = Double(activeSlice.afGain) / 100.0
            try? await send(body: encoder.audioClientGain(clientID: clientID, sliceID: activeSlice.id, gain: value), kind: .audioClientGain)
        }
    }

    public func toggleMute() {
        activeSlice.isMuted.toggle()
        Task {
            guard let clientID else { return }
            try? await send(body: encoder.audioClientMute(clientID: clientID, sliceID: activeSlice.id, muted: activeSlice.isMuted), kind: .audioClientMute)
        }
    }

    public func setTransmitEnabled(_ enabled: Bool) {
        guard txState.txAllowed || !enabled else {
            lastErrorMessage = "Transmit blocked by interlock"
            return
        }

        transition(to: enabled ? .txArming : .rxOnly, status: enabled ? "Arming TX..." : "Returning to RX...")
        Task {
            try? await send(body: encoder.xmit(enabled), kind: .xmit)
        }
    }

    public func setMicGain(_ value: Int) {
        Task {
            try? await send(body: encoder.transmitSet(["miclevel": "\(max(0, min(value, 100)))"]), kind: .transmitSet)
        }
    }

    public func queueCWText(_ text: String) {
        Task {
            let block = await cwEngine.nextBlockIdentifier()
            await cwEngine.send(text: text, block: block)
            cwxQueueState.pendingCount = await cwEngine.pendingCount()
            cwxQueueState.lastBlock = block
            try? await send(body: encoder.cwxSend(text, block: block), kind: .cwxSend)
            scheduleDiagnosticsRefresh()
            await persistPreferences()
        }
    }

    public func clearCWQueue() {
        Task {
            await cwEngine.clear()
            cwxQueueState.pendingCount = 0
            try? await send(body: encoder.cwxClear(), kind: .cwxClear)
            scheduleDiagnosticsRefresh()
        }
    }

    public func triggerMacro(_ macro: CWMacro) {
        queueCWText(macro.text)
    }

    public func saveMacro(slot index: Int, title: String, text: String) {
        let macro = index < availableMacros.count ? CWMacro(id: availableMacros[index].id, title: title, text: text) : CWMacro(title: title, text: text)
        Task {
            await cwEngine.saveMacro(macro)
            if index < 12 {
                try? await send(body: encoder.cwxMacroSave(slot: index + 1, text: text), kind: .cwxMacroSave)
            }
            scheduleDiagnosticsRefresh()
            await persistPreferences()
        }
    }

    public func selectInputDevice(_ id: String?) {
        selectedInputDeviceID = id
        persistPreferences()
    }

    public func selectOutputDevice(_ id: String?) {
        selectedOutputDeviceID = id
        Task { await udpIngress.setOutputDevice(id) }
        persistPreferences()
    }

    public func selectMidiSource(_ id: Int32?) {
        selectedMidiSourceID = id
        persistPreferences()
    }

    public func setCaptureEnabled(_ enabled: Bool) {
        captureEnabled = enabled
        Task {
            if enabled {
                do {
                    try await ensureCaptureRecorderInitialized()
                    try await captureRecorder?.flushManifest()
                    await diagnostics.log(.info, "Capture bundle initialized", metadata: ["path": activeCapturePath ?? "unknown"])
                } catch {
                    await diagnostics.log(.error, "Capture initialization failed", metadata: ["error": error.localizedDescription])
                    await MainActor.run {
                        self.lastErrorMessage = "Capture initialization failed: \(error.localizedDescription)"
                    }
                }
            } else if let recorder = captureRecorder {
                try? await recorder.flushManifest()
                try? await recorder.finish(notes: "capture mode disabled")
                await MainActor.run {
                    self.captureRecorder = nil
                }
            }
            scheduleDiagnosticsRefresh(immediate: true)
        }
    }

    public func playTestTone() {
        Task {
            let outputName = selectedOutputDeviceID.flatMap { id in
                outputDevices.first(where: { $0.id == id })?.name
            } ?? "System Default"
            await diagnostics.log(.info, "Test tone start", metadata: ["device": outputName])
            let report = await udpIngress.playTestTone(outputDeviceName: outputName)
            await diagnostics.log(.info, "Test tone result", metadata: [
                "engine_started": report.engineStarted ? "1" : "0",
                "engine_stopped": report.engineStopped ? "1" : "0",
                "device": report.outputDeviceName,
                "sample_rate": String(format: "%.0f", report.outputSampleRate),
                "channels": "\(report.channelCount)",
                "submitted_buffers": "\(report.submittedBufferCount)",
                "rendered_buffers": "\(report.renderedBufferCount)",
                "non_zero_samples": "\(report.nonZeroSampleCount)",
                "rms": String(format: "%.6f", report.rmsLevel),
                "peak": String(format: "%.6f", report.peakLevel)
            ])
            scheduleDiagnosticsRefresh(immediate: true)
        }
    }

    public func refreshDiagnostics() async {
        let ingress = await udpIngress.snapshot()
        let recorderFrameCount = await captureRecorder?.udpFrameCount() ?? captureFramesWritten
        let events = await diagnostics.recentEvents(limit: 120).filter { $0.level != .debug }
        let macros = await cwEngine.allMacros()
        let pendingCW = await cwEngine.pendingCount()
        await MainActor.run {
            self.udpPacketCount = ingress.udpPacketCount
            self.sequenceGapCount = ingress.sequenceGapCount
            self.networkMetrics.audioBufferDepthFrames = ingress.audioStats.bufferDepth
            self.networkMetrics.packetLossEstimate = ingress.audioStats.packetLossEstimate
            self.networkMetrics.underrunCount = ingress.audioStats.underruns
            self.lastDecodeError = ingress.lastDecodeError ?? ingress.audioStats.lastError
            self.stageCounters = AudioPipelineStageCounters(
                udpAudioPacketsReceived: ingress.udpAudioPacketsReceived,
                vitaAudioPacketsParsed: ingress.vitaAudioPacketsParsed,
                decoderPayloadsAccepted: ingress.audioStats.payloadsAcceptedByDecoder,
                decodedPCMFramesProduced: ingress.audioStats.decodedPCMFrames,
                playbackBuffersSubmitted: ingress.audioStats.playbackBuffersSubmitted,
                playbackBuffersRendered: ingress.audioStats.playbackBuffersRendered,
                captureFramesWritten: recorderFrameCount
            )
            self.availableMacros = macros
            self.cwxQueueState.pendingCount = pendingCW
            self.diagnosticsText = events.suffix(30).map { event in
                let meta = event.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
                return meta.isEmpty ? "\(event.level.rawValue.uppercased()) \(event.message)" : "\(event.level.rawValue.uppercased()) \(event.message) \(meta)"
            }.joined(separator: "\n")
        }
    }

    private func startSession() async {
        let connector = connector(for: connectionProfile.mode)
        do {
            await diagnostics.clear()
            await MainActor.run {
                self.clientHandle = nil
                self.selectedSliceID = nil
                self.selectedSliceOwnedByClient = false
                self.selectedOwnedSliceIsTransmit = false
                self.didAttemptClientSliceProvision = false
                self.didProcessSliceList = false
                self.sawAnySliceInList = false
                self.audioClientSliceID = nil
                self.audioClientBindingInFlightSliceID = nil
                self.captureFramesWritten = 0
                self.stageCounters = AudioPipelineStageCounters()
                self.tracedProtocolSequences.removeAll()
            }
            let transport = try await connector.connect(
                profile: connectionProfile,
                diagnostics: diagnostics,
                onLineReceived: { [weak self] line in await self?.handleIncoming(line: line) },
                onEvent: { [weak self] event in await self?.handleTransportEvent(event) }
            )
            await MainActor.run { self.transport = transport }
            try await prepareCaptureAndUDP()
            transition(to: .bootstrapping, status: "Bootstrapping session")

            let plan = await bootstrapper.bootstrapPlan(profile: connectionProfile, wanProfile: wanProfile)
            await bootstrapper.logPlan(plan)
            for command in plan {
                try await send(body: command.body, kind: command.kind)
            }

            transition(to: .ready, status: "Connected to \(connectionProfile.host)")
            await midiManager.logDiagnosticProbe()
            scheduleDiagnosticsRefresh(immediate: true)
            await persistPreferences()
        } catch {
            await diagnostics.log(.error, "Connection failed", metadata: ["error": error.localizedDescription])
            await MainActor.run {
                self.lastErrorMessage = error.localizedDescription
                self.transition(to: .error, status: "Connection failed")
            }
            scheduleDiagnosticsRefresh(immediate: true)
        }
    }

    private func connector(for mode: ConnectionMode) -> any RadioConnector {
        switch mode {
        case .lan:
            return LanConnector()
        case .manualHost:
            return ManualHostConnector()
        case .vpn:
            return VpnConnector()
        case .smartLink:
            return SmartLinkConnector()
        }
    }

    private func send(body: String, kind: RadioCommandKind) async throws {
        guard let transport else { throw SessionControllerError.notConnected }
        let sequence = await sequenceGenerator.next()
        pendingCommands[sequence] = PendingCommandContext(kind: kind, sentAt: .now, body: body)
        let wire = encoder.wrap(body: body, sequence: sequence)
        if shouldTraceProtocolCommand(body) {
            tracedProtocolSequences.insert(sequence)
            await diagnostics.log(.info, "PROTO OUT", metadata: ["line": wire])
        }
        try? await captureRecorder?.recordControl(direction: .outbound, rawLine: wire)
        try await transport.send(command: wire)
    }

    private func handleIncoming(line: String) async {
        if shouldTraceInboundProtocolLine(line) {
            await diagnostics.log(.info, "PROTO IN", metadata: ["line": line])
        }
        try? await captureRecorder?.recordControl(direction: .inbound, rawLine: line)
        let message = parser.parse(line: line)

        switch message {
        case .handle(let handle):
            await MainActor.run {
                self.clientHandle = Self.normalizeHandle(handle)
            }
        case .status(let status):
            await apply(status: status)
        case .response(let response):
            await apply(response: response)
        case .notice(let notice):
            await diagnostics.log(notice.severity.asLogLevel, "Radio notice", metadata: ["code": notice.codeHex, "message": notice.text])
        default:
            break
        }

        scheduleDiagnosticsRefresh()
    }

    private func apply(response: CommandResponse) async {
        tracedProtocolSequences.remove(response.sequence)
        let context = pendingCommands.removeValue(forKey: response.sequence)
        if context?.kind == .audioClientAdd {
            audioClientBindingInFlightSliceID = nil
        }
        if let context {
            let elapsed = Date().timeIntervalSince(context.sentAt) * 1000
            await MainActor.run {
                self.networkMetrics.commandRTTMilliseconds = elapsed
            }
        }

        guard response.isSuccess else {
            await diagnostics.log(.warning, "Command failed", metadata: [
                "sequence": "\(response.sequence)",
                "kind": context?.kind.rawValue ?? "unknown",
                "command": context?.body ?? "",
                "code": response.codeHex,
                "payload": response.payload
            ])
            if context?.kind == .sliceCreate || context?.kind == .audioClientAdd || context?.kind == .audioClientGain || context?.kind == .audioClientMute {
                return
            }
            await MainActor.run {
                self.lastErrorMessage = response.payload.isEmpty ? "Command failed: \(response.codeHex)" : response.payload
                self.phase = .error
            }
            return
        }

        switch context?.kind {
        case .clientGUI:
            if !response.payload.isEmpty {
                await MainActor.run {
                    self.clientID = response.payload
                    self.connectionProfile.clientID = response.payload
                }
                await ensureAudioClientBindingIfNeeded()
                await persistPreferences()
            }
        case .sliceList:
            let listedSliceIdentifiers = parseSliceIdentifiers(from: response.payload)
            await MainActor.run {
                self.didProcessSliceList = true
                self.sawAnySliceInList = !listedSliceIdentifiers.isEmpty
            }
            await ensureClientOwnedSliceProvisionedIfNeeded()
        case .createRxStream:
            let streamID = parseHexIdentifier(response.payload)
            await udpIngress.setRXStreamID(streamID)
            await MainActor.run {
                self.rxAudioStreamID = streamID
                self.audioState.streamID = response.payload.isEmpty ? self.audioState.streamID : response.payload
                self.audioState.compression = self.wanProfile.remoteAudio.compression.rawValue.uppercased()
                self.audioState.rxEnabled = streamID != nil
            }
            await ensureAudioClientBindingIfNeeded()
        case .createTxStream:
            let streamID = parseHexIdentifier(response.payload)
            await MainActor.run {
                self.txAudioStreamID = streamID
                self.audioState.txAudioEnabled = streamID != nil
            }
        case .audioClientAdd:
            let boundSliceID = parseAudioClientSliceID(from: context?.body) ?? selectedSliceID ?? activeSlice.id
            audioClientSliceID = boundSliceID
            let gain = Double(max(0, min(activeSlice.afGain, 100))) / 100.0
            if let clientID {
                try? await send(body: encoder.audioClientGain(clientID: clientID, sliceID: boundSliceID, gain: gain), kind: .audioClientGain)
                try? await send(body: encoder.audioClientMute(clientID: clientID, sliceID: boundSliceID, muted: activeSlice.isMuted), kind: .audioClientMute)
            }
        default:
            break
        }
    }

    private func apply(status: StatusMessage) async {
        switch status.object {
        case "slice":
            guard let identifier = status.identifier.flatMap(Int.init) else { break }
            let isRadioActive = status.properties["active"] == "1"
            let isTransmitSlice = (status.properties["tx"] ?? "").uppercased() == "1" || (status.properties["tx"] ?? "").uppercased() == "T"
            let frequency = status.properties["RF_frequency"].flatMap(Double.init) ?? status.properties["freq"].flatMap(Double.init)
            let isOwnedByClient: Bool = {
                guard let clientHandle,
                      let sliceHandle = Self.normalizeHandle(status.properties["client_handle"]) else {
                    return false
                }
                return clientHandle == sliceHandle
            }()

            let previousSelection = selectedSliceID
            if isOwnedByClient {
                if selectedSliceID == nil || !selectedSliceOwnedByClient {
                    selectedSliceID = identifier
                    selectedSliceOwnedByClient = true
                    selectedOwnedSliceIsTransmit = isTransmitSlice
                } else if selectedSliceID == identifier {
                    selectedSliceOwnedByClient = true
                    selectedOwnedSliceIsTransmit = isTransmitSlice
                } else if !selectedOwnedSliceIsTransmit, isTransmitSlice {
                    selectedSliceID = identifier
                    selectedSliceOwnedByClient = true
                    selectedOwnedSliceIsTransmit = true
                }
            } else if !selectedSliceOwnedByClient, isTransmitSlice {
                selectedSliceID = identifier
                selectedSliceOwnedByClient = false
                selectedOwnedSliceIsTransmit = true
            }
            let selectionChanged = previousSelection != selectedSliceID

            if selectionChanged, selectedSliceID == identifier {
                await diagnostics.log(.info, "Selected slice", metadata: [
                    "id": "\(identifier)",
                    "tx": isTransmitSlice ? "1" : "0",
                    "active": isRadioActive ? "1" : "0",
                    "owned": isOwnedByClient ? "1" : "0",
                    "freq": frequency.map { String(format: "%.6f", $0) } ?? "unknown"
                ])
            }

            guard selectedSliceID == identifier else { break }

            activeSlice = Slice(
                id: identifier,
                frequencyMHz: activeSlice.frequencyMHz,
                mode: activeSlice.mode,
                filterLowHz: activeSlice.filterLowHz,
                filterHighHz: activeSlice.filterHighHz,
                isTransmitSlice: activeSlice.isTransmitSlice,
                isMuted: activeSlice.isMuted,
                afGain: activeSlice.afGain
            )
            if let frequency {
                activeSlice.frequencyMHz = frequency
            }
            if let modeValue = status.properties["mode"], let mode = RadioMode(rawValue: modeValue) {
                activeSlice.mode = mode
            }
            if let low = parseFilterHz(status.properties["filter_lo"]) {
                activeSlice.filterLowHz = low
            }
            if let high = parseFilterHz(status.properties["filter_hi"]) {
                activeSlice.filterHighHz = high
            }
            activeSlice.isTransmitSlice = isTransmitSlice
            await ensureAudioClientBindingIfNeeded(for: identifier)
        case "interlock":
            let stateString = status.properties["state"] ?? "UNKNOWN"
            let state = InterlockState(rawValue: stateString) ?? .unknown
            await MainActor.run {
                self.txState.interlock = stateString
                self.txState.interlockState = state
                self.txState.reason = status.properties["reason"]
                self.txState.txAllowed = state == .ready || state == .receive || state == .transmitting
                self.txState.isTransmitting = state == .transmitting || state == .pttRequested
                self.phase = state == .transmitting ? .transmitting : (self.phase == .txArming ? .rxOnly : self.phase)
            }
        case "audio_stream":
            await MainActor.run {
                self.audioState.streamID = status.identifier
                self.audioState.compression = status.properties["compression"] ?? self.audioState.compression
                self.audioState.bufferDepth = Int(status.properties["buffer_depth"] ?? "") ?? self.audioState.bufferDepth
                self.audioState.rxEnabled = (status.properties["rx_on"] ?? "").lowercased() == "on"
                self.audioState.txAudioEnabled = (status.properties["tx_audio"] ?? "").lowercased() == "on"
                self.networkMetrics.audioBufferDepthFrames = self.audioState.bufferDepth
            }
        case "stream":
            let streamType = status.properties["type"] ?? ""
            let streamID = parseHexIdentifier(status.identifier)
            if streamType == "remote_audio_rx" {
                await udpIngress.setRXStreamID(streamID)
            }
            await MainActor.run {
                if streamType == "remote_audio_rx" {
                    self.rxAudioStreamID = streamID
                    self.audioState.streamID = status.identifier
                    self.audioState.compression = status.properties["compression"] ?? self.audioState.compression
                    self.audioState.rxEnabled = true
                } else if streamType == "remote_audio_tx" {
                    self.txAudioStreamID = streamID
                    self.audioState.txAudioEnabled = true
                }
            }
            if streamType == "remote_audio_rx" {
                await ensureAudioClientBindingIfNeeded()
            }
        case "cwx":
            if let indexString = status.properties["index"], let index = Int(indexString) {
                await MainActor.run { self.cwxQueueState.lastRadioIndex = index }
            }
        default:
            break
        }
    }

    private func handleTransportEvent(_ event: TransportEvent) async {
        switch event {
        case .ready:
            await diagnostics.log(.info, "TCP transport ready")
        case .disconnected:
            await diagnostics.log(.warning, "TCP transport disconnected")
            await MainActor.run {
                self.transport = nil
                self.pendingCommands.removeAll()
                self.tracedProtocolSequences.removeAll()
                self.rxAudioStreamID = nil
                self.txAudioStreamID = nil
                self.clientHandle = nil
                self.selectedSliceID = nil
                self.selectedSliceOwnedByClient = false
                self.selectedOwnedSliceIsTransmit = false
                self.didAttemptClientSliceProvision = false
                self.didProcessSliceList = false
                self.sawAnySliceInList = false
                self.audioClientSliceID = nil
                self.audioClientBindingInFlightSliceID = nil
                self.captureFramesWritten = 0
                self.stageCounters = AudioPipelineStageCounters()
                if self.manualDisconnectRequested {
                    self.transition(to: .disconnected, status: "Disconnected")
                } else {
                    self.transition(to: .recovering, status: "Connection dropped, retrying…")
                }
            }

            guard !manualDisconnectRequested else { return }
            reconnectTask?.cancel()
            reconnectTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await self.startSession()
            }
        case .failed(let description):
            await diagnostics.log(.error, "TCP transport failed", metadata: ["error": description])
            await MainActor.run {
                self.lastErrorMessage = description
                self.transition(to: .error, status: "Transport error")
            }
        }
    }

    private func refreshHardwareOptions() async {
        let inputs = await audioDeviceManager.inputDevices()
        let outputs = await audioDeviceManager.outputDevices()
        let defaultOutput = await audioDeviceManager.defaultOutputDeviceID()
        let sources = await midiManager.availableSources()
        await MainActor.run {
            self.inputDevices = inputs
            self.outputDevices = outputs
            self.midiSources = sources
            if self.selectedOutputDeviceID == nil {
                self.selectedOutputDeviceID = defaultOutput
            }
        }
    }

    private func restorePreferences() async {
        let initial = PersistedOperatorState(
            connectionProfile: connectionProfile,
            wanProfile: wanProfile,
            audio: AudioPreferenceState(),
            midi: MidiBindingPreference(),
            cwMacros: Self.defaultMacros
        )
        let restored = await preferencesStore.load(defaultState: initial)
        await MainActor.run {
            self.connectionProfile = restored.connectionProfile
            if self.connectionProfile.host == "192.168.1.10" {
                self.connectionProfile.host = "192.168.0.199"
            }
            self.wanProfile = restored.wanProfile
            self.selectedInputDeviceID = restored.audio.inputDeviceID
            self.selectedOutputDeviceID = restored.audio.outputDeviceID
            self.selectedMidiSourceID = restored.midi.sourceID
            self.clientID = restored.connectionProfile.clientID
        }
        await udpIngress.setOutputDevice(restored.audio.outputDeviceID)
        for macro in restored.cwMacros {
            await cwEngine.saveMacro(macro)
        }
    }

    private func persistPreferences() {
        Task { await persistPreferences() }
    }

    private func persistPreferences() async {
        let macros = await cwEngine.allMacros()
        let state = PersistedOperatorState(
            connectionProfile: connectionProfile,
            wanProfile: wanProfile,
            audio: AudioPreferenceState(
                inputDeviceID: selectedInputDeviceID,
                outputDeviceID: selectedOutputDeviceID,
                sidetoneEnabled: true,
                sidetonePitchHz: 600
            ),
            midi: MidiBindingPreference(sourceID: selectedMidiSourceID),
            cwMacros: macros
        )
        await preferencesStore.save(state)
    }

    private func transition(to newPhase: SessionPhase, status: String) {
        phase = newPhase
        connectionStatus = status
    }

    private func prepareCaptureAndUDP() async throws {
        let udpIngress = self.udpIngress
        let udpSocket = UDPStreamSocket { [weak self] data in
            if let self {
                let recorder = await MainActor.run { self.captureRecorder }
                let destination = await MainActor.run { "\(self.connectionProfile.host):\(self.connectionProfile.udpPort)" }
                if let recorder {
                    do {
                        try await recorder.recordUDP(datagram: data, destination: destination)
                        await MainActor.run {
                            self.captureFramesWritten += 1
                        }
                    } catch {
                        await self.diagnostics.log(.error, "Capture frame write failed", metadata: ["error": error.localizedDescription])
                    }
                }
                await udpIngress.handleDatagram(data)
                await MainActor.run {
                    self.scheduleDiagnosticsRefresh()
                }
            }
        }
        try await udpSocket.bind(localPort: connectionProfile.udpPort)
        await udpSocket.configure(remoteHost: connectionProfile.host, remotePort: 4991)
        self.udpSocket = udpSocket
        if captureEnabled {
            try await ensureCaptureRecorderInitialized()
        }
    }

    private func ensureCaptureRecorderInitialized() async throws {
        if let recorder = captureRecorder {
            activeCapturePath = recorder.bundleURL.path
            return
        }

        let baseURL = captureBaseURL()
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let recorder = try CaptureRecorder(baseURL: baseURL, context: captureContext())
        captureRecorder = recorder
        captureFramesWritten = 0
        activeCapturePath = recorder.bundleURL.path
    }

    private func captureBaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("FlexLite", isDirectory: true)
            .appendingPathComponent("CaptureBundles", isDirectory: true)
    }

    private func captureContext() -> CaptureContext {
        CaptureContext(
            sessionName: connectionProfile.name,
            manifest: CaptureBundleManifest(
                appVersion: "dev",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                connectionMode: connectionProfile.mode.rawValue,
                radioIdentity: nil,
                sliceInfo: "slice=\(activeSlice.id)",
                selectedMode: activeSlice.mode.rawValue,
                filterDescription: "\(activeSlice.filterLowHz)...\(activeSlice.filterHighHz)",
                rxAudioEnabled: wanProfile.remoteAudio.rxEnabled,
                txAudioEnabled: wanProfile.remoteAudio.txAudioEnabled,
                cwxUsed: cwxQueueState.pendingCount > 0,
                ctr2Attached: selectedMidiSourceID != nil
            ),
            sessionMetadata: CaptureSessionMetadata(
                sessionName: connectionProfile.name,
                host: connectionProfile.host,
                tcpPort: connectionProfile.tcpPort,
                udpPort: connectionProfile.udpPort
            ),
            operatorSettings: OperatorSettingsSnapshot(
                values: [
                    "wanProfile": wanProfile.name,
                    "inputDeviceID": selectedInputDeviceID ?? "",
                    "outputDeviceID": selectedOutputDeviceID ?? "",
                    "midiSourceID": selectedMidiSourceID.map(String.init) ?? ""
                ]
            )
        )
    }

    private func parseFilterHz(_ rawValue: String?) -> Int? {
        guard let rawValue else { return nil }
        if let intValue = Int(rawValue) {
            return intValue
        }
        if let doubleValue = Double(rawValue) {
            return Int(doubleValue * 1_000_000)
        }
        return nil
    }

    private func parsePreferredSliceIdentifier(from payload: String) -> Int? {
        payload
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .last
    }

    private func parseHexIdentifier(_ rawValue: String?) -> UInt32? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            return UInt32(trimmed.dropFirst(2), radix: 16)
        }
        return UInt32(trimmed, radix: 16) ?? UInt32(trimmed)
    }

    private func shouldTraceProtocolCommand(_ body: String) -> Bool {
        body.hasPrefix("client gui") ||
        body.hasPrefix("client udpport ") ||
        body.hasPrefix("stream create type=remote_audio_rx") ||
        body == "remote_audio rx_on on" ||
        body.hasPrefix("audio client ")
    }

    private func shouldTraceInboundProtocolLine(_ line: String) -> Bool {
        if line.hasPrefix("S"), line.contains("stream "), line.contains("remote_audio_rx") {
            return true
        }
        guard line.hasPrefix("R"), let sequence = responseSequence(from: line) else { return false }
        return tracedProtocolSequences.contains(sequence)
    }

    private func responseSequence(from line: String) -> Int? {
        guard line.count > 1 else { return nil }
        let payload = line.dropFirst()
        let sequencePart = payload.prefix { $0 != "|" }
        return Int(sequencePart)
    }

    private func scheduleDiagnosticsRefresh(immediate: Bool = false) {
        guard diagnosticsRefreshTask == nil else { return }
        diagnosticsRefreshTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(250))
            }
            await self?.refreshDiagnostics()
            await MainActor.run {
                self?.diagnosticsRefreshTask = nil
            }
        }
    }

    private func ensureClientOwnedSliceProvisionedIfNeeded() async {
        let shouldProvision = await MainActor.run {
            guard self.clientHandle != nil else { return false }
            guard self.didProcessSliceList else { return false }
            guard !self.sawAnySliceInList else { return false }
            guard !self.selectedSliceOwnedByClient else { return false }
            guard !self.didAttemptClientSliceProvision else { return false }
            self.didAttemptClientSliceProvision = true
            return true
        }

        guard shouldProvision else { return }
        await diagnostics.log(.info, "Provisioning client-owned slice")
        try? await send(
            body: encoder.sliceCreate(frequencyMHz: connectionProfile.defaultFrequencyMHz, mode: connectionProfile.defaultMode),
            kind: .sliceCreate
        )
    }

    private func ensureAudioClientBindingIfNeeded(for preferredSliceID: Int? = nil) async {
        guard let clientID else { return }
        guard rxAudioStreamID != nil else { return }
        let targetSliceID = preferredSliceID ?? selectedSliceID ?? activeSlice.id
        guard audioClientSliceID != targetSliceID else { return }
        guard audioClientBindingInFlightSliceID != targetSliceID else { return }

        audioClientBindingInFlightSliceID = targetSliceID
        try? await send(body: encoder.audioClientAdd(clientID: clientID, sliceID: targetSliceID), kind: .audioClientAdd)
    }

    private func parseAudioClientSliceID(from commandBody: String?) -> Int? {
        guard let commandBody else { return nil }
        let tokens = commandBody.split(whereSeparator: \.isWhitespace)
        guard let markerIndex = tokens.firstIndex(of: "slice"), tokens.indices.contains(tokens.index(after: markerIndex)) else {
            return nil
        }
        return Int(tokens[tokens.index(after: markerIndex)])
    }

    private func recommendedFilter(for mode: RadioMode) -> (low: Int, high: Int) {
        switch mode {
        case .usb:
            return (100, 2_800)
        case .lsb:
            return (-2_800, -100)
        case .cw:
            return (-200, 200)
        }
    }

    private func parseSliceIdentifiers(from payload: String) -> [Int] {
        payload
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func normalizeHandle(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            return "0x" + trimmed.dropFirst(2).uppercased()
        }
        return "0x" + trimmed.uppercased()
    }

    private static let defaultMacros: [CWMacro] = [
        CWMacro(title: "CQ", text: "CQ CQ DE VK?TEST K"),
        CWMacro(title: "TU", text: "TU 73"),
        CWMacro(title: "CALL", text: "DE VK?TEST")
    ]
}

public actor TuningCoalescer {
    private var pendingFrequencyMHz: Double?
    private var task: Task<Void, Never>?

    public init() {}

    public func submit(
        targetFrequencyMHz: Double,
        delay: Duration = .milliseconds(125),
        action: @escaping @Sendable (Double) async -> Void
    ) {
        pendingFrequencyMHz = targetFrequencyMHz
        guard task == nil else { return }

        task = Task {
            try? await Task.sleep(for: delay)
            let value = await self.consumePendingAndClearTask()
            if let value {
                await action(value)
            }
        }
    }

    private func consumePendingAndClearTask() async -> Double? {
        task = nil
        defer { pendingFrequencyMHz = nil }
        return pendingFrequencyMHz
    }
}

private struct UDPIngressSnapshot: Sendable {
    let udpPacketCount: Int
    let udpAudioPacketsReceived: Int
    let vitaAudioPacketsParsed: Int
    let sequenceGapCount: Int
    let lastDecodeError: String?
    let audioStats: RemoteAudioPipeline.Stats
}

private actor UDPIngressCoordinator {
    private let audioPipeline: RemoteAudioPipeline
    private let vitaParser = VitaParser()
    private var rxAudioStreamID: UInt32?
    private var lastUDPSequenceByStream: [UInt32: UInt16] = [:]
    private var udpPacketCount = 0
    private var udpAudioPacketsReceived = 0
    private var vitaAudioPacketsParsed = 0
    private var sequenceGapCount = 0
    private var lastDecodeError: String?

    init(audioPipeline: RemoteAudioPipeline) {
        self.audioPipeline = audioPipeline
    }

    func setRXStreamID(_ identifier: UInt32?) {
        rxAudioStreamID = identifier
        lastUDPSequenceByStream.removeAll(keepingCapacity: true)
        lastDecodeError = nil
    }

    func reset() async {
        rxAudioStreamID = nil
        lastUDPSequenceByStream.removeAll(keepingCapacity: false)
        udpPacketCount = 0
        udpAudioPacketsReceived = 0
        vitaAudioPacketsParsed = 0
        sequenceGapCount = 0
        lastDecodeError = nil
        await audioPipeline.reset()
    }

    func setOutputDevice(_ deviceID: String?) async {
        await audioPipeline.setOutputDevice(deviceID)
    }

    func playTestTone(outputDeviceName: String) async -> RemoteAudioPipeline.ToneTestReport {
        await audioPipeline.playTestTone(outputDeviceName: outputDeviceName)
    }

    func handleDatagram(_ data: Data) async {
        udpPacketCount += 1

        guard let streamID = extractStreamIdentifier(from: data) else { return }
        guard rxAudioStreamID == nil || streamID == rxAudioStreamID else { return }
        udpAudioPacketsReceived += 1

        do {
            let packet = try vitaParser.parse(data)
            vitaAudioPacketsParsed += 1
            guard rxAudioStreamID == nil || packet.streamIdentifier == rxAudioStreamID else { return }
            if let lastSequence = lastUDPSequenceByStream[packet.streamIdentifier] {
                let expectedSequence = nextSequence(after: lastSequence)
                if packet.sequence != expectedSequence {
                    sequenceGapCount += 1
                }
            }
            lastUDPSequenceByStream[packet.streamIdentifier] = packet.sequence
            try Task.checkCancellation()
            await audioPipeline.receive(packet)
            lastDecodeError = nil
        } catch {
            lastDecodeError = error.localizedDescription
        }
    }

    func snapshot() async -> UDPIngressSnapshot {
        UDPIngressSnapshot(
            udpPacketCount: udpPacketCount,
            udpAudioPacketsReceived: udpAudioPacketsReceived,
            vitaAudioPacketsParsed: vitaAudioPacketsParsed,
            sequenceGapCount: sequenceGapCount,
            lastDecodeError: lastDecodeError,
            audioStats: await audioPipeline.stats()
        )
    }

    private func extractStreamIdentifier(from data: Data) -> UInt32? {
        guard data.count >= 8 else { return nil }
        return data[4..<8].reduce(into: UInt32.zero) { partial, byte in
            partial = (partial << 8) | UInt32(byte)
        }
    }

    private func nextSequence(after value: UInt16) -> UInt16 {
        (value + 1) & 0x000F
    }
}

private extension MessageSeverity {
    var asLogLevel: LogLevel {
        switch self {
        case .informational:
            return .info
        case .warning:
            return .warning
        case .error, .fatal:
            return .error
        }
    }
}
