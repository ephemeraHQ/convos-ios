import XMTPiOS

extension Consent {
    var consentState: XMTPiOS.ConsentState {
        switch self {
        case .allowed: return .allowed
        case .denied: return .denied
        case .unknown: return .unknown
        }
    }
}
