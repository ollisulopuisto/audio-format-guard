# Bolt's Journal - Critical Learnings Only

## 2026-11-05 - Avoid Intermediate Array Allocations in CoreAudio Format Enumeration
**Learning:** In CoreAudio stream inspection, chained `flatMap`, `filter`, and `map` operations allocate multiple intermediate heap arrays for standard sample rates and format choices for every advertised format range on every stream. Accumulating directly into an `inout Set` with a statically allocated standard rates list eliminates per-range allocations and deduplicates in a single pass.
**Action:** When extracting capabilities across CoreAudio stream format ranges, pass an `inout Set` to collect matching domain structs directly rather than transforming intermediate arrays through `flatMap`/`filter`.

## 2026-11-03 - Retain CoreAudio AudioDeviceID to Avoid Redundant HAL Property Queries
**Learning:** Re-querying system devices and fetching UIDs via `AudioObjectGetPropertyData` on each refresh or format apply creates $O(N^2)$ CoreAudio HAL IPC roundtrips across devices. Storing the native `AudioDeviceID` on `AudioOutputDevice` during initial enumeration allows direct $O(1)$ property access and listener registration.
**Action:** Always cache native CoreAudio `AudioObjectID`/`AudioDeviceID` identifiers directly alongside domain models instead of repeatedly mapping UIDs to IDs via global HAL enumeration.

## 2026-11-01 - Changelog Streaming Line Enumeration
**Learning:** `components(separatedBy: .newlines)` buffers and allocates an entire array of intermediate `String` objects when parsing markdown changelogs. Using `enumerateLines` streams line-by-line without pre-allocating an array for all lines.
**Action:** Prefer `enumerateLines` over `components(separatedBy: .newlines)` when parsing multi-line text files or bundles.
