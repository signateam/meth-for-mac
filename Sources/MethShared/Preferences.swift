import Foundation

public enum MethPreferences {
    public static let domain = "com.toli.meth.shared"
    public static let wantedKey = "methWanted"
    public static let ownsOverrideKey = "methOwnsOverride"
    public static let priorCaffeinateKey = "priorCaffeinate"
    public static let caffeinateAtLaunchKey = "caffeinateAtLaunch"

    public static var store: UserDefaults {
        UserDefaults(suiteName: domain) ?? UserDefaults.standard
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
}
