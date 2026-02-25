import PhotosUI
import SwiftUI
import UIKit

struct LibraryView: View {
  var body: some View {
    CollectionLibraryView()
  }
}

struct CollectionLibraryView: View {
  @EnvironmentObject private var player: PlayerEngine
  @EnvironmentObject private var library: LibraryStore

  @State private var collectionSearchText = ""
  @State private var playlistPickerSong: SongSearchItem?

  private var normalizedQuery: String {
    collectionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var filteredCollectionSongs: [SongSearchItem] {
    guard !normalizedQuery.isEmpty else { return library.collectionSongs }
    let query = normalizedQuery

    return library.collectionSongs.filter { song in
      song.name.localizedCaseInsensitiveContains(query)
        || song.artistName.localizedCaseInsensitiveContains(query)
        || (song.albumName?.localizedCaseInsensitiveContains(query) ?? false)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          if library.collectionSongs.isEmpty {
            ContentUnavailableView(
              "Collection is empty",
              systemImage: "heart",
              description: Text("Add songs from Search to build your library.")
            )
          } else if filteredCollectionSongs.isEmpty {
            ContentUnavailableView(
              "No Matches",
              systemImage: "magnifyingglass",
              description: Text("Try searching by track name or artist in your collection.")
            )
          } else {
            ForEach(filteredCollectionSongs) { song in
              SongRowView(
                song: song,
                isPlaying: player.currentTrack?.videoId == song.videoId && player.isPlaying
              ) {
                player.play(song: song, queue: filteredCollectionSongs)
              }
              .contextMenu {
                Button(role: .destructive) {
                  library.removeFromCollection(song)
                } label: {
                  Label("Remove from Collection", systemImage: "heart.slash")
                }

                Button {
                  playlistPickerSong = song
                } label: {
                  Label("Add to Playlist", systemImage: "text.badge.plus")
                }
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  library.removeFromCollection(song)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
              .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
          }
        } header: {
          HStack {
            Text("Collection")
            Spacer()
            Text(
              normalizedQuery.isEmpty
                ? "\(library.collectionSongs.count)"
                : "\(filteredCollectionSongs.count) / \(library.collectionSongs.count)"
            )
            .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Collection")
      .searchable(
        text: $collectionSearchText,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Search collection"
      )
      .scrollDismissesKeyboard(.immediately)
      .sheet(item: $playlistPickerSong) { song in
        PlaylistPickerSheet(song: song)
          .environmentObject(library)
      }
    }
  }
}

struct PlaylistsLibraryView: View {
  @EnvironmentObject private var player: PlayerEngine
  @EnvironmentObject private var library: LibraryStore

  @State private var isCreatePlaylistPresented = false
  @State private var newPlaylistName = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          if library.playlists.isEmpty {
            ContentUnavailableView(
              "No playlists",
              systemImage: "music.note.list",
              description: Text("Create playlists and add songs from Search.")
            )
          } else {
            ForEach(library.playlists) { playlist in
              NavigationLink(value: playlist.id) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(playlist.name)
                    .font(.body.weight(.medium))
                  Text("\(playlist.songs.count) songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                  library.deletePlaylist(id: playlist.id)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
          }
        } header: {
          HStack {
            Text("Playlists")
            Spacer()
            Text("\(library.playlists.count)")
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Playlists")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            isCreatePlaylistPresented = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .sheet(isPresented: $isCreatePlaylistPresented) {
        createPlaylistSheet
      }
      .navigationDestination(for: UUID.self) { playlistID in
        PlaylistDetailView(playlistID: playlistID)
          .environmentObject(player)
          .environmentObject(library)
      }
    }
  }

  private var createPlaylistSheet: some View {
    NavigationStack {
      Form {
        TextField("Playlist name", text: $newPlaylistName)
      }
      .navigationTitle("New Playlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            newPlaylistName = ""
            isCreatePlaylistPresented = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            _ = library.createPlaylist(named: newPlaylistName)
            newPlaylistName = ""
            isCreatePlaylistPresented = false
          }
          .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.height(180)])
  }
}

struct RadioView: View {
  @EnvironmentObject private var player: PlayerEngine
  @EnvironmentObject private var radio: RadioStore

  @State private var isAddStationPresented = false
  @State private var editingStation: RadioStation?

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        if radio.stations.isEmpty {
          ContentUnavailableView(
            "No Radio Stations",
            systemImage: "dot.radiowaves.left.and.right",
            description: Text("Tap + to add your first station.")
          )
          .frame(maxWidth: .infinity)
          .padding(.top, 80)
          .padding(.horizontal, 20)
        } else {
          LazyVGrid(columns: columns, spacing: 12) {
            ForEach(radio.stations) { station in
              RadioStationCard(
                station: station,
                isPlaying: player.currentTrack?.videoId == "radio:\(station.id.uuidString)" && player.isPlaying
              ) {
                player.playRadio(station: station)
              }
              .contextMenu {
                Button {
                  editingStation = station
                } label: {
                  Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                  radio.remove(station)
                } label: {
                  Label("Remove", systemImage: "trash")
                }
              }
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
        }
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Radio")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            isAddStationPresented = true
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("Add radio station")
        }
      }
      .sheet(isPresented: $isAddStationPresented) {
        AddRadioStationSheet()
          .environmentObject(radio)
      }
      .sheet(item: $editingStation) { station in
        AddRadioStationSheet(editingStation: station)
          .environmentObject(radio)
      }
    }
  }
}

private struct RadioStationCard: View {
  let station: RadioStation
  let isPlaying: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .bottomLeading) {
        artwork
          .frame(maxWidth: .infinity)
          .aspectRatio(1, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        LinearGradient(
          colors: [.clear, .black.opacity(0.55)],
          startPoint: .top,
          endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        HStack(spacing: 6) {
          if isPlaying {
            Image(systemName: "speaker.wave.2.fill")
              .font(.caption.weight(.semibold))
          }
          Text(station.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(10)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(.white.opacity(0.08), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var artwork: some View {
    if let data = station.artworkData, let image = UIImage(data: data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(.secondarySystemBackground))
        Image(systemName: "dot.radiowaves.left.and.right")
          .font(.system(size: 28, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct AddRadioStationSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var radio: RadioStore

  private let editingStation: RadioStation?
  @State private var name = ""
  @State private var streamURLString = ""
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var artworkData: Data?
  @State private var photoLoadError: String?
  @State private var isLoadingPhoto = false

  init(editingStation: RadioStation? = nil) {
    self.editingStation = editingStation
    _name = State(initialValue: editingStation?.name ?? "")
    _streamURLString = State(initialValue: editingStation?.streamURLString ?? "")
    _artworkData = State(initialValue: editingStation?.artworkData)
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !streamURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && URL(string: streamURLString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Artwork") {
          PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            HStack(spacing: 14) {
              artworkPreview
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

              VStack(alignment: .leading, spacing: 4) {
                Text(artworkData == nil ? "Choose image from Photos" : "Change image")
                  .font(.body.weight(.medium))
                Text("Optional")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if isLoadingPhoto {
                ProgressView()
              }
            }
          }
          .buttonStyle(.plain)

          if let photoLoadError {
            Text(photoLoadError)
              .font(.footnote)
              .foregroundStyle(.red)
          }

          if artworkData != nil {
            Button(role: .destructive) {
              selectedPhotoItem = nil
              artworkData = nil
            } label: {
              Label("Remove Image", systemImage: "trash")
            }
          }
        }

        Section("Station") {
          TextField("Name", text: $name)

          TextField("Stream URL", text: $streamURLString)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      }
      .navigationTitle(editingStation == nil ? "Add Station" : "Edit Station")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(editingStation == nil ? "Add" : "Save") {
            if let editingStation {
              _ = radio.updateStation(
                id: editingStation.id,
                name: name,
                streamURLString: streamURLString,
                artworkData: artworkData
              )
            } else {
              _ = radio.addStation(
                name: name,
                streamURLString: streamURLString,
                artworkData: artworkData
              )
            }
            dismiss()
          }
          .disabled(!canSave)
        }
      }
      .onChange(of: selectedPhotoItem) { _, newValue in
        guard let newValue else { return }
        loadArtwork(from: newValue)
      }
    }
    .presentationDetents([.medium, .large])
  }

  @ViewBuilder
  private var artworkPreview: some View {
    if let artworkData, let image = UIImage(data: artworkData) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(.secondarySystemBackground))
        Image(systemName: "photo")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func loadArtwork(from item: PhotosPickerItem) {
    isLoadingPhoto = true
    photoLoadError = nil

    Task {
      do {
        guard let rawData = try await item.loadTransferable(type: Data.self) else {
          await MainActor.run {
            isLoadingPhoto = false
            photoLoadError = "Could not read selected image."
          }
          return
        }

        let normalized = normalizedArtworkData(from: rawData) ?? rawData
        await MainActor.run {
          artworkData = normalized
          isLoadingPhoto = false
        }
      } catch {
        await MainActor.run {
          isLoadingPhoto = false
          photoLoadError = error.localizedDescription
        }
      }
    }
  }

  private func normalizedArtworkData(from rawData: Data) -> Data? {
    guard let image = UIImage(data: rawData) else { return nil }

    let sourceSize = image.size
    let sourceWidth = max(1, sourceSize.width)
    let sourceHeight = max(1, sourceSize.height)
    let sourceMinSide = min(sourceWidth, sourceHeight)

    let maxSide: CGFloat = 700
    let targetSide = max(1, min(maxSide, sourceMinSide))
    let scale = targetSide / sourceMinSide
    let drawSize = CGSize(width: sourceWidth * scale, height: sourceHeight * scale)
    let drawOrigin = CGPoint(
      x: (targetSide - drawSize.width) / 2,
      y: (targetSide - drawSize.height) / 2
    )

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide))
    let rendered = renderer.image { _ in
      image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
    }

    return rendered.jpegData(compressionQuality: 0.86)
  }
}

private struct PlaylistDetailView: View {
  @EnvironmentObject private var player: PlayerEngine
  @EnvironmentObject private var library: LibraryStore

  let playlistID: UUID

  @State private var renameDraft = ""
  @State private var isRenamePresented = false

  var body: some View {
    Group {
      if let playlist = library.playlist(id: playlistID) {
        List {
          if playlist.songs.isEmpty {
            ContentUnavailableView(
              "Empty Playlist",
              systemImage: "music.note",
              description: Text("Add songs from Search or Collection.")
            )
          } else {
            ForEach(playlist.songs) { song in
              SongRowView(
                song: song,
                isPlaying: player.currentTrack?.videoId == song.videoId && player.isPlaying
              ) {
                player.play(song: song, queue: playlist.songs)
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  library.remove(song, fromPlaylist: playlist.id)
                } label: {
                  Label("Remove", systemImage: "trash")
                }
              }
              .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
          }
        }
        .navigationTitle(playlist.name)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button("Rename") {
                renameDraft = playlist.name
                isRenamePresented = true
              }
              Button(role: .destructive) {
                library.deletePlaylist(id: playlist.id)
              } label: {
                Label("Delete Playlist", systemImage: "trash")
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
          }
        }
        .sheet(isPresented: $isRenamePresented) {
          NavigationStack {
            Form {
              TextField("Playlist name", text: $renameDraft)
            }
            .navigationTitle("Rename Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                  isRenamePresented = false
                }
              }
              ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                  library.renamePlaylist(id: playlist.id, to: renameDraft)
                  isRenamePresented = false
                }
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              }
            }
          }
          .presentationDetents([.height(180)])
        }
      } else {
        ContentUnavailableView("Playlist not found", systemImage: "exclamationmark.triangle")
      }
    }
  }
}
