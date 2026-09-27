import Foundation

final class CaffeinateController {
    private var activity: NSObjectProtocol?

    var isActive: Bool { activity != nil }

    func setActive(_ active: Bool) {
        if active && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled,
                reason: "Meth Caffeinate is keeping this Mac awake during idle time"
            )
        } else if !active, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    deinit {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }
}
