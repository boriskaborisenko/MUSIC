import SwiftUI

struct MiniPlayerBar: View {
  @EnvironmentObject private var player: PlayerEngine
  @Binding var isPresented: Bool

  var body: some View {
    if let track = player.currentTrack {
      Button {
        isPresented = true
      } label: {
        VStack(spacing: 0) {
          Divider()

          HStack(spacing: 12) {
            artwork(for: track)

            VStack(alignment: .leading, spacing: 2) {
              Text(track.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
              Text(track.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if player.isLoading {
              ProgressView()
                .controlSize(.small)
                .frame(width: 30)
            } else {
              Button {
                player.togglePlayPause()
              } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                  .font(.title3.weight(.semibold))
                  .frame(width: 30, height: 30)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(.ultraThinMaterial)

          GeometryReader { geometry in
            ZStack(alignment: .leading) {
              Rectangle()
                .fill(.secondary.opacity(0.18))
              Rectangle()
                .fill(.primary.opacity(0.65))
                .frame(width: geometry.size.width * player.playbackProgress)
            }
          }
          .frame(height: 2)
        }
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private func artwork(for track: SongSearchItem) -> some View {
    if let url = track.primaryArtworkURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case let .success(image):
          image.resizable().scaledToFill()
        default:
          placeholderArtwork
        }
      }
      .frame(width: 44, height: 44)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    } else {
      placeholderArtwork
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var placeholderArtwork: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(.secondary.opacity(0.16))
      .overlay {
        Image(systemName: "music.note")
          .foregroundStyle(.secondary)
      }
  }
}

