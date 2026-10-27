import Foundation
import Testing
@testable import Minidisc

/// The fork is called Hi-MD, and its skinned Mac player Miniamp. These read the string tables
/// the build compiles from the catalogs, in every language, so a string added or translated
/// with the old names fails here.
@Suite("Brand names")
struct BrandNameTests {
    /// Text that still says Minidisc on purpose. None of it is in a catalog today; the list
    /// documents what may appear if it ever is.
    /// - The upstream project's name, in credits: "Minidisc (Loriage)".
    /// - The old names of the playlists the app keeps on the server, which it still recognises
    ///   until `PlaylistNameMigration` renames them.
    /// - The demo clip's spoken words.
    static let allowedMinidiscText = [
        "Minidisc (Loriage)",
        Mood.legacyPlaylistPrefix,
        WrappedPlaylistService.legacyWrappedPlaylistNamePrefix,
        "Minidisc. Minidisc. Minidisc.",
    ]

    /// Strings that name the Winamp skin and preset formats, which Miniamp reads; they keep
    /// the Winamp name.
    static let allowedWinampKeys: Set<String> = [
        "This file isn't a Winamp skin, or it's damaged.",
        "This file isn't a Winamp equalizer preset.",
    ]

    struct Entry: CustomStringConvertible {
        let table: String
        let language: String
        let key: String
        let value: String
        var description: String { "\(table) [\(language)] \(key.debugDescription) = \(value.debugDescription)" }
    }

    /// Every compiled string table of the app and its widget extension, in every language.
    static func entries() throws -> [Entry] {
        var bundles = [Bundle.main]
        if let plugIns = Bundle.main.builtInPlugInsURL,
           let widgets = Bundle(url: plugIns.appending(path: "MinidiscWidgets.appex")) {
            bundles.append(widgets)
        }
        var entries: [Entry] = []
        for bundle in bundles {
            let tables = try FileManager.default.subpathsOfDirectory(atPath: bundle.bundlePath)
                .filter { $0.hasSuffix(".strings") && $0.contains(".lproj/") && !$0.hasPrefix("PlugIns/") && !$0.hasPrefix("Watch/") }
            for path in tables {
                let url = URL(filePath: bundle.bundlePath).appending(path: path)
                guard let table = NSDictionary(contentsOf: url) as? [String: String] else { continue }
                let language = url.deletingLastPathComponent().deletingPathExtension().lastPathComponent
                let name = url.deletingPathExtension().lastPathComponent
                for (key, value) in table {
                    entries.append(Entry(table: name, language: language, key: key, value: value))
                }
            }
        }
        return entries
    }

    static func saysMinidisc(_ text: String) -> Bool {
        var text = text
        for allowed in allowedMinidiscText {
            text = text.replacingOccurrences(of: allowed, with: "")
        }
        // Whole word and case-sensitive: "MiniDisc", Sony's format, is fine.
        return text.range(of: #"(?<![A-Za-z])Minidisc(?![A-Za-z])"#, options: .regularExpression) != nil
    }

    @Test("The string tables are there to check")
    func tablesAreCompiled() throws {
        let entries = try Self.entries()
        let languages = Set(entries.map(\.language))
        #expect(languages.isSuperset(of: ["en", "de", "el", "es", "fr", "it", "ja", "zh-Hans", "zh-Hant"]))
        #expect(Set(entries.map(\.table)).isSuperset(of: ["Localizable", "InfoPlist", "LocalMusic"]))
    }

    @Test("No translation calls the app Minidisc")
    func noUserFacingMinidisc() throws {
        let offenders = try Self.entries().filter { Self.saysMinidisc($0.value) }
        #expect(offenders.isEmpty, "Still says Minidisc:\n\(offenders.map(\.description).joined(separator: "\n"))")
    }

    @Test("The skinned player is Miniamp; only the skin and preset formats say Winamp")
    func noUserFacingWinampMode() throws {
        let offenders = try Self.entries().filter {
            $0.value.contains("Winamp") && !Self.allowedWinampKeys.contains($0.key)
        }
        #expect(offenders.isEmpty, "Still says Winamp:\n\(offenders.map(\.description).joined(separator: "\n"))")
        #expect(String(localized: "Miniamp") == "Miniamp")
    }

    @Test("The app's name is Hi-MD")
    func displayNameIsHiMD() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Hi-MD")
        #expect(String(localized: "Hi-MD") == "Hi-MD")
    }

    @Test("The checks catch the old name and let the documented exceptions through")
    func matcherFindsTheOldName() {
        #expect(Self.saysMinidisc("Open Minidisc to connect"))
        #expect(Self.saysMinidisc("Minidiscを開いて接続してください"))
        #expect(!Self.saysMinidisc("Open Hi-MD to connect"))
        #expect(!Self.saysMinidisc("A spinning MiniDisc in place of the cover"))
        #expect(!Self.saysMinidisc("\(Mood.legacyPlaylistPrefix)Night"))
        #expect(!Self.saysMinidisc("Minidisc (Loriage)"))
    }
}
