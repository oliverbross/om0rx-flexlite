import Core
import SwiftUI

@main
struct FlexLiteApp: App {
    @StateObject private var controller = RadioSessionController()

    var body: some Scene {
        WindowGroup("FlexLite") {
            MainWindow(controller: controller)
                .frame(minWidth: 1100, minHeight: 760)
        }

        Settings {
            SettingsView(controller: controller)
                .frame(width: 520, height: 360)
        }
    }
}
