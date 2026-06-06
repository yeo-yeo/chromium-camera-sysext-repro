import Foundation
import os.log

enum WebcamLogMode {
    case console
    case file
}

final class WebcamLogger {
    static let shared = WebcamLogger()

    var mode: WebcamLogMode = .file

    private let queue = DispatchQueue(label: "com.example.chromium-feedback.logger")
    private let maxFileSize = 100_000

    static func info(_ event: String, payload: [String: Any] = [:]) {
        shared.log(level: "info", event: event, payload: payload)
    }

    static func error(_ event: String, payload: [String: Any] = [:]) {
        shared.log(level: "error", event: event, payload: payload)
    }

    private func log(level: String, event: String, payload: [String: Any]) {
        var record = payload
        record["level"] = level
        record["event"] = event
        record["timestamp"] = ISO8601DateFormatter().string(from: Date())

        guard let data = try? JSONSerialization.data(withJSONObject: record),
              let line = String(data: data, encoding: .utf8) else {
            os_log(.error, "Failed to encode log event %{public}@", event)
            return
        }

        switch mode {
        case .console:
            print(line)
        case .file:
            queue.async {
                self.append(line + "\n")
            }
        }
    }

    private func append(_ line: String) {
        guard let url = ReproShared.logFileURL else {
            os_log(.default, "%{public}@", line)
            return
        }

        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let attrs = try? manager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > maxFileSize {
            try? manager.removeItem(at: url)
        }

        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(ReproShared.logsChangedNotification),
            nil,
            nil,
            true
        )
    }
}
