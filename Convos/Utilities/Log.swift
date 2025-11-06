import ConvosCore
import Foundation

/// Convos app logging wrapper - uses "Convos" namespace
enum Log {
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        ConvosLog.debug(message, namespace: "Convos", file: file, function: function, line: line)
    }

    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        ConvosLog.info(message, namespace: "Convos", file: file, function: function, line: line)
    }

    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        ConvosLog.warning(message, namespace: "Convos", file: file, function: function, line: line)
    }

    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        ConvosLog.error(message, namespace: "Convos", file: file, function: function, line: line)
    }
}
