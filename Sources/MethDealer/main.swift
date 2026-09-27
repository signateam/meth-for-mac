import Foundation
import IOKit.ps
import MethShared

final class MethDealer: NSObject {
    private var powerSource: CFRunLoopSource?

    func run() {
        // This component never ends a requested Meth session. It also completes
        // an explicit turn-off request if the menu app exits mid-transition.
        reconcile()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<MethDealer>.fromOpaque(context).takeUnretainedValue().reconcile()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), powerSource, .defaultMode)
        }
        Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.current.run()
    }

    @objc private func poll() { reconcile() }

    private func reconcile() {
        let wanted = MethPreferences.wanted
        let owned = MethPreferences.ownsOverride
        guard owned else { return }
        guard let actual = PowerTool.sleepDisabled() else { return }
        if wanted && !actual {
            _ = PowerTool.setSleepDisabled(true)
        } else if !wanted && actual {
            if PowerTool.setSleepDisabled(false) == nil {
                MethPreferences.ownsOverride = false
            }
        } else if !wanted && !actual {
            MethPreferences.ownsOverride = false
        }
    }
}

MethDealer().run()
