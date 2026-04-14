import Flutter
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

    let filePath: String
    switch request.sourceType ?? .file {
    case .file:
      filePath = source
    case .asset:
      let key: String
      if let package = request.assetPackage, !package.isEmpty {
        key = registrar.lookupKey(forAsset: source, fromPackage: package)
      } else {
        key = registrar.lookupKey(forAsset: source)
      }

      if let path = Bundle.main.path(forResource: key, ofType: nil) {
        filePath = path
      } else {
        throw PigeonError(code: "asset-not-found", message: "Unable to resolve asset path for \(key)", details: nil)
      }
    }

    runOnMain {
      self.setContentMode(request.contentMode ?? .scaleToFill)
      self.wrapView.setMute(request.mute ?? false)
      self.wrapView.playHWDMP4(filePath, repeatCount: Int(request.repeatCount ?? 0), delegate: self)
    }
  }

  func stop() {
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
        type: .start
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
