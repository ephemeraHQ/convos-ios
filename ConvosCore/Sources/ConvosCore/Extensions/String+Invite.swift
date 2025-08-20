import Foundation

public extension String {
    // Extracts the invite code from a Convos join URL of the form: https://domain/join/{code}
    var inviteCodeFromJoinURL: String? {
        guard let url = URL(string: self),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let parts = components.path.split(separator: "/").map(String.init)
        guard let joinIndex = parts.firstIndex(of: "join"), parts.count > joinIndex + 1 else { return nil }

        let code = parts[joinIndex + 1]
        return code.isEmpty ? nil : code
    }
}
