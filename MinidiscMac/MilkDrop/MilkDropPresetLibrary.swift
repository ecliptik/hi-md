import AppKit
import OSLog

/// The presets MilkDrop plays: the few written for Hi-MD, which ship in the app, and any in the
/// folder the listener chose, kept as a security-scoped bookmark as a Miniamp skin is. Presets
/// from elsewhere are never bundled.
@MainActor
final class MilkDropPresetLibrary {
    private enum Key {
        static let folderBookmark = "milkdrop.presetFolderBookmark"
    }

    /// Folder presets first, then the built-in ones, each sorted by name.
    private(set) var presets: [URL] = []
    private(set) var folderName: String?
    private var order = MilkDropPresetOrder(count: 0)
    private var accessedFolder: URL?
    private let defaults: UserDefaults

    /// More than any pack would hold; a folder of millions shouldn't stall the window.
    private static let maximumPresets = 20_000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    var current: URL? { order.current.flatMap { presets.indices.contains($0) ? presets[$0] : nil } }
    var hasFolder: Bool { accessedFolder != nil }
    var folderURL: URL? { accessedFolder }

    func next() -> URL? { order.next().map { presets[$0] } }
    func previous() -> URL? { order.previous().map { presets[$0] } }

    // MARK: - Folder

    /// Lets the listener choose a folder of .milk presets, ~/Music/MilkDrop Presets by default.
    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Use Folder")
        panel.message = String(localized: "Choose a folder of MilkDrop presets (.milk files).")
        let suggested = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/MilkDrop Presets")
        panel.directoryURL = FileManager.default.fileExists(atPath: suggested.path) ? suggested : nil
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Key.folderBookmark)
        } catch {
            Logger.ui.error("MilkDrop: couldn't keep access to the preset folder: \(error, privacy: .public)")
            return false
        }
        reload()
        return true
    }

    func forgetFolder() {
        defaults.removeObject(forKey: Key.folderBookmark)
        reload()
    }

    // MARK: - Loading

    func reload() {
        accessedFolder?.stopAccessingSecurityScopedResource()
        accessedFolder = nil
        folderName = nil
        var found: [URL] = []
        if let folder = resolveFolder() {
            accessedFolder = folder
            folderName = folder.lastPathComponent
            found = Self.milkFiles(in: folder)
        }
        let builtIn = (Bundle.main.urls(forResourcesWithExtension: "milk", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        presets = found + builtIn
        order = MilkDropPresetOrder(count: presets.count)
        Logger.ui.info("MilkDrop: \(found.count) presets in the folder, \(builtIn.count) built in")
    }

    private func resolveFolder() -> URL? {
        guard let bookmark = defaults.data(forKey: Key.folderBookmark) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            Logger.ui.info("MilkDrop: the preset folder can't be opened any more")
            return nil
        }
        if isStale, let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                      includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Key.folderBookmark)
        }
        return url
    }

    /// Every .milk file in the folder and its subfolders, as preset packs arrange them.
    private static func milkFiles(in folder: URL) -> [URL] {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var presets: [URL] = []
        for case let url as URL in files where url.pathExtension.caseInsensitiveCompare("milk") == .orderedSame {
            presets.append(url)
            if presets.count == maximumPresets { break }
        }
        return presets.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
