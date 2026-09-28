import Darwin
import Foundation
import IOKit.ps
import MethShared
import ServiceManagement

final class MethDealer: NSObject {
    private static let appBundleID = "com.toli.trymeth"
    private static let label = "\(appBundleID).dealer"
    private var powerSource: CFRunLoopSource?
    private var missingChecks = 0

    func run() {
        // This component ends a requested Meth session only for a safety cutoff
        // (low battery or critical heat). It also completes an explicit turn-off
        // request if the menu app exits mid-transition.
        reconcile()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<MethDealer>.fromOpaque(context).takeUnretainedValue().reconcile()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), powerSource, .defaultMode)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.current.run()
    }

    @objc private func poll() { reconcile() }

    /// Posted on an arbitrary thread; reconcile on the main run loop.
    @objc private func thermalStateChanged() {
        performSelector(onMainThread: #selector(poll), with: nil, waitUntilDone: false)
    }

    private func reconcile() {
        if appWasRemoved() {
            retire()
            return
        }
        var wanted = MethPreferences.wanted
        let owned = MethPreferences.ownsOverride
        guard owned else { return }
        if wanted, let reason = SafetyCutoff.currentReason() {
            // Safety cutoffs end a Meth session even though the user asked for it.
            MethPreferences.cutoffReason = reason
            MethPreferences.wanted = false
            wanted = false
        }
        guard let actual = PowerTool.sleepDisabled() else { return }
        if wanted && !actual {
            _ = PowerTool.setSleepDisabled(true)
            // The app may have turned Meth off while pmset ran. Undo it, and keep ownership
            // if that fails, so no override is left that nothing will restore.
            if !MethPreferences.wanted, PowerTool.setSleepDisabled(false) != nil {
                MethPreferences.ownsOverride = true
            }
        } else if !wanted && actual {
            if PowerTool.setSleepDisabled(false) == nil {
                MethPreferences.ownsOverride = false
            }
        } else if !wanted && !actual {
            MethPreferences.ownsOverride = false
        }
    }

    /// True once Meth.app is in the Trash, or has been missing on two checks in a row.
    /// The kernel path follows the running executable, so after an update replaces the
    /// bundle it points at the discarded copy; the launch location is checked as well.
    private func appWasRemoved() -> Bool {
        // An update leaves a Meth.app at the launch location, whatever happened to the old copy.
        if appIsInstalled(at: launchAppPath) {
            missingChecks = 0
            return false
        }
        guard let path = Self.executablePath() else {
            missingChecks += 1
            return missingChecks >= 2
        }
        if path.contains("/.Trash/") || path.contains("/.Trashes/") { return true }
        missingChecks = FileManager.default.fileExists(atPath: path) ? 0 : missingChecks + 1
        return missingChecks >= 2
    }

    /// The Meth.app that launchd started this dealer from.
    private let launchAppPath = MethDealer.executablePath().map { path in
        (0..<3).reduce(URL(fileURLWithPath: path)) { url, _ in url.deletingLastPathComponent() }.path
    }

    /// Reads Info.plist directly; Bundle(path:) caches bundles that have since been deleted.
    private func appIsInstalled(at path: String?) -> Bool {
        guard let path, !path.contains("/.Trash/"), !path.contains("/.Trashes/") else { return false }
        let plist = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        return NSDictionary(contentsOf: plist)?["CFBundleIdentifier"] as? String == Self.appBundleID
    }

    private static func executablePath() -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// Restores normal sleep and removes this agent so the Mac cannot stay unable to sleep.
    private func retire() {
        if MethPreferences.wanted || MethPreferences.ownsOverride {
            MethPreferences.wanted = false
            // Stay registered and retry on the next check until sleep is restored.
            guard PowerTool.setSleepDisabled(false) == nil else { return }
            MethPreferences.ownsOverride = false
        }
        MethPreferences.store.synchronize()
        do {
            try SMAppService.agent(plistName: "\(Self.label).plist").unregister()
        } catch {
            _ = PowerTool.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(Self.label)"])
        }
        exit(0)
    }
}

MethDealer().run()
