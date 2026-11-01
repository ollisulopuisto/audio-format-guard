# Bolt's Journal - Critical Learnings Only

## 2026-11-01 - Changelog Streaming Line Enumeration
**Learning:** `components(separatedBy: .newlines)` buffers and allocates an entire array of intermediate `String` objects when parsing markdown changelogs. Using `enumerateLines` streams line-by-line without pre-allocating an array for all lines.
**Action:** Prefer `enumerateLines` over `components(separatedBy: .newlines)` when parsing multi-line text files or bundles.
