import Cocoa
import IOKit.pwr_mgt

class KarabasanApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var active = false
    private var assertionID: IOPMAssertionID = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(onClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = active ? "eye.fill" : "eye.slash"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: active ? "Sleep prevented" : "Sleep allowed")
        image?.isTemplate = true
        button.image = image
        button.toolTip = active ? "Karabasan is upon you (sleep prevented)" : "Karabasan sleeps (sleep allowed)"
    }

    @objc private func onClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let statusText = active ? "Karabasan is upon you" : "Karabasan sleeps"
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Karabasan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        self.statusItem.menu = nil
    }

    private func toggle() {
        if active {
            releaseAssertion()
        } else {
            createAssertion()
        }
        updateIcon()
    }

    private func createAssertion() {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Karabasan prevents sleep" as CFString,
            &assertionID
        )
        active = (result == kIOReturnSuccess)
    }

    private func releaseAssertion() {
        if active {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            active = false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        releaseAssertion()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = KarabasanApp()
app.delegate = delegate
app.run()
