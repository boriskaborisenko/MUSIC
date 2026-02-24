import SwiftUI

struct SongRowView: View {
  let song: SongSearchItem
  let isPlaying: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 12) {
        artwork

        VStack(alignment: .leading, spacing: 4) {
          Text(song.name)
            .font(.body.weight(isPlaying ? .semibold : .regular))
            .lineLimit(1)
            .foregroundStyle(isPlaying ? .red : .primary)

          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer(minLength: 12)

        if isPlaying {
          Image(systemName: "speaker.wave.2.fill")
            .foregroundStyle(.red)
            .font(.subheadline.weight(.semibold))
        } else {
          Text(DurationFormatter.mmss(song.duration))
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var artwork: some View {
    if let url = song.primaryArtworkURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case let .success(image):
          image
            .resizable()
            .scaledToFill()
        case .failure:
          placeholderArtwork
        case .empty:
          ZStack {
            placeholderArtwork
            ProgressView()
              .controlSize(.small)
          }
        @unknown default:
          placeholderArtwork
        }
      }
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    } else {
      placeholderArtwork
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  private var placeholderArtwork: some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(
        LinearGradient(
          colors: [.gray.opacity(0.35), .gray.opacity(0.15)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay {
        Image(systemName: "music.note")
          .foregroundStyle(.secondary)
      }
  }

  private var subtitle: String {
    let artist = song.artistName
    if let album = song.albumName, !album.isEmpty {
      return "\(artist) • \(album)"
    }
    return artist
  }
}

