import Foundation
import TurnkeySDK

extension Operations.GetWhoami.Output {
    var response: Result<Operations.GetWhoami.Output.Ok, Error> {
        get async {
            switch self {
            case let .undocumented(statusCode, payload):
                let payloadString: String
                if let body = payload.body,
                   let bodyString = try? await String(collecting: body, upTo: .max) {
                    payloadString = bodyString
                } else {
                    payloadString = ""
                }
                return .failure(
                    NSError(
                        domain: "TurnkeyClientErrorDomain",
                        code: statusCode,
                        userInfo: [NSLocalizedDescriptionKey : payloadString]
                    )
                )
            case .ok(let okResponse):
                return .success(okResponse)
            }
        }
    }
}

extension Operations.CreateReadWriteSession.Output {
    var response: Result<Operations.CreateReadWriteSession.Output.Ok, Error> {
        get async {
            switch self {
            case let .undocumented(statusCode, payload):
                let payloadString: String
                if let body = payload.body,
                   let bodyString = try? await String(collecting: body, upTo: .max) {
                    payloadString = bodyString
                } else {
                    payloadString = ""
                }
                return .failure(
                    NSError(
                        domain: "TurnkeyClientErrorDomain",
                        code: statusCode,
                        userInfo: [NSLocalizedDescriptionKey : payloadString]
                    )
                )
            case .ok(let okResponse):
                return .success(okResponse)
            }
        }
    }
}
