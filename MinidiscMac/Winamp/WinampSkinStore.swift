import AppKit
import OSLog
import UniformTypeIdentifiers

/// Loads the active Winamp skin and remembers a skin the listener opened. A custom skin is kept
/// as a security-scoped bookmark to the file they chose; if the sandbox won't make one, the file
/// is copied into the app's container and bookmarked there instead.
final class WinampSkinStore {
    private let preferences: WinampPreferences
    private var bundledSkin: WinampSkin?

    init(preferences: WinampPreferences) {
        self.preferences = preferences
    }

    /// Hi-MD Gold. Loaded once; every other skin falls back to it for missing sheets.
    func bundled() -> WinampSkin? {
        if let bundledSkin { return bundledSkin }
        do {
            let skin = try WinampSkin.bundled()
            bundledSkin = skin
            return skin
        } catch {
            Logger.ui.error("Winamp: bundled skin failed to load: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The skin in the preferences, or Hi-MD Gold if it can't be found or read.
    func activeSkin() -> WinampSkin? {
        guard case .custom(let name, let bookmark, let isSecurityScoped) = preferences.skin else { return bundled() }
        do {
            return try loadCustom(name: name, bookmark: bookmark, isSecurityScoped: isSecurityScoped)
        } catch {
            Logger.ui.error("Winamp: saved skin unavailable, using the default: \(String(describing: error), privacy: .public)")
            return bundled()
        }
    }

    /// Loads the `.wsz` at `url`, then saves it as the active skin. Throws without saving if the
    /// file isn't a usable skin.
    func adopt(_ url: URL) throws -> WinampSkin {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let skin = try WinampSkin.load(contentsOf: url, fallback: bundled())
        let name = url.deletingPathExtension().lastPathComponent
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            preferences.skin = .custom(name: name, bookmark: bookmark, isSecurityScoped: true)
        } catch {
            Logger.ui.info("Winamp: no security-scoped bookmark, keeping a copy of the skin: \(String(describing: error), privacy: .public)")
            let copy = try copyIntoContainer(url)
            let bookmark = try copy.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            preferences.skin = .custom(name: name, bookmark: bookmark, isSecurityScoped: false)
        }
        return skin
    }

    func useBundled() -> WinampSkin? {
        preferences.skin = .bundled
        return bundled()
    }

    /// Asks for a `.wsz` with the open panel. Returns nil if the listener cancels.
    func chooseSkinFile() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "wsz"), .zip].compactMap(\.self)
        let response = await panel.begin()
        return response == .OK ? panel.url : nil
    }

    private func loadCustom(name: String, bookmark: Data, isSecurityScoped: Bool) throws -> WinampSkin {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: isSecurityScoped ? [.withSecurityScope] : [],
                          relativeTo: nil, bookmarkDataIsStale: &isStale)
        let accessing = isSecurityScoped && url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let skin = try WinampSkin.load(contentsOf: url, fallback: bundled())
        if isStale, let fresh = try? url.bookmarkData(
            options: isSecurityScoped ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess] : [],
            includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            preferences.skin = .custom(name: name, bookmark: fresh, isSecurityScoped: isSecurityScoped)
        }
        return skin
    }

    private func copyIntoContainer(_ url: URL) throws -> URL {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Winamp Skins", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
