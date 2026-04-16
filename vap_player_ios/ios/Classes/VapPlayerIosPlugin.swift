import Flutter
import CryptoKit
import Foundation
import QGVAPlayer
import UIKit

public final class VapPlayerIosPlugin: NSObject, FlutterPlugin, VapHostApi {
  private var registrar: FlutterPluginRegistrar?
  private var eventApi: VapEventApi?
  private var resourceApi: VapResourceApi?
  private var platformViews: [Int64: VapPlayerPlatformView] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VapPlayerIosPlugin(registrar: registrar)
    VapHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.register(
      VapPlayerPlatformViewFactory(plugin: instance, registrar: registrar),
      withId: VapPlayerPlatformView.viewType
    )
  }

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    self.eventApi = VapEventApi(binaryMessenger: registrar.messenger())
    self.resourceApi = VapResourceApi(binaryMessenger: registrar.messenger())
    super.init()
  }

  deinit {
    if let messenger = registrar?.messenger() {
      VapHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    }
  }

  fileprivate func registerPlatformView(_ view: VapPlayerPlatformView) {
    platformViews[view.viewId] = view
  }

  fileprivate func removePlatformView(viewId: Int64) {
    platformViews.removeValue(forKey: viewId)
  }

  func play(request: VapPlayRequestMessage) throws {
    guard let viewId = request.viewId else {
      throw PigeonError(code: "invalid-args", message: "play requires a non-null viewId", details: nil)
    }
    try requireView(viewId: viewId).play(request: request)
  }

  func stop(viewId: Int64) throws {
    try requireView(viewId: viewId).stop()
  }

  func setMute(viewId: Int64, mute: Bool) throws {
    try requireView(viewId: viewId).setMute(mute)
  }

  func setContentMode(viewId: Int64, mode: VapContentModeMessage) throws {
    try requireView(viewId: viewId).setContentMode(mode)
  }

  func setFrameEventsEnabled(viewId: Int64, enabled: Bool) throws {
    try requireView(viewId: viewId).setFrameEventsEnabled(enabled)
  }

  func dispose(viewId: Int64) throws {
    let view = try requireView(viewId: viewId)
    view.release()
    removePlatformView(viewId: viewId)
  }

  func getNetworkCacheSizeBytes(completion: @escaping (Result<Int64, Error>) -> Void) {
    completion(.success(VapNetworkCacheUtils.networkCacheSizeBytes()))
  }

  func clearNetworkCache() throws {
    try VapNetworkCacheUtils.clearNetworkCache()
  }

  func pruneNetworkCacheToBytes(maxBytes: Int64) throws {
    if maxBytes < 0 {
      throw PigeonError(
        code: "invalid-args",
        message: "pruneNetworkCacheToBytes requires maxBytes >= 0",
        details: nil
      )
    }
    try VapNetworkCacheUtils.pruneNetworkCacheToBytes(maxBytes: maxBytes, protectedFileURL: nil)
  }

  func getNetworkAutoEvictionMaxBytes(completion: @escaping (Result<Int64, Error>) -> Void) {
    completion(.success(VapNetworkCacheUtils.autoEvictionMaxBytes()))
  }

  func setNetworkAutoEvictionMaxBytes(maxBytes: Int64) throws {
    if maxBytes < 0 {
      throw PigeonError(
        code: "invalid-args",
        message: "setNetworkAutoEvictionMaxBytes requires maxBytes >= 0",
        details: nil
      )
    }
    VapNetworkCacheUtils.setAutoEvictionMaxBytes(maxBytes)
  }

  private func requireView(viewId: Int64) throws -> VapPlayerPlatformView {
    guard let view = platformViews[viewId] else {
      throw PigeonError(code: "not-found", message: "No VapView found for viewId=\(viewId)", details: nil)
    }
    return view
  }

  fileprivate func resolverApis() -> (VapEventApi, VapResourceApi, FlutterPluginRegistrar) {
    guard let eventApi, let resourceApi, let registrar else {
      fatalError("Plugin is not fully initialized")
    }
    return (eventApi, resourceApi, registrar)
  }
}

final class VapPlayerPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: VapPlayerIosPlugin?

  init(plugin: VapPlayerIosPlugin, registrar: FlutterPluginRegistrar) {
    self.plugin = plugin
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    guard let plugin else {
      fatalError("VapPlayerIosPlugin has been released.")
    }
    let (eventApi, resourceApi, registrar) = plugin.resolverApis()
    let platformView = VapPlayerPlatformView(
      frame: frame,
      viewId: viewId,
      eventApi: eventApi,
      resourceApi: resourceApi,
      registrar: registrar,
      onDisposed: { [weak plugin] id in
        plugin?.removePlatformView(viewId: id)
      }
    )
    plugin.registerPlatformView(platformView)
    return platformView
  }
}

final class VapPlayerPlatformView: NSObject, FlutterPlatformView, VAPWrapViewDelegate {
  static let viewType = "vap_player/view"

  let viewId: Int64

  private let wrapView: QGVAPWrapView
  private let eventApi: VapEventApi
  private let resourceApi: VapResourceApi
  private let registrar: FlutterPluginRegistrar
  private let onDisposed: (Int64) -> Void

  private var tagValues: [String: String] = [:]
  private var frameEventsEnabled = false
  private var playbackRequestToken: Int64 = 0
  private var activeDownloadTask: URLSessionDownloadTask?
  private var activeDownloadDelegate: VapBoundedDownloadTaskDelegate?
  private let playbackRequestLock = NSLock()
  private var released = false

  init(
    frame: CGRect,
    viewId: Int64,
    eventApi: VapEventApi,
    resourceApi: VapResourceApi,
    registrar: FlutterPluginRegistrar,
    onDisposed: @escaping (Int64) -> Void
  ) {
    self.viewId = viewId
    self.eventApi = eventApi
    self.resourceApi = resourceApi
    self.registrar = registrar
    self.onDisposed = onDisposed
    self.wrapView = QGVAPWrapView(frame: frame)

    super.init()

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.wrapView.contentMode = .scaleToFill
      self.wrapView.autoDestoryAfterFinish = false
      self.wrapView.addVapTapGesture { [weak self] _, insideSource, source in
        guard let self, insideSource else { return }
        let info = source?.sourceInfo
        let rect = source?.frame ?? .zero
        self.emitResourceClick(
          VapResourceClickEventMessage(
            viewId: self.viewId,
            resourceId: nil,
            tag: info?.contentTag,
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
          )
        )
      }
    }
  }

  func view() -> UIView {
    wrapView
  }

  func play(request: VapPlayRequestMessage) throws {
    guard let source = request.source, !source.isEmpty else {
      throw PigeonError(code: "invalid-args", message: "play requires a non-empty source", details: nil)
    }

    tagValues = sanitizeTagValues(request.tagValues)
    frameEventsEnabled = request.frameEventsEnabled ?? false
    let requestToken = invalidatePendingNetworkPlayback()

    let repeatCount = Int(request.repeatCount ?? 0)
    setContentMode(request.contentMode ?? .scaleToFill)
    setMute(request.mute ?? false)

    switch request.sourceType ?? .file {
    case .file:
      playLocalFile(path: source, repeatCount: repeatCount, requestToken: requestToken)
    case .asset:
      let key: String
      if let package = request.assetPackage, !package.isEmpty {
        key = registrar.lookupKey(forAsset: source, fromPackage: package)
      } else {
        key = registrar.lookupKey(forAsset: source)
      }

      if let path = Bundle.main.path(forResource: key, ofType: nil) {
        playLocalFile(path: path, repeatCount: repeatCount, requestToken: requestToken)
      } else {
        throw PigeonError(code: "asset-not-found", message: "Unable to resolve asset path for \(key)", details: nil)
      }
    case .network:
      playNetworkSource(urlString: source, repeatCount: repeatCount, requestToken: requestToken)
    }
  }

  func stop() {
    _ = invalidatePendingNetworkPlayback()
    runOnMain {
      self.wrapView.stopHWDMP4()
      self.emitPlayback(
        VapPlaybackEventMessage(
          viewId: self.viewId,
          type: .stopped
        )
      )
    }
  }

  func setMute(_ mute: Bool) {
    runOnMain {
      self.wrapView.setMute(mute)
    }
  }

  func setContentMode(_ mode: VapContentModeMessage) {
    runOnMain {
      switch mode {
      case .scaleToFill:
        self.wrapView.contentMode = .scaleToFill
      case .aspectFit:
        self.wrapView.contentMode = .aspectFit
      case .aspectFill:
        self.wrapView.contentMode = .aspectFill
      }
    }
  }

  func setFrameEventsEnabled(_ enabled: Bool) {
    frameEventsEnabled = enabled
  }

  func release() {
    if released {
      return
    }
    released = true
    _ = invalidatePendingNetworkPlayback()
    runOnMain {
      self.wrapView.stopHWDMP4()
      self.onDisposed(self.viewId)
    }
  }

  @objc(vapWrap_viewshouldStartPlayMP4:config:)
  func vapWrap_viewshouldStartPlayMP4(_ container: UIView, config: QGVAPConfigModel) -> Bool {
    let info = config.info
    let size = info?.size ?? .zero
    let fps = info?.fps ?? 0
    let isMix = info?.isMerged ?? false
    emitPlayback(
      VapPlaybackEventMessage(
        viewId: viewId,
        type: .configReady,
        width: Int64(size.width),
        height: Int64(size.height),
        fps: Int64(fps),
        isMix: isMix
      )
    )
    return true
  }

  @objc(vapWrap_viewDidStartPlayMP4:)
  func vapWrap_viewDidStartPlayMP4(_ container: UIView) {
    emitPlayback(
      VapPlaybackEventMessage(
        viewId: viewId,
        type: .started
      )
    )
  }

  @objc(vapWrap_viewDidPlayMP4AtFrame:view:)
  func vapWrap_viewDidPlayMP4(at frame: QGMP4AnimatedImageFrame, view container: UIView) {
    guard frameEventsEnabled else { return }
    emitPlayback(
      VapPlaybackEventMessage(
        viewId: viewId,
        type: .frame,
        frameIndex: Int64(frame.frameIndex)
      )
    )
  }

  @objc(vapWrap_viewDidStopPlayMP4:view:)
  func vapWrap_viewDidStopPlayMP4(_ lastFrameIndex: Int, view container: UIView) {
    emitPlayback(
      VapPlaybackEventMessage(
        viewId: viewId,
        type: .stopped,
        frameIndex: Int64(lastFrameIndex)
      )
    )
  }

  @objc(vapWrap_viewDidFinishPlayMP4:view:)
  func vapWrap_viewDidFinishPlayMP4(_ totalFrameCount: Int, view container: UIView) {
    emitPlayback(
      VapPlaybackEventMessage(
        viewId: viewId,
        type: .complete,
        frameIndex: Int64(totalFrameCount)
      )
    )
  }

  @objc(vapWrap_viewDidFailPlayMP4:)
  func vapWrap_viewDidFailPlayMP4(_ error: Error) {
    let nsError = error as NSError
    emitPlayback(
      VapPlaybackEventMessage(
        viewId: viewId,
        type: .failed,
        errorCode: Int64(nsError.code),
        errorMessage: nsError.localizedDescription
      )
    )
  }

  @objc(vapWrapview_contentForVapTag:resource:)
  func vapWrapview_content(forVapTag tag: String, resource info: QGVAPSourceInfo) -> String {
    tagValues[tag] ?? tag
  }

  @objc(vapWrapView_loadVapImageWithURL:context:completion:)
  func vapWrapView_loadVapImage(
    withURL urlStr: String,
    context: [AnyHashable: Any],
    completion completionBlock: @escaping VAPImageCompletionBlock
  ) {
    let sourceInfo = context["resource"] as? QGVAPSourceInfo
    let request = VapImageResolveRequestMessage(
      viewId: viewId,
      resourceId: "",
      tag: sourceInfo?.contentTag,
      type: sourceInfo?.type.map { "\($0)" },
      loadType: sourceInfo?.loadType.map { "\($0)" },
      width: Int64(sourceInfo?.size.width ?? 0),
      height: Int64(sourceInfo?.size.height ?? 0),
      url: urlStr
    )

    resourceApi.resolveImage(request: request) { result in
      switch result {
      case .success(let payload):
        guard
          let bytes = payload.imageBytes?.data,
          !bytes.isEmpty,
          let image = UIImage(data: bytes)
        else {
          let error = NSError(
            domain: "vap_player_ios",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: payload.errorMessage ?? "No image bytes returned"]
          )
          completionBlock(nil, error, urlStr)
          return
        }
        completionBlock(image, nil, urlStr)
      case .failure(let error):
        let nsError = NSError(
          domain: "vap_player_ios",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
        completionBlock(nil, nsError, urlStr)
      }
    }
  }

  private func playLocalFile(path: String, repeatCount: Int, requestToken: Int64) {
    runOnMain {
      guard self.isRequestTokenCurrent(requestToken) else { return }
      self.wrapView.playHWDMP4(path, repeatCount: repeatCount, delegate: self)
    }
  }

  private func playNetworkSource(urlString: String, repeatCount: Int, requestToken: Int64) {
    let sanitizedSource = VapNetworkPolicy.sanitizeURLString(urlString)
    guard let url = URL(string: urlString) else {
      emitNetworkFailure(
        code: VapNetworkFailureCode.invalidUrl,
        message: "Invalid network URL: \(sanitizedSource)"
      )
      return
    }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      emitNetworkFailure(
        code: VapNetworkFailureCode.invalidUrl,
        message: "Unsupported URL scheme for network source: \(sanitizedSource)"
      )
      return
    }

    let cacheURL = cacheFileURL(forNetworkURL: urlString)
    if hasCachedFile(at: cacheURL) {
      VapNetworkCacheUtils.touch(fileURL: cacheURL)
      playLocalFile(path: cacheURL.path, repeatCount: repeatCount, requestToken: requestToken)
      return
    }

    startNetworkDownload(
      url: url,
      cacheURL: cacheURL,
      repeatCount: repeatCount,
      requestToken: requestToken,
      sanitizedSource: sanitizedSource
    )
  }

  private func startNetworkDownload(
    url: URL,
    cacheURL: URL,
    repeatCount: Int,
    requestToken: Int64,
    sanitizedSource: String
  ) {
    let maxDownloadBytes = VapNetworkPolicy.maxDownloadBytes(
      autoEvictionMaxBytes: VapNetworkCacheUtils.autoEvictionMaxBytes()
    )
    let downloadDelegate = VapBoundedDownloadTaskDelegate(
      sourceForError: sanitizedSource,
      url: url,
      maxDownloadBytes: maxDownloadBytes,
      maxRedirects: VapNetworkPolicy.maxRedirects
    ) { [weak self] result in
      guard let self else { return }
      self.clearActiveDownloadTask(requestToken: requestToken)
      guard self.isRequestTokenCurrent(requestToken) else {
        if case .success(let tempURL) = result {
          try? FileManager.default.removeItem(at: tempURL)
        }
        return
      }

      do {
        let tempURL: URL
        switch result {
        case .failure(let error):
          self.emitNetworkFailure(code: error.code, message: error.message)
          return
        case .success(let downloadedURL):
          tempURL = downloadedURL
        }

        if !VapNetworkPolicy.hasIsoBmffSignature(fileURL: tempURL) {
          try? FileManager.default.removeItem(at: tempURL)
          self.emitNetworkFailure(
            code: VapNetworkFailureCode.invalidMedia,
            message: "Downloaded file does not have a valid MP4 signature for \(sanitizedSource)"
          )
          return
        }

        let parent = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
          try FileManager.default.removeItem(at: cacheURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: cacheURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if fileSize <= 0 {
          try? FileManager.default.removeItem(at: cacheURL)
          self.emitNetworkFailure(
            code: VapNetworkFailureCode.invalidMedia,
            message: "Downloaded file is empty for \(sanitizedSource)"
          )
          return
        }
        if fileSize > maxDownloadBytes {
          try? FileManager.default.removeItem(at: cacheURL)
          self.emitNetworkFailure(
            code: VapNetworkFailureCode.sizeExceeded,
            message: "Downloaded file exceeds max download size (\(maxDownloadBytes) bytes) for \(sanitizedSource)"
          )
          return
        }
        if !VapNetworkPolicy.hasIsoBmffSignature(fileURL: cacheURL) {
          try? FileManager.default.removeItem(at: cacheURL)
          self.emitNetworkFailure(
            code: VapNetworkFailureCode.invalidMedia,
            message: "Downloaded file does not have a valid MP4 signature for \(sanitizedSource)"
          )
          return
        }
      } catch {
        try? FileManager.default.removeItem(at: cacheURL)
        self.emitNetworkFailure(
          code: VapNetworkFailureCode.networkIo,
          message: "Failed to load network source: \(sanitizedSource)"
        )
        return
      }
      VapNetworkCacheUtils.touch(fileURL: cacheURL)
      try? VapNetworkCacheUtils.pruneNetworkCacheToBytes(
        maxBytes: VapNetworkCacheUtils.autoEvictionMaxBytes(),
        protectedFileURL: cacheURL
      )

      guard self.isRequestTokenCurrent(requestToken) else { return }
      self.playLocalFile(path: cacheURL.path, repeatCount: repeatCount, requestToken: requestToken)
    }

    if setActiveDownloadTask(
      task: downloadDelegate.task,
      delegate: downloadDelegate,
      requestToken: requestToken
    ) {
      downloadDelegate.start()
    }
  }

  private func emitNetworkFailure(code: Int64, message: String) {
    emitPlayback(
      VapPlaybackEventMessage(
        viewId: viewId,
        type: .failed,
        errorCode: code,
        errorMessage: message
      )
    )
  }

  private func invalidatePendingNetworkPlayback() -> Int64 {
    playbackRequestLock.lock()
    defer { playbackRequestLock.unlock() }
    playbackRequestToken += 1
    activeDownloadDelegate?.cancel()
    activeDownloadTask = nil
    activeDownloadDelegate = nil
    return playbackRequestToken
  }

  private func isRequestTokenCurrent(_ requestToken: Int64) -> Bool {
    playbackRequestLock.lock()
    defer { playbackRequestLock.unlock() }
    return playbackRequestToken == requestToken
  }

  private func setActiveDownloadTask(
    task: URLSessionDownloadTask,
    delegate: VapBoundedDownloadTaskDelegate,
    requestToken: Int64
  ) -> Bool {
    playbackRequestLock.lock()
    defer { playbackRequestLock.unlock() }
    guard playbackRequestToken == requestToken else {
      delegate.cancel()
      return false
    }
    activeDownloadDelegate?.cancel()
    activeDownloadTask = task
    activeDownloadDelegate = delegate
    return true
  }

  private func clearActiveDownloadTask(requestToken: Int64) {
    playbackRequestLock.lock()
    defer { playbackRequestLock.unlock() }
    if playbackRequestToken == requestToken {
      activeDownloadTask = nil
      activeDownloadDelegate = nil
    }
  }

  private func cacheFileURL(forNetworkURL urlString: String) -> URL {
    let cacheDirectory = VapNetworkCacheUtils.cacheDirectoryURL()
    let fileName = "\(sha256Hex(urlString)).mp4"
    return cacheDirectory.appendingPathComponent(fileName)
  }

  private func hasCachedFile(at url: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return false
    }
    guard
      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let fileSize = attrs[.size] as? NSNumber
    else {
      return false
    }
    return fileSize.int64Value > 0 && VapNetworkPolicy.hasIsoBmffSignature(fileURL: url)
  }

  private func sha256Hex(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { byte in String(format: "%02x", byte) }.joined()
  }

  private func emitPlayback(_ event: VapPlaybackEventMessage) {
    eventApi.onPlaybackEvent(event: event) { _ in }
  }

  private func emitResourceClick(_ event: VapResourceClickEventMessage) {
    eventApi.onResourceClick(event: event) { _ in }
  }

  private func sanitizeTagValues(_ input: [String?: String?]?) -> [String: String] {
    guard let input else { return [:] }
    var output: [String: String] = [:]
    input.forEach { key, value in
      if let key, let value {
        output[key] = value
      }
    }
    return output
  }

  private func runOnMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
    } else {
      DispatchQueue.main.sync(execute: block)
    }
  }
}

private enum VapNetworkCacheUtils {
  private static let defaultAutoEvictionMaxBytes: Int64 = 100 * 1024 * 1024
  private static let cacheSubdirectory = "vap_player/network"
  private static var configuredAutoEvictionMaxBytes: Int64 =
    defaultAutoEvictionMaxBytes

  static func cacheDirectoryURL() -> URL {
    let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return cacheRoot.appendingPathComponent(cacheSubdirectory, isDirectory: true)
  }

  static func networkCacheSizeBytes() -> Int64 {
    let directory = cacheDirectoryURL()
    guard let fileURLs = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return 0
    }

    var totalSize: Int64 = 0
    for fileURL in fileURLs {
      guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
        values.isRegularFile == true
      else {
        continue
      }
      totalSize += Int64(values.fileSize ?? 0)
    }
    return totalSize
  }

  static func clearNetworkCache() throws {
    let directory = cacheDirectoryURL()
    guard FileManager.default.fileExists(atPath: directory.path) else {
      return
    }
    let fileURLs = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    for fileURL in fileURLs {
      try FileManager.default.removeItem(at: fileURL)
    }
  }

  static func pruneNetworkCacheToBytes(maxBytes: Int64, protectedFileURL: URL?) throws {
    if maxBytes < 0 {
      throw NSError(
        domain: "vap_player_ios",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "maxBytes must be >= 0"]
      )
    }

    let directory = cacheDirectoryURL()
    guard FileManager.default.fileExists(atPath: directory.path) else {
      return
    }

    let urls = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )

    var entries: [(url: URL, size: Int64, modifiedAt: Date)] = []
    for url in urls {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
      guard values.isRegularFile == true else {
        continue
      }
      entries.append((
        url: url,
        size: Int64(values.fileSize ?? 0),
        modifiedAt: values.contentModificationDate ?? .distantPast
      ))
    }

    var totalSize = entries.reduce(Int64(0)) { partial, entry in
      partial + entry.size
    }
    if totalSize <= maxBytes {
      return
    }

    let protectedPath = protectedFileURL?.resolvingSymlinksInPath().path
    let sortedEntries = entries.sorted { lhs, rhs in
      lhs.modifiedAt < rhs.modifiedAt
    }

    for entry in sortedEntries {
      if totalSize <= maxBytes {
        break
      }
      if let protectedPath, entry.url.resolvingSymlinksInPath().path == protectedPath {
        continue
      }
      try FileManager.default.removeItem(at: entry.url)
      totalSize -= entry.size
    }
  }

  static func touch(fileURL: URL) {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return
    }
    try? FileManager.default.setAttributes(
      [.modificationDate: Date()],
      ofItemAtPath: fileURL.path
    )
  }

  static func autoEvictionMaxBytes() -> Int64 {
    configuredAutoEvictionMaxBytes
  }

  static func setAutoEvictionMaxBytes(_ maxBytes: Int64) {
    guard maxBytes >= 0 else {
      return
    }
    configuredAutoEvictionMaxBytes = maxBytes
  }
}
