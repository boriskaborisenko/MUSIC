import Foundation

struct SongSearchItem: Codable, Identifiable, Hashable {
  let type: String
  let videoId: String
  let name: String
  let artist: ArtistReference?
  let album: AlbumReference?
  let duration: Int?
  let thumbnails: [Thumbnail]

  var id: String { videoId }

  var primaryArtworkURL: URL? {
    let rawURL = thumbnails
      .sorted { lhs, rhs in (lhs.width ?? 0) < (rhs.width ?? 0) }
      .last?
      .url

    guard let rawURL else { return nil }
    return URL(string: rawURL)
  }

  var artistName: String {
    artist?.name ?? "Unknown Artist"
  }

  var albumName: String? {
    album?.name
  }
}

struct ArtistReference: Codable, Hashable {
  let name: String
  let artistId: String?
}

struct AlbumReference: Codable, Hashable {
  let name: String
  let albumId: String?
}

struct Thumbnail: Codable, Hashable {
  let url: String
  let width: Int?
  let height: Int?
}
