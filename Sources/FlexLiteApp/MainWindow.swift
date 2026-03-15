import Core
import SmartSDRProtocol
import SwiftUI

struct MainWindow: View {
    @ObservedObject var controller: RadioSessionController
    @State private var cwText = ""
    @State private var frequencyText = ""
    @State private var hostText = ""
    @State private var tcpPortText = ""
    @State private var udpPortText = ""
    @FocusState private var frequencyFieldFocused: Bool

    var body: some View {
        NavigationSplitView {
            List {
                Section("Connection") {
                    Text(controller.connectionStatus)
                    Text("Phase: \(controller.phase.rawValue)")
                        .foregroundStyle(.secondary)
                    TextField("Host", text: $hostText)
                        .onSubmit {
                            controller.setHost(hostText)
                        }
                    Button("Use 192.168.0.199") {
                        hostText = "192.168.0.199"
                        controller.setHost(hostText)
                    }
                    TextField("TCP Port", text: $tcpPortText)
                        .onSubmit {
                            if let port = UInt16(tcpPortText) {
                                controller.setTCPPort(port)
                            }
                        }
                    TextField("UDP Port", text: $udpPortText)
                        .onSubmit {
                            if let port = UInt16(udpPortText) {
                                controller.setUDPPort(port)
                            }
                        }
                    Button("Apply Ports") {
                        if let tcpPort = UInt16(tcpPortText) {
                            controller.setTCPPort(tcpPort)
                        }
                        if let udpPort = UInt16(udpPortText) {
                            controller.setUDPPort(udpPort)
                        }
                    }
                    Button(controller.captureEnabled ? "Disable Capture Mode" : "Enable Capture Mode") {
                        controller.setCaptureEnabled(!controller.captureEnabled)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WAN Profile")
                        HStack {
                            Button("WAN SSB") { controller.wanProfile = .wanSSB }
                            Button("WAN CW Narrow") { controller.wanProfile = .wanCWNarrow }
                            Button("WAN CW Live") { controller.wanProfile = .wanCWLive }
                        }
                    }
                    HStack {
                        Button("Connect") { controller.connect() }
                        Button("Disconnect") { controller.disconnect() }
                        Button("Reconnect") { controller.reconnectNow() }
                    }
                    if let error = controller.lastErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let capturePath = controller.activeCapturePath {
                        Text("Capture: \(capturePath)")
                            .font(.caption2)
                            .textSelection(.enabled)
                    }
                }

                Section("Diagnostics") {
                    LabeledContent("RTT", value: String(format: "%.0f ms", controller.networkMetrics.commandRTTMilliseconds))
                    LabeledContent("Buffer", value: "\(controller.networkMetrics.audioBufferDepthFrames)")
                    LabeledContent("Loss", value: String(format: "%.2f", controller.networkMetrics.packetLossEstimate))
                    LabeledContent("Underruns", value: "\(controller.networkMetrics.underrunCount)")
                    LabeledContent("Client ID", value: controller.clientID ?? "Not assigned")
                    LabeledContent("Audio Stream", value: controller.audioState.streamID ?? "Unknown")
                    LabeledContent("UDP Packets", value: "\(controller.udpPacketCount)")
                    LabeledContent("Seq Gaps", value: "\(controller.sequenceGapCount)")
                    LabeledContent("Last Decode Error", value: controller.lastDecodeError ?? "None")
                }

                Section("Devices") {
                    Picker("Input", selection: Binding(
                        get: { controller.selectedInputDeviceID ?? "" },
                        set: { controller.selectInputDevice($0.isEmpty ? nil : $0) }
                    )) {
                        Text("System Default").tag("")
                        ForEach(controller.inputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }

                    Picker("Output", selection: Binding(
                        get: { controller.selectedOutputDeviceID ?? "" },
                        set: { controller.selectOutputDevice($0.isEmpty ? nil : $0) }
                    )) {
                        Text("System Default").tag("")
                        ForEach(controller.outputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }

                    Picker("MIDI", selection: Binding(
                        get: { controller.selectedMidiSourceID ?? 0 },
                        set: { controller.selectMidiSource($0 == 0 ? nil : $0) }
                    )) {
                        Text("No Device").tag(Int32(0))
                        ForEach(controller.midiSources) { source in
                            Text(source.name).tag(source.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    operatorPanel
                    cwPanel
                    diagnosticsPanel
                }
                .padding(24)
            }
            .background(
                LinearGradient(colors: [.orange.opacity(0.16), .blue.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
    }

    private var operatorPanel: some View {
        GroupBox("Operator") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(controller.activeSlice.frequencyMHz, specifier: "%.6f") MHz")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Spacer()
                    HStack {
                        Button("USB") { controller.setMode(.usb) }
                        Button("LSB") { controller.setMode(.lsb) }
                        Button("CW") { controller.setMode(.cw) }
                    }
                }

                HStack {
                    TextField("14.074000", text: $frequencyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .focused($frequencyFieldFocused)
                        .onSubmit {
                            if let value = Double(frequencyText) {
                                controller.setFrequencyMHz(value)
                            }
                            frequencyFieldFocused = false
                        }
                    Button("Tune") {
                        if let value = Double(frequencyText) {
                            controller.setFrequencyMHz(value)
                        }
                        frequencyFieldFocused = false
                    }
                    Button("-100 Hz") { controller.stepFrequency(by: -0.0001) }
                    Button("+100 Hz") { controller.stepFrequency(by: 0.0001) }
                    Button("-1 kHz") { controller.stepFrequency(by: -0.001) }
                    Button("+1 kHz") { controller.stepFrequency(by: 0.001) }
                }

                HStack {
                    Stepper("Filter Low: \(controller.activeSlice.filterLowHz) Hz", value: Binding(
                        get: { controller.activeSlice.filterLowHz },
                        set: { controller.setFilter(low: $0, high: controller.activeSlice.filterHighHz) }
                    ), in: -6_000...0, step: 50)
                    Stepper("Filter High: \(controller.activeSlice.filterHighHz) Hz", value: Binding(
                        get: { controller.activeSlice.filterHighHz },
                        set: { controller.setFilter(low: controller.activeSlice.filterLowHz, high: $0) }
                    ), in: 0...6_000, step: 50)
                }

                HStack {
                    Button(controller.activeSlice.isMuted ? "Unmute" : "Mute") {
                        controller.toggleMute()
                    }
                    Slider(value: Binding(
                        get: { Double(controller.activeSlice.afGain) },
                        set: { controller.setAFGain(Int($0)) }
                    ), in: 0...100)
                    Text("AF \(controller.activeSlice.afGain)")
                        .monospacedDigit()
                }

                HStack {
                    Button(controller.txState.isTransmitting ? "Stop TX" : "Start TX") {
                        controller.setTransmitEnabled(!controller.txState.isTransmitting)
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    Text("Interlock: \(controller.txState.interlock)")
                    Text(controller.txState.txAllowed ? "TX OK" : "TX Inhibited")
                }

                HStack {
                    Text("Audio RX: \(controller.audioState.rxEnabled ? "On" : "Off")")
                    Text("TX Audio: \(controller.audioState.txAudioEnabled ? "On" : "Off")")
                    Text("CW Queue: \(controller.cwxQueueState.pendingCount)")
                }
            }
        }
        .onAppear {
            frequencyText = String(format: "%.6f", controller.activeSlice.frequencyMHz)
            hostText = controller.connectionProfile.host
            tcpPortText = String(controller.connectionProfile.tcpPort)
            udpPortText = String(controller.connectionProfile.udpPort)
        }
        .onChange(of: controller.activeSlice.frequencyMHz) { _, newValue in
            guard !frequencyFieldFocused else { return }
            frequencyText = String(format: "%.6f", newValue)
        }
        .onChange(of: controller.connectionProfile.host) { _, newValue in
            hostText = newValue
        }
        .onChange(of: controller.connectionProfile.tcpPort) { _, newValue in
            tcpPortText = String(newValue)
        }
        .onChange(of: controller.connectionProfile.udpPort) { _, newValue in
            udpPortText = String(newValue)
        }
    }

    private var cwPanel: some View {
        GroupBox("CW") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("CW text", text: $cwText)
                HStack {
                    Button("Send") {
                        controller.queueCWText(cwText)
                        cwText = ""
                    }
                    .disabled(cwText.isEmpty)
                    Button("Clear") { controller.clearCWQueue() }
                    ForEach(controller.availableMacros) { macro in
                        Button(macro.title) {
                            controller.triggerMacro(macro)
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsPanel: some View {
        GroupBox("Session Log") {
            TextEditor(text: .constant(controller.diagnosticsText))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
        }
    }
}
