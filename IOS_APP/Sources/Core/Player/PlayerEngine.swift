import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class PlayerEngine: ObservableObject {
  @Published private(set) var currentTrack: SongSearchItem?
  @Published private(set) var currentResolution: PlaybackResolution?
  @Published private(set) var isLoading = false
  @Published private(set) var isPlaying = false
  @Published private(set) var currentTime: Double = 0
  @Published private(set) var duration: Double = 0
  @Published private(set) var errorMessage: String?

  let apiClient: APIClient

  private let player = AVPlayer()
  private var timeObserver: Any?
  private var playerStatusObservation: NSKeyValueObservation?
  private var itemStatusObservation: NSKeyValueObservation?
  private var itemEndObserver: NSObjectProtocol?
  private var interruptionObserver: NSObjectProtocol?
  private var routeChangeObserver: NSObjectProtocol?

  private var artworkCache = NSCache<NSURL, UIImage>()
  private var currentArtworkImage: UIImage?
  private var currentArtworkURL: URL?

  private var remoteCommandTokens: [(MPRemoteCommand, Any)] = []
  private var didSetupRemoteCommands = false

  init(apiClient: APIClient) {
    self.apiClient = apiClient

    player.automaticallyWaitsToMinimizeStalling = true
    configureAudioSession()
    installPlayerObservers()
    installRemoteCommandsIfNeeded()
    installNotifications()
  }

  deinit {
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
    }

    if let itemEndObserver {
      NotificationCenter.default.removeObserver(itemEndObserver)
    }
    if let interruptionObserver {
      NotificationCenter.default.removeObserver(interruptionObserver)
    }
    if let routeChangeObserver {
      NotificationCenter.default.removeObserver(routeChangeObserver)
    }

    for (command, token) in remoteCommandTokens {
      command.removeTarget(token)
    }
  }

  var hasTrack: Bool {
    currentTrack != nil
  }

  var playbackProgress: Double {
    guard duration > 0 else { return 0 }
    return min(max(currentTime / duration, 0), 1)
  }

  func play(song: SongSearchItem) {
    Task { [weak self] in
      await self?.loadAndPlay(song: song)
    }
  }

  func togglePlayPause() {
    if isPlaying {
      pause()
    } else {
      resume()
    }
  }

  func pause() {
    player.pause()
    isPlaying = false
    updateNowPlayingInfo()
  }

  func resume() {
    player.play()
    isPlaying = true
    updateNowPlayingInfo()
  }

  func seek(to seconds: Double) {
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    player.seek(to: time) { [weak self] _ in
      Task { @MainActor in
        self?.currentTime = seconds
        self?.updateNowPlayingInfo()
      }
    }
  }

  func skipForward(seconds: Double = 15) {
    seek(to: min(currentTime + seconds, max(duration, currentTime + seconds)))
  }

  func skipBackward(seconds: Double = 15) {
    seek(to: max(currentTime - seconds, 0))
  }

  func stop() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    currentTrack = nil
    currentResolution = nil
    isPlaying = false
    isLoading = false
    currentTime = 0
    duration = 0
    currentArtworkImage = nil
    currentArtworkURL = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func loadAndPlay(song: SongSearchItem) async {
    errorMessage = nil
    isLoading = true
    currentTrack = song
    currentResolution = nil
    duration = Double(song.duration ?? 0)
    currentTime = 0

    do {
      let resolution = try await apiClient.resolvePlayback(videoID: song.videoId)
      currentResolution = resolution

      let streamURLString = resolution.proxyUrl ?? resolution.directUrl
      guard let streamURL = apiClient.buildAbsoluteURL(from: streamURLString) else {
        throw APIClientError.invalidURL
      }

      let item = AVPlayerItem(url: streamURL)
      installItemObservers(for: item)
      player.replaceCurrentItem(with: item)

      if let durationSec = resolution.durationSec, durationSec > 0 {
        duration = Double(durationSec)
      }

      player.play()
      isPlaying = true
      isLoading = false

      await loadArtworkIfNeeded(from: song.primaryArtworkURL)
      updateNowPlayingInfo()
    } catch {
      isLoading = false
      isPlaying = false
      errorMessage = error.localizedDescription
      updateNowPlayingInfo()
    }
  }

  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
      try session.setActive(true)
    } catch {
      print("[PlayerEngine] Audio session config failed: \(error.localizedDescription)")
    }
  }

  private func installPlayerObservers() {
    playerStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
      Task { @MainActor in
        guard let self else { return }
        self.isPlaying = player.timeControlStatus == .playing
        self.updateNowPlayingInfo()
      }
    }

    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      Task { @MainActor in
        guard let self else { return }
        self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)

        if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
          self.duration = itemDuration
        }

        self.updateNowPlayingInfo()
      }
    }
  }

  private func installItemObservers(for item: AVPlayerItem) {
    itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      Task { @MainActor in
        guard let self else { return }
        switch item.status {
        case .failed:
          self.isLoading = false
          self.isPlaying = false
          self.errorMessage = item.error?.localizedDescription ?? "Playback failed."
        case .readyToPlay:
          self.isLoading = false
          self.errorMessage = nil
        case .unknown:
          break
        @unknown default:
          break
        }
        self.updateNowPlayingInfo()
      }
    }

    if let itemEndObserver {
      NotificationCenter.default.removeObserver(itemEndObserver)
    }

    itemEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.isPlaying = false
        self.currentTime = self.duration
        self.updateNowPlayingInfo()
      }
    }
  }

  private func installNotifications() {
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        guard let self else { return }
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
          self.pause()
        case .ended:
          if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
              self.resume()
            }
          }
        @unknown default:
          break
        }
      }
    }

    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.updateNowPlayingInfo()
      }
    }
  }

  private func installRemoteCommandsIfNeeded() {
    guard !didSetupRemoteCommands else { return }
    didSetupRemoteCommands = true

    let center = MPRemoteCommandCenter.shared()

    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.changePlaybackPositionCommand.isEnabled = true
    center.skipForwardCommand.isEnabled = true
    center.skipBackwardCommand.isEnabled = true

    center.skipForwardCommand.preferredIntervals = [15]
    center.skipBackwardCommand.preferredIntervals = [15]

    remoteCommandTokens.append((
      center.playCommand,
      center.playCommand.addTarget { [weak self] _ in
        Task { @MainActor in self?.resume() }
        return .success
      }
    ))
    remoteCommandTokens.append((
      center.pauseCommand,
      center.pauseCommand.addTarget { [weak self] _ in
        Task { @MainActor in self?.pause() }
        return .success
      }
    ))
    remoteCommandTokens.append((
      center.togglePlayPauseCommand,
      center.togglePlayPauseCommand.addTarget { [weak self] _ in
        Task { @MainActor in self?.togglePlayPause() }
        return .success
      }
    ))
    remoteCommandTokens.append((
      center.skipForwardCommand,
      center.skipForwardCommand.addTarget { [weak self] event in
        Task { @MainActor in
          let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
          self?.skipForward(seconds: interval)
        }
        return .success
      }
    ))
    remoteCommandTokens.append((
      center.skipBackwardCommand,
      center.skipBackwardCommand.addTarget { [weak self] event in
        Task { @MainActor in
          let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
          self?.skipBackward(seconds: interval)
        }
        return .success
      }
    ))
    remoteCommandTokens.append((
      center.changePlaybackPositionCommand,
      center.changePlaybackPositionCommand.addTarget { [weak self] event in
        Task { @MainActor in
          if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
            self?.seek(to: positionEvent.positionTime)
          }
        }
        return .success
      }
    ))
  }

  private func loadArtworkIfNeeded(from url: URL?) async {
    guard let url else {
      currentArtworkImage = nil
      currentArtworkURL = nil
      return
    }

    if currentArtworkURL == url, currentArtworkImage != nil {
      return
    }

    currentArtworkURL = url

    if let cached = artworkCache.object(forKey: url as NSURL) {
      currentArtworkImage = cached
      return
    }

    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      if let image = UIImage(data: data) {
        artworkCache.setObject(image, forKey: url as NSURL)
        currentArtworkImage = image
      }
    } catch {
      print("[PlayerEngine] Artwork load failed: \(error.localizedDescription)")
    }
  }

  private func updateNowPlayingInfo() {
    guard let track = currentTrack else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: track.name,
      MPMediaItemPropertyArtist: currentResolution?.author ?? track.artistName,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
    ]

    if duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }

    if let albumName = track.albumName {
      info[MPMediaItemPropertyAlbumTitle] = albumName
    }

    if let image = currentArtworkImage {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}
