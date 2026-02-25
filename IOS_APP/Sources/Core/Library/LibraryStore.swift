import Foundation

@MainActor
final class LibraryStore: ObservableObject {
  struct LibraryPlaylist: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var songs: [SongSearchItem]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, songs: [SongSearchItem] = [], createdAt: Date = .now) {
      self.id = id
      self.name = name
      self.songs = songs
      self.createdAt = createdAt
    }
  }

  @Published private(set) var collectionSongs: [SongSearchItem] = []
  @Published private(set) var playlists: [LibraryPlaylist] = []

  private let storageKey = "music_ios_library_v1"

  private struct Snapshot: Codable {
    let collectionSongs: [SongSearchItem]
    let playlists: [LibraryPlaylist]
  }

  init() {
    load()
  }

  func isInCollection(_ song: SongSearchItem) -> Bool {
    collectionSongs.contains(where: { $0.videoId == song.videoId })
  }

  @discardableResult
  func toggleCollection(_ song: SongSearchItem) -> Bool {
    if isInCollection(song) {
      removeFromCollection(song)
      return false
    } else {
      addToCollection(song)
      return true
    }
  }

  func addToCollection(_ song: SongSearchItem) {
    collectionSongs.removeAll(where: { $0.videoId == song.videoId })
    collectionSongs.insert(song, at: 0)
    persist()
  }

  func removeFromCollection(_ song: SongSearchItem) {
    collectionSongs.removeAll(where: { $0.videoId == song.videoId })
    persist()
  }

  @discardableResult
  func createPlaylist(named rawName: String) -> LibraryPlaylist? {
    let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let existing = playlists.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
      return existing
    }

    let playlist = LibraryPlaylist(name: trimmed)
    playlists.insert(playlist, at: 0)
    persist()
    return playlist
  }

  func renamePlaylist(id: UUID, to rawName: String) {
    let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
    playlists[index].name = trimmed
    persist()
  }

  func deletePlaylist(id: UUID) {
    playlists.removeAll(where: { $0.id == id })
    persist()
  }

  func playlist(id: UUID) -> LibraryPlaylist? {
    playlists.first(where: { $0.id == id })
  }

  func playlistContains(song: SongSearchItem, playlistID: UUID) -> Bool {
    guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return false }
    return playlist.songs.contains(where: { $0.videoId == song.videoId })
  }

  func add(_ song: SongSearchItem, toPlaylist playlistID: UUID) {
    guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }

    playlists[index].songs.removeAll(where: { $0.videoId == song.videoId })
    playlists[index].songs.append(song)
    persist()
  }

  func remove(_ song: SongSearchItem, fromPlaylist playlistID: UUID) {
    guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
    playlists[index].songs.removeAll(where: { $0.videoId == song.videoId })
    persist()
  }

  func add(_ song: SongSearchItem, toPlaylistNamed playlistName: String) {
    guard let playlist = createPlaylist(named: playlistName) else { return }
    add(song, toPlaylist: playlist.id)
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let snapshot = try decoder.decode(Snapshot.self, from: data)

      let filteredCollection = snapshot.collectionSongs.filter(isSupportedSavedTrack)
      let filteredPlaylists = snapshot.playlists.map { playlist in
        var playlist = playlist
        playlist.songs = playlist.songs.filter(isSupportedSavedTrack)
        return playlist
      }

      collectionSongs = filteredCollection
      playlists = filteredPlaylists

      let removedCollectionCount = snapshot.collectionSongs.count - filteredCollection.count
      let removedPlaylistSongsCount =
        snapshot.playlists.reduce(0) { $0 + $1.songs.count } -
        filteredPlaylists.reduce(0) { $0 + $1.songs.count }

      if removedCollectionCount > 0 || removedPlaylistSongsCount > 0 {
        print("[LibraryStore] Dropped legacy tracks after source migration. Collection: \(removedCollectionCount), Playlists: \(removedPlaylistSongsCount)")
        persist()
      }
    } catch {
      print("[LibraryStore] Failed to load library: \(error.localizedDescription)")
    }
  }

  private func isSupportedSavedTrack(_ song: SongSearchItem) -> Bool {
    song.videoId.hasPrefix("dm:")
  }

  private func persist() {
    do {
      let snapshot = Snapshot(collectionSongs: collectionSongs, playlists: playlists)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(snapshot)
      UserDefaults.standard.set(data, forKey: storageKey)
    } catch {
      print("[LibraryStore] Failed to persist library: \(error.localizedDescription)")
    }
  }
}

struct RadioStation: Codable, Identifiable, Hashable {
  let id: UUID
  var name: String
  var streamURLString: String
  var artworkData: Data?
  let createdAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    streamURLString: String,
    artworkData: Data? = nil,
    createdAt: Date = .now
  ) {
    self.id = id
    self.name = name
    self.streamURLString = streamURLString
    self.artworkData = artworkData
    self.createdAt = createdAt
  }

  var streamURL: URL? {
    URL(string: streamURLString)
  }
}

@MainActor
final class RadioStore: ObservableObject {
  @Published private(set) var stations: [RadioStation] = []

  private let storageKey = "music_ios_radio_stations_v1"
  private let seededDefaultsKey = "music_ios_radio_stations_seeded_v1"

  init() {
    load()
    seedDefaultsIfNeeded()
  }

  @discardableResult
  func addStation(
    name rawName: String,
    streamURLString rawURLString: String,
    artworkData: Data?
  ) -> RadioStation? {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    let urlString = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !name.isEmpty, !urlString.isEmpty, URL(string: urlString) != nil else { return nil }

    let station = RadioStation(name: name, streamURLString: urlString, artworkData: artworkData)
    stations.insert(station, at: 0)
    persist()
    return station
  }

  @discardableResult
  func updateStation(
    id: UUID,
    name rawName: String,
    streamURLString rawURLString: String,
    artworkData: Data?
  ) -> RadioStation? {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    let urlString = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !name.isEmpty, !urlString.isEmpty, URL(string: urlString) != nil else { return nil }
    guard let index = stations.firstIndex(where: { $0.id == id }) else { return nil }

    stations[index].name = name
    stations[index].streamURLString = urlString
    stations[index].artworkData = artworkData

    let updated = stations.remove(at: index)
    stations.insert(updated, at: 0)
    persist()
    return updated
  }

  func remove(_ station: RadioStation) {
    stations.removeAll(where: { $0.id == station.id })
    persist()
  }

  private func seedDefaultsIfNeeded() {
    guard stations.isEmpty else { return }
    guard UserDefaults.standard.bool(forKey: seededDefaultsKey) == false else { return }

    stations = [
      RadioStation(
        name: "bravo!",
        streamURLString: "http://c5.hostingcentar.com:8059/stream?4960"
      ),
    ]
    UserDefaults.standard.set(true, forKey: seededDefaultsKey)
    persist()
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      stations = try decoder.decode([RadioStation].self, from: data)
    } catch {
      print("[RadioStore] Failed to load stations: \(error.localizedDescription)")
    }
  }

  private func persist() {
    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(stations)
      UserDefaults.standard.set(data, forKey: storageKey)
    } catch {
      print("[RadioStore] Failed to persist stations: \(error.localizedDescription)")
    }
  }
}
