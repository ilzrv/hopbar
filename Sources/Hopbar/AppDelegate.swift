import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        menuController = MenuController()
    }
}

@main
enum HopbarMain {
    @MainActor
    private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}
