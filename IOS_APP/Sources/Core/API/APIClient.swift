import Foundation

enum APIClientError: LocalizedError {
  case invalidURL
  case invalidResponse
  case httpError(Int, String)
  case serverError(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid server URL."
    case .invalidResponse:
      return "Unexpected server response."
    case let .httpError(code, message):
      return "HTTP \(code): \(message)"
    case let .serverError(message):
      return message
    }
  }
}

final class APIClient {
  static let shared = APIClient(
    metadataBaseURL: AppConfiguration.metadataBaseURL,
    playbackBaseURL: AppConfiguration.playbackBaseURL
  )

  let metadataBaseURL: URL
  let playbackBaseURL: URL
  private let session: URLSession
  private let decoder: JSONDecoder

  init(metadataBaseURL: URL, playbackBaseURL: URL, session: URLSession = .shared) {
    self.metadataBaseURL = metadataBaseURL
    self.playbackBaseURL = playbackBaseURL
    self.session = session
    self.decoder = JSONDecoder()
  }

  func searchSongs(query: String) async throws -> [SongSearchItem] {
    try await request(
      baseURL: metadataBaseURL,
      path: "/api/search",
      queryItems: [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "type", value: "songs"),
      ]
    )
  }

  func resolvePlayback(videoID: String) async throws -> PlaybackResolution {
    try await request(baseURL: playbackBaseURL, path: "/api/playback/\(videoID)/resolve")
  }

  func buildAbsoluteURL(from rawValue: String, relativeTo baseURL: URL? = nil) -> URL? {
    if let absolute = URL(string: rawValue), absolute.scheme != nil {
      return absolute
    }
    let targetBase = baseURL ?? metadataBaseURL
    return URL(string: rawValue, relativeTo: targetBase)?.absoluteURL
  }

  private func request<T: Decodable>(
    baseURL: URL,
    path: String,
    queryItems: [URLQueryItem] = []
  ) async throws -> T {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
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

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw APIClientError.invalidResponse
    }

    guard (200 ... 299).contains(http.statusCode) else {
      if let envelope = try? decoder.decode(ServerFailureEnvelope.self, from: data),
         let message = envelope.error?.message {
        throw APIClientError.httpError(http.statusCode, message)
      }
      let body = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw APIClientError.httpError(http.statusCode, body)
    }

    let envelope = try decoder.decode(ServerEnvelope<T>.self, from: data)
    if envelope.ok {
      return envelope.data
    }

    throw APIClientError.serverError(envelope.error?.message ?? "Server returned an error.")
  }
}
