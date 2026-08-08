import Flutter
import QGVAPlayer
import UIKit

/// A QGVAPWrapView that reports window attachment, so playback requested
/// before the platform view is mounted can be deferred until rendering is
/// actually possible (the VAP Metal view stops when detached from a window).
final class VapWrapView: QGVAPWrapView {
  var onDidMoveToWindow: (() -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      onDidMoveToWindow?()
    }
  }
}

/// A single VAP player: owns the native wrap view, bridges commands from
/// Dart and delegate callbacks back to Dart.
final class VapPlayerInstance: NSObject {
  private static let fetchTimeout: TimeInterval = 5.0
  private static let parseConfigErrorType: Int64 = 10005
  private static let parseConfigErrorMessage = "0x5 parse config fail"

  let playerId: Int64
  let wrapView: VapWrapView

  private let messenger: FlutterBinaryMessenger
  private let flutterApi: VapResourceFlutterApi
  private let enableFrameEvents: Bool
  private let eventSink = QueuingEventSink<PlatformVapEvent>()

  private var hasResourceDelegate = false
  private var mute = false
  private var repeatCount: Int64 = 0
  private var enableOldVersion = false
  private var pendingPlay: PlatformPlayOptions?

  init(
    playerId: Int64,
    messenger: FlutterBinaryMessenger,
    flutterApi: VapResourceFlutterApi,
    options: PlatformCreationOptions
  ) {
    self.playerId = playerId
    self.messenger = messenger
    self.flutterApi = flutterApi
    self.enableFrameEvents = options.enableFrameEvents
    self.wrapView = VapWrapView()
    super.init()

    wrapView.autoDestoryAfterFinish = false
    wrapView.onDidMoveToWindow = { [weak self] in
      guard let self = self, let pending = self.pendingPlay else { return }
      self.pendingPlay = nil
      self.doPlay(pending)
    }
    wrapView.addVapTapGesture { [weak self] _, insideSource, source in
      guard let self = self, insideSource,
        let info = source?.sourceInfo
      else { return }
      self.sendEvent(ResourceClickedEvent(resource: Self.toPlatform(info)))
    }

    VapPlayerInstanceApiSetup.setUp(
      binaryMessenger: messenger, api: self,
      messageChannelSuffix: String(playerId))

    let sink = eventSink
    final class Handler: VapEventsStreamHandler {
      let sink: QueuingEventSink<PlatformVapEvent>
      init(sink: QueuingEventSink<PlatformVapEvent>) { self.sink = sink }
      override func onListen(
        withArguments arguments: Any?,
        sink pigeonSink: PigeonEventSink<PlatformVapEvent>
      ) {
        sink.setDelegate(pigeonSink)
      }
      override func onCancel(withArguments arguments: Any?) {
        sink.setDelegate(nil)
      }
    }
    VapEventsStreamHandler.register(
      with: messenger, instanceName: String(playerId),
      streamHandler: Handler(sink: sink))
  }

  func dispose() {
    pendingPlay = nil
    let view = wrapView
    if Thread.isMainThread {
      view.stopHWDMP4()
    } else {
      DispatchQueue.main.async { view.stopHWDMP4() }
    }
    eventSink.endOfStream()
    VapPlayerInstanceApiSetup.setUp(
      binaryMessenger: messenger, api: nil,
      messageChannelSuffix: String(playerId))
  }

  private func sendEvent(_ event: PlatformVapEvent) {
    if Thread.isMainThread {
      eventSink.success(event)
    } else {
      DispatchQueue.main.async { self.eventSink.success(event) }
    }
  }

  private func doPlay(_ options: PlatformPlayOptions) {
    DispatchQueue.main.async {
      let view = self.wrapView
      // QGVAPWrapView positions its inner VAPView by dividing by the size
      // from the vapc config; for files without one the config model is
      // nil and aspectFit/aspectFill produce a NaN frame, which crashes
      // with CALayerInvalidGeometry. Fall back to scaleToFill (a no-op in
      // the wrap view's layout) for such files.
      let hasVapcBox = Self.fileHasVapcBox(options.path)
      if FileManager.default.fileExists(atPath: options.path),
        let error = Self.oldVersionCompatibilityError(
          hasVapcBox: hasVapcBox,
          enableOldVersion: options.enableOldVersion)
      {
        self.sendEvent(error)
      }
      view.contentMode = {
        guard hasVapcBox else { return QGVAPWrapViewContentMode.scaleToFill }
        switch options.contentMode {
        case .scaleToFill: return QGVAPWrapViewContentMode.scaleToFill
        case .aspectFit: return QGVAPWrapViewContentMode.aspectFit
        case .aspectFill: return QGVAPWrapViewContentMode.aspectFill
        }
      }()
      // setMute also creates the inner VAPView, which enableOldVersion
      // must be applied to before playback parses the file.
      view.setMute(options.mute)
      if let inner = view.value(forKey: "vapView") as? UIView {
        if options.enableOldVersion {
          inner.enableOldVersion(true)
        }
        if !hasVapcBox || options.contentMode == .scaleToFill {
          // The wrap view never sizes the inner view for scaleToFill
          // (its layout switch-case is empty) nor for files without a
          // vapc config, so keep it matched to the wrap view's bounds.
          inner.frame = view.bounds
          inner.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
      }
      view.playHWDMP4(
        options.path,
        repeatCount: Int(options.repeatCount),
        delegate: self)
    }
  }

  static func oldVersionCompatibilityError(
    hasVapcBox: Bool,
    enableOldVersion: Bool
  ) -> FailedEvent? {
    guard !hasVapcBox && !enableOldVersion else { return nil }
    return FailedEvent(
      errorType: parseConfigErrorType,
      errorMsg: parseConfigErrorMessage)
  }

  /// Scans the top-level MP4 boxes of the file for a `vapc` box.
  private static func fileHasVapcBox(_ path: String) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { handle.closeFile() }
    let fileSize = handle.seekToEndOfFile()

    func bigEndian(_ data: Data, _ range: Range<Int>) -> UInt64 {
      data.subdata(in: range).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    var offset: UInt64 = 0
    while offset + 8 <= fileSize {
      handle.seek(toFileOffset: offset)
      let header = handle.readData(ofLength: 16)
      guard header.count >= 8 else { return false }
      if header.subdata(in: 4..<8) == Data("vapc".utf8) { return true }
      var boxSize = bigEndian(header, 0..<4)
      if boxSize == 1 {
        guard header.count >= 16 else { return false }
        boxSize = bigEndian(header, 8..<16)
      } else if boxSize == 0 {
        return false  // Box extends to the end of the file.
      }
      guard boxSize >= 8 else { return false }
      offset += boxSize
    }
    return false
  }

  private static func toPlatform(_ info: QGVAPSourceInfo) -> PlatformVapResource {
    let isImage =
      info.type == QGAGAttachmentSourceType.imgUrl
      || info.type == QGAGAttachmentSourceType.img
    return PlatformVapResource(
      id: info.contentTag,
      type: isImage ? .image : .text,
      tag: info.contentTag)
  }
}

// MARK: - VapPlayerInstanceApi (called from Dart on the platform thread)

extension VapPlayerInstance: VapPlayerInstanceApi {
  func play(options: PlatformPlayOptions) throws {
    mute = options.mute
    repeatCount = options.repeatCount
    if wrapView.window == nil {
      // Platform view not mounted yet; start once it is in a window.
      pendingPlay = options
      return
    }
    doPlay(options)
  }

  func stop() throws {
    pendingPlay = nil
    DispatchQueue.main.async { self.wrapView.stopHWDMP4() }
  }

  func pause() throws {
    DispatchQueue.main.async { self.wrapView.pauseHWDMP4() }
  }

  func resume() throws {
    DispatchQueue.main.async { self.wrapView.resumeHWDMP4() }
  }

  func setMute(mute: Bool) throws {
    self.mute = mute
    DispatchQueue.main.async { self.wrapView.setMute(mute) }
  }

  func setRepeatCount(repeatCount: Int64) throws {
    self.repeatCount = repeatCount
  }

  func setHasResourceDelegate(hasDelegate: Bool) throws {
    hasResourceDelegate = hasDelegate
  }
}

// MARK: - VAPWrapViewDelegate (callbacks arrive on a background queue)

extension VapPlayerInstance: VAPWrapViewDelegate {
  func vapWrap_viewshouldStartPlayMP4(
    _ container: UIView, config: QGVAPConfigModel
  ) -> Bool {
    if let info = config.info {
      sendEvent(
        ConfigReadyEvent(
          width: Int64(info.size.width),
          height: Int64(info.size.height),
          videoWidth: Int64(info.videoSize.width),
          videoHeight: Int64(info.videoSize.height),
          frameCount: Int64(info.framesCount),
          fps: Int64(info.fps),
          isMix: info.isMerged))
    }
    return true
  }

  func vapWrap_viewDidStartPlayMP4(_ container: UIView) {
    sendEvent(StartedEvent())
  }

  func vapWrap_viewDidPlayMP4(
    at frame: QGMP4AnimatedImageFrame, view container: UIView
  ) {
    if enableFrameEvents {
      sendEvent(FrameRenderedEvent(frameIndex: Int64(frame.frameIndex)))
    }
  }

  // viewDidFinishPlayMP4 fires once per loop iteration; the definitive
  // end of playback (all repeats done, or an explicit stop) is
  // viewDidStopPlayMP4, so completion is reported from there.
  func vapWrap_viewDidStopPlayMP4(
    _ lastFrameIndex: Int, view container: UIView
  ) {
    sendEvent(CompletedEvent())
    sendEvent(DestroyedEvent())
  }

  func vapWrap_viewDidFailPlayMP4(_ error: Error) {
    let nsError = error as NSError
    sendEvent(
      FailedEvent(
        errorType: Int64(nsError.code),
        errorMsg: nsError.localizedDescription))
  }

  func vapWrapview_content(
    forVapTag tag: String, resource info: QGVAPSourceInfo
  ) -> String {
    let isImage =
      info.type == QGAGAttachmentSourceType.imgUrl
      || info.type == QGAGAttachmentSourceType.img
    if isImage {
      // Pass the tag through so loadVapImageWithURL is invoked with it
      // and the image can be fetched from Dart.
      return tag
    }
    guard hasResourceDelegate else { return "" }
    // This callback is synchronous and, tracing QGVAPConfigManager's sole
    // caller of loadConfigResources, always arrives on the main thread
    // (playHWDMP4 asserts main thread). A DispatchSemaphore wait here
    // would deadlock: resolveText's reply is delivered via the main run
    // loop, which never gets to spin while this thread sits blocked on
    // the semaphore. Pump the run loop instead so the reply can actually
    // be processed while we wait for it.
    var answer = ""
    var finished = false
    flutterApi.resolveText(
      playerId: self.playerId,
      resource: Self.toPlatform(info)
    ) { result in
      if case .success(let text) = result, let text = text {
        answer = text
      }
      finished = true
    }
    let deadline = Date().addingTimeInterval(Self.fetchTimeout)
    while !finished && Date() < deadline {
      RunLoop.current.run(mode: .default, before: deadline)
    }
    return answer
  }

  func vapWrapView_loadVapImage(
    withURL urlStr: String,
    context: [AnyHashable: Any],
    completion completionBlock: @escaping VAPImageCompletionBlock
  ) {
    guard hasResourceDelegate else {
      completionBlock(
        nil,
        NSError(
          domain: "vap_player_ios", code: -1,
          userInfo: [NSLocalizedDescriptionKey: "No resource delegate"]),
        urlStr)
      return
    }
    let done = NSLock()
    var finished = false
    func finish(_ image: UIImage?, _ error: NSError?) {
      done.lock()
      let alreadyFinished = finished
      finished = true
      done.unlock()
      if !alreadyFinished {
        completionBlock(image, error, urlStr)
      }
    }
    DispatchQueue.main.async {
      let resource = PlatformVapResource(
        id: urlStr, type: .image, tag: urlStr)
      self.flutterApi.resolveImage(
        playerId: self.playerId, resource: resource
      ) { result in
        switch result {
        case .success(let data):
          if let data = data, let image = UIImage(data: data.data) {
            finish(image, nil)
          } else {
            finish(
              nil,
              NSError(
                domain: "vap_player_ios", code: -2,
                userInfo: [
                  NSLocalizedDescriptionKey: "No image for tag \(urlStr)"
                ]))
          }
        case .failure(let error):
          finish(
            nil,
            NSError(
              domain: "vap_player_ios", code: -3,
              userInfo: [
                NSLocalizedDescriptionKey: error.message ?? "resolveImage failed"
              ]))
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.fetchTimeout) {
      finish(
        nil,
        NSError(
          domain: "vap_player_ios", code: -4,
          userInfo: [NSLocalizedDescriptionKey: "resolveImage timed out"]))
    }
  }
}
