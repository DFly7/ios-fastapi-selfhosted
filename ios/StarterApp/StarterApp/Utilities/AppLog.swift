import OSLog

/// Shared loggers for simulator / Console (`subsystem` = app bundle id).
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "StarterApp"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let api = Logger(subsystem: subsystem, category: "api")
    static let purchases = Logger(subsystem: subsystem, category: "purchases")
}
