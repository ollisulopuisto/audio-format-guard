import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var manager: AudioDeviceManager

    private var formatChoices: [AudioFormatChoice] { manager.selectedDevice?.choices ?? [] }
    private var selectedSampleRate: Int? { manager.selectedFormat?.sampleRate }
    private var selectedBitDepth: Int? { manager.selectedFormat?.bitDepth }
    private var selectedChannels: Int? { manager.selectedFormat?.channels }

    private var sampleRates: [SelectionOption] {
        Array(Set(formatChoices.map(\.sampleRate))).sorted().map {
            SelectionOption(value: $0, label: AudioFormatChoice(sampleRate: $0, bitDepth: 0, channels: 0).rateLabel)
        }
    }

    private var bitDepths: [SelectionOption] {
        guard let selectedSampleRate else { return [] }
        return Array(Set(formatChoices.filter { $0.sampleRate == selectedSampleRate }.map(\.bitDepth)))
            .sorted().map { SelectionOption(value: $0, label: "\($0)-bit") }
    }

    private var channelCounts: [SelectionOption] {
        guard let selectedSampleRate, let selectedBitDepth else { return [] }
        return Array(Set(formatChoices.filter {
            $0.sampleRate == selectedSampleRate && $0.bitDepth == selectedBitDepth
        }.map(\.channels))).sorted().map { SelectionOption(value: $0, label: channelLabel($0)) }
    }

    private func chooseSampleRate(_ rate: Int) {
        guard let current = manager.selectedFormat else { return }
        manager.selectedFormat = bestChoice(for: rate, bitDepth: current.bitDepth, channels: current.channels)
    }

    private func chooseBitDepth(_ depth: Int) {
        guard let current = manager.selectedFormat else { return }
        manager.selectedFormat = bestChoice(for: current.sampleRate, bitDepth: depth,
                                            channels: current.channels)
    }

    private func chooseChannels(_ channels: Int) {
        guard let current = manager.selectedFormat else { return }
        manager.selectedFormat = formatChoices.first {
            $0.sampleRate == current.sampleRate && $0.bitDepth == current.bitDepth && $0.channels == channels
        }
    }

    private func bestChoice(for rate: Int, bitDepth: Int, channels: Int) -> AudioFormatChoice? {
        let atRate = formatChoices.filter { $0.sampleRate == rate }
        return atRate.first { $0.bitDepth == bitDepth && $0.channels == channels }
            ?? atRate.first { $0.bitDepth == bitDepth }
            ?? atRate.first { $0.channels == channels }
            ?? atRate.first
    }

    private func channelLabel(_ count: Int) -> String {
        switch count {
        case 1: return "1 · Mono"
        case 2: return "2 · Stereo"
        case 6: return "6 · 5.1"
        case 8: return "8 · 7.1"
        default: return "\(count) channels"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    deviceCard
                    formatCard
                    automationCard
                    activityCard
                }
                .padding(24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { manager.refresh() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.66, blue: 0.96),
                                                Color(red: 0.39, green: 0.40, blue: 0.90)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                Image(systemName: "waveform.path")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Format Guard").font(.system(size: 19, weight: .semibold))
                Text("Keep your output device ready for the formats you use")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
        .padding(.horizontal, 24).padding(.vertical, 17)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 1) }
    }

    private var statusPill: some View {
        let connected = manager.selectedDevice?.isAlive == true
        return HStack(spacing: 6) {
            Circle().fill(connected ? Color.green : Color.secondary).frame(width: 7, height: 7)
            Text(connected ? "Connected" : "Waiting for device")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background((connected ? Color.green : Color.secondary).opacity(0.10), in: Capsule())
        .foregroundStyle(connected ? Color.green : Color.secondary)
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("OUTPUT DEVICE", symbol: "hifispeaker")
            HStack(spacing: 14) {
                Image(systemName: "hifispeaker.fill")
                    .font(.system(size: 20)).foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Picker("Device", selection: Binding(get: { manager.selectedUID ?? "" },
                                                          set: { manager.chooseDevice($0.isEmpty ? nil : $0) })) {
                        Text("Choose an output device").tag("")
                        ForEach(manager.devices) { device in
                            Text(device.name + (device.isAlive ? "" : " · Offline")).tag(device.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                    Text(manager.selectedDevice?.isAlive == true
                         ? "Available to macOS" : "Select a connected output to configure it")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { manager.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered).help("Refresh devices")
            }
        }
        .cardStyle()
    }

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("PREFERRED FORMAT", symbol: "slider.horizontal.3")
            HStack(alignment: .center) {
                formatMetric(title: "CURRENT OUTPUT", value: manager.currentFormat?.summary ?? "Unavailable",
                             symbol: "waveform")
                Spacer()
                if let target = manager.selectedFormat {
                    Label("Target · \(target.summary)", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.tint)
                }
            }
            Rectangle().fill(.quaternary).frame(height: 1)
            if !formatChoices.isEmpty {
                // Keep the picker compact without offering unsupported cross-product modes.
                HStack(alignment: .top, spacing: 12) {
                    SelectionColumn(title: "SAMPLE RATE", options: sampleRates,
                                    selection: selectedSampleRate, onSelect: chooseSampleRate)
                    SelectionColumn(title: "BIT DEPTH", options: bitDepths,
                                    selection: selectedBitDepth, onSelect: chooseBitDepth)
                    SelectionColumn(title: "CHANNELS", options: channelCounts,
                                    selection: selectedChannels, onSelect: chooseChannels)
                }
                Text("Each column only offers values compatible with the selections before it.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            } else {
                Text("Choose a connected device to see its supported output formats.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let error = manager.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack {
                Text("This changes the device’s physical output format in CoreAudio.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    manager.applySelectedFormat()
                } label: {
                    Label(manager.applying ? "Applying…" : "Apply format", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.selectedDevice?.isAlive != true || manager.selectedFormat == nil || manager.applying)
            }
        }
        .cardStyle()
    }

    private var automationCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18)).foregroundStyle(.purple)
                .frame(width: 40, height: 40)
                .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text("Restore automatically").font(.system(size: 13, weight: .semibold))
                Text("Reapply this format when the device reconnects or its capabilities change")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Toggle("Automatically restore", isOn: $manager.automaticallyRestore)
                .labelsHidden().toggleStyle(.switch)
                .disabled(manager.selectedUID == nil)
        }
        .cardStyle()
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("RECENT ACTIVITY", symbol: "clock.arrow.circlepath")
            if manager.activity.isEmpty {
                Text("Format changes and device events will show here.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                ForEach(manager.activity.prefix(4), id: \.self) { line in
                    Text(line).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .cardStyle()
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10, weight: .bold)).tracking(0.85)
            .foregroundStyle(.secondary)
    }

    private func formatMetric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.7)
                .foregroundStyle(.secondary)
            Label(value, systemImage: symbol).font(.system(size: 13, weight: .medium))
        }
        .frame(minWidth: 170, alignment: .leading)
    }
}

private struct SelectionOption: Identifiable {
    let value: Int
    let label: String
    var id: Int { value }
}

private struct SelectionColumn: View {
    let title: String
    let options: [SelectionOption]
    let selection: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(0.65)
                .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(options) { option in
                            Button { onSelect(option.value) } label: {
                                HStack(spacing: 6) {
                                    Text(option.label).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if selection == option.value {
                                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                    }
                                }
                                .font(.system(size: 11, weight: selection == option.value ? .semibold : .regular))
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selection == option.value ? Color.accentColor.opacity(0.16) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selection == option.value ? Color.accentColor : Color.primary)
                            .id(option.value)
                        }
                    }
                    .padding(.horizontal, 5).padding(.bottom, 5)
                }
                .frame(maxHeight: 155)
                .onAppear {
                    scrollToSelection(proxy: proxy, animated: false)
                }
                .onSelectionChange(of: selection) {
                    scrollToSelection(proxy: proxy, animated: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .underPageBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func scrollToSelection(proxy: ScrollViewProxy, animated: Bool) {
        guard let selection else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(selection, anchor: .center)
                }
            } else {
                proxy.scrollTo(selection, anchor: .center)
            }
        }
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(17)
            .background(Color(nsColor: .controlBackgroundColor),
                         in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.65), lineWidth: 1))
    }
}

private extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }

    @ViewBuilder
    func onSelectionChange<V: Equatable>(of value: V, action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, _ in action() }
        } else {
            self.onChange(of: value) { _ in action() }
        }
    }
}
