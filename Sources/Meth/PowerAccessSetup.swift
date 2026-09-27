import AppKit
import Foundation
import MethShared

enum PowerAccessSetup {
    static let agentLabel = "com.toli.meth.dealer"
    private static let legacyAgentLabel = "com.toli.meth.keeper"

    static func migrateLegacyAgentIfNeeded() -> String? {
        guard FileManager.default.fileExists(atPath: agentURL(legacyAgentLabel).path) else { return nil }
        return installAgent()
    }

    static func install() -> String? {
        guard let script = Bundle.main.path(forResource: "install-power-access", ofType: "sh") else {
            return "The setup script is missing from Meth.app."
        }
        let user = NSUserName()
        let shellCommand = "/bin/bash \(shellQuote(script)) \(shellQuote(user))"
        let appleScript = "do shell script \(appleScriptQuote(shellCommand)) with administrator privileges"
        let result = PowerTool.run("/usr/bin/osascript", ["-e", appleScript])
        guard result.code == 0 else {
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return installAgent()
    }

    private static func installAgent() -> String? {
        guard let helper = Bundle.main.path(forAuxiliaryExecutable: "MethDealer") else {
            return "Meth Dealer is missing from Meth.app."
        }
        let plistURL = agentURL(agentLabel)
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [helper],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null"
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return "Could not install the background component: \(error.localizedDescription)"
        }
        let target = "gui/\(getuid())"
        _ = PowerTool.run("/bin/launchctl", ["bootout", target, plistURL.path])
        let result = PowerTool.run("/bin/launchctl", ["bootstrap", target, plistURL.path])
        guard result.code == 0 else {
            return "Meth Dealer did not start: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return retireLegacyAgent(in: target)
    }

    private static func agentURL(_ label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private static func retireLegacyAgent(in target: String) -> String? {
        let legacyURL = agentURL(legacyAgentLabel)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
        _ = PowerTool.run("/bin/launchctl", ["bootout", "\(target)/\(legacyAgentLabel)"])
        let oldJob = PowerTool.run("/bin/launchctl", ["print", "\(target)/\(legacyAgentLabel)"])
        guard oldJob.code != 0 else { return "Meth Keeper is still running. Meth Dealer has started; try setup again to finish the rename." }
        do {
            try FileManager.default.removeItem(at: legacyURL)
        } catch {
            return "Meth Dealer has started, but the old login item could not be removed: \(error.localizedDescription)"
        }
        return nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
