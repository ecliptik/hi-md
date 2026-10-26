import Foundation

/// `GET /1/stats/user/{user}/artists`. Only the artists are read.
nonisolated struct LBTopArtistsResponse: Decodable, Sendable {
    nonisolated struct Payload: Decodable, Sendable {
        let artists: [LBTopArtistDTO]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let failable = try container.decodeIfPresent([Failable].self, forKey: .artists) ?? []
            artists = failable.compactMap(\.value)
        }

        private enum CodingKeys: String, CodingKey { case artists }
    }

    /// Skips entries that don't decode instead of failing the whole list.
    private nonisolated struct Failable: Decodable, Sendable {
        let value: LBTopArtistDTO?
        init(from decoder: any Decoder) throws { value = try? LBTopArtistDTO(from: decoder) }
    }

    let payload: Payload
}

nonisolated struct LBTopArtistDTO: Decodable, Sendable, Equatable {
    let name: String
    /// Older responses list `artist_mbids`, newer ones a single `artist_mbid`; either may be absent.
    let mbid: String?
    let listenCount: Int?

    init(name: String, mbid: String?, listenCount: Int? = nil) {
        self.name = name
        self.mbid = mbid
        self.listenCount = listenCount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let single = try container.decodeIfPresent(String.self, forKey: .mbid)
        let list = try container.decodeIfPresent([String].self, forKey: .mbids)
        mbid = (single?.isEmpty == false ? single : nil) ?? list?.first
        listenCount = try container.decodeIfPresent(Int.self, forKey: .listenCount)
    }

    private enum CodingKeys: String, CodingKey {
        case name = "artist_name"
        case mbid = "artist_mbid"
        case mbids = "artist_mbids"
        case listenCount = "listen_count"
    }
}
