import Flutter
import UIKit

/// iOS implementation of the vap_player plugin.
public final class VapPlayerIosPlugin: NSObject, FlutterPlugin {
  static let platformViewType = "app.misi/vap_player_ios"

  private var players: [Int64: VapPlayerInstance] = [:]
  private var nextPlayerId: Int64 = 1
  private var messenger: FlutterBinaryMessenger!
  private var flutterApi: VapResourceFlutterApi!

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = VapPlayerIosPlugin()
    plugin.messenger = registrar.messenger()
    plugin.flutterApi = VapResourceFlutterApi(
      binaryMessenger: registrar.messenger())
    IosVapPlayerApiSetup.setUp(
      binaryMessenger: registrar.messenger(), api: plugin)
    registrar.register(
      VapPlatformViewFactory(playerLookup: { [weak plugin] playerId in
        plugin?.players[playerId]
      }),
      withId: platformViewType)
    registrar.publish(plugin)
  }

  private func disposeAllPlayers() {
    players.values.forEach { $0.dispose() }
    players.removeAll()
  }
}

extension VapPlayerIosPlugin: IosVapPlayerApi {
  func initialize() throws {
    disposeAllPlayers()
  }

  func create(options: PlatformCreationOptions) throws -> Int64 {
    let playerId = nextPlayerId
    nextPlayerId += 1
    players[playerId] = VapPlayerInstance(
      playerId: playerId,
      messenger: messenger,
      flutterApi: flutterApi,
      options: options)
    return playerId
  }

  func dispose(playerId: Int64) throws {
    players.removeValue(forKey: playerId)?.dispose()
  }
}
