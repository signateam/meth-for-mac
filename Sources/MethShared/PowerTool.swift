import Foundation
import IOKit

public enum PowerTool {
    public static func sleepDisabled() -> Bool? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let property = IORegistryEntryCreateCFProperty(entry, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let number = property as? NSNumber { return number.boolValue }
        return nil
    }

    @discardableResult
    public static func setSleepDisabled(_ active: Bool) -> String? {
        let result = run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", active ? "1" : "0"])
        if result.code != 0 {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Power setting failed (exit \(result.code))." : detail
        }
        guard sleepDisabled() == active else { return "macOS did not confirm the power setting." }
        return nil
    }

    /// Pass `environment` to replace the inherited environment instead of passing it on.
    public static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
