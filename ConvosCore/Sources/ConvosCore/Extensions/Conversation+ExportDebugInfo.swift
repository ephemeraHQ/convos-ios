import Foundation
import XMTPiOS

public extension XMTPiOS.Conversation {
    func exportDebugLogs() async throws -> URL {
        // Get debug information
        let debugInfo: XMTPiOS.ConversationDebugInfo
        switch self {
        case .group(let group):
            debugInfo = try await group.getDebugInformation()
        case .dm(let dm):
            debugInfo = try await dm.getDebugInformation()
        }

        // Convert to JSON
        let jsonData = try JSONSerialization.data(
            withJSONObject: [
                "conversationId": id,
                "epoch": debugInfo.epoch,
                "maybeForked": debugInfo.maybeForked,
                "forkDetails": debugInfo.forkDetails,
                "localCommitLog": debugInfo.localCommitLog,
                "remoteCommitLog": debugInfo.remoteCommitLog,
                "commitLogForkStatus": String(describing: debugInfo.commitLogForkStatus)
            ],
            options: [.prettyPrinted, .sortedKeys]
        )

        // Create temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "conversation-\(id)-debug-\(Date().timeIntervalSince1970).json"
        let fileURL = tempDir.appendingPathComponent(fileName)

        try jsonData.write(to: fileURL)

        return fileURL
    }
}
