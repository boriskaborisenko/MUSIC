import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
  @Published var query: String = ""
  @Published private(set) var results: [SongSearchItem] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isLoadingMore = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var loadMoreErrorMessage: String?

  private let apiClient: APIClient
  private var nextPagePath: String?
  private var currentQueryKey = ""
  private let paginationPrefetchThreshold = 8
  private let autoLoadSongSoftLimit = 120

  var canLoadMore: Bool {
    nextPagePath != nil
  }

  var isAutoLoadPausedForPerformance: Bool {
    canLoadMore && results.count >= autoLoadSongSoftLimit
  }

  init(apiClient: APIClient = .shared) {
    self.apiClient = apiClient
  }

  func searchDebounced() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      results = []
      errorMessage = nil
      isLoading = false
      isLoadingMore = false
      nextPagePath = nil
      loadMoreErrorMessage = nil
      currentQueryKey = ""
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
      isLoadingMore = false
      nextPagePath = nil
      loadMoreErrorMessage = nil
      currentQueryKey = ""
      return
    }

    currentQueryKey = trimmed.lowercased()
    isLoading = true
    isLoadingMore = false
    errorMessage = nil
    loadMoreErrorMessage = nil
    nextPagePath = nil

    do {
      let batch = try await apiClient.searchSongsBatch(query: trimmed)
      if Task.isCancelled { return }
      if trimmed.lowercased() != currentQueryKey { return }
      results = batch.songs
      nextPagePath = batch.nextPagePath
      isLoading = false
    } catch {
      if Task.isCancelled { return }
      if trimmed.lowercased() != currentQueryKey { return }
      results = []
      isLoading = false
      errorMessage = error.localizedDescription
    }
  }

  func loadMoreIfNeeded(currentSongID: String) async {
    guard !isLoading else { return }
    guard !isLoadingMore else { return }
    guard nextPagePath != nil else { return }
    guard !isAutoLoadPausedForPerformance else { return }

    guard let index = results.firstIndex(where: { $0.id == currentSongID }) else { return }
    let thresholdIndex = max(0, results.count - paginationPrefetchThreshold)
    guard index >= thresholdIndex else { return }

    await loadNextPage()
  }

  func loadNextPage() async {
    guard !isLoading else { return }
    guard !isLoadingMore else { return }
    guard let nextPagePath else { return }

    let queryKey = currentQueryKey
    let normalizedPath = apiClient.canonicalDriveMusicPath(nextPagePath)
    isLoadingMore = true
    loadMoreErrorMessage = nil

    do {
      let batch = try await apiClient.fetchDriveMusicSongsPageBatch(path: normalizedPath)
      if Task.isCancelled { return }
      guard queryKey == currentQueryKey else { return }

      let existingIDs = Set(results.map(\.id))
      let newSongs = batch.songs.filter { !existingIDs.contains($0.id) }
      results.append(contentsOf: newSongs)
      self.nextPagePath = batch.nextPagePath
      isLoadingMore = false
    } catch {
      if Task.isCancelled { return }
      guard queryKey == currentQueryKey else { return }
      loadMoreErrorMessage = error.localizedDescription
      isLoadingMore = false
    }
  }
}
