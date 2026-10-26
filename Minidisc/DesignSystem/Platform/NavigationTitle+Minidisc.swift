import SwiftUI

/// Mac windows have no large or inline navigation bar titles, so these do nothing there.
extension View {
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }

    func navigationBarTitleDisplayModeLarge() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.large)
        #endif
    }
}
