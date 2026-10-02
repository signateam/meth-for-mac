import AppKit
import MethShared
import ServiceManagement
import Sparkle

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var setupButton: NSButton?
    private var uninstallButton: NSButton?
    private var setupRow: NSStackView?
    private var offRadio: NSButton?
    private var caffeineRadio: NSButton?
    private var methRadio: NSButton?
    private let caffeinate = CaffeinateController()
    private var lastError: String?
    private var methWasWanted = false
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        MethPreferences.migrateLegacyDomainIfNeeded()
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Meth runs in the menu bar")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        caffeinate.setActive(MethPreferences.wanted || MethPreferences.caffeinateAtLaunch)
        methWasWanted = MethPreferences.wanted
        if let error = PowerAccessSetup.refreshDealerAtLaunch() { lastError = error }
        refreshStatus()
        Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(pollStatus), userInfo: nil, repeats: true)
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func pollStatus() {
        // Meth Dealer enforces the same cutoffs; this covers a dealer that is not running.
        if MethPreferences.wanted, MethPreferences.ownsOverride, let reason = SafetyCutoff.currentReason() {
            MethPreferences.cutoffReason = reason
            MethPreferences.wanted = false
            if PowerTool.setSleepDisabled(false) == nil { MethPreferences.ownsOverride = false }
        }
        // Turning Meth on clears the reason, so a reason here means a cutoff ended the session.
        if methWasWanted && !MethPreferences.wanted && MethPreferences.cutoffReason != nil {
            caffeinate.setActive(MethPreferences.priorCaffeinate)
        }
        methWasWanted = MethPreferences.wanted
        refreshStatus()
    }

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
        let actualMeth = methIsActive()
        let title = NSMenuItem(title: "Meth", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if !MethPreferences.wanted, let reason = MethPreferences.cutoffReason {
            let cutoff = NSMenuItem(title: reason, action: nil, keyEquivalent: "")
            cutoff.isEnabled = false
            menu.addItem(cutoff)
        }
        menu.addItem(.separator())

        // Checkmarks follow the actual power state, not the requested one.
        addItem("Off", #selector(selectOff), to: menu, checked: !actualMeth && !caffeinate.isActive)
        addItem("Caffeine", #selector(selectCaffeinate), to: menu, checked: !actualMeth && caffeinate.isActive)
        addItem("Meth", #selector(selectMeth), to: menu, checked: actualMeth)
        if let lastError {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Meth needs attention…", action: #selector(showLastError), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(NSMenuItem(title: String(lastError.prefix(64)), action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        addItem("Check for Updates…", #selector(checkForUpdates), to: menu)
        addItem("Settings…", #selector(openSettings), to: menu)
        menu.addItem(.separator())
        addItem(MethPreferences.wanted || MethPreferences.ownsOverride ? "Turn Off Meth and Quit" : "Quit Meth", #selector(quit), to: menu)
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
        MethPreferences.cutoffReason = nil
        lastError = nil
        refreshStatus()
    }

    @objc private func selectCaffeinate() {
        guard stopMethIfNeeded() else { return }
        caffeinate.setActive(true)
        MethPreferences.cutoffReason = nil
        lastError = nil
        refreshStatus()
    }

    /// Choosing Meth while it is on does nothing; Off or Caffeine leaves it.
    @objc private func selectMeth() {
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
        if MethPreferences.wanted || MethPreferences.ownsOverride {
            guard stopMethIfNeeded() else { return }
            caffeinate.setActive(MethPreferences.priorCaffeinate)
        } else {
            guard PowerTool.sleepDisabled() == false else {
                showError("Another app has already disabled system sleep. Turn that app off before starting Meth so Meth can restore your original setting safely.")
                refreshModeControls()
                return
            }
            if SafetyCutoff.currentReason() != nil {
                if ProcessInfo.processInfo.thermalState == .critical {
                    showError("Meth can’t turn on while your Mac is too hot. Let it cool down, then try again.")
                } else {
                    let percent = SafetyCutoff.battery()?.percent ?? SafetyCutoff.batteryThreshold
                    showError("Meth can’t turn on with the battery at \(percent)%. Connect power, or turn off “Turn off Meth at \(SafetyCutoff.batteryThreshold)% battery” in Settings.")
                }
                refreshModeControls()
                return
            }
            if !PowerAccessSetup.hasPowerAccess() {
                lastError = "Closed-lid mode is not set up."
                openSettings()
                showError("Meth needs its one-time closed-lid setup before it can prevent lid-close sleep. Choose Set Up Closed-Lid Mode… in Settings.")
                refreshStatus()
                return
            }
            if let error = PowerAccessSetup.ensureDealerHealthy() {
                lastError = error
                openSettings()
                showError(error)
                refreshStatus()
                return
            }
            MethPreferences.cutoffReason = nil
            MethPreferences.priorCaffeinate = caffeinate.isActive
            caffeinate.setActive(true)
            MethPreferences.ownsOverride = true
            MethPreferences.wanted = true
            if let error = PowerTool.setSleepDisabled(true) {
                MethPreferences.wanted = false
                // pmset may have applied the setting even though macOS did not confirm it in time.
                // Ownership is kept until sleep is restored, so Meth Dealer keeps retrying.
                let restoreError = PowerTool.setSleepDisabled(false)
                if restoreError == nil { MethPreferences.ownsOverride = false }
                caffeinate.setActive(MethPreferences.priorCaffeinate)
                lastError = error
                showError("Meth could not turn on. \(error)" + (restoreError == nil ? "" : " Meth could not restore normal sleep yet. Meth Dealer will keep retrying."))
                refreshStatus()
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
        let active = methIsActive()
        let state: EyeIcon.State = active ? .meth : (caffeinate.isActive ? .caffeinate : .off)
        statusItem.button?.image = EyeIcon.make(state)
        statusItem.button?.toolTip = active ? "Meth: closed-lid sleep is off" :
            (MethPreferences.wanted ? "Meth: restoring closed-lid mode" :
             (caffeinate.isActive ? "Caffeine: idle sleep is off" : "Meth: normal sleep"))
        refreshModeControls()
    }

    private func methIsActive() -> Bool {
        MethPreferences.ownsOverride && PowerTool.sleepDisabled() == true
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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 468),
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

        let meth = modeRow("Meth", detail: "Keeps the Mac awake with the lid closed. The screen stays on until you turn Meth off.", action: #selector(selectMeth), identifier: "mode-meth")
        methRadio = meth.button
        modes.addArrangedSubview(meth.view)

        let setup = NSButton(title: "Set Up Closed-Lid Mode…", target: self, action: #selector(setupClosedLid))
        setup.bezelStyle = .rounded
        setup.font = .systemFont(ofSize: 11)
        setupButton = setup

        let uninstall = NSButton(title: "Uninstall Closed-Lid Mode…", target: self, action: #selector(uninstallClosedLid))
        uninstall.bezelStyle = .rounded
        uninstall.font = .systemFont(ofSize: 11)
        uninstallButton = uninstall

        let setupActions = NSStackView(views: [setup, uninstall])
        setupActions.orientation = .horizontal
        setupActions.spacing = 8
        setupRow = setupActions
        modes.addArrangedSubview(setupActions)
        setupActions.leadingAnchor.constraint(equalTo: modes.leadingAnchor, constant: 22).isActive = true

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
        column.setCustomSpacing(10, after: defaults)

        let lowBattery = NSButton(checkboxWithTitle: "Turn off Meth at \(SafetyCutoff.batteryThreshold)% battery", target: self, action: #selector(changeLowBatteryCutoff))
        lowBattery.state = MethPreferences.lowBatteryCutoff ? .on : .off
        lowBattery.identifier = NSUserInterfaceItemIdentifier("low-battery")
        column.addArrangedSubview(lowBattery)
        column.setCustomSpacing(18, after: lowBattery)

        let version = NSTextField(labelWithString: versionText())
        version.font = .systemFont(ofSize: 11)
        version.textColor = .tertiaryLabelColor
        let updates = linkButton("Check for Updates…", size: 11, color: .linkColor, action: #selector(checkForUpdates))
        let about = NSStackView(views: [version, updates])
        about.orientation = .horizontal
        about.alignment = .firstBaseline
        about.spacing = 10
        column.addArrangedSubview(about)

        let footerDivider = separator()
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footerDivider)

        let credit = linkButton("trymeth.com · built by Toli Marchuk", size: 10, color: .tertiaryLabelColor, action: #selector(openWebsite))
        credit.toolTip = "https://trymeth.com"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let github = socialButton("github-mark", fallback: "chevron.left.forwardslash.chevron.right", label: "Meth on GitHub", action: #selector(openGitHub))
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

    private func versionText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    private func linkButton(_ title: String, size: CGFloat, color: NSColor, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: color
        ])
        button.setAccessibilityLabel(title)
        return button
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
        uninstallButton?.isHidden = !PowerAccessSetup.isInstalled()
        setupRow?.isHidden = ready && uninstallButton?.isHidden != false
    }

    private func refreshModeControls() {
        let methActive = methIsActive()
        offRadio?.state = !methActive && !caffeinate.isActive ? .on : .off
        caffeineRadio?.state = !methActive && caffeinate.isActive ? .on : .off
        methRadio?.state = methActive ? .on : .off
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc private func openWebsite() {
        if let url = URL(string: "https://trymeth.com") { NSWorkspace.shared.open(url) }
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/signateam/meth-for-mac") { NSWorkspace.shared.open(url) }
    }

    @objc private func openX() {
        if let url = URL(string: "https://x.com/tolimarchuk") { NSWorkspace.shared.open(url) }
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

    @objc private func changeLowBatteryCutoff(_ sender: NSButton) {
        MethPreferences.lowBatteryCutoff = sender.state == .on
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

    @objc private func uninstallClosedLid() {
        let confirm = NSAlert()
        confirm.messageText = "Uninstall closed-lid mode?"
        confirm.informativeText = "This turns Meth off and restores normal sleep, removes Meth Dealer from your login items, and removes the sudo rule that lets “\(NSUserName())” run “pmset -a disablesleep” without a password (\(PowerAccessScript.sudoersPath(for: NSUserName()) ?? "/etc/sudoers.d/trymeth-…"), plus the older /etc/sudoers.d/meth rule if it is yours). macOS will ask for an administrator password.\n\nCaffeine keeps working. You can set up closed-lid mode again at any time."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Uninstall").hasDestructiveAction = true
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        let methWasWanted = MethPreferences.wanted
        guard stopMethIfNeeded() else { return }
        if methWasWanted { caffeinate.setActive(MethPreferences.priorCaffeinate) }
        lastError = nil
        let error = PowerAccessSetup.uninstall()
        refreshSetupControl()
        refreshStatus()
        if let error {
            showError("Closed-lid mode was not fully removed. \(error)")
        } else {
            let alert = NSAlert()
            alert.messageText = "Closed-lid mode was removed"
            alert.informativeText = "Meth can still use Caffeine. Choose Meth in Settings to set up closed-lid mode again."
            alert.runModal()
        }
    }

    @objc private func quit() {
        guard stopMethIfNeeded() else { return }
        NSApp.terminate(nil)
    }
}
