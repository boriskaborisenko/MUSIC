import Foundation

enum APIClientError: LocalizedError {
  case invalidURL
  case invalidResponse
  case httpError(Int, String)
  case serverError(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid URL."
    case .invalidResponse:
      return "Unexpected response from music source."
    case let .httpError(code, message):
      let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
      let lower = trimmed.lowercased()
      if lower.contains("<html") || lower.contains("<!doctype") {
        return "HTTP \(code): Music source temporarily blocked the request. Please try again."
      }
      let shortMessage = trimmed.count > 220 ? String(trimmed.prefix(220)) + "…" : trimmed
      return "HTTP \(code): \(shortMessage)"
    case let .serverError(message):
      return message
    }
  }
}

enum DriveMusicNewsCategory: String, CaseIterable, Hashable {
  case all
  case international
  case russian

  var title: String {
    switch self {
    case .all:
      return "All"
    case .international:
      return "International"
    case .russian:
      return "Russian"
    }
  }

  var path: String {
    switch self {
    case .all:
      return "/novinki_muzyki/"
    case .international:
      return "/zarubezhnye_novinki/"
    case .russian:
      return "/russkie_novinki/"
    }
  }
}

struct DriveMusicBrowseCard: Identifiable, Hashable {
  let title: String
  let path: String
  let imageURL: URL?
  let subtitle: String?

  var id: String { path }
}

struct DriveMusicQuickLink: Identifiable, Hashable {
  let title: String
  let path: String

  var id: String { path }
}

struct DriveMusicHomeFeed: Hashable {
  let topPlaylists: [DriveMusicBrowseCard]
  let topGenres: [DriveMusicBrowseCard]
  let quickLinks: [DriveMusicQuickLink]
  let chartSongs: [SongSearchItem]
}

struct DriveMusicSongsPageBatch: Hashable {
  let songs: [SongSearchItem]
  let nextPagePath: String?
}

final class APIClient {
  static let shared = APIClient(
    metadataBaseURL: AppConfiguration.metadataBaseURL,
    playbackBaseURL: AppConfiguration.playbackBaseURL
  )

  let metadataBaseURL: URL
  let playbackBaseURL: URL
  fileprivate let session: URLSession

  private var driveMusicTrackPathByID: [String: String] = [:]
  private var driveMusicDirectURLByID: [String: String] = [:]
  private var driveMusicMetadataByID: [String: DriveMusicTrackMetadata] = [:]
  private var driveMusicArtistPathByName: [String: String] = [:]
  private var hasWarmedDriveMusicSession = false

  init(metadataBaseURL: URL, playbackBaseURL: URL, session: URLSession = .shared) {
    self.metadataBaseURL = metadataBaseURL
    self.playbackBaseURL = playbackBaseURL
    self.session = session
  }

  func searchSongs(query: String) async throws -> [SongSearchItem] {
    let batch = try await searchSongsBatch(query: query)
    return batch.songs
  }

  func searchSongsBatch(query: String) async throws -> DriveMusicSongsPageBatch {
    try await searchSongsDriveMusicBatch(query: query)
  }

  func resolvePlayback(videoID: String) async throws -> PlaybackResolution {
    guard let token = parseDriveMusicVideoID(videoID) else {
      throw APIClientError.serverError("Legacy track source is no longer supported. Re-add the track from Search.")
    }
    return try await resolvePlaybackDriveMusic(token: token)
  }

  func resolveDriveMusicArtistPagePath(artistName: String, preferredPath: String? = nil) async throws -> String {
    let trimmedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedArtist.isEmpty else {
      throw APIClientError.serverError("Artist name is empty.")
    }

    if let preferredPath {
      let normalizedPreferred = normalizeDriveMusicPath(preferredPath)
      if normalizedPreferred.hasPrefix("/artist/"), normalizedPreferred.hasSuffix(".html") {
        cacheDriveMusicArtistPath(artistName: trimmedArtist, path: normalizedPreferred)
        return normalizedPreferred
      }
    }

    let lookupKey = normalizeDriveMusicArtistLookupKey(trimmedArtist)
    if let cached = driveMusicArtistPathByName[lookupKey] {
      return cached
    }

    let html = try await fetchDriveMusicSearchHTML(query: trimmedArtist)
    let candidates = parseDriveMusicArtistSearchCandidates(html: html)
    guard !candidates.isEmpty else {
      throw APIClientError.serverError("Could not find artist page on DriveMusic.")
    }

    if let exact = candidates.first(where: { normalizeDriveMusicArtistLookupKey($0.name) == lookupKey }) {
      cacheDriveMusicArtistPath(artistName: trimmedArtist, path: exact.path)
      return exact.path
    }

    if let partial = candidates.first(where: {
      let candidateKey = normalizeDriveMusicArtistLookupKey($0.name)
      return !candidateKey.isEmpty && (candidateKey.contains(lookupKey) || lookupKey.contains(candidateKey))
    }) {
      cacheDriveMusicArtistPath(artistName: trimmedArtist, path: partial.path)
      return partial.path
    }

    let first = candidates[0]
    cacheDriveMusicArtistPath(artistName: trimmedArtist, path: first.path)
    return first.path
  }

  func fetchDriveMusicNews(category: DriveMusicNewsCategory) async throws -> [SongSearchItem] {
    let html = try await fetchDriveMusicHTML(path: category.path)
    return parseDriveMusicSongRows(html: html)
  }

  func fetchDriveMusicHomeFeed() async throws -> DriveMusicHomeFeed {
    let html = try await fetchDriveMusicHTML(path: "/")
    return parseDriveMusicHomeFeed(html: html)
  }

  func fetchDriveMusicSongsPage(path: String) async throws -> [SongSearchItem] {
    let batch = try await fetchDriveMusicSongsPageBatch(path: path)
    return batch.songs
  }

  func fetchDriveMusicSongsPageBatch(path: String) async throws -> DriveMusicSongsPageBatch {
    let normalizedPath = normalizeDriveMusicPath(path)
    let html = try await fetchDriveMusicHTML(path: normalizedPath)
    let songs = parseDriveMusicSongRows(html: html)
    let nextPagePath = parseDriveMusicNextPagePath(html: html, currentPath: normalizedPath, hasSongs: !songs.isEmpty)
    return DriveMusicSongsPageBatch(songs: songs, nextPagePath: nextPagePath)
  }

  func buildAbsoluteURL(from rawValue: String, relativeTo baseURL: URL? = nil) -> URL? {
    if let absolute = URL(string: rawValue), absolute.scheme != nil {
      return absolute
    }
    let targetBase = baseURL ?? metadataBaseURL
    return URL(string: rawValue, relativeTo: targetBase)?.absoluteURL
  }

  func canonicalDriveMusicPath(_ path: String) -> String {
    normalizeDriveMusicPath(path)
  }
}

private enum DriveMusicDirectConstants {
  static let baseURL = URL(string: "https://drivemusic.club")!
  static let userAgents = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
  ]
}

private extension APIClient {
  struct DriveMusicTrackToken {
    let trackID: String
    let path: String?
  }

  struct DriveMusicTrackMetadata {
    let artist: String?
    let title: String
    let durationSec: Int?
    let bitrateKbps: Int?
    let albumName: String?
  }

  func searchSongsDriveMusic(query: String) async throws -> [SongSearchItem] {
    let batch = try await searchSongsDriveMusicBatch(query: query)
    return batch.songs
  }

  func searchSongsDriveMusicBatch(query: String) async throws -> DriveMusicSongsPageBatch {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return DriveMusicSongsPageBatch(songs: [], nextPagePath: nil) }

    let html = try await fetchDriveMusicSearchHTML(query: trimmed)
    let songs = parseDriveMusicSongRows(html: html)
    let nextPagePath = parseDriveMusicSearchNextPagePath(html: html)
      ?? parseDriveMusicNextPagePath(html: html, currentPath: "/?do=search", hasSongs: false)
    return DriveMusicSongsPageBatch(songs: songs, nextPagePath: nextPagePath)
  }

  func resolvePlaybackDriveMusic(token: DriveMusicTrackToken) async throws -> PlaybackResolution {
    if let cachedDirectURL = driveMusicDirectURLByID[token.trackID] {
      let metadata = driveMusicMetadataByID[token.trackID] ?? DriveMusicTrackMetadata(
        artist: nil,
        title: "Track \(token.trackID)",
        durationSec: nil,
        bitrateKbps: nil,
        albumName: nil
      )
      return buildDriveMusicPlaybackResolution(trackID: token.trackID, directURL: cachedDirectURL, metadata: metadata)
    }

    let path = token.path ?? driveMusicTrackPathByID[token.trackID]
    guard let path else {
      throw APIClientError.serverError("Could not resolve track path")
    }

    let html = try await fetchDriveMusicHTML(path: path)
    let metadata = parseDriveMusicTrackMetadata(html: html, trackID: token.trackID)
    let directURL = try extractDriveMusicDirectAudioURL(html: html)

    cacheDriveMusicTrackContext(
      trackID: token.trackID,
      path: path,
      directURL: directURL,
      metadata: metadata
    )

    return buildDriveMusicPlaybackResolution(trackID: token.trackID, directURL: directURL, metadata: metadata)
  }

  func buildDriveMusicPlaybackResolution(
    trackID: String,
    directURL: String,
    metadata: DriveMusicTrackMetadata
  ) -> PlaybackResolution {
    let selected = PlaybackFormatSummary(
      itag: nil,
      mimeType: "audio/mpeg",
      container: "mp3",
      codecs: "mp3",
      audioBitrateKbps: metadata.bitrateKbps,
      contentLength: nil,
      iosPreferred: true
    )

    return PlaybackResolution(
      videoId: makeDriveMusicVideoID(trackID: trackID, path: driveMusicTrackPathByID[trackID]),
      title: metadata.title,
      author: metadata.artist,
      durationSec: metadata.durationSec,
      selected: selected,
      directUrl: directURL,
      expiresAt: nil,
      proxyUrl: nil,
      candidates: [selected]
    )
  }

  func driveMusicRequest(
    path: String,
    queryItems: [URLQueryItem] = [],
    method: String = "GET",
    body: Data? = nil,
    contentType: String? = nil,
    acceptHeader: String? = nil,
    extraHeaders: [String: String] = [:]
  ) async throws -> (data: Data, response: HTTPURLResponse) {
    var lastError: Error?

    for (index, userAgent) in DriveMusicDirectConstants.userAgents.enumerated() {
      do {
        return try await driveMusicRequestOnce(
          path: path,
          queryItems: queryItems,
          method: method,
          body: body,
          contentType: contentType,
          acceptHeader: acceptHeader,
          extraHeaders: extraHeaders,
          userAgent: userAgent
        )
      } catch let APIClientError.httpError(code, bodyText)
        where (code == 403 || code == 429) && index < DriveMusicDirectConstants.userAgents.count - 1 {
        lastError = APIClientError.httpError(code, bodyText)
        print("[APIClient] DriveMusic request blocked with HTTP \(code) using UA #\(index + 1). Retrying with alternate UA.")
        continue
      } catch {
        lastError = error
        break
      }
    }

    throw lastError ?? APIClientError.invalidResponse
  }

  func driveMusicRequestOnce(
    path: String,
    queryItems: [URLQueryItem] = [],
    method: String = "GET",
    body: Data? = nil,
    contentType: String? = nil,
    acceptHeader: String? = nil,
    extraHeaders: [String: String] = [:],
    userAgent: String
  ) async throws -> (data: Data, response: HTTPURLResponse) {
    await warmDriveMusicSessionIfNeeded(using: userAgent)

    guard var components = URLComponents(url: DriveMusicDirectConstants.baseURL, resolvingAgainstBaseURL: false) else {
      throw APIClientError.invalidURL
    }

    components.path = path
    if !queryItems.isEmpty {
      components.queryItems = queryItems
    }

    guard let url = components.url else {
      throw APIClientError.invalidURL
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.httpMethod = method
    request.httpBody = body
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("ru,en-US;q=0.8", forHTTPHeaderField: "Accept-Language")
    request.setValue(
      acceptHeader ?? "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      forHTTPHeaderField: "Accept"
    )
    request.setValue("https://drivemusic.club/", forHTTPHeaderField: "Referer")
    request.setValue("keep-alive", forHTTPHeaderField: "Connection")
    request.setValue("1", forHTTPHeaderField: "DNT")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    request.setValue("no-cache", forHTTPHeaderField: "Pragma")
    request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
    request.setValue(method == "GET" ? "navigate" : "cors", forHTTPHeaderField: "Sec-Fetch-Mode")
    request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
    request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
    if method == "GET" {
      request.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
    }
    if let contentType {
      request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }
    for (header, value) in extraHeaders {
      request.setValue(value, forHTTPHeaderField: header)
    }

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw APIClientError.invalidResponse
    }

    guard (200 ... 299).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "Unexpected response"
      throw APIClientError.httpError(http.statusCode, body)
    }

    return (data, http)
  }

  func warmDriveMusicSessionIfNeeded(using userAgent: String) async {
    guard !hasWarmedDriveMusicSession else { return }
    hasWarmedDriveMusicSession = true

    var request = URLRequest(url: DriveMusicDirectConstants.baseURL)
    request.timeoutInterval = 12
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("ru,en-US;q=0.8", forHTTPHeaderField: "Accept-Language")
    request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
    request.setValue("https://drivemusic.club/", forHTTPHeaderField: "Referer")

    do {
      let (_, response) = try await session.data(for: request)
      if let http = response as? HTTPURLResponse {
        print("[APIClient] Warmed DriveMusic session with HTTP \(http.statusCode)")
      }
    } catch {
      print("[APIClient] DriveMusic warm-up failed: \(error.localizedDescription)")
    }
  }

  func fetchDriveMusicHTML(path: String, queryItems: [URLQueryItem] = []) async throws -> String {
    let (data, _) = try await driveMusicRequest(path: path, queryItems: queryItems)
    if let html = String(data: data, encoding: .utf8) {
      return html
    }
    throw APIClientError.invalidResponse
  }

  func fetchDriveMusicSearchHTML(query: String) async throws -> String {
    let queryItems = [
      URLQueryItem(name: "do", value: "search"),
      URLQueryItem(name: "subaction", value: "search"),
      URLQueryItem(name: "story", value: query),
    ]

    do {
      return try await fetchDriveMusicHTML(path: "/", queryItems: queryItems)
    } catch let APIClientError.httpError(code, body) where code == 403 || code == 429 {
      print("[APIClient] DriveMusic search GET / blocked with HTTP \(code). Trying /index.php. Body prefix: \(String(body.prefix(120)))")
    } catch {
      print("[APIClient] DriveMusic search GET / failed: \(error.localizedDescription). Trying /index.php.")
    }

    do {
      return try await fetchDriveMusicHTML(path: "/index.php", queryItems: queryItems)
    } catch let APIClientError.httpError(code, body) where code == 403 || code == 429 {
      print("[APIClient] DriveMusic search GET /index.php blocked with HTTP \(code). Trying POST. Body prefix: \(String(body.prefix(120)))")
    } catch {
      print("[APIClient] DriveMusic search GET /index.php failed: \(error.localizedDescription). Trying POST.")
    }

    let bodyString = [
      "do=search",
      "subaction=search",
      "story=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)",
      "search_start=0",
      "full_search=0",
      "result_from=1",
      "result_num=25",
    ].joined(separator: "&")

    let (data, _) = try await driveMusicRequest(
      path: "/index.php",
      queryItems: [URLQueryItem(name: "do", value: "search")],
      method: "POST",
      body: Data(bodyString.utf8),
      contentType: "application/x-www-form-urlencoded; charset=UTF-8",
      extraHeaders: [
        "Origin": "https://drivemusic.club",
        "X-Requested-With": "XMLHttpRequest",
      ]
    )

    guard let html = String(data: data, encoding: .utf8) else {
      throw APIClientError.invalidResponse
    }
    return html
  }

  func parseDriveMusicVideoID(_ videoID: String) -> DriveMusicTrackToken? {
    guard videoID.hasPrefix("dm:") else { return nil }
    let payload = String(videoID.dropFirst(3))
    let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    guard let trackID = parts.first, !trackID.isEmpty else { return nil }
    let path = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
    return DriveMusicTrackToken(trackID: trackID, path: path)
  }

  func makeDriveMusicVideoID(trackID: String, path: String?) -> String {
    if let path, !path.isEmpty {
      return "dm:\(trackID)|\(path)"
    }
    return "dm:\(trackID)"
  }

  func cacheDriveMusicTrackContext(
    trackID: String,
    path: String?,
    directURL: String?,
    metadata: DriveMusicTrackMetadata?
  ) {
    if let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
       path.hasPrefix("/"),
       path.hasSuffix(".html") {
      driveMusicTrackPathByID[trackID] = path
    }

    if let directURL = directURL?.trimmingCharacters(in: .whitespacesAndNewlines), !directURL.isEmpty {
      driveMusicDirectURLByID[trackID] = directURL
    }

    if let metadata {
      driveMusicMetadataByID[trackID] = metadata
    }
  }

  func cacheDriveMusicArtistPath(artistName: String, path: String) {
    let key = normalizeDriveMusicArtistLookupKey(artistName)
    guard !key.isEmpty else { return }

    let normalizedPath = normalizeDriveMusicPath(path)
    guard normalizedPath.hasPrefix("/artist/"), normalizedPath.hasSuffix(".html") else { return }

    driveMusicArtistPathByName[key] = normalizedPath
  }

  func normalizeDriveMusicArtistLookupKey(_ value: String) -> String {
    value
      .decodingBasicHTMLEntities()
      .collapsingWhitespace()
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func parseDriveMusicSongRows(html: String) -> [SongSearchItem] {
    let rowPattern = #"(?s)<div class=\"music-popular-wrapper\">\s*(.*?)<div class=\"popular-progress\"></div>\s*</div>"#
    let rowMatches = html.allMatches(pattern: rowPattern)

    var results: [SongSearchItem] = []
    var seenTrackIDs = Set<String>()

    for rowGroups in rowMatches {
      guard let rowHTML = rowGroups[safe: 1],
            let song = parseDriveMusicSongRow(html: rowHTML),
            let token = parseDriveMusicVideoID(song.videoId) else {
        continue
      }

      guard !seenTrackIDs.contains(token.trackID) else { continue }
      seenTrackIDs.insert(token.trackID)
      results.append(song)
    }

    return results
  }

  func parseDriveMusicSongRow(html rowHTML: String) -> SongSearchItem? {
    guard let buttonTag = rowHTML.firstMatch(pattern: #"(?s)<button\b[^>]*\bpopular-play__item\b[^>]*>"#)?[safe: 0] else {
      return nil
    }
    let buttonAttrs = parseHTMLAttributes(in: buttonTag)

    guard let directURL = buttonAttrs["data-url"],
          let titleMatch = rowHTML.firstMatch(pattern: #"(?s)<a href=\"(/[^\"]+\.html)\" class=\"popular-play-author\">(.*?)</a>"#),
          let path = titleMatch[safe: 1],
          let rawTitle = titleMatch[safe: 2] else {
      return nil
    }

    guard let trackID = path.firstMatch(pattern: #"/[^/]+/(\d+)-[^/]+\.html"#)?[safe: 1], !trackID.isEmpty else {
      return nil
    }

    let title = rawTitle.strippingHTMLTags().decodingBasicHTMLEntities().collapsingWhitespace()
    guard !title.isEmpty else { return nil }

    let compositionHTML = rowHTML.firstMatch(pattern: #"(?s)<div class=['\"]popular-play-composition['\"]>(.*?)</div>"#)?[safe: 1] ?? ""
    let artistName = compositionHTML.strippingHTMLTags().decodingBasicHTMLEntities().collapsingWhitespace()
    let artistPath = compositionHTML.firstMatch(pattern: #"(?is)<a\b[^>]*href=\"(/artist/[^\"]+\.html)\"[^>]*>"#)?[safe: 1]
    let durationText = rowHTML.firstMatch(pattern: #"<div class=\"popular-download-number\">\s*([0-9:]+)\s*</div>"#)?[safe: 1] ?? ""
    let auxText = rowHTML.firstMatch(pattern: #"<div class=\"popular-download-date\">\s*(.*?)\s*</div>"#)?[safe: 1] ?? ""
    let bitrateKbps = Int(auxText.firstMatch(pattern: #"(\d+)\s*kbps"#)?[safe: 1] ?? "")

    let metadata = DriveMusicTrackMetadata(
      artist: artistName.isEmpty ? nil : artistName,
      title: title,
      durationSec: parseDurationToSeconds(durationText),
      bitrateKbps: bitrateKbps,
      albumName: nil
    )

    if let artistPath, !artistName.isEmpty {
      cacheDriveMusicArtistPath(artistName: artistName, path: artistPath)
    }

    cacheDriveMusicTrackContext(trackID: trackID, path: path, directURL: directURL, metadata: metadata)

    return SongSearchItem(
      type: "SONG",
      videoId: makeDriveMusicVideoID(trackID: trackID, path: path),
      name: title,
      artist: artistName.isEmpty ? nil : ArtistReference(name: artistName, artistId: artistPath),
      album: nil,
      duration: metadata.durationSec,
      thumbnails: []
    )
  }

  func parseDriveMusicTrackMetadata(html: String, trackID: String) -> DriveMusicTrackMetadata {
    let h1InnerHTML = html.firstMatch(
      pattern: #"(?s)<h1[^>]*class=\"[^\"]*\bsong-title-text\b[^\"]*\"[^>]*>(.*?)</h1>"#
    )?[safe: 1] ?? ""
    let h1Text = h1InnerHTML.strippingHTMLTags().decodingBasicHTMLEntities().collapsingWhitespace()

    var artist: String?
    var title = h1Text

    if let separatorRange = h1Text.range(of: " - ") {
      let lhs = String(h1Text[..<separatorRange.lowerBound]).collapsingWhitespace()
      let rhs = String(h1Text[separatorRange.upperBound...]).collapsingWhitespace()
      artist = lhs.isEmpty ? nil : lhs
      if !rhs.isEmpty { title = rhs }
    }

    if title.isEmpty {
      title = "Track \(trackID)"
    }

    let infoLineGroups = html.firstMatch(
      pattern: #"(?s)<li class=\"author-description-item\">\s*[^<]*?(\d+)\s*kbps[^<]*?([0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)\s*</li>"#
    )

    let bitrateKbps = infoLineGroups.flatMap { Int($0[safe: 1] ?? "") }
    let durationText = infoLineGroups?[safe: 2] ?? ""

    return DriveMusicTrackMetadata(
      artist: artist,
      title: title,
      durationSec: parseDurationToSeconds(durationText),
      bitrateKbps: bitrateKbps,
      albumName: nil
    )
  }

  func extractDriveMusicDirectAudioURL(html: String) throws -> String {
    if let downloadTag = html.firstMatch(
      pattern: #"(?s)<a\b[^>]*class=\"[^\"]*\bbtn-download\b[^\"]*\"[^>]*>"#
    )?[safe: 0] {
      let attrs = parseHTMLAttributes(in: downloadTag)
      if let href = attrs["href"], !href.isEmpty {
        return href
      }
    }

    if let buttonTag = html.firstMatch(
      pattern: #"(?s)<button\b[^>]*\bpopular-play__item\b[^>]*>"#
    )?[safe: 0] {
      let attrs = parseHTMLAttributes(in: buttonTag)
      if let dataURL = attrs["data-url"], !dataURL.isEmpty {
        return dataURL
      }
    }

    throw APIClientError.serverError("Could not find DriveMusic audio URL")
  }

  func parseHTMLAttributes(in tagHTML: String) -> [String: String] {
    let attrPattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*\"([^\"]*)\""#
    var result: [String: String] = [:]
    for groups in tagHTML.allMatches(pattern: attrPattern) where groups.count >= 3 {
      result[groups[1]] = groups[2]
    }
    return result
  }

  func parseDurationToSeconds(_ raw: String) -> Int? {
    let clean = raw.collapsingWhitespace()
    let parts = clean.split(separator: ":").compactMap { Int($0) }
    guard !parts.isEmpty else { return nil }

    switch parts.count {
    case 2:
      return (parts[0] * 60) + parts[1]
    case 3:
      return (parts[0] * 3600) + (parts[1] * 60) + parts[2]
    default:
      return nil
    }
  }

  func normalizeDriveMusicPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "/" }

    if let url = URL(string: trimmed), let host = url.host, host.contains("drivemusic.club") {
      var normalized = url.path
      if let query = url.query, !query.isEmpty {
        normalized += "?\(query)"
      }
      return normalized.isEmpty ? "/" : normalized
    }

    if trimmed.hasPrefix("/") {
      return trimmed
    }

    return "/" + trimmed
  }

  func parseDriveMusicHomeFeed(html: String) -> DriveMusicHomeFeed {
    DriveMusicHomeFeed(
      topPlaylists: parseDriveMusicHomeTopPlaylists(html: html),
      topGenres: parseDriveMusicHomeTopGenres(html: html),
      quickLinks: parseDriveMusicHomeQuickLinks(html: html),
      chartSongs: parseDriveMusicHomeChartSongs(html: html)
    )
  }

  func parseDriveMusicHomeTopPlaylists(html: String) -> [DriveMusicBrowseCard] {
    let matches = html.allMatches(
      pattern: #"(?s)<a href=\"(/[^\"]+)\" class=\"carousel-slide\">(.*?)</a>"#
    )

    var items: [DriveMusicBrowseCard] = []
    var seenPaths = Set<String>()

    for groups in matches {
      guard let path = groups[safe: 1], !path.isEmpty, !seenPaths.contains(path) else { continue }
      let innerHTML = groups[safe: 2] ?? ""
      let title = (innerHTML.firstMatch(pattern: #"(?s)<span class=\"carousel-slide__text\">(.*?)</span>"#)?[safe: 1] ?? "")
        .strippingHTMLTags()
        .decodingBasicHTMLEntities()
        .collapsingWhitespace()

      guard !title.isEmpty else { continue }

      let imageRaw =
        innerHTML.firstMatch(pattern: #"<img[^>]*\sdata-src=\"([^\"]+)\""#)?[safe: 1]
        ?? innerHTML.firstMatch(pattern: #"<img[^>]*\ssrc=\"([^\"]+)\""#)?[safe: 1]
      let imageURL = imageRaw.flatMap { buildAbsoluteURL(from: $0, relativeTo: DriveMusicDirectConstants.baseURL) }

      seenPaths.insert(path)
      items.append(
        DriveMusicBrowseCard(
          title: title,
          path: path,
          imageURL: imageURL,
          subtitle: nil
        )
      )
    }

    return items
  }

  func parseDriveMusicHomeTopGenres(html: String) -> [DriveMusicBrowseCard] {
    let matches = html.allMatches(
      pattern: #"(?s)<li class=\"nav-genre__item\">\s*<a href=\"(/[^\"]+)\" class=\"nav-genre-link\">(.*?)</a>\s*</li>"#
    )

    var items: [DriveMusicBrowseCard] = []
    var seenPaths = Set<String>()

    for groups in matches {
      guard let path = groups[safe: 1], !path.isEmpty, !seenPaths.contains(path) else { continue }
      let innerHTML = groups[safe: 2] ?? ""
      let title = innerHTML
        .strippingHTMLTags()
        .decodingBasicHTMLEntities()
        .collapsingWhitespace()

      guard !title.isEmpty else { continue }

      let styleURLRaw = innerHTML.firstMatch(pattern: #"background-image:\s*url\(([^)]+)\)"#)?[safe: 1]
        .map {
          $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
        }
      let imageURL = styleURLRaw.flatMap { buildAbsoluteURL(from: $0, relativeTo: DriveMusicDirectConstants.baseURL) }

      seenPaths.insert(path)
      items.append(
        DriveMusicBrowseCard(
          title: title,
          path: path,
          imageURL: imageURL,
          subtitle: nil
        )
      )
    }

    return items
  }

  func parseDriveMusicHomeQuickLinks(html: String) -> [DriveMusicQuickLink] {
    let matches = html.allMatches(
      pattern: #"(?s)<a href=\"(/[^\"]+)\" class=\"nav-list-link\">\s*.*?</span>\s*(.*?)\s*</a>"#
    )

    var items: [DriveMusicQuickLink] = []
    var seenPaths = Set<String>()

    for groups in matches {
      guard let path = groups[safe: 1], !path.isEmpty, path != "/", !seenPaths.contains(path) else { continue }
      let title = (groups[safe: 2] ?? "")
        .strippingHTMLTags()
        .decodingBasicHTMLEntities()
        .collapsingWhitespace()

      guard !title.isEmpty else { continue }
      seenPaths.insert(path)
      items.append(DriveMusicQuickLink(title: title, path: path))
    }

    return items
  }

  func parseDriveMusicHomeChartSongs(html: String) -> [SongSearchItem] {
    if let chartBlock = html.firstMatch(
      pattern: #"(?s)<div class=\"main-music-popular\">(.*?)<div class=\"main-music-top main-page\">"# 
    )?[safe: 1] {
      return parseDriveMusicSongRows(html: chartBlock)
    }

    return parseDriveMusicSongRows(html: html)
  }

  func parseDriveMusicNextPagePath(html: String, currentPath: String, hasSongs: Bool) -> String? {
    let currentNormalized = normalizeDriveMusicPath(currentPath)

    for groups in html.allMatches(pattern: #"(?is)<a\b[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>"#) {
      guard let rawHref = groups[safe: 1], let rawLabel = groups[safe: 2] else { continue }
      let label = rawLabel
        .strippingHTMLTags()
        .decodingBasicHTMLEntities()
        .collapsingWhitespace()
        .lowercased()

      guard label.contains("далее") || label == "next" || label.contains("next ") else { continue }

      let candidate = normalizeDriveMusicPath(rawHref)
      guard candidate != currentNormalized else { continue }
      return candidate
    }

    guard hasSongs else { return nil }
    return makeDriveMusicNextPagePathFallback(from: currentNormalized)
  }

  func parseDriveMusicSearchNextPagePath(html: String) -> String? {
    for groups in html.allMatches(pattern: #"(?is)<a\b[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>"#) {
      guard let rawHref = groups[safe: 1], let rawLabel = groups[safe: 2] else { continue }
      let label = rawLabel
        .strippingHTMLTags()
        .decodingBasicHTMLEntities()
        .collapsingWhitespace()
        .lowercased()

      guard label.contains("далее") || label == "next" || label.contains("next ") else { continue }

      let normalized = normalizeDriveMusicPath(rawHref)
      if normalized.contains("do=search") || normalized.contains("subaction=search") || normalized.contains("story=") {
        return normalized
      }
    }

    return nil
  }

  func parseDriveMusicArtistSearchCandidates(html: String) -> [(name: String, path: String)] {
    var seenPaths = Set<String>()
    var items: [(name: String, path: String)] = []

    for groups in html.allMatches(pattern: #"(?is)<a\b[^>]*href=\"(/artist/[^\"]+\.html)\"[^>]*>(.*?)</a>"#) {
      guard let rawHref = groups[safe: 1], let rawInner = groups[safe: 2] else { continue }
      let path = normalizeDriveMusicPath(rawHref)
      guard path.hasPrefix("/artist/"), path.hasSuffix(".html"), !seenPaths.contains(path) else { continue }

      let name = rawInner
        .strippingHTMLTags()
        .decodingBasicHTMLEntities()
        .collapsingWhitespace()

      guard !name.isEmpty else { continue }
      seenPaths.insert(path)
      items.append((name: name, path: path))
    }

    return items
  }

  func makeDriveMusicNextPagePathFallback(from path: String) -> String? {
    let cleanPath = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path

    if let pageGroups = cleanPath.firstMatch(pattern: #"^(.*?/page/)(\d+)/?$"#),
       let prefix = pageGroups[safe: 1],
       let pageString = pageGroups[safe: 2],
       let pageNumber = Int(pageString) {
      return "\(prefix)\(pageNumber + 1)/"
    }

    guard cleanPath.hasSuffix("/") else { return nil }
    guard !cleanPath.hasSuffix("/page/") else { return nil }
    guard !cleanPath.contains(".html") else { return nil }

    return "\(cleanPath)page/2/"
  }
}

private extension String {
  func firstMatch(pattern: String) -> [String]? {
    allMatches(pattern: pattern).first
  }

  func allMatches(pattern: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return []
    }

    let nsRange = NSRange(startIndex ..< endIndex, in: self)
    return regex.matches(in: self, options: [], range: nsRange).map { match in
      (0 ..< match.numberOfRanges).map { index in
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: self) else {
          return ""
        }
        return String(self[swiftRange])
      }
    }
  }

  func strippingHTMLTags() -> String {
    replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
  }

  func decodingBasicHTMLEntities() -> String {
    var value = self
    let replacements: [(String, String)] = [
      ("&amp;", "&"),
      ("&quot;", "\""),
      ("&#34;", "\""),
      ("&#39;", "'"),
      ("&#039;", "'"),
      ("&apos;", "'"),
      ("&lt;", "<"),
      ("&gt;", ">"),
      ("&nbsp;", " "),
      ("&laquo;", "«"),
      ("&raquo;", "»"),
    ]

    for (entity, replacement) in replacements {
      value = value.replacingOccurrences(of: entity, with: replacement)
    }

    return value
  }

  func collapsingWhitespace() -> String {
    replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private extension Array where Element == String {
  subscript(safe index: Int) -> String? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}
