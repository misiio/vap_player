import Flutter
import UIKit

final class VapPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let playerLookup: (Int64) -> VapPlayerInstance?

  init(playerLookup: @escaping (Int64) -> VapPlayerInstance?) {
    self.playerLookup = playerLookup
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let playerId = (args as? NSNumber)?.int64Value ?? -1
    return VapPlatformView(
      frame: frame, instance: playerLookup(playerId))
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

final class VapPlatformView: NSObject, FlutterPlatformView {
  private let containedView: UIView

  init(frame: CGRect, instance: VapPlayerInstance?) {
    if let instance = instance {
      containedView = instance.wrapView
    } else {
      containedView = UIView(frame: frame)
    }
    containedView.frame = frame
    super.init()
  }

  func view() -> UIView {
    return containedView
  }
}
