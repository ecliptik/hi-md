import Foundation

extension HomeDestination {
    /// Parses `minidisc://album|playlist|artist/<id>?name=…&cover=…`, the links widgets open.
    init?(url: URL) {
        guard url.scheme == "minidisc",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let id = String(components.path.dropFirst())
        guard !id.isEmpty else { return nil }
        let name = components.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
        let cover = components.queryItems?.first(where: { $0.name == "cover" })?.value
        switch components.host {
        case "album": self = .albumById(id: id, name: name, subtitle: "", coverArtId: cover)
        case "playlist": self = .playlistById(id: id, name: name, coverArtId: cover)
        case "artist": self = .artistById(id: id, name: name, coverArtId: cover)
        default: return nil
        }
    }
}
