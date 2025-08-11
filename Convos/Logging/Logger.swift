import Foundation

public enum Logger {
    public enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }

    public protocol LoggerProtocol {
        func log(_ message: String, level: LogLevel, file: String, function: String, line: Int)
        var minimumLogLevel: LogLevel { get set }
        func getLogs() -> String
        func clearLogs(completion: (() -> Void)?)
    }

    public class Default: LoggerProtocol {
        public static let shared: LoggerProtocol = Default()
        public var minimumLogLevel: LogLevel = .info
        private let isProduction: Bool
        private let logFileURL: URL?
        private let fileQueue: DispatchQueue = DispatchQueue(label: "com.convos.logger.file", qos: .utility)
        private let maxLogFileSize: Int64 = 10 * 1024 * 1024 // 10MB

        public init(isProduction: Bool = false) {
            self.isProduction = isProduction

            if !isProduction,
               let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                // Create logs directory in app's documents folder
                let logsDirectory = documentsPath.appendingPathComponent("Logs")

                do {
                    try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                    self.logFileURL = logsDirectory.appendingPathComponent("convos.log")
                } catch {
                    print("Failed to create logs directory: \(error)")
                    self.logFileURL = nil
                }
            } else {
                self.logFileURL = nil
            }
        }

        public func log(_ message: String,
                        level: LogLevel = .info,
                        file: String = #file,
                        function: String = #function,
                        line: Int = #line) {
            guard level >= minimumLogLevel else { return }
            if isProduction {
                if message.contains("token") ||
                   message.contains("certificate") ||
                   message.contains("key") ||
                   message.contains("password") {
                    return
                }
            }
            let fileName = (file as NSString).lastPathComponent
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logMessage = "\(level.emoji) [\(timestamp)] [\(level)] [\(fileName):\(line)] \(function): \(message)"

            #if DEBUG
            print(logMessage)
            #endif

            // Write to file if not in production
            if !isProduction, let logFileURL = logFileURL {
                fileQueue.async {
                    self.writeToFile(logMessage, to: logFileURL)
                }
            }
        }

        private func writeToFile(_ message: String, to url: URL) {
            let logEntry = message + "\n"

            do {
                // Check if file exists and get its size
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = fileAttributes[.size] as? Int64 ?? 0

                // If file is too large, truncate it
                if fileSize > maxLogFileSize {
                    try "".write(to: url, atomically: true, encoding: .utf8)
                }

                // Append to file
                if let data = logEntry.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        let fileHandle = try FileHandle(forWritingTo: url)
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    } else {
                        try data.write(to: url)
                    }
                }
            } catch {
                print("Failed to write to log file: \(error)")
            }
        }

        public func getLogs() -> String {
            guard let logFileURL = logFileURL else { return "No log file available" }

            do {
                let logContent = try String(contentsOf: logFileURL, encoding: .utf8)
                return logContent.isEmpty ? "No logs available" : logContent
            } catch {
                return "Failed to read logs: \(error.localizedDescription)"
            }
        }

        public func clearLogs(completion: (() -> Void)? = nil) {
            guard let logFileURL = logFileURL else { return }

            fileQueue.async {
                do {
                    try "".write(to: logFileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to clear logs: \(error)")
                }
                completion?()
            }
        }
    }
}

public extension Logger {
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        Self.Default.shared.log(message, level: .debug, file: file, function: function, line: line)
    }

    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        Self.Default.shared.log(message, level: .info, file: file, function: function, line: line)
    }

    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        Self.Default.shared.log(message, level: .warning, file: file, function: function, line: line)
    }

    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        Self.Default.shared.log(message, level: .error, file: file, function: function, line: line)
    }

    static func getLogs() -> String {
        return Self.Default.shared.getLogs()
    }

    static func clearLogs(completion: (() -> Void)? = nil) {
        Self.Default.shared.clearLogs(completion: completion)
    }
}
