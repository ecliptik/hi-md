import SwiftUI

extension View {
    /// A full-screen cover on iOS; the Mac has none, so it presents a sheet there.
    @ViewBuilder
    func minidiscFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        self.sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        self.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}
