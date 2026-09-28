import SwiftUI
import AppKit

@main
struct AudioFormatGuardApp: App {
    @StateObject private var manager = AudioDeviceManager()

    var body: some Scene {
        WindowGroup("Audio Format Guard", id: "main") {
            MainWindow()
                .environmentObject(manager)
                .frame(minWidth: 720, minHeight: 760)
        }
        .defaultSize(width: 840, height: 840)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(manager)
        } label: {
            Label("Audio Format Guard", systemImage: manager.selectedDevice?.isAlive == true
                  ? "waveform" : "waveform.slash")
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
