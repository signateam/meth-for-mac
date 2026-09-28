import AppKit
import Foundation
import MethShared
import ServiceManagement

enum PowerAccessSetup {
    static let agentLabel = "com.toli.trymeth.dealer"
    private static let legacyAgentLabels = ["com.toli.meth.dealer", "com.toli.meth.keeper"]
    private static let registeredPathKey = "dealerRegisteredAppPath"
    private static let registeredVersionKey = "dealerRegisteredAppVersion"
    private static let safePath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// Bundled at Contents/Library/LaunchAgents with a BundleProgram path, so launchd
    /// runs the helper from whichever copy of Meth.app registered it.
    private static var dealer: SMAppService { SMAppService.agent(plistName: "\(agentLabel).plist") }

    /// Replaces an old hand-written agent, re-points the dealer after Meth.app moves,
    /// and restarts it after an update so the new dealer code runs.
    static func refreshDealerAtLaunch() -> String? {
        // A copy opened from a disk image or App Translocation must not take the
        // dealer away from the installed app; its path disappears on eject.
        guard !isTransientCopy() else { return nil }
        if legacyAgentLabels.contains(where: { FileManager.default.fileExists(atPath: agentURL($0).path) }) {
            // A legacy agent reads the old preferences domain, so it is always retired,
            // even if the replacement cannot start.
            let registerError = registerDealer()
            return retireLegacyAgents(in: "gui/\(getuid())") ?? registerError
        }
        guard dealer.status == .enabled else { return nil }
        if dealerMatchesThisApp() {
            restartDealerAfterUpdate()
            return nil
        }
        // Another copy (for example a development build) leaves an installed Meth.app alone.
        if let registered = UserDefaults.standard.string(forKey: registeredPathKey), isThisApp(atPath: registered) {
            return nil
        }
        return registerDealer()
    }

    static func isReady() -> Bool {
        guard dealer.status == .enabled, dealerMatchesThisApp(), hasOwnRule() else { return false }
        let job = PowerTool.run("/bin/launchctl", ["print", "gui/\(getuid())/\(agentLabel)"])
        return job.code == 0 && hasPowerAccess()
    }

    /// True when anything closed-lid mode installed is still present.
    static func isInstalled() -> Bool {
        dealer.status != .notRegistered || hasOwnRule() || hasPowerAccess()
    }

    static func hasPowerAccess() -> Bool {
        let result = PowerTool.run("/usr/bin/sudo", ["-n", "-l"])
        guard result.code == 0 else { return false }
        let permissions = result.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return ["0", "1"].allSatisfy { value in
            permissions.contains("(root) NOPASSWD: /usr/bin/pmset -a disablesleep \(value)")
        }
    }

    static func install() -> String? {
        if Bundle.main.bundlePath.contains("/AppTranslocation/") {
            return "Move Meth to your Applications folder and open it from there before setting up closed-lid mode."
        }
        if !(hasPowerAccess() && hasOwnRule()) {
            let user = NSUserName()
            let prompt = "Meth wants to let “\(user)” run only “pmset -a disablesleep 0” and “pmset -a disablesleep 1” without a password, so closed-lid mode can turn lid-close sleep off and back on. It installs one sudo rule file in /etc/sudoers.d."
            if let error = runPrivileged("install", user: user, prompt: prompt) { return error }
        }
        return registerDealer()
    }

    /// Unregisters the dealer and removes this user's sudo rule with one admin prompt.
    /// The caller turns Meth off first, while the sudo rule still works.
    static func uninstall() -> String? {
        try? dealer.unregister()
        UserDefaults.standard.removeObject(forKey: registeredPathKey)
        UserDefaults.standard.removeObject(forKey: registeredVersionKey)
        if let error = retireLegacyAgents(in: "gui/\(getuid())") { return error }
        guard hasPowerAccess() || hasOwnRule() else { return nil }
        let user = NSUserName()
        let prompt = "Meth wants to remove the sudo rule that lets “\(user)” run “pmset -a disablesleep” without a password. Caffeine will keep working."
        return runPrivileged("uninstall", user: user, prompt: prompt)
    }

    private static func runPrivileged(_ mode: String, user: String, prompt: String) -> String? {
        guard PowerAccessScript.isValidUserName(user), let target = PowerAccessScript.sudoersPath(for: user) else {
            return "Meth cannot set up closed-lid mode for the account name “\(user)”."
        }
        // The script text itself is the argument, so no file is executed as root.
        let arguments = [PowerAccessScript.text, mode, user, target,
                         PowerAccessScript.sudoersText(for: user), PowerAccessScript.legacySudoersText(for: user)]
        let command = (1...arguments.count).map { "quoted form of (item \($0) of argv)" }
        // env -i and --noprofile --norc keep BASH_ENV, exported functions and other
        // inherited variables from running as root alongside the script.
        let shellCommand = (["\"/usr/bin/env -i PATH=\(safePath) /bin/bash --noprofile --norc -c \" & \(command[0]) & \" trymeth-setup\""] + command.dropFirst()).joined(separator: " & \" \" & ")
        let promptIndex = arguments.count + 1
        let result = PowerTool.run("/usr/bin/osascript", [
            "-e", "on run argv",
            "-e", "do shell script \(shellCommand) with prompt (item \(promptIndex) of argv) with administrator privileges",
            "-e", "end run"
        ] + arguments + [prompt], environment: ["PATH": safePath])
        guard result.code == 0 else {
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func registerDealer() -> String? {
        let service = dealer
        if service.status == .enabled && !dealerMatchesThisApp() {
            // launchd keeps the old bundle location; re-registering points it here.
            try? service.unregister()
        }
        var registerError: Error?
        if service.status != .enabled {
            do { try service.register() } catch { registerError = error }
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "macOS needs your approval to run Meth Dealer. Turn on Meth in System Settings > General > Login Items & Extensions, then choose Repair Closed-Lid Mode."
        }
        guard service.status == .enabled else {
            return "Meth Dealer did not start: \(registerError?.localizedDescription ?? "unknown error")"
        }
        UserDefaults.standard.set(Bundle.main.bundlePath, forKey: registeredPathKey)
        UserDefaults.standard.set(currentVersion, forKey: registeredVersionKey)
        return retireLegacyAgents(in: "gui/\(getuid())")
    }

    private static func dealerMatchesThisApp() -> Bool {
        UserDefaults.standard.string(forKey: registeredPathKey) == Bundle.main.bundlePath
    }

    private static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// An update replaces the bundle in place, so launchd keeps running the old dealer binary.
    private static func restartDealerAfterUpdate() {
        guard let version = currentVersion,
              UserDefaults.standard.string(forKey: registeredVersionKey) != version else { return }
        let result = PowerTool.run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(agentLabel)"])
        if result.code == 0 { UserDefaults.standard.set(version, forKey: registeredVersionKey) }
    }

    private static func isTransientCopy() -> Bool {
        let url = Bundle.main.bundleURL
        if url.path.contains("/AppTranslocation/") { return true }
        return (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }

    /// Reads Info.plist directly; Bundle(path:) caches bundles that have since been deleted.
    private static func isThisApp(atPath path: String) -> Bool {
        let plist = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) else { return false }
        return info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier
    }

    private static func hasOwnRule() -> Bool {
        guard let path = PowerAccessScript.sudoersPath(for: NSUserName()) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private static func agentURL(_ label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private static func retireLegacyAgents(in target: String) -> String? {
        for legacyAgentLabel in legacyAgentLabels {
            let legacyURL = agentURL(legacyAgentLabel)
            guard FileManager.default.fileExists(atPath: legacyURL.path) else { continue }
            _ = PowerTool.run("/bin/launchctl", ["bootout", "\(target)/\(legacyAgentLabel)"])
            let oldJob = PowerTool.run("/bin/launchctl", ["print", "\(target)/\(legacyAgentLabel)"])
            guard oldJob.code != 0 else { return "An older Meth background process is still running. Try setup again to finish the update." }
            do {
                try FileManager.default.removeItem(at: legacyURL)
            } catch {
                return "The old Meth login item could not be removed: \(error.localizedDescription)"
            }
        }
        return nil
    }
}
