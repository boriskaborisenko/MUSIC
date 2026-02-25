import SwiftUI

struct NowPlayingView: View {
  @EnvironmentObject private var player: PlayerEngine
  @EnvironmentObject private var library: LibraryStore

  @State private var isDraggingSlider = false
  @State private var sliderValue: Double = 0
  @State private var playlistPickerSong: SongSearchItem?

  var body: some View {
    NavigationStack {
      ZStack {
        background
          .ignoresSafeArea()

        if let track = player.currentTrack {
          ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay {
                  artwork(for: track)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .frame(maxWidth: 420)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.15), radius: 24, y: 10)

              VStack(alignment: .leading, spacing: 6) {
                Text(track.name)
                  .font(.title2.weight(.semibold))
                  .lineLimit(2)
                Text(player.currentResolution?.author ?? track.artistName)
                  .font(.title3)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              .frame(maxWidth: .infinity, alignment: .leading)

              if player.isRadioPlayback {
                HStack(spacing: 8) {
                  Image(systemName: "dot.radiowaves.left.and.right")
                  Text("LIVE RADIO")
                    .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
              } else {
                VStack(spacing: 10) {
                  Slider(
                    value: Binding(
                      get: {
                        let rawValue = isDraggingSlider ? sliderValue : player.currentTime
                        return min(max(rawValue, 0), max(player.duration, 1))
                      },
                      set: { sliderValue = $0 }
                    ),
                    in: 0 ... max(player.duration, 1),
                    onEditingChanged: { editing in
                      isDraggingSlider = editing
                      if !editing {
                        player.seek(to: sliderValue)
                      }
                    }
                  )
                  .tint(.primary)

                  HStack {
                    Text(DurationFormatter.mmss(isDraggingSlider ? sliderValue : player.currentTime))
                      .font(.footnote.monospacedDigit())
                      .foregroundStyle(.secondary)
                    Spacer()
                    Text(DurationFormatter.mmss(max(player.duration - (isDraggingSlider ? sliderValue : player.currentTime), 0)))
                      .font(.footnote.monospacedDigit())
                      .foregroundStyle(.secondary)
                  }
                }
              }

              VStack(spacing: 14) {
                HStack(spacing: 24) {
                  if !player.isRadioPlayback {
                    CircleButton(icon: "backward.end.fill") {
                      player.playPreviousTrack()
                    }
                  }

                  Button {
                    player.togglePlayPause()
                  } label: {
                    ZStack {
                      Circle()
                        .fill(.primary)
                        .frame(width: 72, height: 72)
                      if player.isLoading {
                        ProgressView()
                          .tint(.black)
                      } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                          .font(.system(size: 28, weight: .semibold))
                          .foregroundStyle(.black)
                          .offset(x: player.isPlaying ? 0 : 2)
                      }
                    }
                  }
                  .buttonStyle(.plain)

                  if !player.isRadioPlayback {
                    CircleButton(icon: "forward.end.fill") {
                      player.playNextTrack()
                    }
                    .opacity(player.canPlayNextTrack ? 1 : 0.45)
                    .disabled(!player.canPlayNextTrack)
                  }
                }

              }
              .padding(.top, 4)

              if !player.upNextTracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                  HStack {
                    Text("Up Next")
                      .font(.headline)
                    Spacer()
                    Text("\(player.upNextTracks.count)")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                  }

                  ForEach(Array(player.upNextTracks.prefix(3)), id: \.videoId) { nextTrack in
                    HStack(spacing: 10) {
                      Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                      VStack(alignment: .leading, spacing: 2) {
                        Text(nextTrack.name)
                          .font(.subheadline)
                          .lineLimit(1)
                        Text(nextTrack.artistName)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                          .lineLimit(1)
                      }
                      Spacer()
                      if let duration = nextTrack.duration {
                        Text(DurationFormatter.mmss(Double(duration)))
                          .font(.caption.monospacedDigit())
                          .foregroundStyle(.secondary)
                      }
                    }
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
              }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
          }
        } else {
          ContentUnavailableView("Nothing Playing", systemImage: "music.note", description: Text("Choose a song from Search."))
        }
      }
      .toolbar {
        if player.currentTrack != nil, !player.isRadioPlayback {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              player.toggleRepeatOne()
            } label: {
              ZStack {
                Circle()
                  .fill(Color(.secondarySystemBackground))
                  .frame(width: 34, height: 34)
                Circle()
                  .strokeBorder(
                    player.isRepeatOneEnabled ? Color.primary.opacity(0.22) : Color.clear,
                    lineWidth: 1
                  )
                  .frame(width: 34, height: 34)
                Image(systemName: "repeat.1")
                  .font(.body.weight(.semibold))
                  .foregroundStyle(player.isRepeatOneEnabled ? .primary : .secondary)
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isRepeatOneEnabled ? "Repeat one on" : "Repeat one off")
          }
        }
        ToolbarItem(placement: .principal) {
          Text("Now Playing")
            .font(.subheadline.weight(.semibold))
        }
        if let track = player.currentTrack, !player.isRadioPlayback {
          ToolbarItemGroup(placement: .topBarTrailing) {
            topBarCircleButton(
              icon: library.isInCollection(track) ? "heart.fill" : "heart",
              iconColor: library.isInCollection(track) ? .red : .primary
            ) {
              _ = library.toggleCollection(track)
            }

            topBarCircleButton(icon: "text.badge.plus") {
              playlistPickerSong = track
            }
            .contextMenu {
              Button {
                playlistPickerSong = track
              } label: {
                Label("Открыть выбор плейлиста", systemImage: "list.bullet")
              }

              if library.playlists.isEmpty {
                Button {
                  playlistPickerSong = track
                } label: {
                  Label("Создать плейлист", systemImage: "plus")
                }
              } else {
                ForEach(library.playlists) { playlist in
                  let containsTrack = library.playlistContains(song: track, playlistID: playlist.id)

                  Button {
                    if containsTrack {
                      library.remove(track, fromPlaylist: playlist.id)
                    } else {
                      library.add(track, toPlaylist: playlist.id)
                    }
                  } label: {
                    Label(
                      containsTrack ? "Убрать из «\(playlist.name)»" : "Добавить в «\(playlist.name)»",
                      systemImage: containsTrack ? "minus.circle" : "plus.circle"
                    )
                  }
                }
              }
            }
          }
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .sheet(item: $playlistPickerSong) { song in
        PlaylistPickerSheet(song: song)
          .environmentObject(library)
      }
      .onAppear {
        sliderValue = player.currentTime
      }
      .onChange(of: player.currentTrack?.videoId) { _, _ in
        // Force-reset slider position on track switches before new buffering progress comes in.
        isDraggingSlider = false
        sliderValue = 0
      }
      .onReceive(player.$currentTime) { newValue in
        if !isDraggingSlider {
          sliderValue = newValue
        }
      }
    }
  }

  private var background: some View {
    Color(.systemBackground)
  }

  @ViewBuilder
  private func artwork(for track: SongSearchItem) -> some View {
    if let image = player.currentArtwork {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else if let url = track.primaryArtworkURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case let .success(image):
          image.resizable().scaledToFill()
        case .failure:
          placeholderArtwork
        case .empty:
          ZStack {
            placeholderArtwork
            ProgressView()
          }
        @unknown default:
          placeholderArtwork
        }
      }
    } else {
      placeholderArtwork
    }
  }

  private var placeholderArtwork: some View {
    ZStack {
      LinearGradient(
        colors: [.gray.opacity(0.3), .gray.opacity(0.15)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Image(systemName: "music.note")
        .font(.system(size: 54, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }

  private func topBarCircleButton(
    icon: String,
    iconColor: Color = .primary,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      ZStack {
        Circle()
          .fill(Color(.secondarySystemBackground))
          .frame(width: 34, height: 34)
        Image(systemName: icon)
          .font(.body.weight(.semibold))
          .foregroundStyle(iconColor)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct CircleButton: View {
  let icon: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Circle()
        .fill(.thinMaterial)
        .frame(width: 52, height: 52)
        .overlay {
          Image(systemName: icon)
            .font(.title3.weight(.semibold))
        }
    }
    .buttonStyle(.plain)
  }
}
