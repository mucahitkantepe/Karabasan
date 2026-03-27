import Cocoa
import IOKit.pwr_mgt

enum Mode {
    case off
    case idle
    case full
}

class KarabasanApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mode: Mode = .off
    private var assertionID: IOPMAssertionID = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(onClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        if querySleepDisabled() { mode = .full }
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        let tip: String
        switch mode {
        case .off:
            symbol = "eye.slash"
            tip = "Off — sleep allowed"
        case .idle:
            symbol = "eye.fill"
            tip = "On — idle sleep prevented"
        case .full:
            symbol = "eye.trianglebadge.exclamationmark.fill"
            tip = "Full — all sleep prevented (including lid close)"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        image?.isTemplate = true
        button.image = image
        button.toolTip = tip
    }

    // MARK: - Click handling

    @objc private func onClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            toggleIdle()
        }
    }

    /// Left-click: toggle between off and idle (no password)
    private func toggleIdle() {
        if mode == .full { return } // left-click disabled in full mode, use menu

        if mode == .off {
            if createAssertion() { mode = .idle }
        } else {
            releaseAssertion()
            mode = .off
        }
        updateIcon()
    }

    private func showMenu() {
        let menu = NSMenu()

        if mode == .full {
            let item = NSMenuItem(title: "Disable Full Sleep Prevention", action: #selector(disableFull), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Prevent ALL Sleep (password required)", action: #selector(enableFull), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let infoItem = NSMenuItem(title: "How It Works", action: #selector(showInfo), keyEquivalent: "")
        infoItem.target = self
        menu.addItem(infoItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Info

    @objc private func showInfo() {
        let alert = NSAlert()
        alert.messageText = "Karabasan"
        alert.informativeText = """
        Left-click the icon to toggle:

        \u{25CC}  Off — sleep allowed
        \u{25C9}  On — prevents idle sleep

        Right-click for Full mode:

        \u{26A0}  Full — prevents ALL sleep, including lid close
              Requires password. Persists after quit.

        vs Caffeine: Same idle prevention + Full mode
        vs Amphetamine: No timers/triggers, but Full mode
        is built-in (no separate helper app needed)

        Named after the Karabasan — the sleep paralysis
        demon from Turkic mythology.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Full mode

    @objc private func enableFull() {
        releaseAssertion()
        if setSleepDisabled(true) { mode = .full }
        updateIcon()
    }

    @objc private func disableFull() {
        if setSleepDisabled(false) { mode = .off }
        updateIcon()
    }

    // MARK: - Idle (IOPMAssertion)

    @discardableResult
    private func createAssertion() -> Bool {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Karabasan prevents sleep" as CFString,
            &assertionID
        )
        return result == kIOReturnSuccess
    }

    private func releaseAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    // MARK: - Full (pmset SleepDisabled)

    @discardableResult
    private func setSleepDisabled(_ disabled: Bool) -> Bool {
        let value = disabled ? "1" : "0"
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil
    }

    private func querySleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return false }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    // MARK: - Cleanup

    func applicationWillTerminate(_ notification: Notification) {
        releaseAssertion()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = KarabasanApp()
app.delegate = delegate
app.run()
