import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Songs dragged within Minidisc, declared in the Mac app's Info.plist.
    nonisolated static let minidiscSongs = UTType(exportedAs: "com.ecliptik.minidisc.songs")
}

/// One dragged song. A playlist's row also carries the playlist and its position there, so dropping
/// it back into the same playlist moves it instead of adding a copy.
nonisolated struct MacSongDrag: Codable, Transferable, Sendable {
    let song: DisplayableSong
    var playlistID: String?
    var position: Int?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .minidiscSongs)
    }
}
