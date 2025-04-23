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
    }

    public class Default: LoggerProtocol {
        public static let shared: LoggerProtocol = Default()
        public var minimumLogLevel: LogLevel = .info
        private let isProduction: Bool

        public init(isProduction: Bool = false) {
            self.isProduction = isProduction
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
}
