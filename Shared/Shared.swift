import Foundation

enum ReproShared {
    private static let teamID: String = {
        if let id = Bundle.main.object(forInfoDictionaryKey: "ChromiumFeedbackTeamID") as? String,
           !id.isEmpty,
           id != "$(DEVELOPMENT_TEAM)"
        {
            return id
        }
        return "TEAMIDXXXX"
    }()

    private static let bundleNamespace = "com.example.ChromiumFeedback"

    static let appGroupSuite = "group.\(teamID).\(bundleNamespace)"
    static let logsChangedNotification =
        "\(teamID).\(bundleNamespace).logsChanged" as CFString

    static let deviceName = "Chromium Repro Camera"
    static let logFileName = "logs.jsonl"

    static var logFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupSuite)?
            .appendingPathComponent(logFileName)
    }
}
