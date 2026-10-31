import SwiftUI
import AppKit

@main
struct AudioFormatGuardApp: App {
    @StateObject private var manager = AudioDeviceManager()
    @StateObject private var whatsNew = WhatsNewState()

    var body: some Scene {
        WindowGroup("Audio Format Guard", id: "main") {
            MainWindow()
                .environmentObject(manager)
                .frame(minWidth: 720, minHeight: 760)
                .sheet(isPresented: Binding(
                    get: { !whatsNew.pendingSections.isEmpty },
                    set: { if !$0 { whatsNew.dismissWithoutRecording() } }
                )) {
                    WhatsNewSheet(
                        title: "What's New in \(whatsNew.currentVersion)",
                        sections: whatsNew.pendingSections,
                        onClose: { whatsNew.acknowledge() }
                    )
                }
                .sheet(isPresented: $whatsNew.showingHistory) {
                    WhatsNewSheet(
                        title: "Release Notes",
                        sections: whatsNew.historySections,
                        onClose: { whatsNew.showingHistory = false }
                    )
                }
                .onAppear { whatsNew.checkForUpgrade() }
        }
        .defaultSize(width: 840, height: 840)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(manager)
                .environmentObject(whatsNew)
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
