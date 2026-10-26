import AppKit
import OSLog
import SwiftUI

/// Winamp mode, a hidden classic-player face for the Mac app. It opens alongside the main
/// window and drives the same PlayerService, so the queue, gapless playback and crossfade are
/// shared. View > Winamp Mode (⌘⇧W) turns it on, and it stays on across launches.
final class WinampMode {
    static let shared = WinampMode()

    let preferences = WinampPreferences()
    private lazy var skins = WinampSkinStore(preferences: preferences)
    private var skin: WinampSkin?
    private var container: AppContainer?
    private var mainWindow: WinampMainWindowController?
    private var folderBrowser: WinampFolderBrowserWindow?

    private init() {}

    /// Called once the app's services are ready; reopens the window if it was open at quit.
    func attach(_ container: AppContainer) {
        guard self.container !== container else { return }
        mainWindow?.tearDown()
        mainWindow = nil
        folderBrowser = nil
        self.container = container
        if preferences.isOpen { show() }
    }

    func setOpen(_ open: Bool) {
        preferences.isOpen = open
        if open { show() } else { hide() }
    }

    func chooseSkin() {
        Task {
            guard let url = await skins.chooseSkinFile() else { return }
            do {
                apply(try skins.adopt(url))
            } catch {
                Logger.ui.error("Winamp: couldn't load skin: \(String(describing: error), privacy: .public)")
                let alert = NSAlert()
                alert.messageText = String(localized: "Couldn't Load Skin")
                alert.informativeText = String(localized: "This file isn't a Winamp skin, or it's damaged.")
                alert.runModal()
            }
        }
    }

    func useDefaultSkin() {
        if let bundled = skins.useBundled() { apply(bundled) }
    }

    var isUsingDefaultSkin: Bool { preferences.skin == .bundled }

    func showFolderBrowser() {
        guard let container else { return }
        let browser = folderBrowser ?? WinampFolderBrowserWindow(container: container)
        folderBrowser = browser
        browser.show()
    }

    // MARK: Windows

    private func show() {
        guard let container else { return }
        if mainWindow == nil {
            guard let skin = skin ?? skins.activeSkin() else { return }
            self.skin = skin
            mainWindow = WinampMainWindowController(
                container: container,
                skin: skin,
                preferences: preferences,
                actions: .init(
                    close: { [weak self] in self?.setOpen(false) },
                    chooseSkin: { [weak self] in self?.chooseSkin() },
                    useDefaultSkin: { [weak self] in self?.useDefaultSkin() },
                    isUsingDefaultSkin: { [weak self] in self?.isUsingDefaultSkin ?? true },
                    showFolderBrowser: { [weak self] in self?.showFolderBrowser() }
                )
            )
        }
        mainWindow?.show()
    }

    private func hide() {
        mainWindow?.tearDown()
        mainWindow = nil
        folderBrowser?.close()
    }

    private func apply(_ skin: WinampSkin) {
        self.skin = skin
        mainWindow?.setSkin(skin)
    }
}

/// View > Winamp Mode, plus the skin items while it's on.
struct WinampCommands: Commands {
    @AppStorage(WinampPreferences.Key.isOpen) private var isOpen = false

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Toggle("Winamp Mode", isOn: Binding(get: { isOpen }, set: { WinampMode.shared.setOpen($0) }))
                .keyboardShortcut("w", modifiers: [.command, .shift])
            if isOpen {
                Button("Load Skin…") { WinampMode.shared.chooseSkin() }
                Button("Default Skin") { WinampMode.shared.useDefaultSkin() }
            }
        }
    }
}

extension View {
    /// Hands the app's services to Winamp mode once they're ready.
    func winampMode(_ container: AppContainer?) -> some View {
        task(id: container.map(ObjectIdentifier.init)) {
            if let container { WinampMode.shared.attach(container) }
        }
    }
}
