import SwiftUI

@main
struct MusicIOSApp: App {
  @StateObject private var player = PlayerEngine(apiClient: .shared)

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(player)
    }
  }
}

