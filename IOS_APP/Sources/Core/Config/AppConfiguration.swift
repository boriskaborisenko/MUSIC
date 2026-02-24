import Foundation

enum AppConfiguration {
  // Task-minimum default for iOS Simulator: local server on the same Mac.
  // Override via scheme env vars if needed.
  private static let defaultMetadataBaseURL = URL(string: "http://127.0.0.1:3000")!
  private static let defaultPlaybackBaseURL = URL(string: "http://127.0.0.1:3000")!

  static let metadataBaseURL = configuredURL(
    envKey: "MUSIC_METADATA_BASE_URL",
    fallback: defaultMetadataBaseURL
  )

  static let playbackBaseURL = configuredURL(
    envKey: "MUSIC_PLAYBACK_BASE_URL",
    fallback: defaultPlaybackBaseURL
  )

  private static func configuredURL(envKey: String, fallback: URL) -> URL {
    guard let raw = ProcessInfo.processInfo.environment[envKey],
          let url = URL(string: raw),
          url.scheme != nil else {
      return fallback
    }
    return url
  }
}
