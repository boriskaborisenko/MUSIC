import SwiftUI

struct MiniPlayerBar: View {
  @EnvironmentObject private var player: PlayerEngine
  @Binding var isPresented: Bool

  private let cornerRadius: CGFloat = 18

  var body: some View {
    if let track = player.currentTrack {
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Button {
            isPresented = true
          } label: {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity, alignment: .leading)

          HStack(spacing: 4) {
            if !player.isRadioPlayback {
              miniControlButton(
                icon: "backward.end.fill",
                isEnabled: player.canPlayPreviousTrack || player.currentTime > 0.5,
                action: { player.playPreviousTrack() }
              )
            }

            if player.isLoading {
              ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
            } else {
              miniControlButton(
                icon: player.isPlaying ? "pause.fill" : "play.fill",
                action: { player.togglePlayPause() }
              )
            }

            if !player.isRadioPlayback {
              miniControlButton(
                icon: "forward.end.fill",
                isEnabled: player.canPlayNextTrack,
                action: { player.playNextTrack() }
              )
            }
          }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)

        if !player.isRadioPlayback {
          GeometryReader { geometry in
            ZStack(alignment: .leading) {
              Capsule()
                .fill(.secondary.opacity(0.15))
              Capsule()
                .fill(.primary.opacity(0.65))
                .frame(width: geometry.size.width * player.playbackProgress)
            }
          }
          .frame(height: 3)
          .padding(.horizontal, 14)
          .padding(.bottom, 10)
        }
      }
      .background(.bar, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(
            LinearGradient(
              colors: [.white.opacity(0.22), .white.opacity(0.05)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
      }
      .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
  }

  @ViewBuilder
  private func artwork(for track: SongSearchItem) -> some View {
    if let image = player.currentArtwork {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    } else if let url = track.primaryArtworkURL {
      CachedRemoteImage(url: url) { phase in
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

  private func miniControlButton(
    icon: String,
    isEnabled: Bool = true,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.body.weight(.semibold))
        .frame(width: 30, height: 30)
        .foregroundStyle(isEnabled ? .primary : .secondary)
        .background(.primary.opacity(isEnabled ? 0.08 : 0), in: Circle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
  }
}
