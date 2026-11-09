import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if connectionOptions.urlContexts.contains(where: { $0.url.scheme == "crewclock" && $0.url.host == "alarms" }) {
      UserDefaults.standard.set(true, forKey: "crewclock.openAlarms")
    }
  }
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    if URLContexts.contains(where: { $0.url.scheme == "crewclock" && $0.url.host == "alarms" }) {
      UserDefaults.standard.set(true, forKey: "crewclock.openAlarms")
      NotificationCenter.default.post(name: Notification.Name("crewclock.openAlarms"), object: nil)
    }
  }
}
