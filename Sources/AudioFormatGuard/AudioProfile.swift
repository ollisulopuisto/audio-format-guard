import Foundation

/// A device-reported signed integer PCM mode used by the editor and CoreAudio setter.
struct AudioFormatChoice: Hashable, Identifiable, Codable {
    let sampleRate: Int
    let bitDepth: Int
    let channels: Int
    /// Optimization: Precomputed and stored summary string avoids repetitive string interpolations
    /// and heap allocations during SwiftUI view re-evaluations and menu bar status updates.
    let summary: String

    var id: String { "\(sampleRate)-\(bitDepth)-\(channels)" }
    /// Optimization: Formats sample rate label directly without constructing dummy AudioFormatChoice instances.
    static func rateLabel(for sampleRate: Int) -> String {
        guard sampleRate >= 1_000 else { return "\(sampleRate) Hz" }
        return sampleRate.isMultiple(of: 1_000)
            ? "\(sampleRate / 1_000) kHz"
            : String(format: "%.1f kHz", Double(sampleRate) / 1_000)
    }

    var rateLabel: String { Self.rateLabel(for: sampleRate) }

    init(sampleRate: Int, bitDepth: Int, channels: Int) {
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.summary = "\(Self.rateLabel(for: sampleRate)) · \(bitDepth)-bit · \(channels) ch"
    }

    private enum CodingKeys: String, CodingKey {
        case sampleRate, bitDepth, channels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        let bitDepth = try container.decode(Int.self, forKey: .bitDepth)
        let channels = try container.decode(Int.self, forKey: .channels)
        self.init(sampleRate: sampleRate, bitDepth: bitDepth, channels: channels)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(bitDepth, forKey: .bitDepth)
        try container.encode(channels, forKey: .channels)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sampleRate)
        hasher.combine(bitDepth)
        hasher.combine(channels)
    }

    static func == (lhs: AudioFormatChoice, rhs: AudioFormatChoice) -> Bool {
        lhs.sampleRate == rhs.sampleRate && lhs.bitDepth == rhs.bitDepth && lhs.channels == rhs.channels
    }
}

/// The user's restore target for one CoreAudio device UID.
struct AudioProfile: Codable {
    var deviceUID: String
    var format: AudioFormatChoice
    var automaticallyRestore: Bool
}
