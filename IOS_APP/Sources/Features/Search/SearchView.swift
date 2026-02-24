import SwiftUI

struct SearchView: View {
  @EnvironmentObject private var player: PlayerEngine
  @StateObject private var viewModel = SearchViewModel()

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          SearchEmptyState()
        } else if viewModel.isLoading && viewModel.results.isEmpty {
          loadingState
        } else if let errorMessage = viewModel.errorMessage, viewModel.results.isEmpty {
          errorState(message: errorMessage)
        } else {
          resultsList
        }
      }
      .navigationTitle("Search")
      .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always))
      .task(id: viewModel.query) {
        await viewModel.searchDebounced()
      }
      .onSubmit(of: .search) {
        Task {
          await viewModel.searchNow()
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
  }

  private var resultsList: some View {
    List {
      if viewModel.isLoading {
        Section {
          HStack(spacing: 12) {
            ProgressView()
            Text("Refreshing results…")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
      }

      Section("Songs") {
        ForEach(viewModel.results) { song in
          SongRowView(song: song, isPlaying: player.currentTrack?.videoId == song.videoId && player.isPlaying) {
            player.play(song: song)
          }
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
      }
    }
    .listStyle(.insetGrouped)
  }
}

private struct SearchEmptyState: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Search")
          .font(.largeTitle.weight(.bold))

        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(
            LinearGradient(
              colors: [.red.opacity(0.85), .orange.opacity(0.75)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(height: 190)
          .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
              Text("Audio-first")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.85))
              Text("Find tracks and play instantly from your private server")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            }
            .padding(18)
          }

        VStack(alignment: .leading, spacing: 8) {
          Text("Try")
            .font(.headline)
          Text("Daft Punk, Justice, Röyksopp, Radiohead")
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .background(Color(.systemGroupedBackground))
  }
}

