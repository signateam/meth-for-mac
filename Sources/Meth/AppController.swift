import AppKit
import MethShared
import ServiceManagement

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var setupButton: NSButton?
    private var offRadio: NSButton?
    private var caffeineRadio: NSButton?
    private var methRadio: NSButton?
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
        else if caffeinate.isActive { statusTitle = "Caffeine is on" }
        else { statusTitle = "Normal sleep" }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        addItem("Off", #selector(selectOff), to: menu, checked: !MethPreferences.wanted && !caffeinate.isActive)
        addItem("Caffeine", #selector(selectCaffeinate), to: menu, checked: !MethPreferences.wanted && caffeinate.isActive)
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

    @objc private func selectMethFromSettings() {
        guard !MethPreferences.wanted && !MethPreferences.ownsOverride else {
            refreshModeControls()
            return
        }
        if !PowerAccessSetup.isReady() && !performClosedLidSetup(showSuccessAlert: false) {
            refreshModeControls()
            return
        }
        toggleMeth()
    }

    @objc private func toggleMeth() {
        if MethPreferences.wanted {
            guard stopMethIfNeeded() else { return }
            caffeinate.setActive(MethPreferences.priorCaffeinate)
        } else {
            guard PowerTool.sleepDisabled() == false else {
                showError("Another app has already disabled system sleep. Turn that app off before starting Meth so Meth can restore your original setting safely.")
                refreshModeControls()
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
                refreshModeControls()
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
             (caffeinate.isActive ? "Caffeine: idle sleep is off" : "Meth: normal sleep"))
        refreshModeControls()
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
        refreshSetupControl()
        refreshModeControls()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 410),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Meth Settings"
        window.center()
        window.isReleasedWhenClosed = false
        guard let content = window.contentView else { return window }

        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)

        let modeTitle = sectionTitle("Mode")
        column.addArrangedSubview(modeTitle)
        column.setCustomSpacing(12, after: modeTitle)

        let modes = NSStackView()
        modes.orientation = .vertical
        modes.alignment = .leading
        modes.spacing = 8
        modes.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(modes)
        modes.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true

        let off = modeRow("Off", detail: "Use your Mac’s normal sleep settings.", action: #selector(selectOff), identifier: "mode-off")
        offRadio = off.button
        modes.addArrangedSubview(off.view)

        let caffeine = modeRow("Caffeine", detail: "Prevents idle sleep. The screen can still turn off.", action: #selector(selectCaffeinate), identifier: "mode-caffeine")
        caffeineRadio = caffeine.button
        modes.addArrangedSubview(caffeine.view)

        let meth = modeRow("Meth", detail: "Keeps the Mac awake with the lid closed. The screen stays on until you turn Meth off.", action: #selector(selectMethFromSettings), identifier: "mode-meth")
        methRadio = meth.button
        modes.addArrangedSubview(meth.view)

        let setup = NSButton(title: "Set Up Closed-Lid Mode…", target: self, action: #selector(setupClosedLid))
        setup.bezelStyle = .rounded
        setup.font = .systemFont(ofSize: 11)
        setupButton = setup
        modes.addArrangedSubview(setup)
        setup.leadingAnchor.constraint(equalTo: modes.leadingAnchor, constant: 22).isActive = true

        column.setCustomSpacing(19, after: modes)
        let modeDivider = separator()
        column.addArrangedSubview(modeDivider)
        modeDivider.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        column.setCustomSpacing(17, after: modeDivider)

        let settingsTitle = sectionTitle("Settings")
        column.addArrangedSubview(settingsTitle)
        column.setCustomSpacing(10, after: settingsTitle)

        let login = NSButton(checkboxWithTitle: "Start at login", target: self, action: #selector(changeLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.identifier = NSUserInterfaceItemIdentifier("login")
        column.addArrangedSubview(login)
        column.setCustomSpacing(10, after: login)

        let defaults = NSButton(checkboxWithTitle: "Caffeinate when Meth launches", target: self, action: #selector(changeDefault))
        defaults.state = MethPreferences.caffeinateAtLaunch ? .on : .off
        column.addArrangedSubview(defaults)

        let footerDivider = separator()
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footerDivider)

        let credit = NSTextField(labelWithString: "Built by Toli Marchuk")
        credit.font = .systemFont(ofSize: 10)
        credit.textColor = .tertiaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let github = socialButton("github-mark", fallback: "chevron.left.forwardslash.chevron.right", label: "Toli Marchuk on GitHub", action: #selector(openGitHub))
        let x = socialButton("x-mark", fallback: "xmark", label: "Toli Marchuk on X", action: #selector(openX))
        let footer = NSStackView(views: [credit, spacer, github, x])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -26),
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            column.bottomAnchor.constraint(lessThanOrEqualTo: footerDivider.topAnchor, constant: -14),
            footerDivider.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            footerDivider.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -15)
        ])
        return window
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.titlePosition = .noTitle
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }

    private func modeRow(_ title: String, detail: String, action: Selector, identifier: String) -> (view: NSStackView, button: NSButton) {
        let button = NSButton(radioButtonWithTitle: title, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        let explanation = NSTextField(labelWithString: detail)
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor
        explanation.lineBreakMode = .byWordWrapping
        explanation.maximumNumberOfLines = 2
        let row = NSStackView(views: [button, explanation])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 1
        explanation.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 22).isActive = true
        explanation.widthAnchor.constraint(equalToConstant: 350).isActive = true
        return (row, button)
    }

    private func socialButton(_ asset: String, fallback: String, label: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.target = self
        button.action = action
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        let image = Bundle.main.path(forResource: asset, ofType: "png").flatMap { NSImage(contentsOfFile: $0) }
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: label)
        image?.size = NSSize(width: 15, height: 15)
        image?.isTemplate = true
        button.image = image
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    private func refreshSetupControl() {
        let ready = PowerAccessSetup.isReady()
        setupButton?.isHidden = ready
        if !ready {
            setupButton?.title = PowerAccessSetup.hasPowerAccess() ? "Repair Closed-Lid Mode…" : "Set Up Closed-Lid Mode…"
        }
    }

    private func refreshModeControls() {
        let methSelected = MethPreferences.wanted || MethPreferences.ownsOverride
        offRadio?.state = !methSelected && !caffeinate.isActive ? .on : .off
        caffeineRadio?.state = !methSelected && caffeinate.isActive ? .on : .off
        methRadio?.state = methSelected ? .on : .off
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/tolimarchuk") { NSWorkspace.shared.open(url) }
    }

    @objc private func openX() {
        if let url = URL(string: "https://x.com/tolibear_") { NSWorkspace.shared.open(url) }
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
        _ = performClosedLidSetup(showSuccessAlert: true)
    }

    private func performClosedLidSetup(showSuccessAlert: Bool) -> Bool {
        let repairing = PowerAccessSetup.hasPowerAccess()
        let explanation = NSAlert()
        explanation.messageText = repairing ? "Repair closed-lid mode" : "Before setting up closed-lid mode"
        explanation.informativeText = "Meth keeps the screen on when the lid is closed. This is required for closed-lid mode in this version and uses battery power. Keep your Mac ventilated and out of a bag.\n\nMeth Dealer must run in the background to keep closed-lid mode active through power changes and when the menu app closes. It starts at login after setup. Meth stays on until you turn it off.\n\nYou can turn Meth on here or by right-clicking the eye in the menu bar."
        explanation.addButton(withTitle: repairing ? "Repair" : "Continue Setup")
        explanation.addButton(withTitle: "Cancel")
        guard explanation.runModal() == .alertFirstButtonReturn else { return false }
        let error = PowerAccessSetup.install()
        refreshSetupControl()
        if let error {
            showError(error)
            return false
        }
        guard PowerAccessSetup.isReady() else {
            showError("Meth Dealer could not be verified after setup. Try again.")
            return false
        }
        if showSuccessAlert {
            let alert = NSAlert()
            alert.messageText = "Closed-lid mode is ready"
            alert.informativeText = "Right-click the eye to turn Meth on. It will stay on until you turn it off."
            alert.runModal()
        }
        return true
    }

    @objc private func quit() {
        guard stopMethIfNeeded() else { return }
        NSApp.terminate(nil)
    }
}
