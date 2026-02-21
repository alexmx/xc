import Core
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.title = Greeting.hello()
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        return true
    }

    func hello() -> String {
        "AppDelegate.hello()"
    }
}
