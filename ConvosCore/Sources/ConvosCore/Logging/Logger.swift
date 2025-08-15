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
        func getLogsAsync(completion: @escaping (String) -> Void)
        func clearLogs(completion: (() -> Void)?)
        func flushPendingWrites()
    }

    public class Default: LoggerProtocol {
        nonisolated(unsafe) public static var shared: LoggerProtocol = {
            Default(isProduction: ConfigManager.shared.currentEnvironment == .production)
        }()
        public var minimumLogLevel: LogLevel = .info
        private let isProduction: Bool
        private let logFileURL: URL?
        private let fileQueue: DispatchQueue = DispatchQueue(label: "com.convos.logger.file", qos: .utility)
        private let readQueue: DispatchQueue = DispatchQueue(label: "com.convos.logger.read", qos: .utility)
        private let maxLogFileSize: Int64 = 10 * 1024 * 1024 // 10MB
        private let maxLogLines: Int = 1000 // Maximum lines to return for performance
        private var logBuffer: [String] = []
        private let bufferQueue: DispatchQueue = DispatchQueue(label: "com.convos.logger.buffer", qos: .utility)
        private let bufferMaxSize: Int = 100 // Keep last 100 log entries in memory

        // File handle optimization
        private var fileHandle: FileHandle?
        private var pendingWrites: [Data] = []
        private let writeBatchSize: Int = 10 // Write in batches of 10
        private var lastFileSizeCheck: Date = Date()
        private let fileSizeCheckInterval: TimeInterval = 30 // Check file size every 30 seconds

        public init(isProduction: Bool = false) {
            self.isProduction = isProduction

            if !isProduction,
               let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                // Create logs directory in app's documents folder
                let logsDirectory = documentsPath.appendingPathComponent("Logs")

                do {
                    try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                    self.logFileURL = logsDirectory.appendingPathComponent("convos.log")
                    // Initialize file handle
                    self.initializeFileHandle()
                } catch {
                    print("Failed to create logs directory: \(error)")
                    self.logFileURL = nil
                }
            } else {
                self.logFileURL = nil
            }
        }

        deinit {
            closeFileHandle()
        }

        private func initializeFileHandle() {
            guard let logFileURL = logFileURL else { return }

            fileQueue.async {
                do {
                    // Create file if it doesn't exist
                    if !FileManager.default.fileExists(atPath: logFileURL.path) {
                        try "".write(to: logFileURL, atomically: true, encoding: .utf8)
                    }

                    // Open file handle for writing
                    self.fileHandle = try FileHandle(forWritingTo: logFileURL)
                    self.fileHandle?.seekToEndOfFile()
                } catch {
                    print("Failed to initialize file handle: \(error)")
                }
            }
        }

        private func closeFileHandle() {
            fileQueue.async {
                do {
                    try self.fileHandle?.close()
                    self.fileHandle = nil
                } catch {
                    print("Failed to close file handle: \(error)")
                }
            }
        }

        private func checkAndTruncateFileIfNeeded() {
            guard let logFileURL = logFileURL else { return }

            let now = Date()
            guard now.timeIntervalSince(lastFileSizeCheck) > fileSizeCheckInterval else { return }

            lastFileSizeCheck = now

            do {
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
                let fileSize = fileAttributes[.size] as? Int64 ?? 0

                if fileSize > maxLogFileSize {
                    // Close current handle
                    try fileHandle?.close()
                    fileHandle = nil

                    // Truncate file
                    try "".write(to: logFileURL, atomically: true, encoding: .utf8)

                    // Reopen handle
                    fileHandle = try FileHandle(forWritingTo: logFileURL)
                    fileHandle?.seekToEndOfFile()

                    // Clear buffer since file was truncated
                    self.bufferQueue.async {
                        self.logBuffer.removeAll()
                    }
                }
            } catch {
                print("Failed to check/truncate file: \(error)")
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

            // Add to buffer for quick access
            bufferQueue.async {
                self.logBuffer.append(logMessage)
                if self.logBuffer.count > self.bufferMaxSize {
                    self.logBuffer.removeFirst()
                }
            }

            // Write to file if not in production
            if !isProduction, let logFileURL = logFileURL {
                fileQueue.async {
                    self.writeToFile(logMessage, to: logFileURL)
                }
            }
        }

        private func writeToFile(_ message: String, to url: URL) {
            let logEntry = message + "\n"

            guard let data = logEntry.data(using: .utf8) else { return }

            // Check file size periodically (not on every write)
            checkAndTruncateFileIfNeeded()

            // Add to pending writes
            pendingWrites.append(data)

            // Write immediately if we have a batch or if it's been a while
            if pendingWrites.count >= writeBatchSize {
                flushPendingWritesInternal()
            }
        }

        private func flushPendingWritesInternal() {
            guard !pendingWrites.isEmpty else { return }

            do {
                // Combine all pending writes into one operation
                let combinedData = pendingWrites.reduce(Data(), +)
                pendingWrites.removeAll()

                if let fileHandle = fileHandle {
                    fileHandle.write(combinedData)
                } else {
                    // Fallback: write directly to file
                    if let logFileURL = logFileURL {
                        if FileManager.default.fileExists(atPath: logFileURL.path) {
                            let handle = try FileHandle(forWritingTo: logFileURL)
                            handle.seekToEndOfFile()
                            handle.write(combinedData)
                            handle.closeFile()
                        } else {
                            try combinedData.write(to: logFileURL)
                        }
                    }
                }
            } catch {
                print("Failed to write to log file: \(error)")
                // Reset file handle on error
                fileHandle = nil
            }
        }

        public func getLogs() -> String {
            // First try to return from buffer for immediate response
            let bufferLogs = bufferQueue.sync {
                logBuffer.joined(separator: "\n")
            }

            // If buffer has content, return it immediately
            if !bufferLogs.isEmpty {
                return bufferLogs
            }

            // Fallback to file reading (synchronous but should be rare)
            guard let logFileURL = logFileURL else { return "No log file available" }

            do {
                let logContent = try String(contentsOf: logFileURL, encoding: .utf8)
                return logContent.isEmpty ? "No logs available" : logContent
            } catch {
                return "Failed to read logs: \(error.localizedDescription)"
            }
        }

        public func getLogsAsync(completion: @escaping (String) -> Void) {
            readQueue.async {
                // First try buffer for immediate response
                let bufferLogs = self.bufferQueue.sync {
                    self.logBuffer.joined(separator: "\n")
                }

                // If buffer has recent logs, return them immediately
                if !bufferLogs.isEmpty {
                    completion(bufferLogs)
                    return
                }

                // Otherwise read from file
                guard let logFileURL = self.logFileURL else {
                    completion("No log file available")
                    return
                }

                do {
                    let logContent = try String(contentsOf: logFileURL, encoding: .utf8)
                    let result = logContent.isEmpty ? "No logs available" : logContent
                    completion(result)
                } catch {
                    completion("Failed to read logs: \(error.localizedDescription)")
                }
            }
        }

        public func clearLogs(completion: (() -> Void)? = nil) {
            guard let logFileURL = logFileURL else { return }

            // Clear buffer immediately
            bufferQueue.async {
                self.logBuffer.removeAll()
            }

            fileQueue.async {
                // Flush any pending writes first
                self.flushPendingWritesInternal()

                // Close and reopen file handle
                do {
                    try self.fileHandle?.close()
                    self.fileHandle = nil

                    // Clear file
                    try "".write(to: logFileURL, atomically: true, encoding: .utf8)

                    // Reopen handle
                    self.fileHandle = try FileHandle(forWritingTo: logFileURL)
                    self.fileHandle?.seekToEndOfFile()
                } catch {
                    print("Failed to clear logs: \(error)")
                }
                completion?()
            }
        }

        /// Flushes any pending writes to disk. Call this when app goes to background.
        public func flushPendingWrites() {
            fileQueue.async {
                self.flushPendingWritesInternal()
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

    static func getLogsAsync(completion: @escaping (String) -> Void) {
        Self.Default.shared.getLogsAsync(completion: completion)
    }

    static func clearLogs(completion: (() -> Void)? = nil) {
        Self.Default.shared.clearLogs(completion: completion)
    }

    static func flushPendingWrites() {
        Self.Default.shared.flushPendingWrites()
    }
}
