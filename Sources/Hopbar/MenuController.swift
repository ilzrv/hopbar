import AppKit
import Foundation

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let configStore: ConfigStore
    private let commandRunner: CommandRunning
    private let loginItemManager: LoginItemManager
    private let menu = NSMenu()
    private let statusItem: NSStatusItem
    private var lastModificationDate: Date?
    private var launchAtLoginMenuItem: NSMenuItem?

    init(
        configStore: ConfigStore = ConfigStore(),
        commandRunner: CommandRunning = CommandRunner(),
        loginItemManager: LoginItemManager = LoginItemManager()
    ) {
        self.configStore = configStore
        self.commandRunner = commandRunner
        self.loginItemManager = loginItemManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusItem()
        menu.delegate = self
        statusItem.menu = menu
        _ = configStore.ensureConfigExists()
        reloadMenu(force: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        switch configStore.modificationDate() {
        case .success(let modificationDate):
            if modificationDate != lastModificationDate {
                reloadMenu(force: true)
            }
        case .failure(let error):
            renderError(error)
        }

        updateLaunchAtLoginMenuItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(named: "PromptSquare") {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = "S"
        }
    }

    private func reloadMenu(force: Bool = false) {
        if !force, case .success(let modificationDate) = configStore.modificationDate(), modificationDate == lastModificationDate {
            return
        }

        switch configStore.modificationDate() {
        case .success(let modificationDate):
            lastModificationDate = modificationDate
        case .failure:
            lastModificationDate = nil
        }

        switch configStore.load() {
        case .success(let model):
            render(model)
        case .failure(let error):
            renderError(error)
        }
    }

    private func render(_ model: MenuModel) {
        menu.removeAllItems()

        for entry in model.entries {
            menu.addItem(menuItem(for: entry))
        }

        appendFixedItems()
    }

    private func renderError(_ error: ConfigStoreError) {
        menu.removeAllItems()

        let errorItem = NSMenuItem(title: "Config Error", action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        menu.addItem(errorItem)

        let detailItem = NSMenuItem(title: error.description, action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        menu.addItem(detailItem)

        appendFixedItems()
    }

    private func menuItem(for entry: MenuEntry) -> NSMenuItem {
        switch entry.kind {
        case .command(let command, let terminal, let open):
            let item = NSMenuItem(title: entry.title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuActionBox(.runCommand(command, terminal: terminal, open: open))
            return item
        case .url(let url):
            let item = NSMenuItem(title: entry.title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuActionBox(.openURL(url))
            return item
        case .group(let children):
            let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: entry.title)
            for child in children {
                submenu.addItem(menuItem(for: child))
            }
            item.submenu = submenu
            return item
        }
    }

    private func appendFixedItems() {
        menu.addItem(.separator())
        menu.addItem(configMenuItem())
        let launchAtLoginItem = fixedItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin))
        self.launchAtLoginMenuItem = launchAtLoginItem
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(fixedItem(title: "Quit", action: #selector(quit)))
        updateLaunchAtLoginMenuItem()
    }

    private func configMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Config", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Config")
        submenu.addItem(fixedItem(title: "Open", action: #selector(openConfig)))
        submenu.addItem(fixedItem(title: "Reveal", action: #selector(revealConfig)))
        submenu.addItem(fixedItem(title: "Reload", action: #selector(reloadConfig)))
        item.submenu = submenu
        return item
    }

    private func fixedItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc
    private func runMenuAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? MenuActionBox else {
            return
        }

        do {
            try commandRunner.run(box.action)
        } catch {
            NSLog("Hopbar command failed: \(error)")
            NSSound.beep()
        }
    }

    @objc
    private func openConfig() {
        NSWorkspace.shared.open(configStore.configURL)
    }

    @objc
    private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([configStore.configURL])
    }

    @objc
    private func reloadConfig() {
        _ = configStore.ensureConfigExists()
        reloadMenu(force: true)
    }

    @objc
    private func toggleLaunchAtLogin() {
        do {
            try loginItemManager.setEnabled(!loginItemManager.isEnabled)
            updateLaunchAtLoginMenuItem()
        } catch {
            NSLog("Hopbar launch-at-login update failed: \(error)")
            NSSound.beep()
        }
    }

    private func updateLaunchAtLoginMenuItem() {
        guard let launchAtLoginMenuItem else {
            return
        }

        launchAtLoginMenuItem.isEnabled = loginItemManager.isSupported
        launchAtLoginMenuItem.state = loginItemManager.isEnabled ? .on : .off
    }

    @objc
    private func quit() {
        NSStatusBar.system.removeStatusItem(statusItem)
        NSApplication.shared.terminate(nil)
    }
}

private final class MenuActionBox: NSObject {
    let action: MenuAction

    init(_ action: MenuAction) {
        self.action = action
    }
}
