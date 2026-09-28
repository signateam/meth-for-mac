import Foundation
import IOKit.ps

public enum SafetyCutoff {
    public static let batteryThreshold = 10

    public struct Battery: Equatable, Sendable {
        public let onBattery: Bool
        public let percent: Int

        public init(onBattery: Bool, percent: Int) {
            self.onBattery = onBattery
            self.percent = percent
        }
    }

    /// Reads the internal battery, or nil on a Mac without one.
    public static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let descriptions = list.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return battery(from: descriptions)
    }

    /// Picks the present internal battery from IOPowerSources descriptions.
    public static func battery(from descriptions: [[String: Any]]) -> Battery? {
        for source in descriptions {
            guard source[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  source[kIOPSIsPresentKey] as? Bool ?? true,
                  let current = source[kIOPSCurrentCapacityKey] as? Int,
                  let max = source[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onBattery = source[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return Battery(onBattery: onBattery, percent: Int((Double(current) * 100 / Double(max)).rounded()))
        }
        return nil
    }

    /// The status line to show when Meth must not stay on, or nil when it is safe.
    public static func reason(
        battery: Battery?,
        thermalState: ProcessInfo.ThermalState,
        lowBatteryEnabled: Bool
    ) -> String? {
        if thermalState == .critical { return "Meth turned off: Mac is too hot" }
        if lowBatteryEnabled, let battery, battery.onBattery, battery.percent <= batteryThreshold {
            return "Meth turned off: battery at \(battery.percent)%"
        }
        return nil
    }

    public static func currentReason() -> String? {
        reason(
            battery: battery(),
            thermalState: ProcessInfo.processInfo.thermalState,
            lowBatteryEnabled: MethPreferences.lowBatteryCutoff
        )
    }
}
