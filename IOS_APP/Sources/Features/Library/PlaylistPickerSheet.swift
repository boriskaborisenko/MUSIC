import SwiftUI

struct PlaylistPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var library: LibraryStore

  let song: SongSearchItem

  @State private var newPlaylistName = ""

  var body: some View {
    NavigationStack {
      List {
        Section("Song") {
          HStack(spacing: 12) {
            Image(systemName: "music.note")
              .foregroundStyle(.secondary)
              .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
              Text(song.name)
                .lineLimit(1)
              Text(song.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }

        Section("Playlists") {
          if library.playlists.isEmpty {
            Text("No playlists yet")
              .foregroundStyle(.secondary)
          } else {
            ForEach(library.playlists) { playlist in
              Button {
                library.add(song, toPlaylist: playlist.id)
                dismiss()
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                    Text("\(playlist.songs.count) songs")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  if library.playlistContains(song: song, playlistID: playlist.id) {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(.green)
                  } else {
                    Image(systemName: "plus.circle")
                      .foregroundStyle(.secondary)
                  }
                }
              }
              .buttonStyle(.plain)
            }
          }
        }

        Section("Create New Playlist") {
          TextField("Playlist name", text: $newPlaylistName)
          Button("Create and Add") {
            library.add(song, toPlaylistNamed: newPlaylistName)
            dismiss()
          }
          .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .navigationTitle("Add to Playlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            dismiss()
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
