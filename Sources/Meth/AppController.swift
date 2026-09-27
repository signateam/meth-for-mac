import AppKit
import MethShared
import ServiceManagement

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let caffeinate = CaffeinateController()
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Meth runs in the menu bar")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        caffeinate.setActive(MethPreferences.wanted || MethPreferences.caffeinateAtLaunch)
        if let error = PowerAccessSetup.migrateLegacyAgentIfNeeded() { lastError = error }
        refreshStatus()
        Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(pollStatus), userInfo: nil, repeats: true)
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func pollStatus() { refreshStatus() }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            toggleMeth()
        } else {
            let menu = makeMenu()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let actualMeth = MethPreferences.ownsOverride && PowerTool.sleepDisabled() == true
        let statusTitle: String
        if actualMeth { statusTitle = "Meth is on" }
        else if MethPreferences.wanted { statusTitle = "Meth is being restored" }
        else if caffeinate.isActive { statusTitle = "Caffeinate is on" }
        else { statusTitle = "Normal sleep" }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        addItem("Off", #selector(selectOff), to: menu, checked: !MethPreferences.wanted && !caffeinate.isActive)
        addItem("Caffeinate", #selector(selectCaffeinate), to: menu, checked: !MethPreferences.wanted && caffeinate.isActive)
        addItem(MethPreferences.wanted ? "Turn Off Meth" : "Turn On Meth", #selector(toggleMeth), to: menu, checked: actualMeth)
        if let lastError {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Meth needs attention…", action: #selector(showLastError), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(NSMenuItem(title: String(lastError.prefix(64)), action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        addItem("Settings…", #selector(openSettings), to: menu)
        addItem(MethPreferences.wanted ? "Turn Off Meth and Quit" : "Quit Meth", #selector(quit), to: menu)
        return menu
    }

    private func addItem(_ title: String, _ action: Selector, to menu: NSMenu, checked: Bool = false) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    @objc private func selectOff() {
        guard stopMethIfNeeded() else { return }
        caffeinate.setActive(false)
        lastError = nil
        refreshStatus()
    }

    @objc private func selectCaffeinate() {
        guard stopMethIfNeeded() else { return }
        caffeinate.setActive(true)
        lastError = nil
        refreshStatus()
    }

    @objc private func toggleMeth() {
        if MethPreferences.wanted {
            guard stopMethIfNeeded() else { return }
            caffeinate.setActive(MethPreferences.priorCaffeinate)
        } else {
            guard PowerTool.sleepDisabled() == false else {
                showError("Another app has already disabled system sleep. Turn that app off before starting Meth so Meth can restore your original setting safely.")
                return
            }
            MethPreferences.priorCaffeinate = caffeinate.isActive
            caffeinate.setActive(true)
            MethPreferences.ownsOverride = true
            MethPreferences.wanted = true
            if let error = PowerTool.setSleepDisabled(true) {
                MethPreferences.wanted = false
                MethPreferences.ownsOverride = false
                caffeinate.setActive(MethPreferences.priorCaffeinate)
                lastError = error
                openSettings()
                showError("Meth needs its one-time power setup before it can prevent lid-close sleep. \(error)")
                return
            }
        }
        lastError = nil
        refreshStatus()
    }

    private func stopMethIfNeeded() -> Bool {
        guard MethPreferences.wanted || MethPreferences.ownsOverride else { return true }
        MethPreferences.wanted = false
        if let error = PowerTool.setSleepDisabled(false) {
            lastError = error
            showError("Meth could not restore normal sleep yet. Meth Dealer will keep retrying. \(error)")
            refreshStatus()
            return false
        }
        MethPreferences.ownsOverride = false
        return true
    }

    private func refreshStatus() {
        guard statusItem != nil else { return }
        let active = MethPreferences.ownsOverride && PowerTool.sleepDisabled() == true
        let state: EyeIcon.State = active ? .meth : (caffeinate.isActive ? .caffeinate : .off)
        statusItem.button?.image = EyeIcon.make(state)
        statusItem.button?.toolTip = active ? "Meth: closed-lid sleep is off" :
            (MethPreferences.wanted ? "Meth: restoring closed-lid mode" :
             (caffeinate.isActive ? "Caffeinate: idle sleep is off" : "Meth: normal sleep"))
    }

    @objc private func showLastError() {
        if let lastError { showError(lastError) }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Meth"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func openSettings() {
        if settingsWindow == nil { settingsWindow = makeSettingsWindow() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 230),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Meth Settings"
        window.center()
        window.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 17
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 26, bottom: 24, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let login = NSButton(checkboxWithTitle: "Start at login", target: self, action: #selector(changeLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.identifier = NSUserInterfaceItemIdentifier("login")
        stack.addArrangedSubview(login)

        let defaults = NSButton(checkboxWithTitle: "Caffeinate when Meth launches", target: self, action: #selector(changeDefault))
        defaults.state = MethPreferences.caffeinateAtLaunch ? .on : .off
        stack.addArrangedSubview(defaults)

        let setup = NSButton(title: "Set Up Closed-Lid Mode…", target: self, action: #selector(setupClosedLid))
        setup.bezelStyle = .rounded
        stack.addArrangedSubview(setup)

        let note = NSTextField(labelWithString: "Meth stays on until you turn it off, even if you reopen the lid. The screen stays on with the lid closed. Keep your Mac ventilated and out of a bag.")
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 0
        note.preferredMaxLayoutWidth = 365
        stack.addArrangedSubview(note)

        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor)
        ])
        return window
    }

    @objc private func changeLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            sender.state = sender.state == .on ? .off : .on
            showError("Start at login could not be changed: \(error.localizedDescription)")
        }
    }

    @objc private func changeDefault(_ sender: NSButton) {
        MethPreferences.caffeinateAtLaunch = sender.state == .on
    }

    @objc private func setupClosedLid() {
        let explanation = NSAlert()
        explanation.messageText = "Before setting up closed-lid mode"
        explanation.informativeText = "Meth keeps the screen on when the lid is closed. This is required for closed-lid mode in this version and uses battery power. Keep your Mac ventilated and out of a bag.\n\nMeth Dealer must run in the background to keep closed-lid mode active through power changes and when the menu app closes. It starts at login after setup. Meth stays on until you turn it off.\n\nAfter setup, right-click the eye in the menu bar to turn on Meth."
        explanation.addButton(withTitle: "Continue Setup")
        explanation.addButton(withTitle: "Cancel")
        guard explanation.runModal() == .alertFirstButtonReturn else { return }
        if let error = PowerAccessSetup.install() { showError(error) }
        else {
            let alert = NSAlert()
            alert.messageText = "Closed-lid mode is ready"
            alert.informativeText = "Right-click the eye to turn Meth on. It will stay on until you turn it off."
            alert.runModal()
        }
    }

    @objc private func quit() {
        guard stopMethIfNeeded() else { return }
        NSApp.terminate(nil)
    }
}
