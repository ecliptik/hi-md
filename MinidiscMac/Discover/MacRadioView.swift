import SwiftSonic
import SwiftUI

/// Internet Radio: the server's stations. Double-click or Return plays one.
struct MacRadioView: View {
    let container: AppContainer

    @Environment(MacPlayback.self) private var playback
    @State private var stations: [InternetRadioStation] = []
    @State private var selection: String?
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        Group {
            if !container.serverState.isOnline {
                ContentUnavailableView {
                    Label("You're Offline", systemImage: "wifi.slash")
                } description: {
                    Text(UserFacingError.noNetwork.displayMessage)
                }
            } else if isLoading, stations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, stations.isEmpty {
                ContentUnavailableView {
                    Label("Unable to Load Radios", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Try Again") { Task { await load(forceRefresh: true) } }
                }
            } else if stations.isEmpty {
                ContentUnavailableView {
                    Label("No Radio Stations", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("No internet radio stations are configured on this server.")
                }
            } else {
                List(stations, id: \.id, selection: $selection) { station in
                    MacRadioRow(station: station)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: String.self) { ids in
                    if let station = station(ids) {
                        Button("Play", systemImage: "play") { playback.playRadio(station) }
                        if let url = station.homePageUrl.flatMap(URL.init(string:)) {
                            Button("Open Home Page", systemImage: "safari") { ExternalLinkOpener.open(url) }
                        }
                    }
                } primaryAction: { ids in
                    if let station = station(ids) { playback.playRadio(station) }
                }
            }
        }
        .navigationTitle("Internet Radio")
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await load(forceRefresh: true) } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(isLoading || !container.serverState.isOnline)
            }
        }
        .task(id: container.serverState.isOnline) {
            guard container.serverState.isOnline else { return }
            await load(forceRefresh: false)
        }
    }

    private func station(_ ids: Set<String>) -> InternetRadioStation? {
        stations.first { ids.contains($0.id) }
    }

    private func load(forceRefresh: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            stations = try await container.radioService.listStations(forceRefresh: forceRefresh)
            error = nil
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            self.error = error
        }
    }
}

private struct MacRadioRow: View {
    let station: InternetRadioStation

    @Environment(MacPlayback.self) private var playback

    private var isPlaying: Bool { playback.state.currentRadio?.id == station.id }

    var body: some View {
        HStack(spacing: 10) {
            MacRadioArtwork(station: station, side: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name)
                    .lineLimit(1)
                if let homePage = station.homePageUrl, !homePage.isEmpty {
                    Text(homePage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.minidiscAccent)
                    .accessibilityLabel("Now Playing")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Play")) { playback.playRadio(station) }
    }
}
