import SwiftUI

/// Shows a spinner while the first load runs, the error when it failed with nothing to show, an
/// empty message when there is nothing, and the content otherwise.
struct MacLoadingState<Content: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    var error: UserFacingError?
    var emptyTitle: LocalizedStringKey = "Nothing here yet"
    var emptySystemImage = "music.note"
    var retry: (() async -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if !isEmpty {
            content()
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ContentUnavailableView {
                Label("Unable to Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.displayMessage)
            } actions: {
                if let retry {
                    Button("Try Again") { Task { await retry() } }
                }
            }
        } else {
            ContentUnavailableView(emptyTitle, systemImage: emptySystemImage)
        }
    }
}
