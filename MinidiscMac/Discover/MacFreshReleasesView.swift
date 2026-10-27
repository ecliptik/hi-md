import SwiftUI

/// Fresh Releases from the past 90 days by artists the user listens to, grouped by month.
struct MacFreshReleasesView: View {
    let container: AppContainer

    @Environment(MacInterface.self) private var interface

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20, alignment: .top)]

    var body: some View {
        let model = interface.discover(for: container)?.allFreshReleases
        let groups = model?.groupedReleases ?? []
        Group {
            if model?.isLoading != false, groups.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                ContentUnavailableView {
                    Label("No Recent Releases", systemImage: "sparkles")
                } description: {
                    Text("Nothing in the past 3 months from artists you listen to.")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(groups, id: \.month) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.month, format: .dateTime.month(.wide).year())
                                    .font(.title2.bold())
                                    .accessibilityAddTraits(.isHeader)
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                    ForEach(Array(group.items.enumerated()), id: \.offset) { _, release in
                                        MacFreshReleaseCard(release: release)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Fresh Releases")
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model?.loadReleases() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model?.isLoading != false)
            }
        }
        .task { await model?.loadReleases() }
    }
}

/// One fresh release: its cover, artist and date, and links to it on the user's stores.
struct MacFreshReleaseDetailView: View {
    let container: AppContainer
    let release: AlbumRecommendation

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                ExternalCoverView(url: release.coverArtURL, showsDiscWhenMissing: true) {
                    Color.secondary.opacity(0.2)
                }
                .frame(width: 260, height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(release.title)
                        .font(.largeTitle.bold())
                        .textSelection(.enabled)
                    Text(release.artistName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let date = release.releaseDate {
                        Text(date, format: .dateTime.day().month(.wide).year())
                            .foregroundStyle(.secondary)
                    }
                    links
                        .padding(.top, 12)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .navigationTitle(Text(verbatim: release.title))
    }

    @ViewBuilder
    private var links: some View {
        let providers = container.externalProvidersStore.load()
        VStack(alignment: .leading, spacing: 8) {
            if providers.isEmpty {
                if let id = release.id, let url = URL(string: "https://listenbrainz.org/release-group/\(id)") {
                    linkButton(Text("View on ListenBrainz"), url: url)
                }
            } else {
                ForEach(providers) { provider in
                    if let url = provider.buildURL(artistName: release.artistName, albumTitle: release.title) {
                        linkButton(Text("View on \(provider.name)"), url: url)
                    }
                }
            }
        }
    }

    private func linkButton(_ title: Text, url: URL) -> some View {
        Button {
            ExternalLinkOpener.open(url)
        } label: {
            Label { title } icon: { Image(systemName: "arrow.up.right") }
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help(url.absoluteString)
    }
}
