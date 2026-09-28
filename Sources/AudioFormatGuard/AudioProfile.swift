import Foundation

/// A device-reported signed integer PCM mode used by the editor and CoreAudio setter.
struct AudioFormatChoice: Hashable, Identifiable, Codable {
    var sampleRate: Int
    var bitDepth: Int
    var channels: Int

    var id: String { "\(sampleRate)-\(bitDepth)-\(channels)" }
    var rateLabel: String {
        guard sampleRate >= 1_000 else { return "\(sampleRate) Hz" }
        return sampleRate.isMultiple(of: 1_000)
            ? "\(sampleRate / 1_000) kHz"
            : String(format: "%.1f kHz", Double(sampleRate) / 1_000)
    }
    var summary: String { "\(rateLabel) · \(bitDepth)-bit · \(channels) ch" }
}

/// The user's restore target for one CoreAudio device UID.
struct AudioProfile: Codable {
    var deviceUID: String
    var format: AudioFormatChoice
    var automaticallyRestore: Bool
}
