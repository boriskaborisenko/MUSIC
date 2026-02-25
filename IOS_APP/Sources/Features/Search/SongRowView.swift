import SwiftUI

struct SongRowView: View {
  let song: SongSearchItem
  let isPlaying: Bool
  let onTap: () -> Void

  @State private var fallbackArtwork: UIImage?
  @State private var isLoadingFallbackArtwork = false

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
      CachedRemoteImage(url: url) { phase in
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
      Group {
        if let fallbackArtwork {
          Image(uiImage: fallbackArtwork)
            .resizable()
            .scaledToFill()
        } else {
          ZStack {
            placeholderArtwork
            if isLoadingFallbackArtwork {
              ProgressView()
                .controlSize(.small)
            }
          }
          .task(id: song.videoId) {
            await loadFallbackArtworkIfNeeded()
          }
        }
      }
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

  private func loadFallbackArtworkIfNeeded() async {
    guard song.primaryArtworkURL == nil else { return }
    guard fallbackArtwork == nil else { return }
    guard !isLoadingFallbackArtwork else { return }

    isLoadingFallbackArtwork = true
    fallbackArtwork = await MusicBrainzCoverArtService.shared.artworkImage(for: song)
    isLoadingFallbackArtwork = false
  }
}

enum RemoteImagePhase {
  case empty
  case success(Image)
  case failure
}

struct CachedRemoteImage<Content: View>: View {
  let url: URL?
  private let content: (RemoteImagePhase) -> Content

  @StateObject private var loader = CachedRemoteImageLoader()

  init(
    url: URL?,
    @ViewBuilder content: @escaping (RemoteImagePhase) -> Content
  ) {
    self.url = url
    self.content = content
  }

  var body: some View {
    content(loader.phase)
      .task(id: url) {
        await loader.load(url: url)
      }
  }
}

@MainActor
private final class CachedRemoteImageLoader: ObservableObject {
  @Published var phase: RemoteImagePhase = .empty

  private var currentURL: URL?

  func load(url: URL?) async {
    currentURL = url

    guard let url else {
      phase = .failure
      return
    }

    if let cached = SharedRemoteImagePipeline.shared.cachedImage(for: url) {
      phase = .success(Image(uiImage: cached))
      return
    }

    phase = .empty
    let requestedURL = url
    let image = await SharedRemoteImagePipeline.shared.image(for: url)

    guard !Task.isCancelled else { return }
    guard currentURL == requestedURL else { return }

    if let image {
      phase = .success(Image(uiImage: image))
    } else {
      phase = .failure
    }
  }
}

@MainActor
private final class SharedRemoteImagePipeline {
  static let shared = SharedRemoteImagePipeline()

  private let cache = NSCache<NSURL, UIImage>()
  private var inFlight: [NSURL: Task<UIImage?, Never>] = [:]

  private init() {
    cache.countLimit = 300
    cache.totalCostLimit = 96 * 1024 * 1024
  }

  func cachedImage(for url: URL) -> UIImage? {
    cache.object(forKey: url as NSURL)
  }

  func image(for url: URL) async -> UIImage? {
    let key = url as NSURL

    if let cached = cache.object(forKey: key) {
      return cached
    }

    if let task = inFlight[key] {
      return await task.value
    }

    let task = Task<UIImage?, Never> {
      await Self.fetchImage(url: url)
    }
    inFlight[key] = task

    let image = await task.value
    inFlight[key] = nil

    if let image {
      cache.setObject(image, forKey: key, cost: Self.cacheCost(for: image))
    }

    return image
  }

  private static func fetchImage(url: URL) async -> UIImage? {
    var request = URLRequest(url: url)
    request.cachePolicy = .returnCacheDataElseLoad
    request.timeoutInterval = 20

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        return nil
      }
      guard let image = UIImage(data: data) else {
        return nil
      }
      return image
    } catch {
      return nil
    }
  }

  private static func cacheCost(for image: UIImage) -> Int {
    let pixelWidth = Int(image.size.width * image.scale)
    let pixelHeight = Int(image.size.height * image.scale)
    return max(1, pixelWidth * pixelHeight * 4)
  }
}
