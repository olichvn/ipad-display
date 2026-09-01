import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let name = connectingSceneSession.role == .windowExternalDisplayNonInteractive
            ? "External Display" : "Default Configuration"
        return UISceneConfiguration(name: name, sessionRole: connectingSceneSession.role)
    }
}
