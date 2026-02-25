import SwiftUI

@main
struct MusicIOSApp: App {
  @StateObject private var player = PlayerEngine(apiClient: .shared)
  @StateObject private var library = LibraryStore()
  @StateObject private var radio = RadioStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(player)
        .environmentObject(library)
        .environmentObject(radio)
        .tint(.red)
    }
  }
}
