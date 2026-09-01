import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let name = connectingSceneSession.role == .windowExternalDisplayNonInteractive
            ? "External Display" : "Default Configuration"
        return UISceneConfiguration(name: name, sessionRole: connectingSceneSession.role)
    }
}
