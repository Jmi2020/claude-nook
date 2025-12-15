//
//  Settings.swift
//  ClaudeNook
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

/// Available idle timeout durations for stale session cleanup
enum IdleTimeout: Int, CaseIterable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case never = 0

    var displayName: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .never: return "Never"
        }
    }

    /// Time interval in seconds, or nil if disabled
    var timeInterval: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue)
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let idleTimeout = "idleTimeout"
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    // MARK: - Idle Timeout

    /// How long to wait before removing inactive sessions
    /// Sessions automatically reappear when they show activity again
    static var idleTimeout: IdleTimeout {
        get {
            let rawValue = defaults.integer(forKey: Keys.idleTimeout)
            // If not set (0) and never explicitly saved, default to 2 minutes
            if rawValue == 0 && defaults.object(forKey: Keys.idleTimeout) == nil {
                return .twoMinutes
            }
            return IdleTimeout(rawValue: rawValue) ?? .twoMinutes
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.idleTimeout)
            // Notify SessionStore of the change
            NotificationCenter.default.post(name: .idleTimeoutChanged, object: nil)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let idleTimeoutChanged = Notification.Name("idleTimeoutChanged")
}
