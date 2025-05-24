import Foundation
import GRDB

protocol DraftConversationWriterProtocol {
}

class DraftConversationWriter {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func save(with members: [Profile]) {
    }
}
