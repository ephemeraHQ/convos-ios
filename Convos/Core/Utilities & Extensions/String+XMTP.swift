import Foundation

extension String {
    var xmtpGroupTopicFormat: String {
        "/xmtp/mls/1/g-\(self)/proto"
    }
}
