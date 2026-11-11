import XCTest
@testable import AudioFormatGuard

final class AudioFormatGuardTests: XCTestCase {
    func testAudioFormatChoiceFormatting() {
        let choice = AudioFormatChoice(sampleRate: 192_000, bitDepth: 24, channels: 6)
        XCTAssertEqual(choice.rateLabel, "192 kHz")
        XCTAssertEqual(choice.summary, "192 kHz · 24-bit · 6 ch")
        XCTAssertEqual(choice.id, "192000-24-6")

        let fractional = AudioFormatChoice(sampleRate: 44_100, bitDepth: 16, channels: 2)
        XCTAssertEqual(fractional.rateLabel, "44.1 kHz")
        XCTAssertEqual(fractional.summary, "44.1 kHz · 16-bit · 2 ch")

        let subKilo = AudioFormatChoice(sampleRate: 800, bitDepth: 16, channels: 1)
        XCTAssertEqual(subKilo.rateLabel, "800 Hz")

        // Test static rateLabel(for:) directly
        XCTAssertEqual(AudioFormatChoice.rateLabel(for: 192_000), "192 kHz")
        XCTAssertEqual(AudioFormatChoice.rateLabel(for: 44_100), "44.1 kHz")
        XCTAssertEqual(AudioFormatChoice.rateLabel(for: 48_000), "48 kHz")
        XCTAssertEqual(AudioFormatChoice.rateLabel(for: 88_200), "88.2 kHz")
        XCTAssertEqual(AudioFormatChoice.rateLabel(for: 800), "800 Hz")
    }

    func testAudioProfileCodable() throws {
        let choice = AudioFormatChoice(sampleRate: 96_000, bitDepth: 24, channels: 2)
        let profile = AudioProfile(deviceUID: "test-device-uid", format: choice, automaticallyRestore: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AudioProfile.self, from: data)

        XCTAssertEqual(decoded.deviceUID, "test-device-uid")
        XCTAssertEqual(decoded.format.sampleRate, 96_000)
        XCTAssertEqual(decoded.format.bitDepth, 24)
        XCTAssertEqual(decoded.format.channels, 2)
        XCTAssertEqual(decoded.format.summary, "96 kHz · 24-bit · 2 ch")
        XCTAssertTrue(decoded.automaticallyRestore)
    }

    func testAudioOutputDeviceProperties() {
        let choice = AudioFormatChoice(sampleRate: 48_000, bitDepth: 24, channels: 2)
        let device = AudioOutputDevice(
            id: "uid-123",
            deviceID: 42,
            name: "Test Output",
            isAlive: true,
            currentFormat: choice,
            choices: [choice]
        )

        XCTAssertEqual(device.id, "uid-123")
        XCTAssertEqual(device.deviceID, 42)
        XCTAssertEqual(device.name, "Test Output")
        XCTAssertTrue(device.isAlive)
        XCTAssertEqual(device.currentFormat, choice)
        XCTAssertEqual(device.choices, [choice])
        XCTAssertEqual(device.streamIDs, [])
    }

    func testAudioOutputDeviceWithStreamIDs() {
        let choice = AudioFormatChoice(sampleRate: 48_000, bitDepth: 24, channels: 2)
        let device = AudioOutputDevice(
            id: "uid-456",
            deviceID: 101,
            name: "Test Stream Output",
            isAlive: true,
            currentFormat: choice,
            choices: [choice],
            streamIDs: [1, 2]
        )

        XCTAssertEqual(device.id, "uid-456")
        XCTAssertEqual(device.deviceID, 101)
        XCTAssertEqual(device.streamIDs, [1, 2])
    }
}
