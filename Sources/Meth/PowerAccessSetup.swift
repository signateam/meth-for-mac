import AppKit
import Foundation
import MethShared

enum PowerAccessSetup {
    static let agentLabel = "com.toli.meth.keeper"

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
        guard let helper = Bundle.main.path(forAuxiliaryExecutable: "MethKeeper") else {
            return "The MethKeeper component is missing from Meth.app."
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = directory.appendingPathComponent("\(agentLabel).plist")
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
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return "Could not install the background component: \(error.localizedDescription)"
        }
        let target = "gui/\(getuid())"
        _ = PowerTool.run("/bin/launchctl", ["bootout", target, plistURL.path])
        let result = PowerTool.run("/bin/launchctl", ["bootstrap", target, plistURL.path])
        guard result.code == 0 else {
            return "Background component did not start: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
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
