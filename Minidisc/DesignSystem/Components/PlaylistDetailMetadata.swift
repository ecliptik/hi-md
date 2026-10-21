import SwiftUI

struct PlaylistDetailMetadata: View {
    let title: String
    let owner: String?
    let updated: Date?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: MinidiscSpacing.xs) {
            Text(title)
                .font(.minidiscDetailTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("playlist.detail.title")

            if isLoading {
                SkeletonBlock(width: 140, height: 18, cornerRadius: 4)
                SkeletonBlock(width: 100, height: 14, cornerRadius: 4)
            } else {
                if let owner, !owner.isEmpty {
                    Text(owner)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let updated {
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.minidiscCaption)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, MinidiscSpacing.xs)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MinidiscSpacing.xxl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playlist.detail.metadata")
    }
}
