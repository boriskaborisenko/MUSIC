import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class PlayerEngine: ObservableObject {
  @Published private(set) var currentTrack: SongSearchItem?
  @Published private(set) var currentResolution: PlaybackResolution?
  @Published private(set) var queue: [SongSearchItem] = []
  @Published private(set) var queueIndex: Int?
  @Published private(set) var isLoading = false
  @Published private(set) var isPlaying = false
  @Published private(set) var currentTime: Double = 0
  @Published private(set) var duration: Double = 0
  @Published private(set) var errorMessage: String?
  @Published private(set) var isRepeatOneEnabled = false

  let apiClient: APIClient

  private let player = AVPlayer()
  private var timeObserver: Any?
  private var playerStatusObservation: NSKeyValueObservation?
  private var itemStatusObservation: NSKeyValueObservation?
  private var itemEndObserver: NSObjectProtocol?
  private var interruptionObserver: NSObjectProtocol?
  private var routeChangeObserver: NSObjectProtocol?
  private var shouldAutoPlayCurrentItem = false
  private var metadataDuration: Double?
  private var lastRadioTLSFallbackSourceURL: URL?
  private var activeSongCacheDownloads = Set<String>()

  private var artworkCache = NSCache<NSURL, UIImage>()
  private var currentArtworkImage: UIImage?
  private var currentArtworkURL: URL?

  private let songCacheDirectoryURL: URL = {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return caches.appendingPathComponent("SongAudioCache", isDirectory: true)
  }()

  private var remoteCommandTokens: [(MPRemoteCommand, Any)] = []
  private var didSetupRemoteCommands = false

  init(apiClient: APIClient) {
    self.apiClient = apiClient

    player.automaticallyWaitsToMinimizeStalling = true
    prepareSongCacheDirectory()
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

  var isRadioPlayback: Bool {
    currentTrack?.type == "radio"
  }

  var currentArtwork: UIImage? {
    currentArtworkImage
  }

  var canPlayNextTrack: Bool {
    guard let queueIndex else { return false }
    return queueIndex + 1 < queue.count
  }

  var canPlayPreviousTrack: Bool {
    guard let queueIndex else { return false }
    return queueIndex > 0
  }

  var upNextTracks: [SongSearchItem] {
    guard let queueIndex else { return [] }
    let startIndex = min(queueIndex + 1, queue.count)
    guard startIndex < queue.count else { return [] }
    return Array(queue[startIndex...])
  }

  var playbackProgress: Double {
    guard duration > 0 else { return 0 }
    return min(max(currentTime / duration, 0), 1)
  }

  func play(song: SongSearchItem) {
    configureQueue([song], currentVideoID: song.videoId)
    Task { [weak self] in
      await self?.loadAndPlay(song: song)
    }
  }

  func play(song: SongSearchItem, queue candidateQueue: [SongSearchItem]) {
    let normalizedQueue = candidateQueue.isEmpty ? [song] : candidateQueue
    configureQueue(normalizedQueue, currentVideoID: song.videoId)
    Task { [weak self] in
      await self?.loadAndPlay(song: song)
    }
  }

  func playRadio(station: RadioStation) {
    guard let streamURL = station.streamURL else {
      errorMessage = "Invalid radio URL."
      return
    }

    let track = makeRadioTrack(from: station)
    configureQueue([track], currentVideoID: track.videoId)

    errorMessage = nil
    isLoading = true
    shouldAutoPlayCurrentItem = true
    currentTrack = track
    currentResolution = nil
    metadataDuration = nil
    lastRadioTLSFallbackSourceURL = nil
    duration = 0
    currentTime = 0
    currentArtworkURL = nil
    currentArtworkImage = station.artworkData.flatMap(UIImage.init(data:))

    let item = AVPlayerItem(url: streamURL)
    installItemObservers(for: item)
    player.replaceCurrentItem(with: item)
    player.play()
    isPlaying = true
    isLoading = false
    updateNowPlayingInfo()
  }

  func togglePlayPause() {
    if isPlaying {
      pause()
    } else {
      resume()
    }
  }

  func toggleRepeatOne() {
    guard !isRadioPlayback else { return }
    isRepeatOneEnabled.toggle()
    updateNowPlayingInfo()
  }

  func pause() {
    shouldAutoPlayCurrentItem = false
    player.pause()
    isPlaying = false
    updateNowPlayingInfo()
  }

  func resume() {
    shouldAutoPlayCurrentItem = true
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

  func playNextTrack() {
    guard let queueIndex, queueIndex + 1 < queue.count else { return }
    let nextIndex = queueIndex + 1
    self.queueIndex = nextIndex
    let nextTrack = queue[nextIndex]
    Task { [weak self] in
      await self?.loadAndPlay(song: nextTrack)
    }
  }

  func playPreviousTrack() {
    // Match native player behavior: restart current track if we're a few seconds in.
    if currentTime > 3 {
      seek(to: 0)
      return
    }

    guard let queueIndex, queueIndex > 0 else {
      seek(to: 0)
      return
    }

    let previousIndex = queueIndex - 1
    self.queueIndex = previousIndex
    let previousTrack = queue[previousIndex]
    Task { [weak self] in
      await self?.loadAndPlay(song: previousTrack)
    }
  }

  func stop() {
    shouldAutoPlayCurrentItem = false
    metadataDuration = nil
    lastRadioTLSFallbackSourceURL = nil
    player.pause()
    player.replaceCurrentItem(with: nil)
    currentTrack = nil
    currentResolution = nil
    queue = []
    queueIndex = nil
    isPlaying = false
    isLoading = false
    currentTime = 0
    duration = 0
    currentArtworkImage = nil
    currentArtworkURL = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    updateRemoteCommandAvailability()
  }

  private func loadAndPlay(song: SongSearchItem) async {
    errorMessage = nil
    isLoading = true
    shouldAutoPlayCurrentItem = true
    lastRadioTLSFallbackSourceURL = nil
    currentTrack = song
    currentResolution = nil
    currentArtworkImage = nil
    currentArtworkURL = nil
    metadataDuration = {
      let raw = Double(song.duration ?? 0)
      return raw > 0 ? raw : nil
    }()
    duration = metadataDuration ?? 0
    currentTime = 0

    do {
      let resolution = try await apiClient.resolvePlayback(videoID: song.videoId)
      currentResolution = resolution

      let streamURLString = resolution.proxyUrl ?? resolution.directUrl
      let streamBaseURL = resolution.proxyUrl != nil ? apiClient.playbackBaseURL : nil
      guard let streamURL = apiClient.buildAbsoluteURL(from: streamURLString, relativeTo: streamBaseURL) else {
        throw APIClientError.invalidURL
      }

      let playbackURL = cachedPlaybackURL(for: song, resolution: resolution, remoteURL: streamURL) ?? streamURL
      let item = AVPlayerItem(url: playbackURL)
      installItemObservers(for: item)
      player.replaceCurrentItem(with: item)

      if let durationSec = resolution.durationSec, durationSec > 0 {
        metadataDuration = Double(durationSec)
        duration = Double(durationSec)
      }

      player.play()
      isPlaying = true
      isLoading = false

      if playbackURL != streamURL {
        print("[PlayerEngine] Playing cached song: \(song.videoId)")
      } else {
        cacheSongAudioIfNeeded(song: song, resolution: resolution, remoteURL: streamURL)
      }

      await loadArtworkIfNeeded(for: song)
      updateNowPlayingInfo()
    } catch {
      shouldAutoPlayCurrentItem = false
      isLoading = false
      isPlaying = false
      errorMessage = error.localizedDescription
      updateNowPlayingInfo()
    }
  }

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    let attempts: [AVAudioSession.CategoryOptions] = [
      // `.allowAirPlay` is not valid with `.playback` and causes OSStatus -50 on device.
      [.allowBluetoothA2DP],
      [],
    ]

    for options in attempts {
      do {
        try session.setCategory(.playback, mode: .default, options: options)
        try session.setActive(true)
        return
      } catch {
        print("[PlayerEngine] Audio session config failed for options \(options): \(error.localizedDescription)")
      }
    }
  }

  private func prepareSongCacheDirectory() {
    do {
      try FileManager.default.createDirectory(
        at: songCacheDirectoryURL,
        withIntermediateDirectories: true
      )
    } catch {
      print("[PlayerEngine] Failed to create song cache dir: \(error.localizedDescription)")
    }
  }

  private func installPlayerObservers() {
    playerStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
      Task { @MainActor in
        guard let self else { return }
        self.isPlaying = player.timeControlStatus == .playing
        if self.isPlaying {
          self.shouldAutoPlayCurrentItem = false
        }
        self.updateNowPlayingInfo()
      }
    }

    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      Task { @MainActor in
        guard let self else { return }
        self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)

        if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
          if self.shouldUsePlayerReportedDuration(itemDuration) {
            self.duration = itemDuration
          }
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
          if self.retryRadioWithHTTPAfterTLSError(from: item) {
            return
          }
          self.shouldAutoPlayCurrentItem = false
          self.isLoading = false
          self.isPlaying = false
          self.errorMessage = item.error?.localizedDescription ?? "Playback failed."
        case .readyToPlay:
          if self.shouldAutoPlayCurrentItem {
            self.player.play()
            self.isPlaying = true
          }
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
        if self.isRepeatOneEnabled, !self.isRadioPlayback, self.currentTrack != nil {
          self.currentTime = 0
          self.isPlaying = true
          self.shouldAutoPlayCurrentItem = true
          self.player.seek(to: .zero) { [weak self] _ in
            Task { @MainActor in
              guard let self else { return }
              self.player.play()
              self.isPlaying = true
              self.updateNowPlayingInfo()
            }
          }
          self.updateNowPlayingInfo()
          return
        }
        if self.canPlayNextTrack {
          self.playNextTrack()
        } else {
          self.isPlaying = false
          self.currentTime = self.duration
          self.updateNowPlayingInfo()
        }
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

  private func retryRadioWithHTTPAfterTLSError(from item: AVPlayerItem) -> Bool {
    guard isRadioPlayback else { return false }
    guard hasTLSError(item.error) else { return false }
    guard let failedAsset = item.asset as? AVURLAsset else { return false }

    let failedURL = failedAsset.url
    guard failedURL.scheme?.lowercased() == "https" else { return false }
    guard lastRadioTLSFallbackSourceURL != failedURL else { return false }

    guard var components = URLComponents(url: failedURL, resolvingAgainstBaseURL: false) else { return false }
    components.scheme = "http"
    guard let fallbackURL = components.url else { return false }

    lastRadioTLSFallbackSourceURL = failedURL

    print("[PlayerEngine] Radio TLS failed for \(failedURL.absoluteString). Retrying over HTTP.")

    errorMessage = nil
    isLoading = true
    isPlaying = false
    shouldAutoPlayCurrentItem = true

    let fallbackItem = AVPlayerItem(url: fallbackURL)
    installItemObservers(for: fallbackItem)
    player.replaceCurrentItem(with: fallbackItem)
    player.play()
    updateNowPlayingInfo()
    return true
  }

  private func cachedPlaybackURL(
    for song: SongSearchItem,
    resolution: PlaybackResolution,
    remoteURL: URL
  ) -> URL? {
    guard let cacheURL = cacheFileURL(for: song, resolution: resolution, remoteURL: remoteURL) else { return nil }
    guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }

    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
      let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
      guard fileSize > 0 else {
        try? FileManager.default.removeItem(at: cacheURL)
        return nil
      }
      return cacheURL
    } catch {
      return nil
    }
  }

  private func cacheSongAudioIfNeeded(
    song: SongSearchItem,
    resolution: PlaybackResolution,
    remoteURL: URL
  ) {
    guard let cacheURL = cacheFileURL(for: song, resolution: resolution, remoteURL: remoteURL) else { return }
    let cacheKey = cacheURL.lastPathComponent

    if FileManager.default.fileExists(atPath: cacheURL.path) {
      return
    }
    if activeSongCacheDownloads.contains(cacheKey) {
      return
    }

    activeSongCacheDownloads.insert(cacheKey)

    let targetDirectory = songCacheDirectoryURL
    let requestURL = remoteURL
    Task(priority: .utility) { [weak self, cacheURL] in
      let fileManager = FileManager.default
      defer {
        self?.activeSongCacheDownloads.remove(cacheKey)
      }

      do {
        guard let scheme = requestURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return }
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let (tempURL, response) = try await URLSession.shared.download(from: requestURL)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
          try? fileManager.removeItem(at: tempURL)
          return
        }

        if fileManager.fileExists(atPath: cacheURL.path) {
          try? fileManager.removeItem(at: tempURL)
          return
        }

        let stagedURL = targetDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("part")
        try? fileManager.removeItem(at: stagedURL)
        try fileManager.moveItem(at: tempURL, to: stagedURL)
        try fileManager.moveItem(at: stagedURL, to: cacheURL)

        print("[PlayerEngine] Cached song audio: \(cacheURL.lastPathComponent)")
      } catch {
        print("[PlayerEngine] Song cache download failed: \(error.localizedDescription)")
      }
    }
  }

  private func cacheFileURL(
    for song: SongSearchItem,
    resolution: PlaybackResolution,
    remoteURL: URL
  ) -> URL? {
    guard let scheme = remoteURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }

    let remoteExt = remoteURL.pathExtension.lowercased()
    if remoteExt == "m3u8" || remoteExt == "m3u" {
      return nil
    }

    let ext = normalizedAudioCacheExtension(resolution: resolution, remoteURL: remoteURL)
    let safeID = song.videoId.map { ch -> Character in
      if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" { return ch }
      return "_"
    }
    let filename = "song_\(String(safeID)).\(ext)"
    return songCacheDirectoryURL.appendingPathComponent(filename)
  }

  private func normalizedAudioCacheExtension(resolution: PlaybackResolution, remoteURL: URL) -> String {
    let remoteExt = remoteURL.pathExtension.lowercased()
    if !remoteExt.isEmpty, remoteExt != "php" {
      return remoteExt
    }

    if let container = resolution.selected.container?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
       !container.isEmpty {
      switch container {
      case "mpeg":
        return "mp3"
      default:
        return container
      }
    }

    if let mime = resolution.selected.mimeType?.lowercased() {
      if mime.contains("mpeg") { return "mp3" }
      if mime.contains("mp4") { return "m4a" }
      if mime.contains("aac") { return "aac" }
      if mime.contains("ogg") { return "ogg" }
    }

    return "audio"
  }

  private func hasTLSError(_ error: Error?) -> Bool {
    guard let error else { return false }

    let tlsCodes: Set<Int> = [
      NSURLErrorSecureConnectionFailed,
      NSURLErrorServerCertificateHasBadDate,
      NSURLErrorServerCertificateUntrusted,
      NSURLErrorServerCertificateHasUnknownRoot,
      NSURLErrorServerCertificateNotYetValid,
      NSURLErrorClientCertificateRejected,
      NSURLErrorClientCertificateRequired,
    ]

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain && tlsCodes.contains(nsError.code) {
      return true
    }

    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error, hasTLSError(underlying) {
      return true
    }

    return false
  }

  private func installRemoteCommandsIfNeeded() {
    guard !didSetupRemoteCommands else { return }
    didSetupRemoteCommands = true

    let center = MPRemoteCommandCenter.shared()

    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.changePlaybackPositionCommand.isEnabled = true
    center.skipForwardCommand.isEnabled = false
    center.skipBackwardCommand.isEnabled = false
    center.nextTrackCommand.isEnabled = false
    center.previousTrackCommand.isEnabled = false

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
    remoteCommandTokens.append((
      center.nextTrackCommand,
      center.nextTrackCommand.addTarget { [weak self] _ in
        Task { @MainActor in
          guard let self, self.canPlayNextTrack else { return }
          self.playNextTrack()
        }
        return .success
      }
    ))
    remoteCommandTokens.append((
      center.previousTrackCommand,
      center.previousTrackCommand.addTarget { [weak self] _ in
        Task { @MainActor in
          self?.playPreviousTrack()
        }
        return .success
      }
    ))

    updateRemoteCommandAvailability()
  }

  private func loadArtworkIfNeeded(for song: SongSearchItem) async {
    let url = song.primaryArtworkURL
    guard let url else {
      currentArtworkImage = await MusicBrainzCoverArtService.shared.artworkImage(for: song)
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
        return
      }
    } catch {
      print("[PlayerEngine] Artwork load failed: \(error.localizedDescription)")
    }

    currentArtworkImage = await MusicBrainzCoverArtService.shared.artworkImage(for: song)
    currentArtworkURL = nil
  }

  private func updateNowPlayingInfo() {
    guard let track = currentTrack else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      updateRemoteCommandAvailability()
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

    if let queueIndex {
      info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queueIndex
      info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count
    }

    if let image = currentArtworkImage {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    updateRemoteCommandAvailability()
  }

  private func configureQueue(_ songs: [SongSearchItem], currentVideoID: String) {
    if songs.isEmpty {
      queue = []
      queueIndex = nil
      updateRemoteCommandAvailability()
      return
    }

    queue = songs
    queueIndex = songs.firstIndex(where: { $0.videoId == currentVideoID }) ?? 0
    updateRemoteCommandAvailability()
  }

  private func updateRemoteCommandAvailability() {
    guard didSetupRemoteCommands else { return }
    let center = MPRemoteCommandCenter.shared()
    center.nextTrackCommand.isEnabled = !isRadioPlayback && canPlayNextTrack
    center.previousTrackCommand.isEnabled = !isRadioPlayback && hasTrack
    center.changePlaybackPositionCommand.isEnabled = !isRadioPlayback && duration > 0
  }

  private func shouldUsePlayerReportedDuration(_ candidate: Double) -> Bool {
    guard candidate.isFinite, candidate > 0 else { return false }

    // Some HTTP progressive streams report obviously broken durations via AVPlayer.
    // Prefer metadata when we have it and only accept small corrections.
    if let metadataDuration, metadataDuration > 0 {
      let tolerance = max(3, metadataDuration * 0.08)
      return abs(candidate - metadataDuration) <= tolerance
    }

    // Without metadata, keep a sane upper bound and ignore absurd durations.
    return candidate < 6 * 60 * 60
  }

  private func makeRadioTrack(from station: RadioStation) -> SongSearchItem {
    SongSearchItem(
      type: "radio",
      videoId: "radio:\(station.id.uuidString)",
      name: station.name,
      artist: ArtistReference(name: "Radio", artistId: nil),
      album: nil,
      duration: nil,
      thumbnails: []
    )
  }
}

@MainActor
final class MusicBrainzCoverArtService {
  static let shared = MusicBrainzCoverArtService()

  private enum CacheEntry {
    case image(UIImage)
    case miss
  }

  private enum CandidateKind: Hashable {
    case release
    case releaseGroup
  }

  private struct Candidate: Hashable {
    let kind: CandidateKind
    let id: String
    let score: Int
  }

  private struct RecordingSearchResponse: Decodable {
    let recordings: [Recording]?
  }

  private struct FlexibleInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let intValue = try? container.decode(Int.self) {
        value = intValue
        return
      }
      if let stringValue = try? container.decode(String.self),
         let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
        value = intValue
        return
      }
      throw DecodingError.typeMismatch(
        Int.self,
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected int or numeric string")
      )
    }
  }

  private struct Recording: Decodable {
    let title: String?
    let score: FlexibleInt?
    let releases: [Release]?
    let artistCredit: [ArtistCredit]?

    enum CodingKeys: String, CodingKey {
      case title
      case score
      case releases
      case artistCredit = "artist-credit"
    }
  }

  private struct Release: Decodable {
    let id: String
    let title: String?
    let status: String?
    let releaseGroup: ReleaseGroup?

    enum CodingKeys: String, CodingKey {
      case id
      case title
      case status
      case releaseGroup = "release-group"
    }
  }

  private struct ReleaseGroup: Decodable {
    let id: String?
  }

  private struct ArtistCredit: Decodable {
    let name: String?
    let artist: Artist?
  }

  private struct Artist: Decodable {
    let name: String?
  }

  private struct ITunesSearchResponse: Decodable {
    let results: [ITunesTrackResult]
  }

  private struct ITunesTrackResult: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?
  }

  private var cache: [String: CacheEntry] = [:]
  private var inFlight: [String: Task<UIImage?, Never>] = [:]
  private var nextMusicBrainzRequestAt: Date = .distantPast

  private let session = URLSession.shared
  private let decoder = JSONDecoder()

  private init() {}

  func artworkImage(for song: SongSearchItem) async -> UIImage? {
    let key = cacheKey(for: song)
    guard !key.isEmpty else { return nil }

    if let entry = cache[key] {
      switch entry {
      case let .image(image):
        return image
      case .miss:
        return nil
      }
    }

    if let task = inFlight[key] {
      return await task.value
    }

    let task = Task<UIImage?, Never> { [song] in
      await self.resolveArtworkImage(for: song)
    }
    inFlight[key] = task

    let image = await task.value
    inFlight[key] = nil
    cache[key] = image.map(CacheEntry.image) ?? .miss
    return image
  }

  private func resolveArtworkImage(for song: SongSearchItem) async -> UIImage? {
    guard song.type.lowercased() != "radio" else { return nil }

    if let image = await fetchITunesArtwork(for: song) {
      return image
    }

    do {
      let candidates = try await searchCandidates(for: song)
      guard !candidates.isEmpty else { return nil }
      return await fetchFirstAvailableCover(from: candidates)
    } catch {
      print("[MusicBrainzCoverArt] Lookup failed: \(error.localizedDescription)")
      return nil
    }
  }

  private func fetchITunesArtwork(for song: SongSearchItem) async -> UIImage? {
    let title = song.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let artist = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
    let album = song.albumName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !title.isEmpty, !artist.isEmpty else { return nil }

    guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
    let termParts = [artist, title, album].filter { !$0.isEmpty }
    components.queryItems = [
      URLQueryItem(name: "term", value: termParts.joined(separator: " ")),
      URLQueryItem(name: "entity", value: "song"),
      URLQueryItem(name: "media", value: "music"),
      URLQueryItem(name: "limit", value: "8"),
      URLQueryItem(name: "country", value: "US"),
    ]
    guard let url = components.url else { return nil }

    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 12
      request.setValue("Musicous/1.0 (iOS app; artwork fallback)", forHTTPHeaderField: "User-Agent")

      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return nil }

      let payload = try decoder.decode(ITunesSearchResponse.self, from: data)
      guard !payload.results.isEmpty else { return nil }

      let targetTitle = normalizedForMatch(title)
      let targetArtist = normalizedForMatch(artist)
      let targetAlbum = normalizedForMatch(album)

      let bestURL = payload.results
        .compactMap { result -> (URL, Int)? in
          guard let rawArtwork = result.artworkUrl100,
                let imageURL = upgradedITunesArtworkURL(from: rawArtwork)
          else { return nil }

          let resultTitle = normalizedForMatch(result.trackName ?? "")
          let resultArtist = normalizedForMatch(result.artistName ?? "")
          let resultAlbum = normalizedForMatch(result.collectionName ?? "")

          var score = 0
          if !targetTitle.isEmpty {
            if resultTitle == targetTitle {
              score += 50
            } else if resultTitle.contains(targetTitle) || targetTitle.contains(resultTitle) {
              score += 18
            }
          }
          if !targetArtist.isEmpty {
            if resultArtist == targetArtist {
              score += 40
            } else if resultArtist.contains(targetArtist) || targetArtist.contains(resultArtist) {
              score += 14
            }
          }
          if !targetAlbum.isEmpty {
            if resultAlbum == targetAlbum {
              score += 28
            } else if resultAlbum.contains(targetAlbum) || targetAlbum.contains(resultAlbum) {
              score += 10
            }
          }

          return (imageURL, score)
        }
        .sorted { lhs, rhs in
          if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
          return lhs.0.absoluteString < rhs.0.absoluteString
        }
        .first?
        .0

      guard let bestURL else { return nil }

      let (imageData, imageResponse) = try await session.data(from: bestURL)
      guard let imageHTTP = imageResponse as? HTTPURLResponse,
            (200 ... 299).contains(imageHTTP.statusCode),
            let image = UIImage(data: imageData)
      else {
        return nil
      }

      return image
    } catch {
      return nil
    }
  }

  private func upgradedITunesArtworkURL(from rawValue: String) -> URL? {
    let upgraded = rawValue
      .replacingOccurrences(of: "100x100bb", with: "600x600bb")
      .replacingOccurrences(of: "100x100-75", with: "600x600-75")
    return URL(string: upgraded)
  }

  private func searchCandidates(for song: SongSearchItem) async throws -> [Candidate] {
    let title = song.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let artist = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
    let album = song.albumName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !title.isEmpty, !artist.isEmpty else { return [] }

    guard var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording") else {
      return []
    }

    var queryParts = [
      #"recording:"\#(escapeMusicBrainzQueryValue(title))""#,
      #"artist:"\#(escapeMusicBrainzQueryValue(artist))""#,
    ]
    if !album.isEmpty {
      queryParts.append(#"release:"\#(escapeMusicBrainzQueryValue(album))""#)
    }

    components.queryItems = [
      URLQueryItem(name: "fmt", value: "json"),
      URLQueryItem(name: "limit", value: "6"),
      URLQueryItem(name: "query", value: queryParts.joined(separator: " AND ")),
    ]

    guard let url = components.url else { return [] }

    await waitForMusicBrainzRateLimit()

    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Musicous/1.0 (iOS app; Cover Art fallback)", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
      return []
    }

    let payload: RecordingSearchResponse
    do {
      payload = try decoder.decode(RecordingSearchResponse.self, from: data)
    } catch {
      let snippet = String(data: data.prefix(240), encoding: .utf8) ?? "<non-utf8>"
      print("[MusicBrainzCoverArt] Decode failed: \(error.localizedDescription). Body: \(snippet)")
      throw error
    }
    let recordings = payload.recordings ?? []
    guard !recordings.isEmpty else { return [] }

    let targetTitle = normalizedForMatch(title)
    let targetArtist = normalizedForMatch(artist)
    let targetAlbum = normalizedForMatch(album)

    var ranked: [Candidate] = []
    var seen = Set<String>()

    for recording in recordings {
      let recordingTitle = normalizedForMatch(recording.title ?? "")
      let recordingArtist = normalizedForMatch(joinedArtistCredit(recording.artistCredit))
      let baseScore = recording.score?.value ?? 0

      var recordingScore = baseScore
      if !targetTitle.isEmpty {
        if recordingTitle == targetTitle {
          recordingScore += 40
        } else if recordingTitle.contains(targetTitle) || targetTitle.contains(recordingTitle) {
          recordingScore += 14
        }
      }
      if !targetArtist.isEmpty {
        if recordingArtist == targetArtist {
          recordingScore += 28
        } else if recordingArtist.contains(targetArtist) || targetArtist.contains(recordingArtist) {
          recordingScore += 10
        }
      }

      for release in recording.releases ?? [] {
        let releaseTitle = normalizedForMatch(release.title ?? "")
        var score = recordingScore
        if !targetAlbum.isEmpty {
          if releaseTitle == targetAlbum {
            score += 35
          } else if releaseTitle.contains(targetAlbum) || targetAlbum.contains(releaseTitle) {
            score += 12
          }
        }
        if (release.status ?? "").lowercased() == "official" {
          score += 5
        }

        let releaseKey = "r:\(release.id)"
        if seen.insert(releaseKey).inserted {
          ranked.append(Candidate(kind: .release, id: release.id, score: score))
        }

        if let releaseGroupID = release.releaseGroup?.id, !releaseGroupID.isEmpty {
          let rgKey = "g:\(releaseGroupID)"
          if seen.insert(rgKey).inserted {
            ranked.append(Candidate(kind: .releaseGroup, id: releaseGroupID, score: score - 2))
          }
        }
      }
    }

    return ranked
      .sorted { lhs, rhs in
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.id < rhs.id
      }
      .prefix(10)
      .map { $0 }
  }

  private func fetchFirstAvailableCover(from candidates: [Candidate]) async -> UIImage? {
    for candidate in candidates {
      guard let imageURL = coverArtURL(for: candidate, size: 500) else { continue }
      do {
        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 15
        request.setValue("Musicous/1.0 (iOS app; Cover Art fallback)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              let image = UIImage(data: data)
        else {
          continue
        }
        return image
      } catch {
        continue
      }
    }
    return nil
  }

  private func coverArtURL(for candidate: Candidate, size: Int) -> URL? {
    let base: String
    switch candidate.kind {
    case .release:
      base = "https://coverartarchive.org/release/\(candidate.id)"
    case .releaseGroup:
      base = "https://coverartarchive.org/release-group/\(candidate.id)"
    }
    return URL(string: "\(base)/front-\(size)")
  }

  private func waitForMusicBrainzRateLimit() async {
    let now = Date()
    if nextMusicBrainzRequestAt > now {
      let delay = nextMusicBrainzRequestAt.timeIntervalSince(now)
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
    }
    nextMusicBrainzRequestAt = Date().addingTimeInterval(1.1)
  }

  private func cacheKey(for song: SongSearchItem) -> String {
    let title = normalizedForMatch(song.name)
    let artist = normalizedForMatch(song.artistName)
    let album = normalizedForMatch(song.albumName ?? "")
    let key = "\(artist)|\(title)|\(album)"
    return key.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func joinedArtistCredit(_ credits: [ArtistCredit]?) -> String {
    collapseWhitespace((credits ?? [])
      .compactMap { $0.artist?.name ?? $0.name }
      .joined(separator: " ")
    )
  }

  private func escapeMusicBrainzQueryValue(_ raw: String) -> String {
    collapseWhitespace(raw
      .replacingOccurrences(of: "\"", with: " ")
      .replacingOccurrences(of: "\\", with: " ")
    )
  }

  private func normalizedForMatch(_ raw: String) -> String {
    let lower = raw.lowercased()
    let withoutParens = lower.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
    let noFeat = withoutParens.replacingOccurrences(
      of: #"\b(feat|ft)\.?\b.*$"#,
      with: " ",
      options: .regularExpression
    )
    let filteredScalars = noFeat.unicodeScalars.map { scalar -> Unicode.Scalar in
      CharacterSet.alphanumerics.contains(scalar) || scalar == " " ? scalar : " "
    }
    return collapseWhitespace(String(String.UnicodeScalarView(filteredScalars)))
  }

  private func collapseWhitespace(_ raw: String) -> String {
    raw
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
