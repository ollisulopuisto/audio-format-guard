import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var manager: AudioDeviceManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: manager.selectedDevice?.isAlive == true ? "waveform" : "waveform.slash")
                    .font(.system(size: 20)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Format Guard").font(.system(size: 13, weight: .semibold))
                    Text(manager.selectedDevice?.name ?? "No device selected")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(manager.selectedDevice?.isAlive == true ? .green : .gray)
                    .frame(width: 8, height: 8)
            }
            Divider()
            HStack {
                Text("Current").foregroundStyle(.secondary)
                Spacer()
                Text(manager.currentFormat?.summary ?? "—").fontWeight(.medium)
            }.font(.system(size: 11))
            HStack {
                Text("Preferred").foregroundStyle(.secondary)
                Spacer()
                Text(manager.selectedFormat?.summary ?? "—").fontWeight(.medium)
            }.font(.system(size: 11))
            if manager.automaticallyRestore {
                Label("Automatic restore is on", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10)).foregroundStyle(.green)
            }
            Divider()
            Button("Open Audio Format Guard…") { openWindow(id: "main") }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(15).frame(width: 290)
        .onAppear { manager.refresh() }
    }
}
