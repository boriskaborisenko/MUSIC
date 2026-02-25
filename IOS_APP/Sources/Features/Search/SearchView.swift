import SwiftUI
import UIKit

struct SearchView: View {
  @EnvironmentObject private var player: PlayerEngine
  @EnvironmentObject private var library: LibraryStore
  @AppStorage("music_ios_quick_searches_v1") private var quickSearchesStorage = "[]"
  @StateObject private var viewModel = SearchViewModel()
  @State private var playlistPickerSong: SongSearchItem?
  @State private var isQuickSearchSheetPresented = false
  @State private var quickSearchDraft = ""

  private var quickSearches: [String] {
    decodeQuickSearches(from: quickSearchesStorage)
  }

  private var searchListBottomClearance: CGFloat {
    guard player.currentTrack != nil else { return 0 }
    return player.isRadioPlayback ? 122 : 138
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          SearchEmptyState(
            quickSearches: quickSearches,
            onTapQuickSearch: applyQuickSearch,
            onDeleteQuickSearch: deleteQuickSearch,
            bottomClearance: searchListBottomClearance
          )
        } else if viewModel.isLoading && viewModel.results.isEmpty {
          loadingState
        } else if let errorMessage = viewModel.errorMessage, viewModel.results.isEmpty {
          errorState(message: errorMessage)
        } else {
          resultsList
        }
      }
      .navigationTitle("Search")
      .searchable(
        text: $viewModel.query,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Songs, artists..."
      )
      .task(id: viewModel.query) {
        await viewModel.searchDebounced()
      }
      .onSubmit(of: .search) {
        Task {
          await viewModel.searchNow()
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            presentQuickSearchSheet(prefill: viewModel.query)
          } label: {
            Image(systemName: "plus.circle")
          }
          .accessibilityLabel("Add quick search")
        }
      }
      .overlay(alignment: .bottom) {
        if let error = player.errorMessage, player.currentTrack != nil {
          Text(error)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.red.opacity(0.9), in: Capsule())
            .padding(.bottom, 10)
          .transition(.opacity)
        }
      }
      .sheet(isPresented: $isQuickSearchSheetPresented) {
        quickSearchSheet
      }
      .sheet(item: $playlistPickerSong) { song in
        PlaylistPickerSheet(song: song)
          .environmentObject(library)
      }
    }
  }

  private var loadingState: some View {
    VStack(spacing: 14) {
      ProgressView()
      Text("Searching songs…")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
    .safeAreaInset(edge: .bottom) {
      Color.clear.frame(height: searchListBottomClearance)
    }
  }

  private func errorState(message: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "wifi.exclamationmark")
        .font(.system(size: 28, weight: .semibold))
      Text("Couldn’t Load Results")
        .font(.headline)
      Text(message)
        .multilineTextAlignment(.center)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
    .safeAreaInset(edge: .bottom) {
      Color.clear.frame(height: searchListBottomClearance)
    }
  }

  private var resultsList: some View {
    List {
      Section("Songs") {
        ForEach(viewModel.results) { song in
          SongRowView(song: song, isPlaying: player.currentTrack?.videoId == song.videoId && player.isPlaying) {
            playSongImmediately(song)
          }
          .onAppear {
            Task {
              await viewModel.loadMoreIfNeeded(currentSongID: song.id)
            }
          }
          .contextMenu {
            libraryActions(for: song)
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
              playlistPickerSong = song
            } label: {
              Label("Playlist", systemImage: "text.badge.plus")
            }
            .tint(.red)

            Button {
              _ = library.toggleCollection(song)
            } label: {
              Label(
                library.isInCollection(song) ? "Remove" : "Collect",
                systemImage: library.isInCollection(song) ? "heart.slash" : "heart.fill"
              )
            }
            .tint(library.isInCollection(song) ? .gray : .pink)
          }
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }

        if viewModel.isLoadingMore {
          HStack(spacing: 10) {
            ProgressView()
            Text("Loading more results…")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 8)
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } else if let loadMoreError = viewModel.loadMoreErrorMessage {
          VStack(spacing: 8) {
            Text(loadMoreError)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            Button("Load more") {
              Task {
                await viewModel.loadNextPage()
              }
            }
            .buttonStyle(.bordered)
          }
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 8)
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } else if viewModel.isAutoLoadPausedForPerformance, viewModel.canLoadMore {
          VStack(spacing: 8) {
            Text("Auto-loading paused to keep scrolling smooth.")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            Button("Load more") {
              Task {
                await viewModel.loadNextPage()
              }
            }
            .buttonStyle(.bordered)
          }
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 8)
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }

        if searchListBottomClearance > 0 {
          Color.clear
            .frame(height: searchListBottomClearance)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }
    }
    .listStyle(.insetGrouped)
    .scrollDismissesKeyboard(.immediately)
  }

  @ViewBuilder
  private func libraryActions(for song: SongSearchItem) -> some View {
    Button {
      _ = library.toggleCollection(song)
    } label: {
      Label(
        library.isInCollection(song) ? "Remove from Collection" : "Add to Collection",
        systemImage: library.isInCollection(song) ? "heart.slash" : "heart"
      )
    }

    Button {
      playlistPickerSong = song
    } label: {
      Label("Add to Playlist", systemImage: "text.badge.plus")
    }
  }

  private func playSongImmediately(_ song: SongSearchItem) {
    // Helps avoid the search field keeping focus and swallowing the first tap on device.
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    player.play(song: song, queue: viewModel.results)
  }

  private func presentQuickSearchSheet(prefill rawValue: String) {
    quickSearchDraft = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    isQuickSearchSheetPresented = true
  }

  private func applyQuickSearch(_ rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    viewModel.query = trimmed
  }

  private func saveQuickSearchDraft() {
    let trimmed = quickSearchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    var updated = quickSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
    updated.insert(trimmed, at: 0)
    updated = Array(updated.prefix(16))
    quickSearchesStorage = encodeQuickSearches(updated)
    isQuickSearchSheetPresented = false
  }

  private func deleteQuickSearch(_ rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let updated = quickSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
    quickSearchesStorage = encodeQuickSearches(updated)
  }

  private var quickSearchSheet: some View {
    NavigationStack {
      Form {
        Section("Quick Search") {
          TextField("Type anything", text: $quickSearchDraft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      }
      .navigationTitle("Add Quick Search")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            isQuickSearchSheetPresented = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            saveQuickSearchDraft()
          }
          .disabled(quickSearchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.height(220)])
  }
}

private struct SearchEmptyState: View {
  let quickSearches: [String]
  let onTapQuickSearch: (String) -> Void
  let onDeleteQuickSearch: (String) -> Void
  let bottomClearance: CGFloat

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Quick Search")
            .font(.headline)

          if quickSearches.isEmpty {
            Text("Save your favorite queries here for one-tap search.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          } else {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(quickSearches, id: \.self) { query in
                HStack(spacing: 10) {
                  Button {
                    onTapQuickSearch(query)
                  } label: {
                    Text(query)
                      .font(.subheadline)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .buttonStyle(.plain)

                  Button {
                    onDeleteQuickSearch(query)
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .font(.subheadline)
                      .foregroundStyle(.tertiary)
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("Delete quick search \(query)")
                }
                .contextMenu {
                  Button(role: .destructive) {
                    onDeleteQuickSearch(query)
                  } label: {
                    Label("Delete", systemImage: "trash")
                  }
                }
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .scrollDismissesKeyboard(.immediately)
    .safeAreaInset(edge: .bottom) {
      Color.clear.frame(height: bottomClearance)
    }
  }
}

private func decodeQuickSearches(from rawValue: String) -> [String] {
  guard let data = rawValue.data(using: .utf8) else { return [] }
  guard let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }

  var seen = Set<String>()
  var result: [String] = []

  for item in decoded {
    let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }

    let key = trimmed.lowercased()
    guard seen.insert(key).inserted else { continue }
    result.append(trimmed)
  }

  return result
}

private func encodeQuickSearches(_ values: [String]) -> String {
  guard let data = try? JSONEncoder().encode(values),
        let rawValue = String(data: data, encoding: .utf8) else {
    return "[]"
  }
  return rawValue
}
