import Foundation
import OSLog

/// Shared loggers for simulator / Console (`subsystem` = app bundle id).
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "StarterApp"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let api = Logger(subsystem: subsystem, category: "api")
    static let purchases = Logger(subsystem: subsystem, category: "purchases")

    #if DEBUG
    /// DEBUG-only: mirror this app's `os_log` entries to stdout so they stream via
    /// `xcrun devicectl device process launch --console`. That path works on a
    /// *wireless* device, where `idevicesyslog` (USB-only) can't reach — so this is
    /// how you read device logs from the terminal without a cable. Release builds
    /// never call this and keep pure `os_log` (no stdout, privacy annotations intact).
    static func startConsoleMirror() {
        let sub = subsystem
        Task.detached(priority: .utility) {
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return }
            let out = FileHandle.standardOutput
            var lastDate = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let position = store.position(date: lastDate)
                guard let entries = try? store.getEntries(at: position) else { continue }
                for entry in entries {
                    guard let log = entry as? OSLogEntryLog,
                          log.subsystem == sub,
                          log.date > lastDate else { continue }
                    lastDate = log.date
                    out.write(Data("[\(log.category)] \(log.composedMessage)\n".utf8))
                }
            }
        }
    }
    #endif
}
