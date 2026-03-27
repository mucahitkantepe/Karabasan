import Cocoa
import IOKit.pwr_mgt

enum Mode {
    case off
    case idle
    case full
}

struct Duration {
    let title: String
    let seconds: TimeInterval? // nil = indefinite
}

let durations: [Duration] = [
    Duration(title: "30 Minutes", seconds: 30 * 60),
    Duration(title: "1 Hour", seconds: 60 * 60),
    Duration(title: "2 Hours", seconds: 2 * 60 * 60),
    Duration(title: "4 Hours", seconds: 4 * 60 * 60),
    Duration(title: "8 Hours", seconds: 8 * 60 * 60),
    Duration(title: "Indefinitely", seconds: nil),
]

class KarabasanApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mode: Mode = .off
    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?
    private var expiresAt: Date?
    private var tooltipTimer: Timer?
    private var activeDurationIndex: Int? // which duration is currently active

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

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
        var tip: String
        switch mode {
        case .off:
            symbol = "eye.slash"
            tip = "Off — sleep allowed"
        case .idle:
            symbol = "eye.fill"
            if let expires = expiresAt {
                tip = "On — idle sleep prevented (\(formatTime(expires.timeIntervalSinceNow)) left)"
            } else {
                tip = "On — idle sleep prevented"
            }
        case .full:
            symbol = "eye.fill"
            if let expires = expiresAt {
                tip = "Full — all sleep prevented (\(formatTime(expires.timeIntervalSinceNow)) left)"
            } else {
                tip = "Full — all sleep prevented (including lid close)"
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        if mode == .full {
            image?.isTemplate = false
            let tinted = NSImage(size: image!.size)
            tinted.lockFocus()
            image!.draw(in: NSRect(origin: .zero, size: image!.size))
            NSColor.systemRed.setFill()
            NSRect(origin: .zero, size: image!.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.isTemplate = false
            button.image = tinted
        } else {
            image?.isTemplate = true
            button.image = image
        }
        button.toolTip = tip
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
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

    /// Left-click: toggle idle prevention (indefinite, no password)
    private func toggleIdle() {
        if mode == .full {
            deactivateFull()
        } else if mode == .idle {
            deactivateIdle()
        } else {
            activateIdle(seconds: nil)
            activeDurationIndex = durations.count - 1 // "Indefinitely"
        }
    }

    // MARK: - Idle mode (IOPMAssertion)

    private func activateIdle(seconds: TimeInterval?) {
        deactivateAll()

        if createAssertion() {
            mode = .idle
            startTimer(seconds: seconds)
        }
        updateIcon()
    }

    private func deactivateIdle() {
        releaseAssertion()
        cancelTimer()
        mode = .off
        expiresAt = nil
        updateIcon()
    }

    // MARK: - Full mode (pmset SleepDisabled)

    private func activateFull(seconds: TimeInterval?) {
        deactivateAll()

        if setSleepDisabled(true) {
            mode = .full
            startTimer(seconds: seconds)
        }
        updateIcon()
    }

    private func deactivateFull() {
        _ = setSleepDisabled(false)
        cancelTimer()
        mode = .off
        expiresAt = nil
        updateIcon()
    }

    private func deactivateAll() {
        releaseAssertion()
        if mode == .full { _ = setSleepDisabled(false) }
        cancelTimer()
        expiresAt = nil
        activeDurationIndex = nil
    }

    // MARK: - Timer

    private func startTimer(seconds: TimeInterval?) {
        guard let seconds = seconds else { return }
        expiresAt = Date().addingTimeInterval(seconds)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.mode == .full {
                self.deactivateFull()
            } else {
                self.deactivateIdle()
            }
        }
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
        tooltipTimer?.invalidate()
        tooltipTimer = nil
    }

    // MARK: - Menu

    private func buildDurationSubmenu(action: Selector, activeMode: Mode) -> NSMenu {
        let submenu = NSMenu()
        for (i, d) in durations.enumerated() {
            let item = NSMenuItem(title: d.title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = i
            if mode == activeMode && activeDurationIndex == i { item.state = .on }
            submenu.addItem(item)
        }
        return submenu
    }

    private func showMenu() {
        let menu = NSMenu()

        let idleItem = NSMenuItem(title: "Prevent Idle Sleep", action: nil, keyEquivalent: "")
        idleItem.submenu = buildDurationSubmenu(action: #selector(idleDurationSelected(_:)), activeMode: .idle)
        menu.addItem(idleItem)

        let fullItem = NSMenuItem(title: "Prevent ALL Sleep", action: nil, keyEquivalent: "")
        fullItem.submenu = buildDurationSubmenu(action: #selector(fullDurationSelected(_:)), activeMode: .full)
        menu.addItem(fullItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About", action: #selector(showInfo), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func idleDurationSelected(_ sender: NSMenuItem) {
        if mode == .idle && activeDurationIndex == sender.tag {
            deactivateIdle()
        } else {
            activateIdle(seconds: durations[sender.tag].seconds)
            activeDurationIndex = sender.tag
        }
    }

    @objc private func fullDurationSelected(_ sender: NSMenuItem) {
        if mode == .full && activeDurationIndex == sender.tag {
            deactivateFull()
        } else {
            activateFull(seconds: durations[sender.tag].seconds)
            activeDurationIndex = sender.tag
        }
    }

    // MARK: - Info

    @objc private func showInfo() {
        let alert = NSAlert()
        alert.messageText = "Karabasan"
        alert.informativeText = """
        Left-click: toggle idle sleep prevention

        Right-click for duration and mode options:

        Prevent Idle Sleep — blocks auto-sleep when idle.
        Lid close and manual sleep still work.

        Prevent ALL Sleep — blocks everything,
        including lid close. Requires password.

        Red eye = full mode active.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - IOPMAssertion

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

    // MARK: - pmset SleepDisabled

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
        cancelTimer()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = KarabasanApp()
app.delegate = delegate
app.run()
