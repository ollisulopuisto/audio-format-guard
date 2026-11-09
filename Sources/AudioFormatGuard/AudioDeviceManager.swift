import AudioToolbox
import CoreAudio
import Foundation
import SwiftUI

/// A point-in-time view of one output device and its advertised physical PCM modes.
struct AudioOutputDevice: Identifiable, Hashable {
    let id: String
    let deviceID: AudioDeviceID
    let name: String
    let isAlive: Bool
    let currentFormat: AudioFormatChoice?
    let choices: [AudioFormatChoice]
    let streamIDs: [AudioStreamID]

    init(
        id: String,
        deviceID: AudioDeviceID,
        name: String,
        isAlive: Bool,
        currentFormat: AudioFormatChoice?,
        choices: [AudioFormatChoice],
        streamIDs: [AudioStreamID] = []
    ) {
        self.id = id
        self.deviceID = deviceID
        self.name = name
        self.isAlive = isAlive
        self.currentFormat = currentFormat
        self.choices = choices
        self.streamIDs = streamIDs
    }
}

/// A lightweight, stack-allocated hashable key for tracked CoreAudio HAL property listeners.
/// Optimization: Avoids heap string allocations and string formatting on every listener registration.
private struct PropertyListenerKey: Hashable {
    let object: AudioObjectID
    let selector: AudioObjectPropertySelector
    let scope: AudioObjectPropertyScope
}

@MainActor
/// Owns device discovery, CoreAudio change listeners, per-device preferences, and format changes.
/// All published state stays on the main actor; HAL callbacks are debounced before refreshing it.
final class AudioDeviceManager: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var activity: [String] = []
    @Published private(set) var applying = false
    @Published private(set) var lastError: String?

    @Published private(set) var selectedUID: String?
    @Published var selectedFormat: AudioFormatChoice? {
        didSet { if !changingDevice { saveProfile() } }
    }
    @Published var automaticallyRestore = false {
        didSet {
            if !changingDevice {
                saveProfile()
                if automaticallyRestore { scheduleRefresh() }
            }
        }
    }

    private var watched = Set<PropertyListenerKey>()
    private var lastAppliedSignature = ""
    private var refreshQueued = false
    private var changingDevice = false
    /// Held while any device profile arms automatic restore: App Nap would delay
    /// the HAL-listener -> debounce -> format-restore path when the window is
    /// closed, leaving the amp in stereo for seconds after reconnect. The
    /// background option only disables App Nap; display/system sleep unaffected.
    private var napAssertion: NSObjectProtocol?
    private let profileKey = "AudioFormatGuard.profile"
    private let selectedDeviceKey = "AudioFormatGuard.selectedDevice"
    private var profiles: [String: AudioProfile] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: profileKey) {
            profiles = (try? JSONDecoder().decode([String: AudioProfile].self, from: data)) ?? [:]
            if profiles.isEmpty,
               let legacyProfile = try? JSONDecoder().decode(AudioProfile.self, from: data) {
                profiles[legacyProfile.deviceUID] = legacyProfile
            }
        }
        let preferredUID = UserDefaults.standard.string(forKey: selectedDeviceKey)
        let initialProfile = preferredUID.flatMap { profiles[$0] } ?? profiles.values.first
        selectedUID = initialProfile?.deviceUID
        selectedFormat = initialProfile?.format
        automaticallyRestore = initialProfile?.automaticallyRestore ?? false
        updateAppNapHold()
        listen(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
        refresh()
    }

    /// Hold an App Nap assertion exactly while an automatic-restore profile exists.
    private func updateAppNapHold() {
        let needed = profiles.values.contains { $0.automaticallyRestore }
        if needed, napAssertion == nil {
            napAssertion = ProcessInfo.processInfo.beginActivity(
                options: .background,
                reason: "Restoring audio formats on device reconnect"
            )
        } else if !needed, let assertion = napAssertion {
            ProcessInfo.processInfo.endActivity(assertion)
            napAssertion = nil
        }
    }

    var selectedDevice: AudioOutputDevice? {
        devices.first(where: { $0.id == selectedUID })
    }

    var currentFormat: AudioFormatChoice? { selectedDevice?.currentFormat }

    func chooseDevice(_ uid: String?) {
        let savedProfile = uid.flatMap { profiles[$0] }
        changingDevice = true
        selectedUID = uid
        guard let device = devices.first(where: { $0.id == uid }) else {
            selectedFormat = nil
            automaticallyRestore = false
            changingDevice = false
            UserDefaults.standard.removeObject(forKey: selectedDeviceKey)
            return
        }
        if let saved = savedProfile?.format, device.choices.contains(saved) {
            selectedFormat = saved
        } else if let current = device.currentFormat, device.choices.contains(current) {
            selectedFormat = current
        } else {
            selectedFormat = device.choices.first
        }
        automaticallyRestore = savedProfile?.automaticallyRestore ?? false
        changingDevice = false
        UserDefaults.standard.set(uid, forKey: selectedDeviceKey)
        saveProfile()
        lastAppliedSignature = ""
        if automaticallyRestore { scheduleRefresh() }
    }

    /// Applies the target chosen in the window, regardless of the auto-restore setting.
    func applySelectedFormat() {
        guard let device = selectedDevice, let choice = selectedFormat else { return }
        applying = true
        defer { applying = false }
        do {
            try Self.apply(choice, to: device.deviceID, streams: device.streamIDs)
            lastError = nil
            record("Applied \(choice.summary) to \(device.name)")
            lastAppliedSignature = "\(device.id):\(choice.id)"
            refresh()
        } catch {
            lastError = error.localizedDescription
            record("Could not apply format: \(error.localizedDescription)")
        }
    }

    /// Re-enumerates devices and streams, installs listeners for newly seen objects, and
    /// restores the selected device's target only when that device is alive and opted in.
    func refresh() {
        let currentUID = selectedUID
        let updated = Self.enumerateDevices()
        devices = updated.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // Optimization: Use device.deviceID directly instead of re-querying all system devices
        // and fetching device UIDs over CoreAudio HAL for each device (eliminates redundant O(N^2) IPC queries).
        // Optimization: Re-use cached device.streamIDs instead of repeatedly querying HAL outputStreams.
        for device in devices {
            listen(device.deviceID, selector: kAudioDevicePropertyDeviceIsAlive)
            listen(device.deviceID, selector: kAudioDevicePropertyStreams,
                   scope: kAudioDevicePropertyScopeOutput)
            for streamID in device.streamIDs {
                listen(streamID, selector: kAudioStreamPropertyAvailablePhysicalFormats,
                       scope: kAudioObjectPropertyScopeOutput)
                listen(streamID, selector: kAudioStreamPropertyPhysicalFormat,
                       scope: kAudioObjectPropertyScopeOutput)
            }
        }
        guard let currentUID, let device = devices.first(where: { $0.id == currentUID }) else { return }
        guard device.isAlive, automaticallyRestore, let target = selectedFormat,
              device.choices.contains(target) else { return }
        let signature = "\(device.id):\(target.id):\(device.currentFormat?.id ?? "unknown")"
        guard signature != lastAppliedSignature, device.currentFormat != target else { return }
        lastAppliedSignature = signature
        applySelectedFormat()
    }

    private func saveProfile() {
        guard let selectedUID, let selectedFormat else { return }
        profiles[selectedUID] = AudioProfile(deviceUID: selectedUID, format: selectedFormat,
                                             automaticallyRestore: automaticallyRestore)
        updateAppNapHold()
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }

    private func record(_ message: String) {
        let time = Date.now.formatted(date: .omitted, time: .shortened)
        activity.insert("\(time)  \(message)", at: 0)
        activity = Array(activity.prefix(8))
    }

    /// Delays and coalesces HAL notifications, which can arrive in a burst during HDMI renegotiation.
    private func scheduleRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350)) { [weak self] in
            self?.refreshQueued = false
            self?.refresh()
        }
    }

    /// Watches one HAL property once for the lifetime of this manager.
    /// Optimization: Uses PropertyListenerKey struct to eliminate intermediate string allocations.
    private func listen(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        let key = PropertyListenerKey(object: object, selector: selector, scope: scope)
        guard watched.insert(key).inserted else { return }
        var address = Self.address(selector, scope: scope)
        let status = AudioObjectAddPropertyListenerBlock(object, &address, .main) { [weak self] _, _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        if status != noErr { watched.remove(key) }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func readArray<T>(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress,
                                     as type: T.Type = T.self) -> [T] {
        var property = property
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<T>.size else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        return [T](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            var returnedSize = size
            let status = AudioObjectGetPropertyData(object, &property, 0, nil,
                                                    &returnedSize, buffer.baseAddress!)
            initializedCount = status == noErr ? Int(returnedSize) / MemoryLayout<T>.stride : 0
        }
    }

    private static func readString(_ object: AudioObjectID,
                                   _ property: AudioObjectPropertyAddress) -> String? {
        var property = property
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }

    private static func readUInt32(_ object: AudioObjectID,
                                   _ property: AudioObjectPropertyAddress) -> UInt32? {
        var property = property
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func readUID(_ object: AudioObjectID) -> String? {
        readString(object, address(kAudioDevicePropertyDeviceUID))
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        readArray(AudioObjectID(kAudioObjectSystemObject),
                  address(kAudioHardwarePropertyDevices), as: AudioDeviceID.self)
    }

    fileprivate static func outputStreams(_ device: AudioDeviceID) -> [AudioStreamID] {
        readArray(device, address(kAudioDevicePropertyStreams,
                                  scope: kAudioDevicePropertyScopeOutput), as: AudioStreamID.self)
    }

    // Optimization: Statically allocate standard sample rates once instead of re-allocating
    // an 11-element Int array on every stream format range during device enumeration.
    private static let standardRates = [
        32_000, 44_100, 48_000, 88_200, 96_000, 176_400, 192_000,
        352_800, 384_000, 705_600, 768_000
    ]

    private static func enumerateDevices() -> [AudioOutputDevice] {
        allDeviceIDs().compactMap { device in
            guard let uid = readUID(device),
                  let name = readString(device, address(kAudioObjectPropertyName)) else { return nil }
            let alive = readUInt32(device, address(kAudioDevicePropertyDeviceIsAlive)) == 1
            let streams = outputStreams(device)
            var uniqueChoices = Set<AudioFormatChoice>()
            for stream in streams {
                collectSupportedChoices(from: stream, into: &uniqueChoices)
            }
            let choices = uniqueChoices.sorted {
                if $0.channels != $1.channels { return $0.channels < $1.channels }
                if $0.sampleRate != $1.sampleRate { return $0.sampleRate < $1.sampleRate }
                return $0.bitDepth < $1.bitDepth
            }
            // Optimization: Lazily inspect stream formats to short-circuit upon finding the first valid
            // physical format, avoiding redundant CoreAudio HAL queries across remaining output streams.
            let current = streams.lazy.compactMap(currentChoice).first
            return AudioOutputDevice(id: uid, deviceID: device, name: name, isAlive: alive,
                                     currentFormat: current, choices: choices, streamIDs: streams)
        }
    }

    /// Converts the device's reported physical format ranges to selectable UI choices.
    /// Optimization: Inserts directly into `choices` to avoid intermediate array allocations
    /// from `filter`, `map`, and `flatMap`.
    private static func collectSupportedChoices(from stream: AudioStreamID,
                                                into choices: inout Set<AudioFormatChoice>) {
        let formats = readArray(stream, address(kAudioStreamPropertyAvailablePhysicalFormats,
                                                scope: kAudioObjectPropertyScopeOutput),
                                as: AudioStreamRangedDescription.self)
        for ranged in formats {
            let format = ranged.mFormat
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0,
                  format.mFormatFlags & kAudioFormatFlagIsFloat == 0 else { continue }
            let bitDepth = Int(format.mBitsPerChannel)
            let channels = Int(format.mChannelsPerFrame)
            let fixedRate = Int(format.mSampleRate.rounded())
            let minimumRate = ranged.mSampleRateRange.mMinimum
            let maximumRate = ranged.mSampleRateRange.mMaximum

            if minimumRate == maximumRate, fixedRate > 0 {
                choices.insert(AudioFormatChoice(sampleRate: fixedRate, bitDepth: bitDepth, channels: channels))
            } else {
                var matchedFixedRate = false
                for rate in standardRates {
                    let rateDouble = Double(rate)
                    if rateDouble >= minimumRate && rateDouble <= maximumRate {
                        choices.insert(AudioFormatChoice(sampleRate: rate, bitDepth: bitDepth, channels: channels))
                        if rate == fixedRate { matchedFixedRate = true }
                    }
                }
                if fixedRate > 0, !matchedFixedRate,
                   Double(fixedRate) >= minimumRate, Double(fixedRate) <= maximumRate {
                    choices.insert(AudioFormatChoice(sampleRate: fixedRate, bitDepth: bitDepth, channels: channels))
                }
            }
        }
    }

    private static func currentChoice(_ stream: AudioStreamID) -> AudioFormatChoice? {
        var property = address(kAudioStreamPropertyPhysicalFormat,
                               scope: kAudioObjectPropertyScopeOutput)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(stream, &property, 0, nil, &size, &format) == noErr,
              format.mFormatID == kAudioFormatLinearPCM else { return nil }
        return AudioFormatChoice(sampleRate: Int(format.mSampleRate.rounded()),
                                 bitDepth: Int(format.mBitsPerChannel),
                                 channels: Int(format.mChannelsPerFrame))
    }

    /// Re-reads capabilities before setting the stream, because HDMI capabilities can change
    /// between rendering the UI and applying a choice.
    /// Optimization: Re-uses known streams when provided, avoiding a redundant HAL outputStreams query.
    private static func apply(_ choice: AudioFormatChoice, to device: AudioDeviceID,
                              streams: [AudioStreamID] = []) throws {
        guard readUInt32(device, address(kAudioDevicePropertyDeviceIsAlive)) == 1 else {
            throw AudioFormatError.deviceUnavailable
        }
        let targetStreams = streams.isEmpty ? outputStreams(device) : streams
        for stream in targetStreams {
            let formats = readArray(stream, address(kAudioStreamPropertyAvailablePhysicalFormats,
                                                    scope: kAudioObjectPropertyScopeOutput),
                                    as: AudioStreamRangedDescription.self)
            guard let match = formats.first(where: { ranged in
                let format = ranged.mFormat
                return format.mFormatID == kAudioFormatLinearPCM &&
                    format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 &&
                    format.mFormatFlags & kAudioFormatFlagIsFloat == 0 &&
                    Int(format.mBitsPerChannel) == choice.bitDepth &&
                    Int(format.mChannelsPerFrame) == choice.channels &&
                    (format.mSampleRate == kAudioStreamAnyRate ||
                     (Double(choice.sampleRate) >= ranged.mSampleRateRange.mMinimum &&
                      Double(choice.sampleRate) <= ranged.mSampleRateRange.mMaximum))
            }) else { continue }
            var property = address(kAudioStreamPropertyPhysicalFormat,
                                   scope: kAudioObjectPropertyScopeOutput)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(stream, &property, &settable) == noErr,
                  settable.boolValue else { throw AudioFormatError.formatNotWritable }
            var desired = match.mFormat
            desired.mSampleRate = Double(choice.sampleRate)
            let status = AudioObjectSetPropertyData(stream, &property, 0, nil,
                                                    UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                                                    &desired)
            guard status == noErr else { throw AudioFormatError.coreAudio(status) }
            return
        }
        throw AudioFormatError.formatUnavailable
    }
}

private enum AudioFormatError: LocalizedError {
    case deviceUnavailable
    case formatUnavailable
    case formatNotWritable
    case coreAudio(OSStatus)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return "The output device is not connected or available."
        case .formatUnavailable: return "The selected format is not advertised by this device."
        case .formatNotWritable: return "macOS reports that this stream format cannot be changed."
        case let .coreAudio(status): return "CoreAudio rejected the format change (error \(status))."
        }
    }
}
