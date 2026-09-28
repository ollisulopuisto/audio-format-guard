# Architecture

## App structure

- `AudioFormatGuardApp.swift` owns one `AudioDeviceManager`, presents the main
  window, and adds a compact `MenuBarExtra` status panel.
- `AudioDeviceManager.swift` is the CoreAudio boundary. It enumerates output
  devices and PCM format capabilities, listens for HAL property changes, saves
  profiles, and applies a selected physical stream format.
- `AudioProfile.swift` contains the Codable profile and the value type used by
  the format editor.
- `MainWindow.swift` is the device and format editor. Its three columns are
  dependent selectors: sample rate filters bit depths, then the selected rate
  and depth filter channel counts. Selecting an option always resolves to a
  complete format advertised by the device.
- `MenuBarView.swift` gives a quick status summary and opens the main window.
- `build-app.sh` wraps the SwiftPM executable in a signed local `.app` bundle.
  `install-app.sh` copies it to `~/Applications` and starts it at login.

## CoreAudio format selection

For each output device, the manager follows its CoreAudio UID and reads the
device's output streams. It inspects each stream's available physical formats,
retaining signed integer linear PCM modes. Sample rates are intersected with the
advertised rate range; the menu offers common rates in that range and a fixed
rate reported by the driver. Applying a choice re-reads the stream capabilities
before setting `kAudioStreamPropertyPhysicalFormat`, so stale UI state cannot
request a mode that is no longer advertised.

When automatic restore is enabled, the app subscribes to device-list, liveness,
stream-list, available-format, and current-format changes. Events are debounced
onto the main queue. The current mode is compared with the saved target before
applying, and each apply attempt is guarded by a device/target/current signature
to avoid an error-driven tight retry loop.

## Profile storage

Profiles are JSON-encoded in `UserDefaults` under `AudioFormatGuard.profile`,
indexed by CoreAudio device UID. A second preference remembers the selected UID
so the same device is selected when the app starts again. No network service or
analytics is used.

## Extending format support

Keep device discovery independent from UI. To add Float PCM or a new format
family, update capability parsing, the Codable format value, and the apply-time
capability match together. Add explicit format-family UI only when the physical
device advertises that family. Channel-layout mapping should be designed as a
separate feature; channel count alone does not describe where each speaker is
routed.
