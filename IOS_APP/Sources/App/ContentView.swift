import SwiftUI
import Combine

struct ContentView: View {
  @EnvironmentObject private var player: PlayerEngine
  @EnvironmentObject private var library: LibraryStore
  @State private var selectedTab: Tab = .home
  @State private var isNowPlayingPresented = false
  @State private var isKeyboardVisible = false
  @State private var showStartupSplash = true
  @State private var didStartStartupSplash = false
  private let floatingTabBarClearance: CGFloat = 84
  private let systemTabBarOffset: CGFloat = 54

  init() {
    // iOS 26 has a system split search tab. Older versions use our custom floating bar.
    #if os(iOS)
    if #available(iOS 26, *) {
      UITabBar.appearance().isHidden = false
    } else {
      UITabBar.appearance().isHidden = true
    }
    UITabBar.appearance().tintColor = .systemRed
    #endif
  }

  private var usesSystemSplitTabBar: Bool {
    if #available(iOS 26, *) {
      return true
    }
    return false
  }

  private var miniPlayerContentInset: CGFloat {
    player.isRadioPlayback ? 82 : 96
  }

  private var miniPlayerTabBarOffset: CGFloat {
    usesSystemSplitTabBar ? systemTabBarOffset : (floatingTabBarClearance + 6)
  }

  private var shouldShowMiniPlayer: Bool {
    guard player.currentTrack != nil else { return false }
    if selectedTab == .search, isKeyboardVisible {
      return false
    }
    return true
  }

  var body: some View {
    rootTabView
    .safeAreaInset(edge: .bottom) {
      if !usesSystemSplitTabBar {
        Color.clear
          .frame(height: floatingTabBarClearance)
          .allowsHitTesting(false)
      }
    }
    .safeAreaInset(edge: .bottom) {
      Color.clear
        .frame(height: shouldShowMiniPlayer ? miniPlayerContentInset : 0)
        .allowsHitTesting(false)
    }
    .overlay(alignment: .bottom) {
      if !usesSystemSplitTabBar {
        FloatingSplitTabBar(selectedTab: $selectedTab)
          .padding(.horizontal, 12)
          .padding(.bottom, 8)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .overlay(alignment: .bottom) {
      if shouldShowMiniPlayer {
        MiniPlayerBar(
          isPresented: $isNowPlayingPresented
        )
        .environmentObject(player)
        .padding(.horizontal, 12)
        .offset(y: -miniPlayerTabBarOffset)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .overlay {
      if showStartupSplash {
        StartupSplashOverlay()
          .transition(.opacity)
          .zIndex(20)
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: player.currentTrack?.videoId)
    .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isKeyboardVisible)
    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: selectedTab)
    .onAppear {
      startStartupSplashIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      isKeyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      isKeyboardVisible = false
    }
    .sheet(isPresented: $isNowPlayingPresented) {
      NowPlayingView()
        .environmentObject(player)
        .environmentObject(library)
        .presentationDetents([.fraction(0.94)])
        .presentationDragIndicator(.visible)
    }
  }

  @ViewBuilder
  private var rootTabView: some View {
    if #available(iOS 26, *) {
      TabView(selection: $selectedTab) {
        SwiftUI.Tab("Home", systemImage: "house.fill", value: Tab.home) {
          HomeView(selectedTab: $selectedTab)
        }

        SwiftUI.Tab("Collection", systemImage: "heart.fill", value: Tab.collection) {
          CollectionLibraryView()
        }

        SwiftUI.Tab("Playlists", systemImage: "music.note.list", value: Tab.playlists) {
          PlaylistsLibraryView()
        }

        SwiftUI.Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: Tab.radio) {
          RadioView()
        }

        SwiftUI.Tab(value: Tab.search, role: .search) {
          SearchView()
        } label: {
          Label("Search", systemImage: "magnifyingglass")
        }
      }
      .tint(.red)
    } else {
      TabView(selection: $selectedTab) {
        HomeView(selectedTab: $selectedTab)
          .tabItem {
            Label("Home", systemImage: "house.fill")
          }
          .tag(Tab.home)

        SearchView()
          .tabItem {
            Label("Search", systemImage: "magnifyingglass")
          }
          .tag(Tab.search)

        CollectionLibraryView()
          .tabItem {
            Label("Collection", systemImage: "heart.fill")
          }
          .tag(Tab.collection)

        PlaylistsLibraryView()
          .tabItem {
            Label("Playlists", systemImage: "music.note.list")
          }
          .tag(Tab.playlists)

        RadioView()
          .tabItem {
            Label("Radio", systemImage: "dot.radiowaves.left.and.right")
          }
          .tag(Tab.radio)
      }
      .toolbar(.hidden, for: .tabBar)
      .toolbarBackground(.hidden, for: .tabBar)
    }
  }

  private func startStartupSplashIfNeeded() {
    guard !didStartStartupSplash else { return }
    didStartStartupSplash = true

    Task {
      try? await Task.sleep(for: .milliseconds(900))
      if Task.isCancelled { return }
      await MainActor.run {
        withAnimation(.easeOut(duration: 0.2)) {
          showStartupSplash = false
        }
      }
    }
  }
}

private enum Tab {
  case home
  case search
  case radio
  case collection
  case playlists

  var title: String {
    switch self {
    case .home: "Home"
    case .search: "Search"
    case .radio: "Radio"
    case .collection: "Collection"
    case .playlists: "Playlists"
    }
  }

  var icon: String {
    switch self {
    case .home: "house.fill"
    case .search: "magnifyingglass"
    case .radio: "dot.radiowaves.left.and.right"
    case .collection: "heart.fill"
    case .playlists: "music.note.list"
    }
  }
}

private struct FloatingSplitTabBar: View {
  @Binding var selectedTab: Tab

  private let mainTabs: [Tab] = [.home, .collection, .playlists, .radio]
  private let barHeight: CGFloat = 68
  private let searchButtonSize: CGFloat = 68

  var body: some View {
    HStack(spacing: 10) {
      HStack(spacing: 6) {
        ForEach(mainTabs, id: \.self) { tab in
          Button {
            selectedTab = tab
          } label: {
            VStack(spacing: 4) {
              Image(systemName: tab.icon)
                .font(.system(size: 18, weight: .semibold))
              Text(tab.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
              .foregroundStyle(selectedTab == tab ? Color.red : .primary)
            .background {
              if selectedTab == tab {
                Capsule(style: .continuous)
                  .fill(Color.primary.opacity(0.09))
              }
            }
            .contentShape(Capsule(style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 8)
      .frame(height: barHeight)
      .frame(maxWidth: .infinity)
      .background(.ultraThinMaterial, in: Capsule(style: .continuous))
      .overlay {
        Capsule(style: .continuous)
          .strokeBorder(.white.opacity(0.10))
      }
      .shadow(color: .black.opacity(0.14), radius: 16, y: 8)

      Button {
        selectedTab = .search
      } label: {
        Image(systemName: Tab.search.icon)
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(selectedTab == .search ? Color.red : .primary)
          .frame(width: searchButtonSize, height: searchButtonSize)
          .background(
            Circle()
              .fill(selectedTab == .search ? Color.primary.opacity(0.09) : Color.clear)
          )
      }
      .buttonStyle(.plain)
      .background(.ultraThinMaterial, in: Circle())
      .overlay {
        Circle()
          .strokeBorder(.white.opacity(0.10))
      }
      .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
      .accessibilityLabel("Search")
    }
  }
}

private struct StartupSplashOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Color("LaunchBackground")
        .ignoresSafeArea()

      VStack(spacing: 12) {
        ProgressView()
          .controlSize(.large)
          .scaleEffect(1.15)
          .tint(.primary)

        if !reduceMotion {
          Text("Loading")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
      }
    }
    .allowsHitTesting(true)
    .accessibilityHidden(true)
  }
}

private struct HomeView: View {
  @EnvironmentObject private var player: PlayerEngine
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var radio: RadioStore

  @Binding var selectedTab: Tab

  @StateObject private var viewModel = HomeViewModel()

  private var driveMusicCollectionSongs: [SongSearchItem] {
    library.collectionSongs.filter(isDriveMusicSong)
  }

  private var homePlaylistsWithDriveMusic: [LibraryStore.LibraryPlaylist] {
    library.playlists.filter { playlist in
      playlist.songs.contains(where: isDriveMusicSong)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          homeHeroSection

          if viewModel.isLoadingHomeFeed, viewModel.homeFeed == nil {
            HomeCard {
              HStack(spacing: 10) {
                ProgressView()
                Text("Loading DriveMusic…")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 8)
            }
          }

          if let message = viewModel.homeFeedErrorMessage, viewModel.homeFeed == nil {
            HomeCard {
              VStack(alignment: .leading, spacing: 8) {
                Text("Couldn’t load DriveMusic home")
                  .font(.subheadline.weight(.semibold))
                Text(message)
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                Button("Retry") {
                  Task {
                    await viewModel.refreshAll()
                  }
                }
                .buttonStyle(.bordered)
              }
            }
          }

          if let feed = viewModel.homeFeed {
            if !feed.topPlaylists.isEmpty {
              topPlaylistsSection(feed)
            }
            if !feed.topGenres.isEmpty {
              topGenresSection(feed)
            }
            if !curatedBrowseLinks.isEmpty || !feed.quickLinks.isEmpty {
              quickLinksSection(feed)
            }
            if !feed.chartSongs.filter(isDriveMusicSong).isEmpty {
              chartSection(feed)
            }
          }

          if !radio.stations.isEmpty {
            radioSection
          }

          if !driveMusicCollectionSongs.isEmpty {
            collectionSection
          }

          if !homePlaylistsWithDriveMusic.isEmpty {
            playlistsSection
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 120)
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Home")
      .navigationBarTitleDisplayMode(.large)
      .task {
        await viewModel.loadAllIfNeeded()
      }
      .refreshable {
        await viewModel.refreshAll()
      }
    }
  }

  private var homeHeroSection: some View {
    HomeCard {
      VStack(alignment: .leading, spacing: 8) {
        Text("Discover")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)

        Text("DriveMusic Home")
          .font(.title2.weight(.bold))

        Text("Playlists, genres, chart, and your library in one place.")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        HStack(spacing: 10) {
          Button {
            selectedTab = .search
          } label: {
            Label("Search", systemImage: "magnifyingglass")
          }
          .buttonStyle(.borderedProminent)

          NavigationLink {
            DriveMusicSongsPageView(title: "Chart", path: "/hits_top40.html")
          } label: {
            Label("Open Chart", systemImage: "chart.bar.fill")
          }
          .buttonStyle(.bordered)
        }
        .padding(.top, 2)
      }
    }
  }

  private func topPlaylistsSection(_ feed: DriveMusicHomeFeed) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Top Playlists")
        .font(.headline)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(Array(feed.topPlaylists.prefix(12))) { item in
            NavigationLink {
              DriveMusicSongsPageView(title: item.title, path: item.path)
            } label: {
              HomeBrowseCard(
                title: item.title,
                subtitle: item.subtitle,
                imageURL: item.imageURL,
                size: CGSize(width: 166, height: 166)
              )
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  private func topGenresSection(_ feed: DriveMusicHomeFeed) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Top Genres")
        .font(.headline)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(Array(feed.topGenres.prefix(12))) { item in
            NavigationLink {
              DriveMusicSongsPageView(title: item.title, path: item.path)
            } label: {
              HomeBrowseCard(
                title: item.title,
                subtitle: nil,
                imageURL: nil,
                size: CGSize(width: 126, height: 126),
                backgroundStyle: .gradient(seed: item.title)
              )
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  private func quickLinksSection(_ feed: DriveMusicHomeFeed) -> some View {
    let items = curatedBrowseLinks.isEmpty ? Array(feed.quickLinks.prefix(12)) : curatedBrowseLinks

    return VStack(alignment: .leading, spacing: 10) {
      Text("Browse")
        .font(.headline)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(items) { item in
            NavigationLink {
              DriveMusicSongsPageView(title: item.title, path: item.path)
            } label: {
              Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                  Capsule(style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                )
                .overlay {
                  Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private var curatedBrowseLinks: [DriveMusicQuickLink] {
    [
      DriveMusicQuickLink(title: "New Releases", path: "/zarubezhnye_novinki/"),
      DriveMusicQuickLink(title: "Rock", path: "/rock_music/"),
      DriveMusicQuickLink(title: "Indie", path: "/indie/"),
      DriveMusicQuickLink(title: "Road Trip", path: "/road_rock/")
    ]
  }

  private func chartSection(_ feed: DriveMusicHomeFeed) -> some View {
    let songs = Array(feed.chartSongs.filter(isDriveMusicSong).prefix(6))

    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("DriveMusic Chart")
          .font(.headline)
        Spacer()
        NavigationLink("All") {
          DriveMusicSongsPageView(title: "DriveMusic Chart", path: "/hits_top40.html")
        }
        .font(.subheadline.weight(.medium))
      }

      HomeCard {
        VStack(spacing: 0) {
          ForEach(Array(songs.enumerated()), id: \.element.id) { row in
            let index = row.offset
            let song = row.element

            SongRowView(
              song: song,
              isPlaying: player.currentTrack?.videoId == song.videoId && player.isPlaying
            ) {
              player.play(song: song, queue: feed.chartSongs.filter(isDriveMusicSong))
            }
            .padding(.vertical, 6)

            if index < songs.count - 1 {
              Divider()
            }
          }
        }
      }
    }
  }

  private var newReleasesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HomeSectionHeader(
        title: "New Releases",
        trailingTitle: "Refresh"
      ) {
        Task {
          await viewModel.refreshNews()
        }
      }

      HomeCard {
        VStack(alignment: .leading, spacing: 10) {
          newsCategoryTabs

          if viewModel.isLoadingNews && viewModel.newsSongs.isEmpty {
            HStack(spacing: 10) {
              ProgressView()
              Text("Loading new releases…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 18)
          } else if let error = viewModel.newsErrorMessage, viewModel.newsSongs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              Text("Couldn’t load new releases")
                .font(.subheadline.weight(.semibold))
              Text(error)
                .font(.footnote)
                .foregroundStyle(.secondary)
              Button("Retry") {
                Task {
                  await viewModel.refreshNews()
                }
              }
              .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
          } else if viewModel.newsSongs.isEmpty {
            Text("Nothing here yet")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 18)
          } else {
            songTileRail(
              songs: Array(viewModel.newsSongs.filter(isDriveMusicSong).prefix(12)),
              fullQueue: viewModel.newsSongs.filter(isDriveMusicSong)
            )
          }
        }
      }
    }
  }

  private var newsCategoryTabs: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 18) {
        ForEach(DriveMusicNewsCategory.allCases, id: \.self) { category in
          Button {
            viewModel.setNewsCategory(category)
          } label: {
            VStack(alignment: .leading, spacing: 5) {
              Text(category.title)
                .font(.subheadline.weight(viewModel.selectedNewsCategory == category ? .semibold : .regular))
                .foregroundStyle(viewModel.selectedNewsCategory == category ? .primary : .secondary)

              Capsule()
                .fill(viewModel.selectedNewsCategory == category ? Color.orange : .clear)
                .frame(height: 2)
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.top, 2)
    }
  }

  private var radioSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HomeSectionHeader(title: "Your Radio", trailingTitle: "All") {
        selectedTab = .radio
      }

      HomeCard {
        VStack(spacing: 0) {
          let stations = Array(radio.stations.prefix(6))
          ForEach(Array(stations.enumerated()), id: \.element.id) { row in
            let index = row.offset
            let station = row.element

            HomeRadioRow(
              station: station,
              isPlaying: player.currentTrack?.videoId == "radio:\(station.id.uuidString)" && player.isPlaying
            ) {
              player.playRadio(station: station)
            }
            .padding(.vertical, 6)

            if index < stations.count - 1 {
              Divider()
            }
          }
        }
      }
    }
  }

  private var collectionSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HomeSectionHeader(title: "Recently Added", trailingTitle: "All") {
        selectedTab = .collection
      }

      HomeCard {
        VStack(spacing: 0) {
          let songs = Array(driveMusicCollectionSongs.prefix(6))
          ForEach(Array(songs.enumerated()), id: \.element.id) { row in
            let index = row.offset
            let song = row.element

            SongRowView(
              song: song,
              isPlaying: player.currentTrack?.videoId == song.videoId && player.isPlaying
            ) {
              player.play(song: song, queue: driveMusicCollectionSongs)
            }
            .padding(.vertical, 6)

            if index < songs.count - 1 {
              Divider()
            }
          }
        }
      }
    }
  }

  private var playlistsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HomeSectionHeader(title: "Playlists", trailingTitle: "All") {
        selectedTab = .playlists
      }

      HomeCard {
        VStack(spacing: 0) {
          let playlists = Array(homePlaylistsWithDriveMusic.prefix(4))
          ForEach(Array(playlists.enumerated()), id: \.element.id) { row in
            let index = row.offset
            let playlist = row.element
            let supportedSongCount = playlist.songs.filter(isDriveMusicSong).count
            Button {
              selectedTab = .playlists
            } label: {
              HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .fill(Color(.secondarySystemBackground))
                  .frame(width: 44, height: 44)
                  .overlay {
                    Image(systemName: "music.note.list")
                      .foregroundStyle(.secondary)
                  }

                VStack(alignment: .leading, spacing: 3) {
                  Text(playlist.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                  Text("\(supportedSongCount) songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.tertiary)
              }
              .padding(.vertical, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if index < playlists.count - 1 {
              Divider()
            }
          }
        }
      }
    }
  }

  private func songTileRail(songs: [SongSearchItem], fullQueue: [SongSearchItem]) -> some View {
    let columns = chunkedForTwoRowRail(songs)

    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 12) {
        ForEach(Array(columns.enumerated()), id: \.offset) { column in
          VStack(spacing: 12) {
            ForEach(column.element) { song in
              HomeSongTile(
                song: song,
                isPlaying: player.currentTrack?.videoId == song.videoId && player.isPlaying
              ) {
                player.play(song: song, queue: fullQueue)
              }
            }

            if column.element.count == 1 {
              Color.clear
                .frame(width: HomeSongTile.tileSize, height: HomeSongTile.tileSize)
            }
          }
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func chunkedForTwoRowRail(_ songs: [SongSearchItem]) -> [[SongSearchItem]] {
    guard !songs.isEmpty else { return [] }
    var result: [[SongSearchItem]] = []
    var index = 0
    while index < songs.count {
      let end = min(index + 2, songs.count)
      result.append(Array(songs[index ..< end]))
      index = end
    }
    return result
  }

  private func isDriveMusicSong(_ song: SongSearchItem) -> Bool {
    song.videoId.hasPrefix("dm:")
  }
}

@MainActor
private final class HomeViewModel: ObservableObject {
  @Published var selectedNewsCategory: DriveMusicNewsCategory = .international
  @Published private(set) var homeFeed: DriveMusicHomeFeed?
  @Published private(set) var isLoadingHomeFeed = false
  @Published private(set) var homeFeedErrorMessage: String?
  @Published private(set) var newsSongs: [SongSearchItem] = []
  @Published private(set) var isLoadingNews = false
  @Published private(set) var newsErrorMessage: String?

  private let apiClient: APIClient
  private var homeFeedCache: DriveMusicHomeFeed?
  private var newsCache: [DriveMusicNewsCategory: [SongSearchItem]] = [:]

  init(apiClient: APIClient = .shared) {
    self.apiClient = apiClient
  }

  func setNewsCategory(_ category: DriveMusicNewsCategory) {
    guard selectedNewsCategory != category else { return }
    selectedNewsCategory = category
    newsErrorMessage = nil

    if let cached = newsCache[category] {
      newsSongs = cached
    } else {
      newsSongs = []
    }
  }

  func loadNewsIfNeeded() async {
    await loadNews(force: false)
  }

  func loadAllIfNeeded() async {
    await loadHomeFeed(force: false)
  }

  func refreshAll() async {
    await loadHomeFeed(force: true)
  }

  func refreshNews() async {
    await loadNews(force: true)
  }

  private func loadHomeFeed(force: Bool) async {
    if !force, let cached = homeFeedCache {
      homeFeed = cached
      homeFeedErrorMessage = nil
      isLoadingHomeFeed = false
      return
    }

    isLoadingHomeFeed = true
    if force {
      homeFeedErrorMessage = nil
    }

    do {
      let feed = try await apiClient.fetchDriveMusicHomeFeed()
      if Task.isCancelled { return }
      homeFeedCache = feed
      homeFeed = feed
      homeFeedErrorMessage = nil
      isLoadingHomeFeed = false
    } catch {
      if Task.isCancelled { return }
      if homeFeed == nil {
        homeFeedErrorMessage = error.localizedDescription
      }
      isLoadingHomeFeed = false
    }
  }

  private func loadNews(force: Bool) async {
    let category = selectedNewsCategory

    if !force, let cached = newsCache[category], !cached.isEmpty {
      newsSongs = cached
      newsErrorMessage = nil
      isLoadingNews = false
      return
    }

    isLoadingNews = true
    if force {
      newsErrorMessage = nil
    }

    do {
      let songs = try await apiClient.fetchDriveMusicNews(category: category)
      if Task.isCancelled { return }
      newsCache[category] = songs

      guard selectedNewsCategory == category else { return }
      newsSongs = songs
      newsErrorMessage = nil
      isLoadingNews = false
    } catch {
      if Task.isCancelled { return }
      guard selectedNewsCategory == category else { return }
      if newsSongs.isEmpty {
        newsErrorMessage = error.localizedDescription
      }
      isLoadingNews = false
    }
  }
}

private struct HomeSectionHeader: View {
  let title: String
  var trailingTitle: String?
  var action: (() -> Void)?

  init(title: String, trailingTitle: String? = nil, action: (() -> Void)? = nil) {
    self.title = title
    self.trailingTitle = trailingTitle
    self.action = action
  }

  var body: some View {
    HStack {
      Text(title)
        .font(.headline)
      Spacer()
      if let trailingTitle, let action {
        Button(trailingTitle, action: action)
          .font(.subheadline.weight(.medium))
      }
    }
  }
}

private struct HomeSongTile: View {
  static let tileSize: CGFloat = 152

  let song: SongSearchItem
  let isPlaying: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .bottomLeading) {
        artwork
          .frame(width: Self.tileSize, height: Self.tileSize)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        LinearGradient(
          colors: [.clear, .black.opacity(0.12), .black.opacity(0.72)],
          startPoint: .top,
          endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            if isPlaying {
              Image(systemName: "speaker.wave.2.fill")
                .font(.caption2.weight(.semibold))
            }
            if let duration = song.duration {
              Text(DurationFormatter.mmss(duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
            }
          }

          Text(song.name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)

          Text(song.artistName)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(1)
        }
        .padding(10)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(.white.opacity(0.08), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var artwork: some View {
    if let url = song.primaryArtworkURL {
      CachedRemoteImage(url: url) { phase in
        switch phase {
        case let .success(image):
          image.resizable().scaledToFill()
        case .empty:
          ZStack {
            placeholder
            ProgressView()
              .controlSize(.small)
          }
        case .failure:
          placeholder
        @unknown default:
          placeholder
        }
      }
    } else {
      placeholder
    }
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
      .fill(
        LinearGradient(
          colors: [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay {
        Image(systemName: "music.note")
          .font(.title3.weight(.medium))
          .foregroundStyle(.secondary)
      }
  }
}

private struct HomeCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
    }
  }
}

private struct HomeRadioRow: View {
  let station: RadioStation
  let isPlaying: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        artwork
          .frame(width: 52, height: 52)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        VStack(alignment: .leading, spacing: 4) {
          Text(station.name)
            .font(.body.weight(isPlaying ? .semibold : .regular))
            .foregroundStyle(isPlaying ? .red : .primary)
            .lineLimit(1)

          Text("Radio")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer(minLength: 12)

        if isPlaying {
          Image(systemName: "speaker.wave.2.fill")
            .foregroundStyle(.red)
            .font(.subheadline.weight(.semibold))
        } else {
          Image(systemName: "dot.radiowaves.left.and.right")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var artwork: some View {
    if let data = station.artworkData, let image = UIImage(data: data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .overlay {
          Image(systemName: "dot.radiowaves.left.and.right")
            .foregroundStyle(.secondary)
        }
    }
  }
}

private struct HomeRadioCard: View {
  let station: RadioStation
  let isPlaying: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .bottomLeading) {
        artwork
          .frame(maxWidth: .infinity)
          .aspectRatio(1, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        LinearGradient(
          colors: [.clear, .black.opacity(0.5)],
          startPoint: .top,
          endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        HStack(spacing: 6) {
          if isPlaying {
            Image(systemName: "speaker.wave.2.fill")
              .font(.caption.weight(.semibold))
          }

          Text(station.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(10)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(.white.opacity(0.08), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var artwork: some View {
    if let data = station.artworkData, let image = UIImage(data: data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(.secondarySystemBackground))
        Image(systemName: "dot.radiowaves.left.and.right")
          .font(.system(size: 24, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct HomeBrowseCard: View {
  enum BackgroundStyle: Hashable {
    case image
    case gradient(seed: String)
  }

  let title: String
  let subtitle: String?
  let imageURL: URL?
  let size: CGSize
  let backgroundStyle: BackgroundStyle

  init(
    title: String,
    subtitle: String?,
    imageURL: URL?,
    size: CGSize,
    backgroundStyle: BackgroundStyle = .image
  ) {
    self.title = title
    self.subtitle = subtitle
    self.imageURL = imageURL
    self.size = size
    self.backgroundStyle = backgroundStyle
  }

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      artwork
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

      LinearGradient(
        colors: [.clear, .black.opacity(0.18), .black.opacity(0.72)],
        startPoint: .top,
        endPoint: .bottom
      )
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

      VStack(alignment: .leading, spacing: 2) {
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(1)
        }

        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(2)
      }
      .padding(10)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
    }
  }

  @ViewBuilder
  private var artwork: some View {
    if case let .gradient(seed) = backgroundStyle {
      gradientArtwork(seed: seed)
    } else if let imageURL {
      CachedRemoteImage(url: imageURL) { phase in
        switch phase {
        case let .success(image):
          image.resizable().scaledToFill()
        case .empty:
          ZStack {
            placeholder
            ProgressView()
              .controlSize(.small)
          }
        case .failure:
          placeholder
        @unknown default:
          placeholder
        }
      }
    } else {
      placeholder
    }
  }

  private func gradientArtwork(seed: String) -> some View {
    let palette = genreGradientPalette(for: seed)
    let useDiagonal = (abs(seed.hashValue) % 2) == 0

    return RoundedRectangle(cornerRadius: 16, style: .continuous)
      .fill(
        LinearGradient(
          colors: palette,
          startPoint: useDiagonal ? .topLeading : .leading,
          endPoint: useDiagonal ? .bottomTrailing : .trailing
        )
      )
      .overlay {
        RadialGradient(
          colors: [.white.opacity(0.22), .clear],
          center: .topLeading,
          startRadius: 4,
          endRadius: 90
        )
      }
  }

  private func genreGradientPalette(for seed: String) -> [Color] {
    let palettes: [[Color]] = [
      [Color(red: 0.11, green: 0.23, blue: 0.52), Color(red: 0.32, green: 0.62, blue: 0.97)],
      [Color(red: 0.20, green: 0.13, blue: 0.45), Color(red: 0.62, green: 0.31, blue: 0.93)],
      [Color(red: 0.08, green: 0.35, blue: 0.28), Color(red: 0.29, green: 0.76, blue: 0.53)],
      [Color(red: 0.47, green: 0.16, blue: 0.15), Color(red: 0.93, green: 0.42, blue: 0.28)],
      [Color(red: 0.31, green: 0.21, blue: 0.07), Color(red: 0.93, green: 0.67, blue: 0.20)],
      [Color(red: 0.12, green: 0.28, blue: 0.36), Color(red: 0.24, green: 0.73, blue: 0.78)],
      [Color(red: 0.33, green: 0.12, blue: 0.34), Color(red: 0.93, green: 0.34, blue: 0.61)],
      [Color(red: 0.12, green: 0.16, blue: 0.24), Color(red: 0.36, green: 0.46, blue: 0.69)]
    ]

    let scalarSum = seed.unicodeScalars.reduce(into: 0) { partialResult, scalar in
      partialResult = partialResult &+ Int(scalar.value)
    }
    let index = abs(scalarSum) % palettes.count
    return palettes[index]
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
      .fill(
        LinearGradient(
          colors: [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay {
        Image(systemName: "music.note.list")
          .font(.title3.weight(.medium))
          .foregroundStyle(.secondary)
      }
  }
}

struct DriveMusicSongsPageView: View {
  @EnvironmentObject private var player: PlayerEngine

  let title: String
  let path: String

  @StateObject private var viewModel: DriveMusicSongsPageViewModel
  @State private var didAttemptScrollRestore = false

  init(title: String, path: String) {
    self.title = title
    self.path = path
    _viewModel = StateObject(wrappedValue: DriveMusicSongsPageViewModel(path: path))
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if viewModel.isLoading, viewModel.songs.isEmpty {
            HomeCard {
              HStack(spacing: 10) {
                ProgressView()
                Text("Loading tracks…")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 8)
            }
          }

          if let error = viewModel.errorMessage, viewModel.songs.isEmpty {
            HomeCard {
              VStack(alignment: .leading, spacing: 8) {
                Text("Couldn’t load page")
                  .font(.subheadline.weight(.semibold))
                Text(error)
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                Button("Retry") {
                  Task {
                    await viewModel.refresh()
                    await restoreScrollIfNeeded(proxy: proxy)
                  }
                }
                .buttonStyle(.bordered)
              }
            }
          }

          if !viewModel.songs.isEmpty {
            HomeCard {
              VStack(spacing: 0) {
                ForEach(Array(viewModel.songs.enumerated()), id: \.element.id) { row in
                  let index = row.offset
                  let song = row.element

                  SongRowView(
                    song: song,
                    isPlaying: player.currentTrack?.videoId == song.videoId && player.isPlaying
                  ) {
                    player.play(song: song, queue: viewModel.songs)
                  }
                  .id(song.id)
                  .padding(.vertical, 6)
                  .onAppear {
                    viewModel.noteVisibleSong(song.id)
                    Task {
                      await viewModel.loadMoreIfNeeded(currentSongID: song.id)
                    }
                  }

                  if index < viewModel.songs.count - 1 {
                    Divider()
                  }
                }

                if viewModel.isLoadingMore {
                  Divider()
                  HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading more tracks…")
                      .font(.subheadline)
                      .foregroundStyle(.secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .center)
                  .padding(.vertical, 12)
                } else if let loadMoreError = viewModel.loadMoreErrorMessage {
                  Divider()
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
                  .padding(.vertical, 10)
                } else if viewModel.isAutoLoadPausedForPerformance, viewModel.canLoadMore {
                  Divider()
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
                  .padding(.vertical, 10)
                }
              }
            }
          } else if !viewModel.isLoading, viewModel.errorMessage == nil {
            HomeCard {
              Text("No tracks found on this page yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 120)
      }
      .background(Color(.systemGroupedBackground))
      .task {
        await viewModel.loadIfNeeded()
        await restoreScrollIfNeeded(proxy: proxy)
      }
      .onChange(of: viewModel.songs.count) { _, _ in
        Task {
          await restoreScrollIfNeeded(proxy: proxy)
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .refreshable {
      await viewModel.refresh()
      didAttemptScrollRestore = false
    }
  }

  private func restoreScrollIfNeeded(proxy: ScrollViewProxy) async {
    guard !didAttemptScrollRestore else { return }
    guard let targetSongID = viewModel.scrollRestoreSongID else { return }

    didAttemptScrollRestore = true
    try? await Task.sleep(for: .milliseconds(120))
    withAnimation(.easeInOut(duration: 0.2)) {
      proxy.scrollTo(targetSongID, anchor: .top)
    }
  }
}

@MainActor
private final class DriveMusicSongsPageViewModel: ObservableObject {
  private struct CachedState {
    var songs: [SongSearchItem]
    var nextPagePath: String?
    var loadedPagePaths: Set<String>
    var lastVisibleSongID: String?
  }

  private static var cacheByPath: [String: CachedState] = [:]

  @Published private(set) var songs: [SongSearchItem] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isLoadingMore = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var loadMoreErrorMessage: String?

  private let path: String
  private let apiClient: APIClient
  private let cacheKey: String
  private let paginationPrefetchThreshold = 8
  private let autoLoadSongSoftLimit = 120
  private var hasLoaded = false
  private var nextPagePath: String?
  private var loadedPagePaths = Set<String>()
  private var lastVisibleSongID: String?

  var canLoadMore: Bool {
    nextPagePath != nil
  }

  var isAutoLoadPausedForPerformance: Bool {
    canLoadMore && songs.count >= autoLoadSongSoftLimit
  }

  var scrollRestoreSongID: String? {
    lastVisibleSongID
  }

  init(path: String, apiClient: APIClient = .shared) {
    self.path = path
    self.apiClient = apiClient
    cacheKey = apiClient.canonicalDriveMusicPath(path)

    if let cached = Self.cacheByPath[cacheKey] {
      songs = cached.songs
      nextPagePath = cached.nextPagePath
      loadedPagePaths = cached.loadedPagePaths
      lastVisibleSongID = cached.lastVisibleSongID
      hasLoaded = !cached.songs.isEmpty || !cached.loadedPagePaths.isEmpty
    }
  }

  func loadIfNeeded() async {
    guard !hasLoaded else { return }
    await load(force: false)
  }

  func refresh() async {
    await load(force: true)
  }

  func noteVisibleSong(_ songID: String) {
    guard songs.contains(where: { $0.id == songID }) else { return }
    lastVisibleSongID = songID
    persistCache()
  }

  func loadMoreIfNeeded(currentSongID: String) async {
    guard hasLoaded else { return }
    guard !isLoading else { return }
    guard !isLoadingMore else { return }
    guard nextPagePath != nil else { return }
    guard !isAutoLoadPausedForPerformance else { return }

    guard let index = songs.firstIndex(where: { $0.id == currentSongID }) else { return }
    let thresholdIndex = max(0, songs.count - paginationPrefetchThreshold)
    guard index >= thresholdIndex else { return }

    await loadNextPage()
  }

  func loadNextPage() async {
    guard !isLoading else { return }
    guard !isLoadingMore else { return }
    guard let nextPagePath else { return }

    let normalized = apiClient.canonicalDriveMusicPath(nextPagePath)
    guard !loadedPagePaths.contains(normalized) else {
      self.nextPagePath = nil
      persistCache()
      return
    }

    isLoadingMore = true
    loadMoreErrorMessage = nil

    do {
      let batch = try await apiClient.fetchDriveMusicSongsPageBatch(path: normalized)
      if Task.isCancelled { return }

      let existingIDs = Set(songs.map(\.id))
      let newSongs = batch.songs
        .filter { $0.videoId.hasPrefix("dm:") }
        .filter { !existingIDs.contains($0.id) }

      songs.append(contentsOf: newSongs)
      loadedPagePaths.insert(normalized)
      self.nextPagePath = batch.nextPagePath
      persistCache()
      isLoadingMore = false
    } catch {
      if Task.isCancelled { return }
      loadMoreErrorMessage = error.localizedDescription
      isLoadingMore = false
    }
  }

  private func load(force: Bool) async {
    if force {
      hasLoaded = false
      nextPagePath = nil
      loadedPagePaths = []
      loadMoreErrorMessage = nil
      lastVisibleSongID = nil
      Self.cacheByPath.removeValue(forKey: cacheKey)
    }

    guard !isLoading else { return }
    isLoading = true
    if force || songs.isEmpty {
      errorMessage = nil
    }

    do {
      let normalizedPath = apiClient.canonicalDriveMusicPath(path)
      let batch = try await apiClient.fetchDriveMusicSongsPageBatch(path: normalizedPath)
      if Task.isCancelled { return }
      songs = batch.songs.filter { $0.videoId.hasPrefix("dm:") }
      nextPagePath = batch.nextPagePath
      loadedPagePaths = [normalizedPath]
      if let existingVisible = lastVisibleSongID, songs.contains(where: { $0.id == existingVisible }) {
        lastVisibleSongID = existingVisible
      } else {
        lastVisibleSongID = songs.first?.id
      }
      loadMoreErrorMessage = nil
      errorMessage = nil
      hasLoaded = true
      persistCache()
      isLoading = false
    } catch {
      if Task.isCancelled { return }
      if songs.isEmpty {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }

  private func persistCache() {
    Self.cacheByPath[cacheKey] = CachedState(
      songs: songs,
      nextPagePath: nextPagePath,
      loadedPagePaths: loadedPagePaths,
      lastVisibleSongID: lastVisibleSongID
    )
  }
}
