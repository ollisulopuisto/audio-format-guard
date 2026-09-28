# Audio Format Guard

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-555)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-blue)

A native macOS menu bar utility for restoring a preferred physical PCM format
when an audio output reconnects. It is hardware-agnostic: select any CoreAudio
output, then choose from the integer PCM formats that device advertises.

The format editor uses three linked columns: sample rate, bit depth, and channel
count. Each later column narrows to modes compatible with the earlier choices, so
the selected combination is always one the device reports as supported.

## Build and install

Requires macOS 13 or later and the Xcode Command Line Tools.
The build creates an app for the Mac architecture on which it runs.

```sh
./build-app.sh
./install-app.sh
```

The app appears in the menu bar. Open its window to select an output and one
of that output's reported sample-rate, bit-depth, and channel-count combinations.
Use **Apply format** to change it now. Turn on **Restore automatically** to
reapply that selected mode when CoreAudio reports a device or capability change.
Automation is off by default. Each device keeps its own mode and automation setting
in the current macOS user's preferences, keyed by the device's CoreAudio UID.

The utility does not play audio, change the system default output, alter speaker
assignments in Audio MIDI Setup, or resample application audio. CoreAudio may
reject format changes while another client holds the device or when the driver
does not permit writes. The app reports those errors in its window.

The first public version is source-built and ad-hoc signed. It is not notarized;
the build and install scripts are intended for local use by the Mac's owner.

Remove its login service with:

```sh
./uninstall-app.sh
```

## How it works

`AudioDeviceManager` reads output devices and physical stream formats from the
CoreAudio HAL. Device profiles are keyed by the device UID, not its display name,
and remain in the signed-in user's preferences. CoreAudio property listeners
schedule a debounced refresh when devices, streams, or formats change. If automatic
restore is enabled for that device, the manager sets the selected advertised
physical PCM format. It does not poll or play a probe tone.

The window shows the current physical format next to the preferred target. A
manual **Apply format** action works even when automatic restore is off. Recent
activity and CoreAudio errors are shown in the window to make rejected changes
visible.

## Limitations

Current format choices cover advertised signed-integer linear PCM combinations.
Float PCM, compressed passthrough, DSD, and channel-layout remapping are outside
this first version. Devices exposing output as multiple independent streams are
listed, but a requested mode must be supported by one stream.

## License

Audio Format Guard is released under the MIT License. See [LICENSE](LICENSE).

The menu bar app and format editor require a logged-in macOS GUI session. The
LaunchAgent opens the app at login; the audio format itself remains unchanged
unless a user applies it or enables automatic restore. Switching a live device
format may interrupt playback briefly, depending on its driver and clients.

This avoids hard-coding one device name or format into a one-off watcher. Do not
run multiple automatic format controllers against the same output: they can
compete to set CoreAudio's physical mode.
