import Cocoa
import IOKit.pwr_mgt

// MARK: - Types

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

// MARK: - App

class KarabasanApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mode: Mode = .off
    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?
    private var expiresAt: Date?
    private var tooltipTimer: Timer?
    private var pollTimer: Timer?
    private var activeDurationIndex: Int?
    private var fullTimerPID: Int32? // PID of background root process for timed full mode

    private var stateFile: String {
        NSHomeDirectory() + "/.karabasan_state"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance check
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mucahit.karabasan")
            .filter { $0.processIdentifier != me }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(onClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        syncWithSystem()
        updateIcon()

        // Poll pmset state every 10s to stay in sync with external changes
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.syncWithSystem()
        }
    }

    /// Sync internal state with actual pmset state
    private func syncWithSystem() {
        let systemDisabled = querySleepDisabled()
        let savedExpiry = loadFullState()

        if systemDisabled && mode != .full {
            // SleepDisabled is on but we didn't know — check if a timer expired
            if let expiry = savedExpiry, expiry != .distantPast, expiry <= Date() {
                // Timer should have fired but didn't (crash/reboot). Clean up.
                _ = setSleepDisabled(false)
                clearFullState()
                mode = .off
                updateIcon()
                return
            }
            // Ongoing session (indefinite or still timed)
            releaseAssertion()
            cancelTimer()
            mode = .full
            if let expiry = savedExpiry, expiry != .distantPast {
                expiresAt = expiry
                activeDurationIndex = nil // can't know which duration
            } else {
                expiresAt = nil
                activeDurationIndex = durations.count - 1 // indefinite
            }
            updateIcon()
        } else if !systemDisabled && mode == .full {
            // Background timer expired, or something external turned it off
            fullTimerPID = nil
            cancelTimer()
            clearFullState()
            mode = .off
            activeDurationIndex = nil
            expiresAt = nil
            updateIcon()
        }
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
            activeDurationIndex = durations.count - 1
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

        if let seconds = seconds {
            // Timed: enable now, spawn background process to disable later
            if setSleepDisabled(true) {
                mode = .full
                expiresAt = Date().addingTimeInterval(seconds)
                saveFullState(expiresAt: expiresAt)

                // Background process to auto-disable after duration
                let secs = Int(seconds)
                let bgProcess = Process()
                bgProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
                bgProcess.arguments = ["-c", "sleep \(secs) && /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0"]
                bgProcess.standardOutput = FileHandle.nullDevice
                bgProcess.standardError = FileHandle.nullDevice
                try? bgProcess.run()
                fullTimerPID = bgProcess.processIdentifier

                // Timer to update UI when duration expires
                timer = Timer.scheduledTimer(withTimeInterval: seconds + 1, repeats: false) { [weak self] _ in
                    self?.syncWithSystem()
                }
                tooltipTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    self?.updateIcon()
                }
            }
        } else {
            // Indefinite: just enable
            if setSleepDisabled(true) {
                mode = .full
                saveFullState(expiresAt: nil)
            }
        }
        updateIcon()
    }

    private func deactivateFull() {
        // Kill background timer process if running
        if let pid = fullTimerPID {
            kill(pid, SIGTERM)
            fullTimerPID = nil
        }
        _ = setSleepDisabled(false)
        clearFullState()
        cancelTimer()
        mode = .off
        expiresAt = nil
        updateIcon()
    }

    private func deactivateAll() {
        releaseAssertion()
        if let pid = fullTimerPID {
            kill(pid, SIGTERM)
            fullTimerPID = nil
        }
        if mode == .full {
            _ = setSleepDisabled(false)
            clearFullState()
        }
        cancelTimer()
        expiresAt = nil
        activeDurationIndex = nil
    }

    // MARK: - Timer

    private func startTimer(seconds: TimeInterval?) {
        guard let seconds = seconds else { return }
        expiresAt = Date().addingTimeInterval(seconds)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.deactivateIdle()
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

    private func showMenu() {
        let menu = NSMenu()

        // Idle sleep — with duration submenu
        let idleItem = NSMenuItem(title: "Prevent Idle Sleep", action: nil, keyEquivalent: "")
        let idleSubmenu = NSMenu()
        for (i, d) in durations.enumerated() {
            let item = NSMenuItem(title: d.title, action: #selector(idleDurationSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            if mode == .idle && activeDurationIndex == i { item.state = .on }
            idleSubmenu.addItem(item)
        }
        idleItem.submenu = idleSubmenu
        menu.addItem(idleItem)

        // Full sleep — with duration submenu
        let fullItem = NSMenuItem(title: "Prevent ALL Sleep", action: nil, keyEquivalent: "")
        let fullSubmenu = NSMenu()
        for (i, d) in durations.enumerated() {
            let item = NSMenuItem(title: d.title, action: #selector(fullDurationSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            if mode == .full && activeDurationIndex == i { item.state = .on }
            fullSubmenu.addItem(item)
        }
        fullItem.submenu = fullSubmenu
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
        Persists even after quitting Karabasan.

        Red eye = full mode active.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - State persistence

    /// Save expiry to disk so we can recover after crash/reboot
    private func saveFullState(expiresAt: Date?) {
        if let exp = expiresAt {
            try? String(exp.timeIntervalSince1970).write(toFile: stateFile, atomically: true, encoding: .utf8)
        } else {
            // indefinite
            try? "indefinite".write(toFile: stateFile, atomically: true, encoding: .utf8)
        }
    }

    private func clearFullState() {
        try? FileManager.default.removeItem(atPath: stateFile)
    }

    /// Returns nil for indefinite, a Date for timed, or .distantPast if no state
    private func loadFullState() -> Date? {
        guard let content = try? String(contentsOfFile: stateFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .distantPast
        }
        if content == "indefinite" { return nil }
        if let ts = Double(content) { return Date(timeIntervalSince1970: ts) }
        return .distantPast
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", value]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
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
        pollTimer?.invalidate()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = KarabasanApp()
app.delegate = delegate
app.run()
