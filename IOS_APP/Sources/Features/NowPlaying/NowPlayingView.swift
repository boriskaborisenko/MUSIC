import SwiftUI

struct NowPlayingView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var player: PlayerEngine

  @State private var isDraggingSlider = false
  @State private var sliderValue: Double = 0

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

              VStack(spacing: 10) {
                Slider(
                  value: Binding(
                    get: {
                      isDraggingSlider ? sliderValue : player.currentTime
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

              HStack(spacing: 28) {
                CircleButton(icon: "gobackward.15") {
                  player.skipBackward()
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

                CircleButton(icon: "goforward.15") {
                  player.skipForward()
                }
              }
              .padding(.top, 4)

              VStack(alignment: .leading, spacing: 10) {
                Text("Playback")
                  .font(.headline)

                Label(
                  player.currentResolution?.selected.mimeType ?? "Unknown format",
                  systemImage: "waveform"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let bitrate = player.currentResolution?.selected.audioBitrateKbps {
                  Label("\(bitrate) kbps", systemImage: "speedometer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if let expiresAt = player.currentResolution?.expiresAt {
                  Label("URL expires: \(expiresAt)", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(16)
              .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
          }
        } else {
          ContentUnavailableView("Nothing Playing", systemImage: "music.note", description: Text("Choose a song from Search."))
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "chevron.down")
              .font(.body.weight(.semibold))
          }
        }
        ToolbarItem(placement: .principal) {
          Text("Now Playing")
            .font(.subheadline.weight(.semibold))
        }
      }
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
      .onAppear {
        sliderValue = player.currentTime
      }
      .onReceive(player.$currentTime) { newValue in
        if !isDraggingSlider {
          sliderValue = newValue
        }
      }
    }
  }

  private var background: some View {
    LinearGradient(
      colors: [
        Color.red.opacity(0.22),
        Color.orange.opacity(0.12),
        Color(.systemBackground)
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  @ViewBuilder
  private func artwork(for track: SongSearchItem) -> some View {
    if let url = track.primaryArtworkURL {
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

