import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
  @Published var query: String = ""
  @Published private(set) var results: [SongSearchItem] = []
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?

  private let apiClient: APIClient

  init(apiClient: APIClient = .shared) {
    self.apiClient = apiClient
  }

  func searchDebounced() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      results = []
      errorMessage = nil
      isLoading = false
      return
    }

    do {
      try await Task.sleep(for: .milliseconds(350))
    } catch {
      return
    }

    if Task.isCancelled { return }
    await searchNow()
  }

  func searchNow() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      results = []
      errorMessage = nil
      isLoading = false
      return
    }

    isLoading = true
    errorMessage = nil

    do {
      let songs = try await apiClient.searchSongs(query: trimmed)
      if Task.isCancelled { return }
      results = songs
      isLoading = false
    } catch {
      if Task.isCancelled { return }
      results = []
      isLoading = false
      errorMessage = error.localizedDescription
    }
  }
}

