import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var player: PlayerEngine
  @State private var selectedTab: Tab = .search
  @State private var isNowPlayingPresented = false

  var body: some View {
    ZStack {
      TabView(selection: $selectedTab) {
        ListenNowPlaceholderView()
          .tabItem {
            Label("Home", systemImage: "house.fill")
          }
          .tag(Tab.home)

        SearchView()
          .tabItem {
            Label("Search", systemImage: "magnifyingglass")
          }
          .tag(Tab.search)

        LibraryPlaceholderView()
          .tabItem {
            Label("Library", systemImage: "music.note.list")
          }
          .tag(Tab.library)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if player.currentTrack != nil {
          MiniPlayerBar(
            isPresented: $isNowPlayingPresented
          )
          .environmentObject(player)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: player.currentTrack?.videoId)
    .sheet(isPresented: $isNowPlayingPresented) {
      NowPlayingView()
        .environmentObject(player)
    }
  }
}

private enum Tab {
  case home
  case search
  case library
}

private struct ListenNowPlaceholderView: View {
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("Listen Now")
            .font(.largeTitle.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)

          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
              LinearGradient(
                colors: [.pink.opacity(0.8), .orange.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(height: 180)
            .overlay(alignment: .bottomLeading) {
              VStack(alignment: .leading, spacing: 6) {
                Text("Native iOS Prototype")
                  .font(.headline.weight(.semibold))
                Text("Search and play from your private YTMusic backend")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .padding(18)
            }

          Text("This tab is a placeholder for a future Apple Music-like home screen.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
    }
  }
}

private struct LibraryPlaceholderView: View {
  var body: some View {
    NavigationStack {
      List {
        Section("Planned") {
          Label("Local Library", systemImage: "music.note.house")
          Label("Playlists", systemImage: "music.note.list")
          Label("Recently Played", systemImage: "clock.arrow.circlepath")
          Label("Downloads", systemImage: "arrow.down.circle")
        }
      }
      .navigationTitle("Library")
    }
  }
}

