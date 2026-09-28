import Foundation

public enum MethPreferences {
    public static let domain = "com.toli.trymeth.shared"
    private static let legacyDomain = "com.toli.meth.shared"
    public static let wantedKey = "methWanted"
    public static let ownsOverrideKey = "methOwnsOverride"
    public static let priorCaffeinateKey = "priorCaffeinate"
    public static let caffeinateAtLaunchKey = "caffeinateAtLaunch"
    public static let lowBatteryCutoffKey = "lowBatteryCutoff"
    public static let cutoffReasonKey = "cutoffReason"

    public static var store: UserDefaults {
        UserDefaults(suiteName: domain) ?? UserDefaults.standard
    }

    private static var keys: [String] {
        [wantedKey, ownsOverrideKey, priorCaffeinateKey, caffeinateAtLaunchKey]
    }

    /// Copies settings from the pre-1.0 domain once, before anything reads the new one.
    public static func migrateLegacyDomainIfNeeded() {
        let current = store
        guard keys.allSatisfy({ current.object(forKey: $0) == nil }),
              let legacy = UserDefaults(suiteName: legacyDomain) else { return }
        for key in keys {
            if let value = legacy.object(forKey: key) { current.set(value, forKey: key) }
        }
    }

    public static var wanted: Bool {
        get { store.bool(forKey: wantedKey) }
        set { store.set(newValue, forKey: wantedKey) }
    }

    public static var ownsOverride: Bool {
        get { store.bool(forKey: ownsOverrideKey) }
        set { store.set(newValue, forKey: ownsOverrideKey) }
    }

    public static var priorCaffeinate: Bool {
        get { store.object(forKey: priorCaffeinateKey) as? Bool ?? true }
        set { store.set(newValue, forKey: priorCaffeinateKey) }
    }

    public static var caffeinateAtLaunch: Bool {
        get { store.object(forKey: caffeinateAtLaunchKey) as? Bool ?? true }
        set { store.set(newValue, forKey: caffeinateAtLaunchKey) }
    }

    public static var lowBatteryCutoff: Bool {
        get { store.object(forKey: lowBatteryCutoffKey) as? Bool ?? true }
        set { store.set(newValue, forKey: lowBatteryCutoffKey) }
    }

    /// Why a safety cutoff last turned Meth off, shown until Meth is chosen again.
    public static var cutoffReason: String? {
        get { store.string(forKey: cutoffReasonKey) }
        set { store.set(newValue, forKey: cutoffReasonKey) }
    }
}
