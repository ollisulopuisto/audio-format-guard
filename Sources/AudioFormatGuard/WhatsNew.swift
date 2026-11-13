import SwiftUI

// MARK: - Changelog parsing

struct ChangelogSection: Equatable {
    let version: String
    let items: [String]
}

enum ChangelogNotes {
    // Optimization: Cache loaded changelog sections for the main bundle so repetitive
    // calls (e.g. checkForUpgrade, version fallback, showHistory) avoid redundant file I/O and parsing.
    private static var cachedMainSections: [ChangelogSection]?

    /// Released sections from the bundled CHANGELOG.md, newest first.
    /// Headings are Keep a Changelog calver: `## [v26.09.28.6] - 2026-09-28`.
    /// `[Unreleased]` never ships in the dialog. A missing bundle resource is
    /// silence, not a crash.
    static func load(bundle: Bundle = .main) -> [ChangelogSection] {
        if bundle == .main, let cached = cachedMainSections {
            return cached
        }
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let sections = parse(text)
        if bundle == .main {
            cachedMainSections = sections
        }
        return sections
    }

    static func parse(_ markdown: String) -> [ChangelogSection] {
        var sections: [ChangelogSection] = []
        var currentVersion: String?
        var items: [String] = []

        func flush() {
            if let version = currentVersion, !items.isEmpty {
                sections.append(ChangelogSection(version: version, items: items))
            }
        }

        // Optimization: Use enumerateLines to stream lines lazily without allocating
        // an intermediate array of String instances for every line in the markdown.
        markdown.enumerateLines { line, _ in
            if line.hasPrefix("## ") {
                flush()
                currentVersion = nil
                items = []
                guard let open = line.firstIndex(of: "["),
                      let close = line.firstIndex(of: "]"), open < close else { return }
                let name = String(line[line.index(after: open)..<close])
                if name != "Unreleased", !name.isEmpty {
                    currentVersion = name
                }
            } else if line.hasPrefix("### ") {
                return
            } else if currentVersion != nil, line.hasPrefix("- ") {
                let item = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty { items.append(item) }
            }
        }
        flush()
        return sections
    }

    /// Numeric per-segment compare, ignoring a leading "v" or "V". A missing trailing
    /// segment counts as zero, so 26.09.28 < 26.09.28.1.
    ///
    /// Optimization: Walks both version strings in a single pass with index arithmetic
    /// instead of `split(separator:)`, which allocated a `[Substring]` array (plus per-segment
    /// Substrings and iterators) on every call. Segments are still parsed with `Int`, so
    /// non-numeric or overflowing segments coerce to zero and the "missing trailing segment
    /// counts as zero" rule is preserved exactly as before.
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let aStart: String.Index = (a.hasPrefix("v") || a.hasPrefix("V")) ? a.index(after: a.startIndex) : a.startIndex
        let bStart: String.Index = (b.hasPrefix("v") || b.hasPrefix("V")) ? b.index(after: b.startIndex) : b.startIndex
        var ia = aStart, ib = bStart
        let ea = a.endIndex, eb = b.endIndex

        /// Extracts the next segment. Empty runs of "." are skipped, mirroring
        /// `split(separator:)` which omits empty subsequences. Returns `present: false`
        /// when the string is exhausted, i.e. a missing trailing segment (counts as zero).
        func nextSegment(_ s: String, _ i: inout String.Index, _ end: String.Index) -> (value: Int, present: Bool) {
            while i < end, s[i] == "." { i = s.index(after: i) }
            guard i < end else { return (0, false) }
            var j = i
            while j < end, s[j] != "." { j = s.index(after: j) }
            let seg = s[i..<j]
            i = (j < end) ? s.index(after: j) : j
            return (Int(seg) ?? 0, true)
        }

        while true {
            let (va, ha) = nextSegment(a, &ia, ea)
            let (vb, hb) = nextSegment(b, &ib, eb)
            if !ha && !hb { return 0 }
            if va != vb { return va < vb ? -1 : 1 }
        }
    }

    /// Sections newer than `lastSeen`, up to and including `current`.
    /// `lastSeen` of "" means full history.
    static func sectionsSince(_ sections: [ChangelogSection], current: String, lastSeen: String)
        -> [ChangelogSection]
    {
        sections.filter {
            compareVersions($0.version, lastSeen) > 0 && compareVersions($0.version, current) <= 0
        }
    }
}

// MARK: - Seen-marker state

@MainActor
final class WhatsNewState: ObservableObject {
    @Published var pendingSections: [ChangelogSection] = []
    @Published var showingHistory = false
    @Published var historySections: [ChangelogSection] = []

    private static let seenKey = "whatsNewSeenVersion"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var currentVersion: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !v.isEmpty { return v }
        // `swift run` has no Info.plist; fall back to the newest shipped entry.
        return ChangelogNotes.load().first?.version ?? ""
    }

    /// Called once the UI is up. Shows the after-upgrade sheet when the
    /// running build is newer than the acknowledged version. A downgrade or
    /// reinstall of an older build shows nothing and keeps the marker; the
    /// first run of this feature shows the current version only.
    func checkForUpgrade() {
        let current = currentVersion
        guard !current.isEmpty else { return }
        let sections = ChangelogNotes.load()
        guard !sections.isEmpty else { return }
        let lastSeen = defaults.string(forKey: Self.seenKey) ?? ""
        if lastSeen.isEmpty {
            // First run of the feature: the current version's notes only.
            pendingSections = sections.filter {
                ChangelogNotes.compareVersions($0.version, current) == 0
            }
            return
        }
        guard ChangelogNotes.compareVersions(current, lastSeen) > 0 else { return }
        pendingSections = ChangelogNotes.sectionsSince(sections, current: current, lastSeen: lastSeen)
    }

    /// Full released history for the menu item; never touches the marker.
    func showHistory() {
        let sections = ChangelogNotes.load()
        guard !sections.isEmpty else { return }
        historySections = sections
        showingHistory = true
    }

    /// The marker is recorded only on the sheet's explicit Close, and only
    /// ever moves forward.
    func acknowledge() {
        Self.recordSeen(currentVersion, defaults: defaults)
        pendingSections = []
    }

    /// Forward-only write of the acknowledged version. Empty versions are
    /// never recorded (an unpackaged dev run has no bundle version).
    static func recordSeen(_ version: String, defaults: UserDefaults) {
        guard !version.isEmpty else { return }
        let existing = defaults.string(forKey: seenKey) ?? ""
        if existing.isEmpty || ChangelogNotes.compareVersions(version, existing) > 0 {
            defaults.set(version, forKey: seenKey)
        }
    }

    /// Non-explicit dismissal (Escape): hide the sheet without recording the
    /// marker, so the notes reappear on the next launch.
    func dismissWithoutRecording() {
        pendingSections = []
    }
}

// MARK: - View

struct WhatsNewSheet: View {
    let title: String
    let sections: [ChangelogSection]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).fontWeight(.semibold)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections, id: \.version) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            if sections.count > 1 {
                                Text(section.version).font(.headline)
                            }
                            ForEach(section.items, id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                    Text(item).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Close", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
    }
}
