import Foundation

struct PlaybackResolution: Decodable {
  let videoId: String
  let title: String
  let author: String?
  let durationSec: Int?
  let selected: PlaybackFormatSummary
  let directUrl: String
  let expiresAt: String?
  let proxyUrl: String?
  let candidates: [PlaybackFormatSummary]
}

struct PlaybackFormatSummary: Decodable {
  let itag: Int?
  let mimeType: String?
  let container: String?
  let codecs: String?
  let audioBitrateKbps: Int?
  let contentLength: Int?
  let iosPreferred: Bool?
}

