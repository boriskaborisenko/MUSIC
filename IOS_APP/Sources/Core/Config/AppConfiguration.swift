import Foundation

enum AppConfiguration {
  // Local-first defaults.
  // Simulator can use 127.0.0.1 directly.
  // Physical device must use your Mac's LAN IP.
  #if targetEnvironment(simulator)
  private static let localDefaultBaseURL = URL(string: "http://127.0.0.1:3000")!
  #else
  private static let localDefaultBaseURL = URL(string: "http://192.168.100.85:3000")!
  #endif
  private static let defaultMetadataBaseURL = localDefaultBaseURL
  private static let defaultPlaybackBaseURL = localDefaultBaseURL

  private static let commonBaseURL = configuredURL(
    envKey: "MUSIC_SERVER_BASE_URL",
    fallback: nil
  )

  static let metadataBaseURL = configuredURL(
    envKey: "MUSIC_METADATA_BASE_URL",
    fallback: commonBaseURL ?? defaultMetadataBaseURL
  )!

  static let playbackBaseURL = configuredURL(
    envKey: "MUSIC_PLAYBACK_BASE_URL",
    fallback: commonBaseURL ?? defaultPlaybackBaseURL
  )!

  private static func configuredURL(envKey: String, fallback: URL?) -> URL? {
    guard let raw = ProcessInfo.processInfo.environment[envKey],
          let url = URL(string: raw),
          url.scheme != nil else {
      return fallback
    }
    return url
  }
}
