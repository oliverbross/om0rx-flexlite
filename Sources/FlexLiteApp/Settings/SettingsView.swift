import Core
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: RadioSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection")
                .font(.headline)

            LabeledContent("Profile", value: controller.connectionProfile.name)
            LabeledContent("Mode", value: controller.connectionProfile.mode.rawValue)
            LabeledContent("Host", value: controller.connectionProfile.host)
            LabeledContent("TCP Port", value: String(controller.connectionProfile.tcpPort))
            LabeledContent("UDP Port", value: String(controller.connectionProfile.udpPort))
            LabeledContent("Station", value: controller.connectionProfile.stationName)

            HStack {
                Button("Use 192.168.0.199") {
                    controller.setHost("192.168.0.199")
                }
                Button("Manual Mode") {
                    controller.setConnectionMode(.manualHost)
                }
            }

            Text("Edit live connection details from the main window sidebar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
    }
}
